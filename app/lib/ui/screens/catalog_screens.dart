import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../services.dart';
import '../../state/local_models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/products.dart';

/// Top-level categories (18 on sophie.co.ke). Sub-categories load when a
/// category is opened, instead of downloading all 700+ up front.
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
    repoOf(context).cachedCategories(parent: 0).then((c) {
      if (c != null && mounted && _cats == null) setState(() => _cats = c);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await repoOf(context).categories(parent: 0);
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
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _tile(context, null, 'On sale', Icons.local_offer_outlined, () => context.push('/sale')),
            for (final c in cats)
              _tile(context, c.image, c.name, null,
                  () => context.push('/category/${c.id}?name=${Uri.encodeComponent(c.name)}')),
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

/// Products in a category (with its sub-categories as chips), on sale, or
/// matching a website category slug.
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
  late final PagedProducts _paged = PagedProducts(repoOf(context), _query());
  ProductSort _sort = ProductSort.popular;
  List<Category> _subs = const [];

  String get _title {
    if (widget.title != null) return widget.title!;
    if (widget.onSale) return 'On sale';
    final slug = widget.categorySlug;
    if (slug == null) return 'Shop';
    return slug.split('-').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  ProductQuery _query() => ProductQuery(
        categoryId: widget.categoryId,
        categorySlug: widget.categorySlug,
        onSale: widget.onSale,
        sort: _sort,
      );

  @override
  void initState() {
    super.initState();
    final id = widget.categoryId;
    if (id != null) {
      final repo = repoOf(context);
      repo.cachedCategories(parent: id).then((c) {
        if (c != null && mounted && _subs.isEmpty) setState(() => _subs = c);
      });
      repo.categories(parent: id).then((c) {
        if (mounted) setState(() => _subs = c);
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(_title),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
            PopupMenuButton<ProductSort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              initialValue: _sort,
              onSelected: (s) {
                setState(() => _sort = s);
                _paged.setQuery(_query());
              },
              itemBuilder: (_) => [for (final s in ProductSort.values) PopupMenuItem(value: s, child: Text(s.label))],
            ),
          ],
        ),
        if (_subs.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                scrollDirection: Axis.horizontal,
                itemCount: _subs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_subs[i].name),
                  onPressed: () =>
                      context.push('/category/${_subs[i].id}?name=${Uri.encodeComponent(_subs[i].name)}'),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ProductSliverGrid(_paged),
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
