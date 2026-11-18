import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'models/product.dart';
import 'state/cart_model.dart';
import 'ui/screens/account_screens.dart';
import 'ui/screens/cart_screen.dart';
import 'ui/screens/catalog_screens.dart';
import 'ui/screens/checkout_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/product_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Routes. Deep links from ads, QR codes or shared website links open the
/// right screen directly:
/// - `https://STORE/product/SLUG/` opens the product
/// - `https://STORE/product-category/SLUG/` opens the category
/// - `sophieshop://open/product/ID` opens the product (custom scheme)
GoRouter buildRouter() => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/',
      redirect: (context, state) {
        final path = state.uri.path;
        // Website URLs end with "/"; normalise them.
        if (path.length > 1 && path.endsWith('/')) {
          return path.substring(0, path.length - 1);
        }
        if (path == '/shop' || path == '/home') return '/';
        if (path.startsWith('/product-category/')) {
          final slug = path.split('/').where((s) => s.isNotEmpty).last;
          return '/c/$slug';
        }
        return null;
      },
      errorBuilder: (context, state) => const _NotFound(),
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => _Shell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (_, _) => const CartScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (_, _) => const MeScreen())]),
          ],
        ),
        GoRoute(
          path: '/product/:ref',
          parentNavigatorKey: _rootKey,
          builder: (_, s) => ProductScreen(
            key: ValueKey(s.pathParameters['ref']),
            ref: s.pathParameters['ref']!,
            initial: s.extra is Product ? s.extra as Product : null,
          ),
        ),
        GoRoute(
          path: '/category/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, s) => ProductListScreen(
            categoryId: int.tryParse(s.pathParameters['id']!),
            title: s.uri.queryParameters['name'],
          ),
        ),
        GoRoute(
          path: '/c/:slug',
          parentNavigatorKey: _rootKey,
          builder: (_, s) => ProductListScreen(categorySlug: s.pathParameters['slug']),
        ),
        GoRoute(
          path: '/sale',
          parentNavigatorKey: _rootKey,
          builder: (_, _) => const ProductListScreen(onSale: true),
        ),
        GoRoute(path: '/search', parentNavigatorKey: _rootKey, builder: (_, _) => const SearchScreen()),
        GoRoute(path: '/checkout', parentNavigatorKey: _rootKey, builder: (_, _) => const CheckoutScreen()),
        GoRoute(
          path: '/order/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, s) => OrderSuccessScreen(orderId: s.pathParameters['id']!),
        ),
        GoRoute(path: '/wishlist', parentNavigatorKey: _rootKey, builder: (_, _) => const WishlistScreen()),
        GoRoute(path: '/orders', parentNavigatorKey: _rootKey, builder: (_, _) => const OrdersScreen()),
        GoRoute(path: '/address', parentNavigatorKey: _rootKey, builder: (_, _) => const AddressScreen()),
      ],
    );

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final count = context.select<CartModel, int>((c) => c.count);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Categories'),
          NavigationDestination(
            icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.shopping_bag_outlined)),
            selectedIcon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.shopping_bag)),
            label: 'Cart',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Page not found'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Go to shop')),
          ]),
        ),
      );
}
