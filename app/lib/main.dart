import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'data/demo_store.dart';
import 'data/regions.dart';
import 'data/shop_repository.dart';
import 'data/store_api.dart';
import 'router.dart';
import 'services.dart';
import 'state/cart_model.dart';
import 'state/local_models.dart';
import 'tracking/tracker.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final regions = await Regions.load();
  final ShopRepository repo = AppConfig.isDemo ? DemoStore() : StoreApi(AppConfig.storeUrl, prefs);

  // Start the UI immediately; ad SDKs initialise in the background so they
  // never slow down app start.
  final tracker = LazyTracker(MultiTracker.create(enabled: prefs.getBool('ads_consent') ?? true));

  final services = Services(repo: repo, tracker: tracker, prefs: prefs, regions: regions);
  runApp(SophieApp(services: services));
}

class SophieApp extends StatefulWidget {
  const SophieApp({super.key, required this.services});
  final Services services;

  @override
  State<SophieApp> createState() => _SophieAppState();
}

class _SophieAppState extends State<SophieApp> {
  late final _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return MultiProvider(
      providers: [
        Provider.value(value: s),
        ChangeNotifierProvider(create: (_) => CartModel(s.repo, s.tracker)..load()),
        ChangeNotifierProvider(create: (_) => WishlistModel(s.prefs, s.tracker)),
        ChangeNotifierProvider(create: (_) => ProfileModel(s.prefs)),
      ],
      child: MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: _router,
      ),
    );
  }
}
