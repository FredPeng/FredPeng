import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../services.dart';
import '../../state/local_models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'checkout_screen.dart';

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = context.read<ProfileModel>().orders.where((o) => '${o.id}' == orderId).firstOrNull;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: const Color(0xFF2FB36D).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Color(0xFF2FB36D), size: 56),
            ),
            const SizedBox(height: 24),
            Text('Thank you for your order!', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Order #$orderId', style: const TextStyle(color: muted, fontSize: 16)),
            if (order != null) ...[
              const SizedBox(height: 16),
              Text('${order.total} · ${order.paymentMethod}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 12),
            Text(
              order != null && order.paymentMethod.contains('M-Pesa')
                  ? 'If you have not finished paying, complete the M-Pesa payment on your phone. '
                      'You can find this order under Me → My orders.'
                  : 'We will contact you to confirm delivery. You can find this order under Me → My orders.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.4),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => context.go('/'),
              child: const Text('Continue shopping'),
            ),
          ]),
        ),
      ),
    );
  }
}

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileModel>();
    final wishCount = context.select<WishlistModel, int>((w) => w.items.length);
    final name = profile.address.firstName;
    final services = context.read<Services>();

    Widget tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Widget? trailing}) => ListTile(
          leading: Icon(icon, color: ink),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: muted)),
          trailing: trailing ?? const Icon(Icons.chevron_right, color: muted),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: brand.withValues(alpha: 0.12),
              child: Text(
                name.isEmpty ? '👋' : name[0].toUpperCase(),
                style: const TextStyle(fontSize: 22, color: brand, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name.isEmpty ? 'Welcome!' : 'Hi, $name',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ]),
        ),
        const Divider(),
        tile(Icons.receipt_long_outlined, 'My orders',
            subtitle: profile.orders.isEmpty ? null : '${profile.orders.length} placed on this phone',
            onTap: () => context.push('/orders')),
        tile(Icons.favorite_border, 'Wishlist',
            subtitle: wishCount == 0 ? null : '$wishCount saved', onTap: () => context.push('/wishlist')),
        tile(Icons.location_on_outlined, 'Delivery details',
            subtitle: profile.address.isComplete ? profile.address.address : 'Save them for faster checkout',
            onTap: () => context.push('/address')),
        if (AppConfig.whatsapp.isNotEmpty)
          tile(Icons.chat_outlined, 'Chat with us on WhatsApp',
              onTap: () => launchUrl(Uri.parse('https://wa.me/${AppConfig.whatsapp}'), mode: LaunchMode.externalApplication)),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.campaign_outlined, color: ink),
          title: const Text('Personalised ads', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: const Text('Share app activity with our ad partners (Meta, Google, TikTok, X)',
              style: TextStyle(color: muted)),
          value: profile.adsConsent,
          onChanged: (v) => profile.setAdsConsent(v, services.tracker),
        ),
        if (AppConfig.privacyPolicyUrl.isNotEmpty)
          tile(Icons.privacy_tip_outlined, 'Privacy policy',
              onTap: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode: LaunchMode.inAppBrowserView)),
        const SizedBox(height: 24),
        Center(
          child: Text(
            AppConfig.isDemo ? '${AppConfig.appName} · demo mode' : AppConfig.appName,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wish = context.watch<WishlistModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: wish.items.isEmpty
          ? const EmptyView(
              icon: Icons.favorite_border,
              title: 'No saved items yet',
              message: 'Tap the heart on any product to save it here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: wish.items.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (context, i) {
                final w = wish.items[i];
                return InkWell(
                  onTap: () => context.push('/product/${w.id}'),
                  child: Row(children: [
                    SizedBox(width: 72, height: 72, child: NetImage(w.image, radius: 10)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(w.price, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: muted), onPressed: () => wish.remove(w.id)),
                  ]),
                );
              },
            ),
    );
  }
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<ProfileModel>().orders;
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: orders.isEmpty
          ? const EmptyView(icon: Icons.receipt_long_outlined, title: 'No orders yet')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (_, i) {
                final o = orders[i];
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('Order #${o.id}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(date(o.date), style: const TextStyle(color: muted)),
                  ]),
                  const SizedBox(height: 4),
                  Text(o.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
                  const SizedBox(height: 4),
                  Text('${o.total} · ${o.paymentMethod}', style: const TextStyle(fontWeight: FontWeight.w500)),
                ]);
              },
            ),
    );
  }
}

class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final _form = GlobalKey<FormState>();
  late final _c = AddressFormController(context.read<ProfileModel>().address);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Delivery details')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [AddressForm(controller: _c)]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                context.read<ProfileModel>().saveAddress(_c.value);
                context.pop();
                showMessage(context, 'Saved');
              },
              child: const Text('Save'),
            ),
          ),
        ),
      );
}
