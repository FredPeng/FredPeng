import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/shop_repository.dart';
import '../../models/address.dart';
import '../../models/cart.dart';
import '../../services.dart';
import '../../state/cart_model.dart';
import '../../state/local_models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cart_screen.dart';

const _paymentTitles = {
  'cod': 'Cash on delivery',
  'mpesa': 'M-Pesa',
  'bacs': 'Bank transfer',
  'cheque': 'Cheque',
  'paypal': 'PayPal',
  'ppcp-gateway': 'PayPal',
  'stripe': 'Debit / credit card',
  'pesapal': 'Pesapal (card / M-Pesa)',
  'woocommerce_payments': 'Debit / credit card',
};

String paymentTitle(String id) {
  final t = _paymentTitles[id];
  if (t != null) return t;
  if (id.toLowerCase().contains('mpesa')) return 'M-Pesa';
  final words = id.replaceAll(RegExp(r'[-_]+'), ' ').trim();
  return words.isEmpty ? id : words[0].toUpperCase() + words.substring(1);
}

IconData _paymentIcon(String id) {
  if (id == 'cod') return Icons.payments_outlined;
  if (id.contains('mpesa')) return Icons.phone_android;
  if (id == 'bacs') return Icons.account_balance_outlined;
  return Icons.credit_card;
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final AddressFormController _address;
  String? _payment;
  bool _placing = false;
  Timer? _debounce;
  String _lastSynced = '';

  @override
  void initState() {
    super.initState();
    _address = AddressFormController(context.read<ProfileModel>().address)..addListener(_onAddressChanged);
    final cart = context.read<CartModel>();
    context.read<Services>().tracker.beginCheckout(cart.trackItems, cart.cart.total.value);
    _syncCustomer();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _address.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _syncCustomer);
  }

  /// Sends county/area to WooCommerce so shipping zones & rates are computed.
  Future<void> _syncCustomer() async {
    final a = _address.value;
    if (a.county.isEmpty) return;
    final key = '${a.county}|${a.area}';
    if (key == _lastSynced) return;
    _lastSynced = key;
    final err = await context.read<CartModel>().updateCustomer(a);
    if (err != null && mounted) showMessage(context, err);
  }

  Future<void> _place(Cart cart) async {
    if (!_form.currentState!.validate()) {
      showMessage(context, 'Please complete your delivery details');
      return;
    }
    final a = _address.value;
    final payment = _payment ?? (cart.paymentMethods.isEmpty ? 'cod' : cart.paymentMethods.first);
    final profile = context.read<ProfileModel>();
    final cartModel = context.read<CartModel>();
    profile.saveAddress(a);
    setState(() => _placing = true);
    try {
      final summary = cart.items.map((i) => '${i.quantity}× ${i.name}').join(', ');
      final total = cart.total;
      final result = await cartModel.checkout(a, payment);
      profile.addOrder(OrderRecord(
        id: result.orderId,
        date: DateTime.now(),
        total: (result.total.isZero ? total : result.total).format(),
        summary: summary,
        paymentMethod: paymentTitle(payment),
      ));
      if (!mounted) return;
      if (result.redirectUrl != null) {
        // Online payment gateways (card / M-Pesa STK pages) finish in the browser.
        await launchUrl(Uri.parse(result.redirectUrl!), mode: LaunchMode.inAppBrowserView);
      }
      if (mounted) context.go('/order/${result.orderId}');
    } on ShopException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not place your order. Please try again.');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<CartModel>();
    final cart = model.cart;
    if (cart.isEmpty && !_placing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyView(
          icon: Icons.shopping_bag_outlined,
          title: 'Your cart is empty',
          action: FilledButton(onPressed: () => context.go('/'), child: const Text('Start shopping')),
        ),
      );
    }
    final payments = cart.paymentMethods.isEmpty ? const ['cod'] : cart.paymentMethods;
    _payment ??= payments.first;
    if (!payments.contains(_payment)) _payment = payments.first;
    final shippingBusy = model.isBusy('customer') || model.isBusy('shipping');

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _Title('Delivery details'),
            AddressForm(controller: _address),
            if (cart.needsShipping) ...[
              const _Title('Delivery method'),
              if (_address.value.county.isEmpty)
                const Text('Choose your county to see delivery options.', style: TextStyle(color: muted))
              else if (shippingBusy && cart.shippingRates.isEmpty)
                const LinearProgressIndicator(minHeight: 2)
              else if (cart.shippingRates.isEmpty)
                const Text('Delivery cost will be confirmed by phone.', style: TextStyle(color: muted))
              else
                for (final r in cart.shippingRates)
                  _OptionTile(
                    selected: r.selected,
                    icon: r.rateId.startsWith('local_pickup') ? Icons.storefront_outlined : Icons.local_shipping_outlined,
                    title: r.name,
                    trailing: r.price.isZero ? 'Free' : r.price.format(),
                    onTap: shippingBusy ? null : () => context.read<CartModel>().selectRate(r),
                  ),
            ],
            const _Title('Payment'),
            for (final p in payments)
              _OptionTile(
                selected: _payment == p,
                icon: _paymentIcon(p),
                title: paymentTitle(p),
                onTap: () => setState(() => _payment = p),
              ),
            const _Title('Order summary'),
            for (final i in cart.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 44, height: 44, child: NetImage(i.image, radius: 8)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${i.quantity} × ${i.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(i.lineTotal.format(), style: const TextStyle(fontWeight: FontWeight.w500)),
                ]),
              ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            summaryRow('Subtotal', cart.subtotal.format()),
            if (!cart.discount.isZero) summaryRow('Discount', '-${cart.discount.format()}'),
            if (cart.needsShipping)
              summaryRow(
                'Delivery',
                cart.shipping == null ? '—' : (cart.shipping!.isZero ? 'Free' : cart.shipping!.format()),
                faded: cart.shipping == null,
              ),
            const SizedBox(height: 4),
            summaryRow('Total', cart.total.format(), bold: true),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            onPressed: _placing || shippingBusy ? null : () => _place(cart),
            child: _placing
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Place order · ${cart.total.format()}'),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.selected, required this.icon, required this.title, this.trailing, this.onTap});
  final bool selected;
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? brand : const Color(0xFFE2E2E7), width: selected ? 1.6 : 1),
              color: selected ? brand.withValues(alpha: 0.04) : Colors.white,
            ),
            child: Row(children: [
              Icon(icon, color: selected ? brand : muted),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
              if (trailing != null) Text(trailing!, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? brand : muted, size: 20),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------ address form

class AddressFormController extends ChangeNotifier {
  AddressFormController(Address a)
      : firstName = TextEditingController(text: a.firstName),
        lastName = TextEditingController(text: a.lastName),
        phone = TextEditingController(text: a.phone),
        email = TextEditingController(text: a.email),
        address = TextEditingController(text: a.address),
        area = TextEditingController(text: a.area),
        county = a.county;

  final TextEditingController firstName, lastName, phone, email, address, area;
  String county;

  void setCounty(String code) {
    if (code == county) return;
    county = code;
    area.clear();
    notifyListeners();
  }

  void setArea(String v) {
    area.text = v;
    notifyListeners();
  }

  void changed() => notifyListeners();

  Address get value => Address(
        firstName: firstName.text.trim(),
        lastName: lastName.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        county: county,
        area: area.text.trim(),
        address: address.text.trim(),
      );

  @override
  void dispose() {
    for (final c in [firstName, lastName, phone, email, address, area]) {
      c.dispose();
    }
    super.dispose();
  }
}

class AddressForm extends StatelessWidget {
  const AddressForm({super.key, required this.controller});
  final AddressFormController controller;

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _phone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Required';
    if (digits.length < 9 || digits.length > 13) return 'Enter a valid phone number';
    return null;
  }

  String? _email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Enter a valid email';
  }

  @override
  Widget build(BuildContext context) {
    final regions = context.read<Services>().regions;
    const gap = SizedBox(height: 12);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final county = regions.byCode(controller.county);
        return Column(children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: controller.firstName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.givenName],
                decoration: const InputDecoration(labelText: 'First name'),
                validator: _required,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: controller.lastName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.familyName],
                decoration: const InputDecoration(labelText: 'Last name'),
                validator: _required,
              ),
            ),
          ]),
          gap,
          TextFormField(
            controller: controller.phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(labelText: 'Phone', hintText: '07XX XXX XXX'),
            validator: _phone,
          ),
          gap,
          _PickerField(
            label: 'County',
            value: county?.name,
            validator: (_) => controller.county.isEmpty ? 'Required' : null,
            onTap: () async {
              final picked = await pickFromList(
                context,
                title: 'Choose county',
                items: [for (final c in regions.counties) c.name],
              );
              if (picked != null) {
                controller.setCounty(regions.counties.firstWhere((c) => c.name == picked).code);
              }
            },
          ),
          gap,
          if (county != null && county.areas.isNotEmpty)
            _PickerField(
              label: 'Area',
              value: controller.area.text.isEmpty ? null : controller.area.text,
              validator: (_) => controller.area.text.isEmpty ? 'Required' : null,
              onTap: () async {
                final picked = await pickFromList(context, title: 'Choose area', items: county.areas);
                if (picked != null) controller.setArea(picked);
              },
            )
          else
            TextFormField(
              controller: controller.area,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Area'),
              validator: _required,
              onChanged: (_) => controller.changed(),
            ),
          gap,
          TextFormField(
            controller: controller.address,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.streetAddressLine1],
            decoration: const InputDecoration(labelText: 'Address', hintText: 'Street, building, house number'),
            validator: _required,
          ),
          gap,
          TextFormField(
            controller: controller.email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email (optional)', hintText: 'For your order confirmation'),
            validator: _email,
          ),
        ]);
      },
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.value, required this.onTap, this.validator});
  final String label;
  final String? value;
  final VoidCallback onTap;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => FormField<String>(
        validator: validator,
        builder: (state) => InkWell(
          onTap: () {
            FocusScope.of(context).unfocus();
            onTap();
            state.didChange(value);
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(
              labelText: label,
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.expand_more),
            ),
            child: Text(value ?? '', style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
}

/// Searchable bottom-sheet picker (1,000+ areas need search).
Future<String?> pickFromList(BuildContext context, {required String title, required List<String> items}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => _PickerSheet(title: title, items: items),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = q.isEmpty ? widget.items : widget.items.where((i) => i.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (widget.items.length > 8)
              TextField(
                autofocus: false,
                decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(list[i]),
              onTap: () => Navigator.pop(context, list[i]),
            ),
          ),
        ),
      ]),
    );
  }
}
