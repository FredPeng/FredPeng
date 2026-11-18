import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import 'tracker.dart';

/// Google: Firebase Analytics. Link the Firebase project to Google Ads and
/// import `purchase` as a conversion to run App Campaigns optimised for sales.
///
/// Enabled when `android/app/google-services.json` exists at build time;
/// otherwise Firebase.initializeApp() throws and this platform is skipped.
class FirebasePlatform implements AdPlatform {
  late final FirebaseAnalytics _fa;

  @override
  String get name => 'Google';

  @override
  Future<void> init() async {
    await Firebase.initializeApp();
    _fa = FirebaseAnalytics.instance;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    await _fa.setAnalyticsCollectionEnabled(enabled);
    await _fa.setConsent(
      adStorageConsentGranted: enabled,
      analyticsStorageConsentGranted: enabled,
      adUserDataConsentGranted: enabled,
      adPersonalizationSignalsConsentGranted: enabled,
    );
  }

  AnalyticsEventItem _item(TrackItem i) => AnalyticsEventItem(
        itemId: i.id,
        itemName: i.name,
        itemCategory: i.category,
        price: i.price,
        quantity: i.quantity,
      );

  @override
  Future<void> viewItem(TrackItem item, String currency) =>
      _fa.logViewItem(currency: currency, value: item.price, items: [_item(item)]);

  @override
  Future<void> search(String query) => _fa.logSearch(searchTerm: query);

  @override
  Future<void> addToCart(TrackItem item, String currency) =>
      _fa.logAddToCart(currency: currency, value: item.price * item.quantity, items: [_item(item)]);

  @override
  Future<void> addToWishlist(TrackItem item, String currency) =>
      _fa.logAddToWishlist(currency: currency, value: item.price, items: [_item(item)]);

  @override
  Future<void> beginCheckout(List<TrackItem> items, double value, String currency) =>
      _fa.logBeginCheckout(currency: currency, value: value, items: items.map(_item).toList());

  @override
  Future<void> purchase(String orderId, List<TrackItem> items, double value, String currency) => _fa.logPurchase(
        transactionId: orderId,
        currency: currency,
        value: value,
        items: items.map(_item).toList(),
      );

  @override
  Future<void> identify({String? phone, String? email, String? firstName, String? lastName}) async {
    // Google Ads enhanced conversions for apps use hashed data configured in
    // the Firebase console; nothing personal is sent from here.
  }
}
