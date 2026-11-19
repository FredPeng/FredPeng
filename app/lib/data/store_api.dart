import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/address.dart';
import '../models/cart.dart';
import '../models/money.dart';
import '../models/product.dart';
import 'disk_cache.dart';
import 'shop_repository.dart';

/// Client for the WooCommerce Store API (`/wp-json/wc/store/v1`).
///
/// The Store API is the public, customer-facing API that WooCommerce Blocks
/// use: no admin keys are needed in the app. The cart lives on the server and
/// is identified by a `Cart-Token`, so a customer's cart is the same cart
/// WooCommerce checks out (stock, coupons, shipping zones all apply).
class StoreApi extends ShopRepository {
  StoreApi(String storeUrl, this._prefs, this._disk, {http.Client? client})
      : _base = '${storeUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json/wc/store/v1',
        _http = client ?? http.Client() {
    _cartToken = _prefs.getString(_tokenKey);
  }

  static const _tokenKey = 'cart_token';
  static const _timeout = Duration(seconds: 20);
  static const _memoryTtl = Duration(minutes: 5);

  /// Product list cards only need these fields; leaving out descriptions,
  /// attributes and variations makes each page about 35% smaller to download
  /// and parse. The product page loads the full product itself.
  static const _listFields =
      'id,name,slug,permalink,type,prices,images,on_sale,is_in_stock,is_purchasable,has_options,average_rating,review_count';

  final String _base;
  final http.Client _http;
  final SharedPreferences _prefs;
  final DiskCache _disk;
  String? _cartToken;
  String? _nonce;

  final _memory = <String, ({DateTime at, Object value, int totalPages})>{};
  final _inflight = <String, Future<({Object value, int totalPages})>>{};

  // ---------------------------------------------------------------- catalog

  String _productsPath(ProductQuery q, int page, int perPage) {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'orderby': q.sort.orderBy,
      'order': q.sort.order,
      if (q.categoryId != null)
        'category': '${q.categoryId}'
      else if (q.categorySlug != null)
        'category': q.categorySlug!,
      if (q.search != null && q.search!.isNotEmpty) 'search': q.search!,
      if (q.onSale) 'on_sale': 'true',
      if (q.featured) 'featured': 'true',
      if (q.include != null) 'include': q.include!.join(','),
      'stock_status': 'instock,onbackorder',
      '_fields': _listFields,
    };
    return '/products?${Uri(queryParameters: params).query}';
  }

  String _categoriesPath(int? parent) =>
      parent == null ? '/products/categories' : '/products/categories?parent=$parent';

  @override
  Future<ProductPage?> cachedProducts(ProductQuery query, {int perPage = 20}) async {
    final r = await _peek(_productsPath(query, 1, perPage), _Kind.products);
    return r == null ? null : ProductPage(r.value as List<Product>, r.totalPages);
  }

  @override
  Future<List<Category>?> cachedCategories({int? parent}) async {
    final r = await _peek(_categoriesPath(parent), _Kind.categories);
    return r?.value as List<Category>?;
  }

  @override
  Future<Product?> cachedProduct(int id) async {
    final r = await _peek('/products/$id', _Kind.product);
    return r?.value as Product?;
  }

  @override
  Future<ProductPage> products(ProductQuery query, {int page = 1, int perPage = 20}) async {
    final path = _productsPath(query, page, perPage);
    final hasSearch = query.search != null && query.search!.isNotEmpty;
    final r = await _get(path, _Kind.products, persist: page == 1 && !hasSearch);
    return ProductPage(r.value as List<Product>, r.totalPages);
  }

  @override
  Future<Product> product(int id) async => (await _get('/products/$id', _Kind.product, persist: true)).value as Product;

  @override
  Future<Product?> productBySlug(String slug) async {
    final r = await _get('/products?slug=${Uri.encodeQueryComponent(slug)}', _Kind.products);
    final list = r.value as List<Product>;
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<List<Category>> categories({int? parent}) async =>
      (await _get(_categoriesPath(parent), _Kind.categories, persist: true)).value as List<Category>;

  /// Memory (fresh) -> network -> disk (offline fallback). Concurrent calls
  /// for the same path share one request.
  Future<({Object value, int totalPages})> _get(String path, _Kind kind, {bool persist = false}) {
    final mem = _memory[path];
    if (mem != null && DateTime.now().difference(mem.at) < _memoryTtl) {
      return Future.value((value: mem.value, totalPages: mem.totalPages));
    }
    return _inflight[path] ??= () async {
      try {
        final res = await _send('GET', path, withCart: false);
        final body = utf8.decode(res.bodyBytes);
        final pages = int.tryParse(res.headers['x-wp-totalpages'] ?? '') ?? 1;
        final value = await _parse(kind, body);
        _memory[path] = (at: DateTime.now(), value: value, totalPages: pages);
        if (persist) unawaited(_disk.write(path, '$pages\n$body'));
        return (value: value, totalPages: pages);
      } on ShopException {
        final stale = await _peek(path, kind);
        if (stale != null) return stale;
        rethrow;
      } finally {
        _inflight.remove(path);
      }
    }();
  }

  Future<({Object value, int totalPages})?> _peek(String path, _Kind kind) async {
    final mem = _memory[path];
    if (mem != null) return (value: mem.value, totalPages: mem.totalPages);
    final raw = await _disk.read(path);
    if (raw == null) return null;
    try {
      final nl = raw.indexOf('\n');
      final pages = int.parse(raw.substring(0, nl));
      final value = await _parse(kind, raw.substring(nl + 1));
      return (value: value, totalPages: pages);
    } catch (_) {
      return null;
    }
  }

  /// Large JSON is decoded on a background isolate so scrolling never janks.
  static Future<Object> _parse(_Kind kind, String body) {
    if (body.length < 16 * 1024) return Future.value(_parseSync((kind, body)));
    return compute(_parseSync, (kind, body));
  }

  static Object _parseSync((_Kind, String) input) {
    final (kind, body) = input;
    final Object json;
    try {
      json = jsonDecode(body) as Object;
    } catch (_) {
      throw ShopException('Unexpected response from the store. Please try again later.');
    }
    switch (kind) {
      case _Kind.products:
        return <Product>[for (final p in json as List) Product.fromJson((p as Map).cast<String, dynamic>())];
      case _Kind.product:
        return Product.fromJson((json as Map).cast<String, dynamic>());
      case _Kind.categories:
        return <Category>[
          for (final c in json as List) Category.fromJson((c as Map).cast<String, dynamic>()),
        ]..removeWhere((c) => c.count == 0 || c.slug == 'uncategorized');
    }
  }

  // ------------------------------------------------------------------- cart

  /// No saved cart token means the cart is empty: skip the request, so
  /// browsing never creates a WooCommerce session on the server.
  @override
  Future<Cart> cart() async => _cartToken == null ? Cart.empty : _cartFrom(await _send('GET', '/cart'));


  @override
  Future<Cart> addToCart(int productId, int quantity, {Map<String, String> options = const {}}) async {
    final body = {
      'id': productId,
      'quantity': quantity,
      if (options.isNotEmpty)
        'variation': [
          for (final e in options.entries) {'attribute': e.key, 'value': e.value},
        ],
    };
    return _cartFrom(await _send('POST', '/cart/add-item', body: body));
  }

  @override
  Future<Cart> updateItem(String key, int quantity) async =>
      _cartFrom(await _send('POST', '/cart/update-item', body: {'key': key, 'quantity': quantity}));

  @override
  Future<Cart> removeItem(String key) async => _cartFrom(await _send('POST', '/cart/remove-item', body: {'key': key}));

  @override
  Future<Cart> updateCustomer(Address address) async => _cartFrom(await _send(
        'POST',
        '/cart/update-customer',
        body: {
          'billing_address': address.toStoreApi(),
          'shipping_address': address.toStoreApi(billing: false),
        },
      ));

  @override
  Future<Cart> selectShippingRate(int packageId, String rateId) async => _cartFrom(await _send(
        'POST',
        '/cart/select-shipping-rate',
        body: {'package_id': packageId, 'rate_id': rateId},
      ));

  @override
  Future<Cart> applyCoupon(String code) async =>
      _cartFrom(await _send('POST', '/cart/apply-coupon', body: {'code': code}));

  @override
  Future<OrderResult> checkout(Address address, String paymentMethod, {String note = ''}) async {
    final res = await _send('POST', '/checkout', body: {
      'billing_address': address.toStoreApi(),
      'shipping_address': address.toStoreApi(billing: false),
      'customer_note': note,
      'payment_method': paymentMethod,
      'payment_data': <Object>[],
    });
    final j = (_decode(res) as Map).cast<String, dynamic>();
    final payment = (j['payment_result'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (payment['payment_status'] == 'failure' || payment['payment_status'] == 'error') {
      final details = payment['payment_details'];
      String? msg;
      if (details is List) {
        for (final d in details) {
          if (d is Map && d['key'] == 'message') msg = '${d['value']}';
        }
      }
      throw ShopException(msg ?? 'Payment failed. Please try another payment method.');
    }
    final totals = (j['totals'] as Map?)?.cast<String, dynamic>();
    final redirect = payment['redirect_url'] as String?;
    return OrderResult(
      orderId: (j['order_id'] as num).toInt(),
      status: '${j['status']}',
      orderKey: '${j['order_key'] ?? ''}',
      total: totals == null
          ? const Money(0)
          : Money.parse(totals['total_price'], CurrencyInfo.fromJson(totals)),
      redirectUrl: (redirect == null || redirect.isEmpty) ? null : redirect,
    );
  }

  Cart _cartFrom(http.Response res) => Cart.fromJson((_decode(res) as Map).cast<String, dynamic>());

  // ---------------------------------------------------------------- network

  Future<http.Response> _send(String method, String path, {Object? body, bool retry = true, bool withCart = true}) async {
    // Cart changes need a Cart-Token and Nonce: fetch them once, up front.
    if (method != 'GET' && withCart && retry && (_cartToken == null || _nonce == null)) {
      await _send('GET', '/cart', retry: false);
    }
    final uri = Uri.parse('$_base$path');
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      // Catalogue requests carry no cart token, so they are identical for
      // every shopper and can be served from the server / Cloudflare cache.
      if (withCart) 'Cart-Token': ?_cartToken,
      if (withCart) 'Nonce': ?_nonce,
    };
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    } on TimeoutException {
      if (retry && method == 'GET') return _send(method, path, retry: false, withCart: withCart);
      throw ShopException('The connection timed out. Please check your internet and try again.');
    } catch (_) {
      if (retry && method == 'GET') return _send(method, path, retry: false, withCart: withCart);
      throw ShopException('No internet connection. Please try again.');
    }

    if (!withCart) {
      if (res.statusCode >= 400) throw ShopException(_errorMessage(res), code: _errorCode(res));
      return res;
    }
    final token = res.headers['cart-token'];
    if (token != null && token.isNotEmpty && token != _cartToken) {
      _cartToken = token;
      unawaited(_prefs.setString(_tokenKey, token));
    }
    final nonce = res.headers['nonce'];
    if (nonce != null && nonce.isNotEmpty) _nonce = nonce;

    // An expired cart token: start a fresh cart once.
    if (res.statusCode == 401 || res.statusCode == 403) {
      final code = _errorCode(res);
      if (retry && (code?.contains('cart_token') == true || code == 'woocommerce_rest_missing_nonce')) {
        _cartToken = null;
        await _prefs.remove(_tokenKey);
        if (method != 'GET') await _send('GET', '/cart', retry: false);
        return _send(method, path, body: body, retry: false);
      }
    }
    if (res.statusCode >= 400) {
      throw ShopException(_errorMessage(res), code: _errorCode(res));
    }
    return res;
  }

  Object _decode(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Object;
    } catch (_) {
      throw ShopException('Unexpected response from the store. Please try again later.');
    }
  }

  String? _errorCode(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map)['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _errorMessage(http.Response res) {
    try {
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final msg = m['message'] as String?;
      if (msg != null && msg.isNotEmpty) {
        return msg.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&quot;', '"').replaceAll('&amp;', '&');
      }
    } catch (_) {}
    if (res.statusCode >= 500) return 'The store is temporarily unavailable. Please try again.';
    return 'Something went wrong (${res.statusCode}).';
  }
}

enum _Kind { products, product, categories }
