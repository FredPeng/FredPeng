import 'dart:async';

import '../models/address.dart';
import '../models/cart.dart';
import '../models/money.dart';
import '../models/product.dart';
import 'shop_repository.dart';

/// Offline catalogue used when no STORE_URL is configured, so the app can be
/// tried, demoed and screenshotted without a live WooCommerce site.
class DemoStore implements ShopRepository {
  DemoStore() {
    _products = _seed();
  }

  static const _cur = CurrencyInfo.kes;
  static const _latency = Duration(milliseconds: 250);

  late final List<Product> _products;
  final List<CartItem> _items = [];
  int _shippingFee = 25000;
  bool _shippingKnown = false;
  int _nextOrder = 10231;

  static final _cats = [
    const Category(id: 1, name: 'Dresses', slug: 'dresses', parent: 0, count: 4),
    const Category(id: 2, name: 'Shoes', slug: 'shoes', parent: 0, count: 3),
    const Category(id: 3, name: 'Bags', slug: 'bags', parent: 0, count: 3),
    const Category(id: 4, name: 'Beauty', slug: 'beauty', parent: 0, count: 3),
    const Category(id: 5, name: 'Home', slug: 'home', parent: 0, count: 3),
  ];

  List<Product> _seed() {
    Product p(int id, String name, int cat, int price, {int? was, bool sizes = false, String? desc}) {
      final c = _cats.firstWhere((c) => c.id == cat);
      final attrs = sizes
          ? [
              const ProductAttribute(
                name: 'Size',
                taxonomy: 'pa_size',
                hasVariations: true,
                terms: [
                  AttributeTerm(name: 'S', slug: 's'),
                  AttributeTerm(name: 'M', slug: 'm'),
                  AttributeTerm(name: 'L', slug: 'l'),
                  AttributeTerm(name: 'XL', slug: 'xl'),
                ],
              ),
            ]
          : <ProductAttribute>[];
      return Product(
        id: id,
        name: name,
        slug: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        permalink: '',
        type: sizes ? 'variable' : 'simple',
        price: Money(price * 100, _cur),
        regularPrice: Money((was ?? price) * 100, _cur),
        images: [
          for (var i = 0; i < 3; i++)
            ProductImage(
              src: 'https://picsum.photos/seed/sophie$id$i/900/900',
              thumbnail: 'https://picsum.photos/seed/sophie$id$i/400/400',
            ),
        ],
        categories: [CategoryRef(id: c.id, name: c.name, slug: c.slug)],
        onSale: was != null,
        inStock: true,
        purchasable: true,
        hasOptions: sizes,
        attributes: attrs,
        variations: sizes
            ? [
                for (final (i, s) in ['s', 'm', 'l', 'xl'].indexed)
                  Variation(id: id * 100 + i, attributes: {'Size': s}),
              ]
            : const [],
        shortDescription: desc ?? 'Quality you can feel, at a price you will love. Delivered to your door.',
        description: '${desc ?? 'Quality you can feel, at a price you will love.'}\n\n'
            '• Carefully selected by Sophie\n• Pay on delivery available\n• Easy exchange within 7 days',
        rating: 4.0 + (id % 10) / 10,
        reviewCount: 12 + id * 3,
      );
    }

    return [
      p(101, 'Floral Wrap Midi Dress', 1, 2499, was: 3299, sizes: true),
      p(102, 'Linen Shirt Dress', 1, 2899, sizes: true),
      p(103, 'Satin Slip Evening Dress', 1, 3999, was: 4999, sizes: true),
      p(104, 'Kitenge Print Maxi Dress', 1, 3499, sizes: true),
      p(201, 'White Leather Sneakers', 2, 3299, was: 3999),
      p(202, 'Block Heel Sandals', 2, 2199),
      p(203, 'Everyday Ballet Flats', 2, 1799, was: 2299),
      p(301, 'Woven Straw Tote', 3, 1999),
      p(302, 'Mini Crossbody Bag', 3, 1499, was: 1899),
      p(303, 'Classic Leather Handbag', 3, 4599),
      p(401, 'Shea Butter Body Cream', 4, 899),
      p(402, 'Matte Lipstick Set (3)', 4, 1299, was: 1599),
      p(403, 'Rose Water Face Mist', 4, 699),
      p(501, 'Scented Soy Candle', 5, 999),
      p(502, 'Cotton Throw Blanket', 5, 2499, was: 2999),
      p(503, 'Ceramic Mug Set (4)', 5, 1599),
    ];
  }

  @override
  Future<ProductPage> products(ProductQuery query, {int page = 1, int perPage = 20}) async {
    await Future<void>.delayed(_latency);
    var list = _products.where((p) {
      if (query.categoryId != null && !p.categories.any((c) => c.id == query.categoryId)) return false;
      if (query.onSale && !p.onSale) return false;
      if (query.include != null && !query.include!.contains(p.id)) return false;
      final s = query.search?.trim().toLowerCase();
      if (s != null && s.isNotEmpty && !p.name.toLowerCase().contains(s)) return false;
      return true;
    }).toList();
    switch (query.sort) {
      case ProductSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case ProductSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case ProductSort.newest:
        list = list.reversed.toList();
      case ProductSort.popular:
        list.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
    }
    final pages = (list.length / perPage).ceil().clamp(1, 999);
    final start = (page - 1) * perPage;
    return ProductPage(start >= list.length ? [] : list.sublist(start, (start + perPage).clamp(0, list.length)), pages);
  }

  @override
  Future<Product> product(int id) async {
    await Future<void>.delayed(_latency);
    return _products.firstWhere((p) => p.id == id, orElse: () => throw ShopException('Product not found'));
  }

  @override
  Future<Product?> productBySlug(String slug) async {
    await Future<void>.delayed(_latency);
    for (final p in _products) {
      if (p.slug == slug) return p;
    }
    return null;
  }

  @override
  Future<List<Category>> categories() async {
    await Future<void>.delayed(_latency);
    return _cats;
  }

  Cart _cart() {
    final sub = _items.fold<Money>(const Money(0, _cur), (m, i) => m + i.lineTotal);
    final ship = _items.isEmpty || !_shippingKnown ? null : Money(_shippingFee, _cur);
    return Cart(
      items: List.unmodifiable(_items),
      subtotal: sub,
      shipping: ship,
      total: sub + (ship ?? const Money(0, _cur)),
      paymentMethods: const ['cod', 'mpesa'],
      shippingRates: _shippingKnown && _items.isNotEmpty
          ? [
              ShippingRate(
                packageId: 0,
                rateId: 'flat_rate:1',
                name: 'Standard delivery (1–3 days)',
                price: const Money(25000, _cur),
                selected: _shippingFee == 25000,
              ),
              ShippingRate(
                packageId: 0,
                rateId: 'local_pickup:2',
                name: 'Pick up in store',
                price: const Money(0, _cur),
                selected: _shippingFee == 0,
              ),
            ]
          : const [],
    );
  }

  @override
  Future<Cart> cart() async => _cart();

  @override
  Future<Cart> addToCart(int productId, int quantity, {Map<String, String> options = const {}}) async {
    await Future<void>.delayed(_latency);
    final parent = _products.firstWhere(
      (p) => p.id == productId || p.variations.any((v) => v.id == productId),
      orElse: () => throw ShopException('Product not found'),
    );
    final key = '$productId';
    final idx = _items.indexWhere((i) => i.key == key);
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(quantity: _items[idx].quantity + quantity);
    } else {
      _items.add(CartItem(
        key: key,
        productId: parent.id,
        name: parent.name,
        quantity: quantity,
        unitPrice: parent.price,
        lineTotal: parent.price * quantity,
        image: parent.thumbnail,
        options: options.entries.map((e) => '${e.key.replaceFirst('pa_', '').toUpperCase()[0]}${e.key.replaceFirst('pa_', '').substring(1)}: ${e.value.toUpperCase()}').join(' · '),
      ));
    }
    return _cart();
  }

  @override
  Future<Cart> updateItem(String key, int quantity) async {
    await Future<void>.delayed(_latency);
    final idx = _items.indexWhere((i) => i.key == key);
    if (idx >= 0) _items[idx] = _items[idx].copyWith(quantity: quantity);
    return _cart();
  }

  @override
  Future<Cart> removeItem(String key) async {
    await Future<void>.delayed(_latency);
    _items.removeWhere((i) => i.key == key);
    return _cart();
  }

  @override
  Future<Cart> updateCustomer(Address address) async {
    await Future<void>.delayed(_latency);
    _shippingKnown = address.county.isNotEmpty;
    return _cart();
  }

  @override
  Future<Cart> selectShippingRate(int packageId, String rateId) async {
    _shippingFee = rateId.startsWith('local_pickup') ? 0 : 25000;
    return _cart();
  }

  @override
  Future<Cart> applyCoupon(String code) async {
    await Future<void>.delayed(_latency);
    throw ShopException('Coupon "$code" does not exist!');
  }

  @override
  Future<OrderResult> checkout(Address address, String paymentMethod, {String note = ''}) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (_items.isEmpty) throw ShopException('Your cart is empty.');
    final total = _cart().total;
    _items.clear();
    _shippingKnown = false;
    return OrderResult(orderId: _nextOrder++, status: 'processing', total: total);
  }
}
