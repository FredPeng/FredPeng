import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/shop_repository.dart';
import '../../data/store_api.dart';
import '../../models/product.dart';
import '../../services.dart';
import '../../state/local_models.dart';
import '../theme.dart';
import 'common.dart';

/// Paginated product list with instant cached first page and infinite scroll.
class PagedProducts extends ChangeNotifier {
  PagedProducts(this._repo, this.query, {this.perPage = 20}) {
    final repo = _repo;
    if (repo is StoreApi) {
      final cached = repo.peekProducts(query, perPage: perPage);
      if (cached != null) {
        items.addAll(cached.items);
        _totalPages = cached.totalPages;
      }
    }
    refresh();
  }

  final ShopRepository _repo;
  ProductQuery query;
  final int perPage;

  final List<Product> items = [];
  int _page = 0;
  int _totalPages = 1;
  bool loading = false;
  String? error;
  bool _disposed = false;

  bool get hasMore => _page < _totalPages;
  bool get initialLoading => loading && items.isEmpty;

  Future<void> refresh() async {
    _page = 0;
    _totalPages = 1;
    await _load(reset: true);
  }

  void setQuery(ProductQuery q) {
    query = q;
    items.clear();
    refresh();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore || error != null) return;
    await _load();
  }

  Future<void> _load({bool reset = false}) async {
    loading = true;
    error = null;
    _notify();
    final q = query;
    try {
      final page = await _repo.products(q, page: _page + 1, perPage: perPage);
      if (!identical(q, query)) return;
      if (reset) items.clear();
      items.addAll(page.items);
      _page++;
      _totalPages = page.totalPages;
    } on ShopException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not load products.';
    } finally {
      loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard(this.product, {super.key, this.hero = true});
  final Product product;

  /// Only one card per product may carry the Hero (a product can appear in
  /// both the "On sale" strip and the grid).
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final wished = context.select<WishlistModel, bool>((w) => w.contains(p.id));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/product/${p.id}', extra: p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              if (hero)
                Hero(tag: 'p${p.id}', child: NetImage(p.thumbnail, radius: 12))
              else
                NetImage(p.thumbnail, radius: 12),
              if (p.discountPercent > 0)
                Positioned(left: 8, top: 8, child: Badge2('-${p.discountPercent}%')),
              if (!p.inStock)
                const Positioned(left: 8, bottom: 8, child: Badge2('Sold out', color: muted)),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.9)),
                  icon: Icon(wished ? Icons.favorite : Icons.favorite_border, size: 18, color: wished ? brand : ink),
                  onPressed: () => context.read<WishlistModel>().toggle(p),
                  tooltip: 'Wishlist',
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, height: 1.25)),
          const SizedBox(height: 4),
          PriceText(
            price: p.displayPrice,
            was: p.discountPercent > 0 ? p.regularPrice.format() : null,
            size: 14.5,
          ),
        ],
      ),
    );
  }
}

const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 220,
  mainAxisSpacing: 18,
  crossAxisSpacing: 12,
  childAspectRatio: 0.62,
);

/// Sliver grid bound to a [PagedProducts]; triggers loadMore near the end.
class ProductSliverGrid extends StatelessWidget {
  const ProductSliverGrid(this.paged, {super.key});
  final PagedProducts paged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: paged,
      builder: (context, _) {
        if (paged.initialLoading) return const SkeletonGrid();
        if (paged.items.isEmpty && paged.error != null) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(message: paged.error!, onRetry: paged.refresh),
          );
        }
        if (paged.items.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(icon: Icons.search_off_rounded, title: 'No products found'),
          );
        }
        return SliverMainAxisGroup(slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.builder(
              gridDelegate: _gridDelegate,
              itemCount: paged.items.length,
              itemBuilder: (context, i) {
                if (i >= paged.items.length - 6) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => paged.loadMore());
                }
                return ProductCard(paged.items[i]);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 72,
              child: Center(
                child: paged.loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : paged.error != null
                        ? TextButton(onPressed: paged.loadMore, child: const Text('Load more'))
                        : null,
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: _gridDelegate,
          itemCount: count,
          itemBuilder: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(decoration: BoxDecoration(color: surfaceGrey, borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 10),
            Container(height: 12, width: double.infinity, color: surfaceGrey),
            const SizedBox(height: 6),
            Container(height: 12, width: 70, color: surfaceGrey),
          ]),
        ),
      );
}

/// Horizontal strip of product cards (e.g. "On sale").
class ProductStrip extends StatelessWidget {
  const ProductStrip({super.key, required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 232,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 148, child: ProductCard(products[i], hero: false)),
        ),
      );
}

ShopRepository repoOf(BuildContext context) => context.read<Services>().repo;
