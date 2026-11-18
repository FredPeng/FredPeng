import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/address.dart';
import '../models/cart.dart';
import '../models/money.dart';
import '../models/product.dart';
import 'shop_repository.dart';

/// Client for the WooCommerce Store API (`/wp-json/wc/store/v1`).
///
/// The Store API is the public, customer-facing API that WooCommerce Blocks
/// use: no admin keys are needed in the app. The cart lives on the server and
/// is identified by a `Cart-Token`, so a customer's cart is the same cart
/// WooCommerce checks out (stock, coupons, shipping zones all apply).
class StoreApi implements ShopRepository {
  StoreApi(String storeUrl, this._prefs, {http.Client? client})
      : _base = '${storeUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json/wc/store/v1',
        _http = client ?? http.Client() {
    _cartToken = _prefs.getString(_tokenKey);
  }

  static const _tokenKey = 'cart_token';
  static const _diskPrefix = 'cache:';
  static const _timeout = Duration(seconds: 20);
  static const _memoryTtl = Duration(minutes: 5);

  final String _base;
  final http.Client _http;
  final SharedPreferences _prefs;
  String? _cartToken;
  String? _nonce;

  final _memory = <String, ({DateTime at, Object data, int totalPages})>{};

  // ---------------------------------------------------------------- catalog

  String _productsPath(ProductQuery q, int page, int perPage) {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'orderby': q.sort.orderBy,
      'order': q.sort.order,
      if (q.categoryId != null) 'category': '${q.categoryId}',
      if (q.search != null && q.search!.isNotEmpty) 'search': q.search!,
      if (q.onSale) 'on_sale': 'true',
      if (q.featured) 'featured': 'true',
      if (q.include != null) 'include': q.include!.join(','),
      'stock_status': 'instock,onbackorder',
    };
    return '/products?${Uri(queryParameters: params).query}';
  }

  /// Returns a cached page instantly (memory, then disk) so screens can render
  /// before the network answers. Only the first page is persisted to disk.
  ProductPage? peekProducts(ProductQuery q, {int page = 1, int perPage = 20}) {
    final path = _productsPath(q, page, perPage);
    final mem = _memory[path];
    if (mem != null) return ProductPage(_parseProducts(mem.data), mem.totalPages);
    final disk = _prefs.getString('$_diskPrefix$path');
    if (disk == null) return null;
    try {
      final m = jsonDecode(disk) as Map<String, dynamic>;
      return ProductPage(_parseProducts(m['data']!), (m['pages'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  List<Category>? peekCategories() {
    final disk = _prefs.getString('$_diskPrefix/products/categories');
    if (disk == null) return null;
    try {
      return _parseCategories((jsonDecode(disk) as Map)['data']!);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ProductPage> products(ProductQuery query, {int page = 1, int perPage = 20}) async {
    final path = _productsPath(query, page, perPage);
    final res = await _cachedGet(path, persist: page == 1 && query.search == null);
    return ProductPage(_parseProducts(res.data), res.totalPages);
  }

  @override
  Future<Product> product(int id) async {
    final res = await _cachedGet('/products/$id');
    return Product.fromJson((res.data as Map).cast<String, dynamic>());
  }

  @override
  Future<Product?> productBySlug(String slug) async {
    final res = await _cachedGet('/products?slug=${Uri.encodeQueryComponent(slug)}');
    final list = _parseProducts(res.data);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<List<Category>> categories() async {
    final res = await _cachedGet('/products/categories', persist: true);
    return _parseCategories(res.data);
  }

  List<Product> _parseProducts(Object data) => [
        for (final p in data as List) Product.fromJson((p as Map).cast<String, dynamic>()),
      ];

  List<Category> _parseCategories(Object data) => [
        for (final c in data as List) Category.fromJson((c as Map).cast<String, dynamic>()),
      ]
        ..removeWhere((c) => c.count == 0 || c.slug == 'uncategorized');

  Future<({Object data, int totalPages})> _cachedGet(String path, {bool persist = false}) async {
    final mem = _memory[path];
    if (mem != null && DateTime.now().difference(mem.at) < _memoryTtl) {
      return (data: mem.data, totalPages: mem.totalPages);
    }
    final res = await _send('GET', path);
    final data = _decode(res);
    final pages = int.tryParse(res.headers['x-wp-totalpages'] ?? '') ?? 1;
    _memory[path] = (at: DateTime.now(), data: data, totalPages: pages);
    if (persist) {
      unawaited(_prefs.setString('$_diskPrefix$path', jsonEncode({'data': data, 'pages': pages})));
    }
    return (data: data, totalPages: pages);
  }

  // ------------------------------------------------------------------- cart

  @override
  Future<Cart> cart() async => _cartFrom(await _send('GET', '/cart'));

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

  Future<http.Response> _send(String method, String path, {Object? body, bool retry = true}) async {
    final uri = Uri.parse('$_base$path');
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      'Cart-Token': ?_cartToken,
      'Nonce': ?_nonce,
    };
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    } on TimeoutException {
      if (retry && method == 'GET') return _send(method, path, retry: false);
      throw ShopException('The connection timed out. Please check your internet and try again.');
    } catch (_) {
      if (retry && method == 'GET') return _send(method, path, retry: false);
      throw ShopException('No internet connection. Please try again.');
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
