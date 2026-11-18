import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../services.dart';
import '../../state/cart_model.dart';
import '../../state/local_models.dart';
import '../../tracking/tracker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/products.dart';

/// Product page. `ref` is a numeric id or a website slug (deep links from
/// ads and shared links use `https://STORE/product/SLUG/`).
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.ref, this.initial});
  final String ref;
  final Product? initial;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Product? _p;
  String? _error;
  bool _tracked = false;
  int _qty = 1;
  int _image = 0;
  final Map<String, String> _selected = {};
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _p = widget.initial;
    _initSelection();
    _load();
  }

  void _initSelection() {
    final p = _p;
    if (p == null) return;
    for (final a in p.variationAttributes) {
      if (a.terms.length == 1) _selected[a.name] = a.terms.first.slug;
    }
    _track();
  }

  void _track() {
    final p = _p;
    if (_tracked || p == null) return;
    _tracked = true;
    context.read<Services>().tracker.viewItem(TrackItem(
          id: '${p.id}',
          name: p.name,
          price: p.price.value,
          category: p.categories.isEmpty ? null : p.categories.first.name,
        ));
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    try {
      final id = int.tryParse(widget.ref);
      final p = id != null ? await repo.product(id) : await repo.productBySlug(widget.ref);
      if (!mounted) return;
      if (p == null) {
        setState(() => _error = 'This product is no longer available.');
        return;
      }
      final first = _p == null;
      setState(() {
        _p = p;
        _error = null;
      });
      if (first) _initSelection();
    } catch (e) {
      if (mounted && _p == null) setState(() => _error = '$e');
    }
  }

  Variation? get _variation => _p!.isVariable ? _p!.findVariation(_selected) : null;

  bool get _optionsComplete =>
      !_p!.isVariable || _p!.variationAttributes.every((a) => _selected.containsKey(a.name));

  Future<void> _addToCart({bool buyNow = false}) async {
    final p = _p!;
    if (!_optionsComplete) {
      final missing = p.variationAttributes.firstWhere((a) => !_selected.containsKey(a.name));
      showMessage(context, 'Please choose a ${missing.name.toLowerCase()}');
      return;
    }
    final v = _variation;
    if (p.isVariable && v == null) {
      showMessage(context, 'This combination is not available');
      return;
    }
    setState(() => _adding = true);
    final options = <String, String>{
      for (final a in p.variationAttributes) (a.taxonomy.isNotEmpty ? a.taxonomy : a.name): _selected[a.name]!,
    };
    final err = await context.read<CartModel>().add(p, quantity: _qty, variationId: v?.id, options: options);
    if (!mounted) return;
    setState(() => _adding = false);
    if (err != null) {
      showMessage(context, err);
    } else if (buyNow) {
      context.push('/checkout');
    } else {
      showMessage(
        context,
        'Added to cart',
        action: SnackBarAction(label: 'VIEW CART', textColor: Colors.white, onPressed: () => context.go('/cart')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: () {
                setState(() => _error = null);
                _load();
              })
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final wished = context.select<WishlistModel, bool>((w) => w.contains(p.id));
    final cartCount = context.select<CartModel, int>((c) => c.count);
    final width = MediaQuery.sizeOf(context).width;
    final images = p.images.isEmpty ? [null] : p.images.map((i) => i.src).toList();
    final canBuy = p.inStock && p.purchasable;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: width.clamp(0, 600).toDouble(),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: cartCount > 0,
                label: Text('$cartCount'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              onPressed: () => context.go('/cart'),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _image = i),
                itemBuilder: (_, i) {
                  final img = NetImage(images[i], fit: BoxFit.cover);
                  return i == 0 ? Hero(tag: 'p${p.id}', child: img) : img;
                },
              ),
              if (images.length > 1)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < images.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _image ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _image ? ink : Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverList.list(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(p.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 21)),
              ),
              IconButton(
                icon: Icon(wished ? Icons.favorite : Icons.favorite_border, color: wished ? brand : ink),
                onPressed: () => context.read<WishlistModel>().toggle(p),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              PriceText(
                price: p.displayPrice,
                was: p.discountPercent > 0 ? p.regularPrice.format() : null,
                size: 20,
              ),
              if (p.discountPercent > 0) ...[const SizedBox(width: 8), Badge2('-${p.discountPercent}%')],
            ]),
            if (p.reviewCount > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFB400), size: 18),
                const SizedBox(width: 4),
                Text(p.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('  (${p.reviewCount} reviews)', style: const TextStyle(color: muted)),
              ]),
            ],
            if (!canBuy) ...[
              const SizedBox(height: 8),
              const Text('Currently out of stock', style: TextStyle(color: saleRed, fontWeight: FontWeight.w600)),
            ],
            for (final a in p.variationAttributes) ...[
              const SizedBox(height: 20),
              Text(
                _selected[a.name] == null
                    ? a.name
                    : '${a.name}: ${a.terms.firstWhere((t) => t.slug == _selected[a.name], orElse: () => a.terms.first).name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in a.terms)
                  ChoiceChip(
                    label: Text(t.name),
                    selected: _selected[a.name] == t.slug,
                    showCheckmark: false,
                    selectedColor: ink,
                    labelStyle: TextStyle(
                      color: _selected[a.name] == t.slug ? Colors.white : ink,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _selected[a.name] = t.slug),
                  ),
              ]),
            ],
            if (canBuy) ...[
              const SizedBox(height: 20),
              Row(children: [
                const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                QtyStepper(
                  value: _qty,
                  max: p.maxQuantity ?? 99,
                  onChanged: (v) => setState(() => _qty = v.clamp(1, 99)),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const _Perks(),
            const Divider(),
            if (p.description.isNotEmpty || p.shortDescription.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                p.description.isNotEmpty ? p.description : p.shortDescription,
                style: const TextStyle(height: 1.5, color: Color(0xFF3C3C43)),
              ),
            ],
            if (p.sku.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('SKU: ${p.sku}', style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEDEDF0))),
          ),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canBuy && !_adding ? () => _addToCart() : null,
                child: _adding
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add to cart'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: canBuy && !_adding ? () => _addToCart(buyNow: true) : null,
                child: const Text('Buy now'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Perks extends StatelessWidget {
  const _Perks();

  @override
  Widget build(BuildContext context) {
    Widget perk(IconData i, String t) => Expanded(
          child: Column(children: [
            Icon(i, color: brand, size: 22),
            const SizedBox(height: 6),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: muted)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        perk(Icons.local_shipping_outlined, 'Fast delivery'),
        perk(Icons.payments_outlined, 'Pay on delivery'),
        perk(Icons.verified_outlined, 'Quality checked'),
      ]),
    );
  }
}
