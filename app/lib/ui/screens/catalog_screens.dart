import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/store_api.dart';
import '../../models/product.dart';
import '../../services.dart';
import '../../state/local_models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/products.dart';

/// All categories.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category>? _cats;
  String? _error;

  @override
  void initState() {
    super.initState();
    final repo = repoOf(context);
    if (repo is StoreApi) _cats = repo.peekCategories();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await repoOf(context).categories();
      if (mounted) {
        setState(() {
          _cats = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    Widget body;
    if (cats == null && _error != null) {
      body = ErrorView(message: _error!, onRetry: _load);
    } else if (cats == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final top = cats.where((c) => c.parent == 0).toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _tile(context, null, 'On sale', Icons.local_offer_outlined, () => context.push('/sale')),
            for (final c in top) ...[
              _tile(context, c.image, c.name, null,
                  () => context.push('/category/${c.id}?name=${Uri.encodeComponent(c.name)}')),
              for (final sub in cats.where((s) => s.parent == c.id))
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: ListTile(
                    dense: true,
                    title: Text(sub.name),
                    trailing: const Icon(Icons.chevron_right, size: 20, color: muted),
                    onTap: () => context.push('/category/${sub.id}?name=${Uri.encodeComponent(sub.name)}'),
                  ),
                ),
            ],
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Categories')), body: body);
  }

  Widget _tile(BuildContext context, String? image, String name, IconData? icon, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: image != null
              ? NetImage(image, radius: 10)
              : Container(
                  decoration: BoxDecoration(color: surfaceGrey, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: icon != null
                      ? Icon(icon, color: brand)
                      : Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: brand)),
                ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: muted),
        onTap: onTap,
      );
}

/// Products in a category, on sale, or matching a website category slug.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, this.categoryId, this.categorySlug, this.title, this.onSale = false});
  final int? categoryId;
  final String? categorySlug;
  final String? title;
  final bool onSale;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  PagedProducts? _paged;
  String? _title;
  ProductSort _sort = ProductSort.popular;

  @override
  void initState() {
    super.initState();
    _title = widget.title ?? (widget.onSale ? 'On sale' : null);
    if (widget.categorySlug != null) {
      _resolveSlug();
    } else {
      _paged = PagedProducts(repoOf(context), _query(widget.categoryId));
    }
  }

  ProductQuery _query(int? cat) => ProductQuery(categoryId: cat, onSale: widget.onSale, sort: _sort);

  Future<void> _resolveSlug() async {
    try {
      final cats = await repoOf(context).categories();
      final c = cats.where((c) => c.slug == widget.categorySlug).firstOrNull;
      if (!mounted) return;
      setState(() {
        _title = c?.name ?? 'Shop';
        _paged = PagedProducts(repoOf(context), _query(c?.id));
      });
    } catch (_) {
      if (mounted) setState(() => _paged = PagedProducts(repoOf(context), _query(null)));
    }
  }

  @override
  void dispose() {
    _paged?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paged = _paged;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(_title ?? ''),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
            PopupMenuButton<ProductSort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              initialValue: _sort,
              onSelected: (s) {
                setState(() => _sort = s);
                paged?.setQuery(ProductQuery(
                  categoryId: paged.query.categoryId,
                  onSale: widget.onSale,
                  sort: s,
                ));
              },
              itemBuilder: (_) => [for (final s in ProductSort.values) PopupMenuItem(value: s, child: Text(s.label))],
            ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (paged == null) const SkeletonGrid() else ProductSliverGrid(paged),
      ]),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  PagedProducts? _paged;
  Timer? _debounce;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q, record: false));
    setState(() {});
  }

  void _search(String q, {bool record = true}) {
    q = q.trim();
    if (q.isEmpty) {
      setState(() {
        _paged?.dispose();
        _paged = null;
      });
      return;
    }
    if (record) {
      context.read<ProfileModel>().addSearch(q);
      context.read<Services>().tracker.search(q);
    }
    final query = ProductQuery(search: q);
    if (_paged == null) {
      setState(() => _paged = PagedProducts(repoOf(context), query));
    } else if (_paged!.query.search != q) {
      _paged!.setQuery(query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _paged?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileModel>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (q) => _search(q),
            decoration: InputDecoration(
              hintText: 'Search products',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              prefixIcon: const Icon(Icons.search, color: muted),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _controller.clear();
                        _search('');
                      },
                    ),
            ),
          ),
        ),
      ),
      body: _paged == null
          ? ListView(padding: const EdgeInsets.all(16), children: [
              if (profile.recentSearches.isNotEmpty) ...[
                Row(children: [
                  const Expanded(child: Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w600))),
                  TextButton(onPressed: profile.clearSearches, child: const Text('Clear')),
                ]),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in profile.recentSearches)
                    ActionChip(
                      label: Text(s),
                      onPressed: () {
                        _controller.text = s;
                        _search(s);
                      },
                    ),
                ]),
              ],
            ])
          : NotificationListener<ScrollStartNotification>(
              onNotification: (_) {
                FocusScope.of(context).unfocus();
                if (_controller.text.trim().isNotEmpty) {
                  context.read<ProfileModel>().addSearch(_controller.text);
                }
                return false;
              },
              child: CustomScrollView(slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ProductSliverGrid(_paged!),
              ]),
            ),
    );
  }
}
