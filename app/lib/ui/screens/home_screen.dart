import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../config.dart';
import '../../models/product.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/products.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PagedProducts _popular = PagedProducts(repoOf(context), const ProductQuery());
  late final PagedProducts _sale = PagedProducts(repoOf(context), const ProductQuery(onSale: true), perPage: 10);
  List<Category> _categories = const [];

  @override
  void initState() {
    super.initState();
    repoOf(context).cachedCategories(parent: 0).then((c) {
      if (c != null && mounted && _categories.isEmpty) setState(() => _categories = c);
    });
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final c = await repoOf(context).categories(parent: 0);
      if (mounted) setState(() => _categories = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    _popular.dispose();
    _sale.dispose();
    super.dispose();
  }

  Future<void> _refresh() => Future.wait([_popular.refresh(), _sale.refresh(), _loadCategories()]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(AppConfig.appName),
              actions: [
                if (AppConfig.isDemo)
                  const Padding(padding: EdgeInsets.only(right: 12), child: Badge2('DEMO', color: muted)),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _SearchBox(onTap: () => context.push('/search')),
                ),
              ),
            ),
            if (_categories.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final c = _categories[i];
                      return ActionChip(
                        label: Text(c.name),
                        onPressed: () => context.push('/category/${c.id}?name=${Uri.encodeComponent(c.name)}'),
                      );
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: _sale,
                builder: (context, _) {
                  if (_sale.items.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionHeader('On sale', action: 'See all', onAction: () => context.push('/sale')),
                    ProductStrip(products: _sale.items),
                  ]);
                },
              ),
            ),
            const SliverToBoxAdapter(child: SectionHeader('Popular now')),
            ProductSliverGrid(_popular),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: surfaceGrey,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: const SizedBox(
            height: 46,
            child: Row(children: [
              SizedBox(width: 14),
              Icon(Icons.search, color: muted),
              SizedBox(width: 10),
              Text('Search products', style: TextStyle(color: muted, fontSize: 15)),
            ]),
          ),
        ),
      );
}
