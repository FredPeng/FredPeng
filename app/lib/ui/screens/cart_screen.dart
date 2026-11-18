import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/cart.dart';
import '../../state/cart_model.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<CartModel>();
    final cart = model.cart;
    return Scaffold(
      appBar: AppBar(title: Text(cart.isEmpty ? 'Cart' : 'Cart (${cart.count})')),
      body: !model.loaded
          ? const Center(child: CircularProgressIndicator())
          : cart.isEmpty
              ? EmptyView(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Your cart is empty',
                  message: 'Find something you love and it will show up here.',
                  action: FilledButton(onPressed: () => context.go('/'), child: const Text('Start shopping')),
                )
              : RefreshIndicator(
                  onRefresh: model.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: cart.items.length + 1,
                    separatorBuilder: (_, _) => const Divider(height: 24),
                    itemBuilder: (context, i) {
                      if (i == cart.items.length) return _Summary(cart: cart);
                      return _CartLine(item: cart.items[i]);
                    },
                  ),
                ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton(
                  onPressed: () => context.push('/checkout'),
                  child: Text('Checkout · ${cart.subtotal.format()}'),
                ),
              ),
            ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.item});
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final model = context.read<CartModel>();
    Future<void> run(Future<String?> f) async {
      final err = await f;
      if (err != null && context.mounted) showMessage(context, err);
    }

    return Dismissible(
      key: ValueKey(item.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: saleRed, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => run(model.remove(item)),
      child: InkWell(
        onTap: () => context.push('/product/${item.productId}'),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 84, height: 84, child: NetImage(item.image, radius: 10)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (item.options.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(item.options, style: const TextStyle(color: muted, fontSize: 12.5)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(item.lineTotal.format(), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                QtyStepper(
                  value: item.quantity,
                  min: 1,
                  canRemove: true,
                  max: item.maxQuantity,
                  onChanged: (q) => run(q < 1 ? model.remove(item) : model.setQuantity(item, q)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Summary extends StatefulWidget {
  const _Summary({required this.cart});
  final Cart cart;

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  final _coupon = TextEditingController();
  bool _showCoupon = false;

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _coupon.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    final err = await context.read<CartModel>().applyCoupon(code);
    if (!mounted) return;
    showMessage(context, err ?? 'Coupon applied');
    if (err == null) setState(() => _showCoupon = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cart;
    final busy = context.select<CartModel, bool>((m) => m.isBusy('coupon'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_showCoupon)
        Row(children: [
          Expanded(
            child: TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Coupon code', isDense: true),
              onSubmitted: (_) => _apply(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(80, 48)),
              onPressed: busy ? null : _apply,
              child: const Text('Apply'),
            ),
          ),
        ])
      else
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showCoupon = true),
            icon: const Icon(Icons.local_offer_outlined, size: 18),
            label: const Text('Have a coupon?'),
          ),
        ),
      const SizedBox(height: 8),
      _row('Subtotal', c.subtotal.format()),
      if (!c.discount.isZero) _row('Discount', '-${c.discount.format()}'),
      _row('Delivery', 'Calculated at checkout', faded: true),
    ]);
  }
}

Widget _row(String label, String value, {bool faded = false, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: bold ? ink : muted, fontWeight: bold ? FontWeight.w700 : null))),
        Text(value,
            style: TextStyle(
              color: faded ? muted : ink,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontSize: bold ? 16 : 14,
            )),
      ]),
    );

Widget summaryRow(String label, String value, {bool faded = false, bool bold = false}) =>
    _row(label, value, faded: faded, bold: bold);
