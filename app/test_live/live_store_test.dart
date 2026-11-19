// Live checks against the real store. Not part of `flutter test`; run with:
//   flutter test test_live --dart-define=STORE_URL=https://sophie.co.ke
// Adds one item to a guest cart and removes it again. Never places an order.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie_shop/data/disk_cache.dart';
import 'package:sophie_shop/data/store_api.dart';
import 'package:sophie_shop/models/product.dart';

class _Net extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final ca = Platform.environment['SSL_CERT_FILE'] ?? '/root/.ccr/ca-bundle.crt';
    final ctx = File(ca).existsSync() ? (SecurityContext()..setTrustedCertificates(ca)) : context;
    return super.createHttpClient(ctx)..findProxy = HttpClient.findProxyFromEnvironment;
  }
}

void main() {
  const url = String.fromEnvironment('STORE_URL', defaultValue: 'https://sophie.co.ke');
  late StoreApi api;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _Net();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    api = StoreApi(url, await SharedPreferences.getInstance(), MemoryOnlyCache());
  });

  Future<T> timed<T>(String label, Future<T> Function() f) async {
    final sw = Stopwatch()..start();
    final r = await f();
    // ignore: avoid_print
    print('$label: ${sw.elapsedMilliseconds} ms');
    return r;
  }

  test('catalogue', () async {
    final page = await timed('products page 1', () => api.products(const ProductQuery()));
    expect(page.items, isNotEmpty);
    expect(page.totalPages, greaterThan(1));
    final p = page.items.first;
    expect(p.name, isNotEmpty);
    expect(p.price.format(), startsWith('KSh'));
    await timed('products page 1 (memory cache)', () => api.products(const ProductQuery()));
    await timed('products page 2', () => api.products(const ProductQuery(), page: 2));

    final top = await timed('top-level categories', () => api.categories(parent: 0));
    expect(top.length, inInclusiveRange(5, 60));
    final subs = await timed('sub-categories of ${top.first.name}', () => api.categories(parent: top.first.id));
    expect(subs, isA<List<Category>>());

    final bySlug = await timed('category by slug', () => api.products(ProductQuery(categorySlug: top.first.slug)));
    expect(bySlug.items, isNotEmpty);

    final full = await timed('product detail', () => api.product(p.id));
    expect(full.id, p.id);
    final variable = page.items.where((x) => x.type == 'variable').firstOrNull;
    if (variable != null) {
      final v = await api.product(variable.id);
      // ignore: avoid_print
      print('variable product ${v.id}: ${v.variationAttributes.map((a) => '${a.name}(${a.terms.length})')} '
          '${v.variations.length} variations');
      expect(v.variations, isNotEmpty);
    }
    final slugged = await timed('product by slug', () => api.productBySlug(p.slug));
    expect(slugged?.id, p.id);
  });

  test('cart round trip (no order placed)', () async {
    expect((await api.cart()).isEmpty, isTrue); // no request without a token
    final page = await api.products(const ProductQuery(sort: ProductSort.priceLow));
    final simple = page.items.firstWhere((p) => p.type == 'simple' && p.inStock && p.purchasable);
    final cart = await timed('add to cart', () => api.addToCart(simple.id, 1));
    expect(cart.items.single.productId, simple.id);
    // ignore: avoid_print
    print('cart total ${cart.total.format()}, payment methods ${cart.paymentMethods}');
    final empty = await timed('remove from cart', () => api.removeItem(cart.items.single.key));
    expect(empty.isEmpty, isTrue);
  });
}
