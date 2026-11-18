import 'package:facebook_app_events/facebook_app_events.dart';

import 'tracker.dart';

/// Meta (Facebook & Instagram ads) via the Facebook App Events SDK.
/// The App ID / Client Token are injected into AndroidManifest by Gradle.
class MetaPlatform implements AdPlatform {
  final _fb = FacebookAppEvents();

  @override
  String get name => 'Meta';

  @override
  Future<void> init() async {
    await _fb.setAutoLogAppEventsEnabled(true);
    await _fb.setAdvertiserIdCollectionEnabled(true);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    await _fb.setAutoLogAppEventsEnabled(enabled);
    await _fb.setAdvertiserIdCollectionEnabled(enabled);
  }

  @override
  Future<void> viewItem(TrackItem item, String currency) =>
      _fb.logViewContent(id: item.id, type: 'product', currency: currency, price: item.price);

  @override
  Future<void> search(String query) =>
      _fb.logEvent(name: 'fb_mobile_search', parameters: {'fb_search_string': query, 'fb_content_type': 'product'});

  @override
  Future<void> addToCart(TrackItem item, String currency) =>
      _fb.logAddToCart(id: item.id, type: 'product', currency: currency, price: item.price * item.quantity);

  @override
  Future<void> addToWishlist(TrackItem item, String currency) =>
      _fb.logAddToWishlist(id: item.id, type: 'product', currency: currency, price: item.price);

  @override
  Future<void> beginCheckout(List<TrackItem> items, double value, String currency) => _fb.logInitiatedCheckout(
        totalPrice: value,
        currency: currency,
        contentType: 'product',
        contentId: items.map((i) => i.id).join(','),
        numItems: items.fold<int>(0, (n, i) => n + i.quantity),
      );

  @override
  Future<void> purchase(String orderId, List<TrackItem> items, double value, String currency) => _fb.logPurchase(
        amount: value,
        currency: currency,
        parameters: {
          'fb_content_type': 'product',
          'fb_content_id': items.map((i) => i.id).join(','),
          'fb_num_items': items.fold<int>(0, (n, i) => n + i.quantity),
          'fb_order_id': orderId,
        },
      );

  @override
  Future<void> identify({String? phone, String? email, String? firstName, String? lastName}) => _fb.setUserData(
        phone: phone,
        email: email,
        firstName: firstName,
        lastName: lastName,
      );
}
