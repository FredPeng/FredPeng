import 'package:flutter/foundation.dart';

import '../data/shop_repository.dart';
import '../models/address.dart';
import '../models/cart.dart';
import '../models/product.dart';
import '../tracking/tracker.dart';

class CartModel extends ChangeNotifier {
  CartModel(this._repo, this._tracker);

  final ShopRepository _repo;
  final Tracker _tracker;

  Cart _cart = Cart.empty;
  Cart get cart => _cart;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Items being added right now (shown immediately in the badge).
  int _pending = 0;
  int get count => _cart.count + _pending;

  final Set<String> _busy = {};
  bool isBusy(String key) => _busy.contains(key);

  Future<void> load() async {
    try {
      _cart = await _repo.cart();
    } catch (_) {
      // Offline at launch: keep the empty cart; it syncs on the next action.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Adds to cart. Returns null on success, or a message to show.
  Future<String?> add(Product p, {int quantity = 1, int? variationId, Map<String, String> options = const {}}) async {
    _pending += quantity;
    notifyListeners();
    try {
      _cart = await _repo.addToCart(variationId ?? p.id, quantity, options: options);
      _tracker.addToCart(TrackItem(
        id: '${p.id}',
        name: p.name,
        price: p.price.value,
        quantity: quantity,
        category: p.categories.isEmpty ? null : p.categories.first.name,
      ));
      return null;
    } on ShopException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not add to cart. Please try again.';
    } finally {
      _pending -= quantity;
      notifyListeners();
    }
  }

  Future<String?> setQuantity(CartItem item, int quantity) async {
    if (quantity < 1) return remove(item);
    return _mutate(item.key, () => _repo.updateItem(item.key, quantity), optimistic: () {
      _cart = Cart(
        items: [for (final i in _cart.items) i.key == item.key ? i.copyWith(quantity: quantity) : i],
        subtotal: _cart.subtotal,
        shipping: _cart.shipping,
        discount: _cart.discount,
        total: _cart.total,
        paymentMethods: _cart.paymentMethods,
        shippingRates: _cart.shippingRates,
        needsShipping: _cart.needsShipping,
      );
    });
  }

  Future<String?> remove(CartItem item) => _mutate(item.key, () => _repo.removeItem(item.key), optimistic: () {
        _cart = Cart(
          items: [for (final i in _cart.items) if (i.key != item.key) i],
          subtotal: _cart.subtotal,
          shipping: _cart.shipping,
          discount: _cart.discount,
          total: _cart.total,
          paymentMethods: _cart.paymentMethods,
          shippingRates: _cart.shippingRates,
          needsShipping: _cart.needsShipping,
        );
      });

  Future<String?> updateCustomer(Address a) => _mutate('customer', () => _repo.updateCustomer(a));

  Future<String?> selectRate(ShippingRate r) =>
      _mutate('shipping', () => _repo.selectShippingRate(r.packageId, r.rateId));

  Future<String?> applyCoupon(String code) => _mutate('coupon', () => _repo.applyCoupon(code));

  Future<OrderResult> checkout(Address address, String paymentMethod, {String note = ''}) async {
    final items = trackItems;
    final value = _cart.total.value;
    final result = await _repo.checkout(address, paymentMethod, note: note);
    _tracker.identify(phone: address.phone, email: address.email, firstName: address.firstName, lastName: address.lastName);
    _tracker.purchase('${result.orderId}', items, result.total.isZero ? value : result.total.value);
    _cart = Cart.empty;
    notifyListeners();
    // Refresh in the background (the server has emptied the cart).
    load();
    return result;
  }

  List<TrackItem> get trackItems => [
        for (final i in _cart.items)
          TrackItem(id: '${i.productId}', name: i.name, price: i.unitPrice.value, quantity: i.quantity),
      ];

  Future<String?> _mutate(String key, Future<Cart> Function() call, {VoidCallback? optimistic}) async {
    final before = _cart;
    _busy.add(key);
    optimistic?.call();
    notifyListeners();
    try {
      _cart = await call();
      return null;
    } on ShopException catch (e) {
      _cart = before;
      return e.message;
    } catch (_) {
      _cart = before;
      return 'Something went wrong. Please try again.';
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }
}
