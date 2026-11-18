import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/address.dart';
import '../models/product.dart';
import '../tracking/tracker.dart';

class WishItem {
  const WishItem({required this.id, required this.name, required this.price, this.image});
  final int id;
  final String name;
  final String price;
  final String? image;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price, 'image': image};
  factory WishItem.fromJson(Map<String, dynamic> j) => WishItem(
        id: (j['id'] as num).toInt(),
        name: '${j['name']}',
        price: '${j['price']}',
        image: j['image'] as String?,
      );
}

/// Wishlist saved on the device (no account needed).
class WishlistModel extends ChangeNotifier {
  WishlistModel(this._prefs, this._tracker) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _items.addAll([for (final j in jsonDecode(raw) as List) WishItem.fromJson((j as Map).cast<String, dynamic>())]);
      } catch (_) {}
    }
  }

  static const _key = 'wishlist';
  final SharedPreferences _prefs;
  final Tracker _tracker;
  final List<WishItem> _items = [];

  List<WishItem> get items => List.unmodifiable(_items);
  bool contains(int id) => _items.any((i) => i.id == id);

  void toggle(Product p) {
    if (contains(p.id)) {
      _items.removeWhere((i) => i.id == p.id);
    } else {
      _items.insert(0, WishItem(id: p.id, name: p.name, price: p.displayPrice, image: p.thumbnail));
      _tracker.addToWishlist(TrackItem(id: '${p.id}', name: p.name, price: p.price.value));
    }
    _save();
  }

  void remove(int id) {
    _items.removeWhere((i) => i.id == id);
    _save();
  }

  void _save() {
    _prefs.setString(_key, jsonEncode([for (final i in _items) i.toJson()]));
    notifyListeners();
  }
}

/// Saved checkout details, order history, recent searches and privacy choice.
class ProfileModel extends ChangeNotifier {
  ProfileModel(this._prefs) {
    final a = _prefs.getString('address');
    if (a != null) {
      try {
        _address = Address.fromJson((jsonDecode(a) as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    final o = _prefs.getString('orders');
    if (o != null) {
      try {
        _orders.addAll([for (final j in jsonDecode(o) as List) OrderRecord.fromJson((j as Map).cast<String, dynamic>())]);
      } catch (_) {}
    }
    _searches.addAll(_prefs.getStringList('searches') ?? const []);
  }

  final SharedPreferences _prefs;

  Address _address = const Address();
  Address get address => _address;

  final List<OrderRecord> _orders = [];
  List<OrderRecord> get orders => List.unmodifiable(_orders);

  final List<String> _searches = [];
  List<String> get recentSearches => List.unmodifiable(_searches);

  bool get adsConsent => _prefs.getBool('ads_consent') ?? true;

  void saveAddress(Address a) {
    _address = a;
    _prefs.setString('address', jsonEncode(a.toJson()));
    notifyListeners();
  }

  void addOrder(OrderRecord o) {
    _orders.insert(0, o);
    _prefs.setString('orders', jsonEncode([for (final x in _orders.take(50)) x.toJson()]));
    notifyListeners();
  }

  void addSearch(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    _searches
      ..remove(q)
      ..insert(0, q);
    if (_searches.length > 8) _searches.removeLast();
    _prefs.setStringList('searches', _searches);
    notifyListeners();
  }

  void clearSearches() {
    _searches.clear();
    _prefs.remove('searches');
    notifyListeners();
  }

  Future<void> setAdsConsent(bool v, Tracker tracker) async {
    await _prefs.setBool('ads_consent', v);
    await tracker.setEnabled(v);
    notifyListeners();
  }
}
