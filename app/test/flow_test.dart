import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie_shop/data/demo_store.dart';
import 'package:sophie_shop/data/regions.dart';
import 'package:sophie_shop/main.dart';
import 'package:sophie_shop/services.dart';
import 'package:sophie_shop/tracking/tracker.dart';
import 'package:sophie_shop/ui/widgets/common.dart';

/// Records events so the test can check what ad platforms would receive.
class FakeTracker implements Tracker {
  final events = <String>[];
  @override
  List<String> get activePlatforms => const ['fake'];
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  void viewItem(TrackItem item) => events.add('view:${item.id}');
  @override
  void search(String query) => events.add('search:$query');
  @override
  void addToCart(TrackItem item) => events.add('cart:${item.id}');
  @override
  void addToWishlist(TrackItem item) => events.add('wish:${item.id}');
  @override
  void beginCheckout(List<TrackItem> items, double value) => events.add('checkout:$value');
  @override
  void purchase(String orderId, List<TrackItem> items, double value) => events.add('purchase:$orderId:$value');
  @override
  void identify({String? phone, String? email, String? firstName, String? lastName}) => events.add('identify');
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('browse, buy now, fill Kenyan address, place order', (t) async {
    NetImage.enabled = false;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.7;
    addTearDown(t.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final regions = await Regions.load();
    final tracker = FakeTracker();
    await t.pumpWidget(SophieApp(
      services: Services(repo: DemoStore(), tracker: tracker, prefs: prefs, regions: regions),
    ));
    await settle(t);

    expect(find.text('Popular now'), findsOneWidget);
    await t.tap(find.text('Ceramic Mug Set (4)').first);
    await settle(t);
    expect(find.text('Buy now'), findsOneWidget);
    expect(tracker.events, contains('view:503'));

    await t.tap(find.text('Buy now'));
    await settle(t);
    expect(find.text('Checkout'), findsOneWidget);
    expect(tracker.events, contains('cart:503'));

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await t.enterText(field('First name'), 'Wanjiru');
    await t.enterText(field('Last name'), 'Kamau');
    await t.enterText(field('Phone'), '0712345678');

    await t.tap(find.text('County'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Search'), 'Nairo');
    await settle(t);
    await t.tap(find.text('Nairobi').last);
    await settle(t);

    await t.tap(find.text('Area'));
    await settle(t);
    final firstArea = regions.byCode('KE30')!.areas.first;
    await t.tap(find.text(firstArea).last);
    await settle(t);

    await t.enterText(field('Address'), 'Moi Avenue, House 12');
    await settle(t);

    // Shipping rates appear once the county is known.
    expect(find.text('Standard delivery (1–3 days)'), findsOneWidget);

    await t.tap(find.textContaining('Place order'));
    await settle(t);
    await settle(t);
    expect(find.text('Thank you for your order!'), findsOneWidget);
    expect(find.text('Order #10231'), findsOneWidget);
    expect(tracker.events.where((e) => e.startsWith('purchase:10231')), hasLength(1));
    expect(prefs.getString('address'), contains('KE30'));
  });
}
