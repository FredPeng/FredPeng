import 'package:shared_preferences/shared_preferences.dart';

import 'data/regions.dart';
import 'data/shop_repository.dart';
import 'tracking/tracker.dart';

/// App-wide singletons, provided at the root of the widget tree.
class Services {
  Services({required this.repo, required this.tracker, required this.prefs, required this.regions});

  final ShopRepository repo;
  final Tracker tracker;
  final SharedPreferences prefs;
  final Regions regions;
}
