import 'html.dart';
import 'money.dart';

class CartItem {
  const CartItem({
    required this.key,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.image,
    this.options = '',
    this.maxQuantity = 99,
  });

  final String key;
  final int productId;
  final String name;
  final int quantity;
  final Money unitPrice;
  final Money lineTotal;
  final String? image;

  /// e.g. "Size: M · Colour: Red"
  final String options;
  final int maxQuantity;

  CartItem copyWith({int? quantity}) => CartItem(
        key: key,
        productId: productId,
        name: name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice,
        lineTotal: unitPrice * (quantity ?? this.quantity),
        image: image,
        options: options,
        maxQuantity: maxQuantity,
      );

  factory CartItem.fromJson(Map<String, dynamic> j, CurrencyInfo totalsCur) {
    final prices = (j['prices'] as Map?)?.cast<String, dynamic>() ?? const {};
    final totals = (j['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final priceCur = prices.isEmpty ? totalsCur : CurrencyInfo.fromJson(prices);
    final images = (j['images'] as List?) ?? const [];
    final limits = (j['quantity_limits'] as Map?)?.cast<String, dynamic>();
    final variation = (j['variation'] as List?) ?? const [];
    return CartItem(
      key: (j['key'] as String?) ?? '',
      productId: (j['id'] as num).toInt(),
      name: decodeEntities((j['name'] as String?) ?? ''),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: Money.parse(prices['price'], priceCur),
      lineTotal: Money.parse(totals['line_subtotal'] ?? totals['line_total'], totalsCur),
      image: images.isEmpty
          ? null
          : ((images.first as Map)['thumbnail'] as String?) ?? ((images.first as Map)['src'] as String?),
      options: variation
          .map((v) => '${decodeEntities('${v['attribute']}')}: ${decodeEntities('${v['value']}')}')
          .join(' · '),
      maxQuantity: (limits?['maximum'] as num?)?.toInt() ?? 99,
    );
  }
}

class ShippingRate {
  const ShippingRate({
    required this.packageId,
    required this.rateId,
    required this.name,
    required this.price,
    required this.selected,
  });

  final int packageId;
  final String rateId;
  final String name;
  final Money price;
  final bool selected;
}

class Cart {
  const Cart({
    this.items = const [],
    this.subtotal = const Money(0),
    this.shipping,
    this.discount = const Money(0),
    this.total = const Money(0),
    this.paymentMethods = const ['cod'],
    this.shippingRates = const [],
    this.needsShipping = true,
  });

  final List<CartItem> items;
  final Money subtotal;
  final Money? shipping;
  final Money discount;
  final Money total;
  final List<String> paymentMethods;
  final List<ShippingRate> shippingRates;
  final bool needsShipping;

  static const empty = Cart();

  bool get isEmpty => items.isEmpty;
  int get count => items.fold(0, (n, i) => n + i.quantity);
  CurrencyInfo get currency => total.currency;

  factory Cart.fromJson(Map<String, dynamic> j) {
    final totals = (j['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cur = CurrencyInfo.fromJson(totals);
    final rates = <ShippingRate>[];
    for (final pkg in (j['shipping_rates'] as List? ?? const [])) {
      final pid = (pkg['package_id'] as num?)?.toInt() ?? 0;
      for (final r in (pkg['shipping_rates'] as List? ?? const [])) {
        final rcur = r is Map && r['currency_code'] != null
            ? CurrencyInfo.fromJson(r.cast<String, dynamic>())
            : cur;
        rates.add(ShippingRate(
          packageId: pid,
          rateId: '${r['rate_id']}',
          name: decodeEntities('${r['name']}'),
          price: Money.parse(r['price'], rcur),
          selected: r['selected'] == true,
        ));
      }
    }
    final shipping = totals['total_shipping'];
    return Cart(
      items: [
        for (final i in (j['items'] as List? ?? const []))
          CartItem.fromJson((i as Map).cast<String, dynamic>(), cur),
      ],
      subtotal: Money.parse(totals['total_items'], cur),
      shipping: shipping == null ? null : Money.parse(shipping, cur),
      discount: Money.parse(totals['total_discount'], cur),
      total: Money.parse(totals['total_price'], cur),
      paymentMethods: [for (final p in (j['payment_methods'] as List? ?? const ['cod'])) '$p'],
      shippingRates: rates,
      needsShipping: (j['needs_shipping'] as bool?) ?? true,
    );
  }
}

/// Result of placing an order.
class OrderResult {
  const OrderResult({
    required this.orderId,
    required this.status,
    required this.total,
    this.redirectUrl,
    this.orderKey = '',
  });

  final int orderId;
  final String status;
  final Money total;
  final String? redirectUrl;
  final String orderKey;
}
