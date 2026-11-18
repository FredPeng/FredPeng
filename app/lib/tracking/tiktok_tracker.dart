import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';

import '../config.dart';
import 'tracker.dart';

/// TikTok ads via the TikTok Business (Events) SDK.
class TikTokPlatform implements AdPlatform {
  @override
  String get name => 'TikTok';

  @override
  Future<void> init() => TikTokEventsSdk.initSdk(
        androidAppId: AppConfig.tiktokAppId,
        tikTokAndroidId: AppConfig.tiktokAndroidId,
        iosAppId: AppConfig.iosAppStoreId,
        tiktokIosId: AppConfig.tiktokIosId,
        isDebugMode: AppConfig.debugTracking,
        logLevel: AppConfig.debugTracking ? TikTokLogLevel.debug : TikTokLogLevel.none,
        androidOptions: TikTokAndroidOptions(),
        iosOptions: TikTokIosOptions(),
      );

  @override
  Future<void> setEnabled(bool enabled) => TikTokEventsSdk.setTrackingEnabled(enabled: enabled);

  CurrencyCode? _cur(String code) {
    for (final c in CurrencyCode.values) {
      if (c.name == code) return c;
    }
    return null;
  }

  Future<void> _log(TTEventType type, {String? eventId, EventProperties? props}) => TikTokEventsSdk.logEvent(
        event: TikTokEvent(eventName: type.name, eventType: type, eventId: eventId, properties: props),
      );

  EventProperties _props(TrackItem i, String currency, {double? value}) => EventProperties(
        contentId: i.id,
        contentName: i.name,
        contentType: 'product',
        price: i.price,
        quantity: i.quantity,
        value: value ?? i.price * i.quantity,
        currency: _cur(currency),
      );

  @override
  Future<void> viewItem(TrackItem item, String currency) =>
      _log(TTEventType.viewContent, props: _props(item, currency));

  @override
  Future<void> search(String query) => TikTokEventsSdk.logEvent(
        event: TikTokEvent(
          eventName: 'Search',
          properties: EventProperties(customProperties: {'query': query}),
        ),
      );

  @override
  Future<void> addToCart(TrackItem item, String currency) =>
      _log(TTEventType.addToCart, props: _props(item, currency));

  @override
  Future<void> addToWishlist(TrackItem item, String currency) =>
      _log(TTEventType.addToWishlist, props: _props(item, currency));

  @override
  Future<void> beginCheckout(List<TrackItem> items, double value, String currency) => _log(
        TTEventType.checkout,
        props: EventProperties(
          contentType: 'product',
          contentId: items.map((i) => i.id).join(','),
          quantity: items.fold<int>(0, (n, i) => n + i.quantity),
          value: value,
          currency: _cur(currency),
        ),
      );

  @override
  Future<void> purchase(String orderId, List<TrackItem> items, double value, String currency) => _log(
        TTEventType.purchase,
        eventId: 'order_$orderId',
        props: EventProperties(
          contentType: 'product',
          contentId: items.map((i) => i.id).join(','),
          quantity: items.fold<int>(0, (n, i) => n + i.quantity),
          value: value,
          currency: _cur(currency),
          description: 'order $orderId',
        ),
      );

  @override
  Future<void> identify({String? phone, String? email, String? firstName, String? lastName}) =>
      TikTokEventsSdk.identify(
        identifier: TikTokIdentifier(
          externalId: phone ?? email ?? '',
          externalUserName: [firstName, lastName].whereType<String>().join(' '),
          phoneNumber: phone ?? '',
          email: email ?? '',
        ),
      );
}
