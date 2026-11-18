import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import 'appsflyer_tracker.dart';
import 'firebase_tracker.dart';
import 'meta_tracker.dart';
import 'tiktok_tracker.dart';

/// One product line in an analytics event.
class TrackItem {
  const TrackItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.category,
  });

  final String id;
  final String name;
  final double price;
  final int quantity;
  final String? category;
}

/// The standard e-commerce events every ad platform optimises for.
///
/// Each platform adapter maps these onto its own standard event names, so ad
/// campaigns can optimise for purchases (not just installs) and build
/// retargeting audiences (viewed but did not buy, added to cart, ...).
abstract class AdPlatform {
  String get name;
  Future<void> init();
  Future<void> setEnabled(bool enabled);
  Future<void> viewItem(TrackItem item, String currency);
  Future<void> search(String query);
  Future<void> addToCart(TrackItem item, String currency);
  Future<void> addToWishlist(TrackItem item, String currency);
  Future<void> beginCheckout(List<TrackItem> items, double value, String currency);
  Future<void> purchase(String orderId, List<TrackItem> items, double value, String currency);
  Future<void> identify({String? phone, String? email, String? firstName, String? lastName});
}

/// What the app calls. Implementations: [MultiTracker] (real SDKs),
/// [LazyTracker] (queues until SDKs are ready) and [Tracker.none].
abstract class Tracker {
  /// No-op tracker for tests and previews.
  factory Tracker.none() => MultiTracker._(const []);

  List<String> get activePlatforms;
  Future<void> setEnabled(bool enabled);
  void viewItem(TrackItem item);
  void search(String query);
  void addToCart(TrackItem item);
  void addToWishlist(TrackItem item);
  void beginCheckout(List<TrackItem> items, double value);
  void purchase(String orderId, List<TrackItem> items, double value);
  void identify({String? phone, String? email, String? firstName, String? lastName});
}

/// Fans out each event to every configured platform. Failures in one SDK
/// never affect the shopper or the other platforms.
class MultiTracker implements Tracker {
  MultiTracker._(this._platforms);

  final List<AdPlatform> _platforms;
  bool _enabled = true;

  @override
  List<String> get activePlatforms => [for (final p in _platforms) p.name];

  static Future<Tracker> create({required bool enabled}) async {
    final candidates = <AdPlatform>[
      if (!kIsWeb && AppConfig.metaAppId.isNotEmpty) MetaPlatform(),
      if (!kIsWeb) FirebasePlatform(),
      if (!kIsWeb && AppConfig.tiktokAppId.isNotEmpty) TikTokPlatform(),
      if (!kIsWeb && AppConfig.appsflyerDevKey.isNotEmpty) AppsFlyerPlatform(),
    ];
    final ready = <AdPlatform>[];
    await Future.wait(candidates.map((p) async {
      try {
        await p.init().timeout(const Duration(seconds: 5));
        ready.add(p);
      } catch (e) {
        debugPrint('[tracking] ${p.name} disabled: $e');
      }
    }));
    final t = MultiTracker._(ready);
    await t.setEnabled(enabled);
    debugPrint('[tracking] active: ${t.activePlatforms}');
    return t;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _each((p) => p.setEnabled(enabled), force: true);
  }

  @override
  void viewItem(TrackItem item) => _each((p) => p.viewItem(item, AppConfig.currency));
  @override
  void search(String query) => _each((p) => p.search(query));
  @override
  void addToCart(TrackItem item) => _each((p) => p.addToCart(item, AppConfig.currency));
  @override
  void addToWishlist(TrackItem item) => _each((p) => p.addToWishlist(item, AppConfig.currency));
  @override
  void beginCheckout(List<TrackItem> items, double value) =>
      _each((p) => p.beginCheckout(items, value, AppConfig.currency));
  @override
  void purchase(String orderId, List<TrackItem> items, double value) =>
      _each((p) => p.purchase(orderId, items, value, AppConfig.currency));
  @override
  void identify({String? phone, String? email, String? firstName, String? lastName}) =>
      _each((p) => p.identify(phone: phone, email: email, firstName: firstName, lastName: lastName));

  Future<void> _each(Future<void> Function(AdPlatform) f, {bool force = false}) async {
    if (!_enabled && !force) return;
    for (final p in _platforms) {
      unawaited(Future.sync(() => f(p)).catchError((Object e) {
        if (AppConfig.debugTracking) debugPrint('[tracking] ${p.name} error: $e');
      }));
    }
  }
}

/// Lets the UI start before the ad SDKs finish initialising: events fired
/// early (e.g. a product opened from an ad deep link) are queued, not lost.
class LazyTracker implements Tracker {
  LazyTracker(Future<Tracker> future) {
    future.then((t) {
      _real = t;
      for (final f in _queue) {
        f(t);
      }
      _queue.clear();
    });
  }

  Tracker? _real;
  final _queue = <void Function(Tracker)>[];

  void _run(void Function(Tracker) f) => _real != null ? f(_real!) : _queue.add(f);

  @override
  List<String> get activePlatforms => _real?.activePlatforms ?? const [];
  @override
  Future<void> setEnabled(bool enabled) async => _run((t) => t.setEnabled(enabled));
  @override
  void viewItem(TrackItem item) => _run((t) => t.viewItem(item));
  @override
  void search(String query) => _run((t) => t.search(query));
  @override
  void addToCart(TrackItem item) => _run((t) => t.addToCart(item));
  @override
  void addToWishlist(TrackItem item) => _run((t) => t.addToWishlist(item));
  @override
  void beginCheckout(List<TrackItem> items, double value) => _run((t) => t.beginCheckout(items, value));
  @override
  void purchase(String orderId, List<TrackItem> items, double value) =>
      _run((t) => t.purchase(orderId, items, value));
  @override
  void identify({String? phone, String? email, String? firstName, String? lastName}) =>
      _run((t) => t.identify(phone: phone, email: email, firstName: firstName, lastName: lastName));
}
