import 'package:appsflyer_sdk/appsflyer_sdk.dart';

import '../config.dart';
import 'tracker.dart';

/// AppsFlyer mobile measurement partner (MMP).
///
/// X (Twitter) does not ship an app-events SDK of its own: X app campaigns
/// receive installs and in-app conversions from an MMP. Enable "X Ads" as an
/// integrated partner in AppsFlyer and these events flow to X. The same
/// integration can also feed Snapchat, Pinterest, etc. without app changes.
class AppsFlyerPlatform implements AdPlatform {
  final _af = AppsFlyerSdk.instance;

  @override
  String get name => 'AppsFlyer (X)';

  @override
  Future<void> init() async {
    await _af.init(devKey: AppConfig.appsflyerDevKey, appId: AppConfig.iosAppStoreId);
    await _af.start();
  }

  @override
  Future<void> setEnabled(bool enabled) => _af.stop(!enabled);

  Map<String, dynamic> _item(TrackItem i, String currency) => {
        'af_content_id': i.id,
        'af_content_type': 'product',
        'af_price': i.price,
        'af_quantity': i.quantity,
        'af_currency': currency,
      };

  @override
  Future<void> viewItem(TrackItem item, String currency) =>
      _af.logEvent('af_content_view', eventValues: _item(item, currency));

  @override
  Future<void> search(String query) =>
      _af.logEvent('af_search', eventValues: {'af_search_string': query});

  @override
  Future<void> addToCart(TrackItem item, String currency) =>
      _af.logEvent('af_add_to_cart', eventValues: _item(item, currency));

  @override
  Future<void> addToWishlist(TrackItem item, String currency) =>
      _af.logEvent('af_add_to_wishlist', eventValues: _item(item, currency));

  @override
  Future<void> beginCheckout(List<TrackItem> items, double value, String currency) =>
      _af.logEvent('af_initiated_checkout', eventValues: {
        'af_price': value,
        'af_currency': currency,
        'af_content_id': items.map((i) => i.id).toList(),
        'af_quantity': items.fold<int>(0, (n, i) => n + i.quantity),
      });

  @override
  Future<void> purchase(String orderId, List<TrackItem> items, double value, String currency) =>
      _af.logEvent('af_purchase', eventValues: {
        'af_revenue': value,
        'af_currency': currency,
        'af_order_id': orderId,
        'af_content_id': items.map((i) => i.id).toList(),
        'af_quantity': items.fold<int>(0, (n, i) => n + i.quantity),
      });

  @override
  Future<void> identify({String? phone, String? email, String? firstName, String? lastName}) async {
    if (phone != null && phone.isNotEmpty) await _af.setCustomerUserId(phone);
  }
}
