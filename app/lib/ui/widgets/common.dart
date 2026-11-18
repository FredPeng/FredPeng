import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Network image sized to its box (decoded at display size, not full size),
/// cached on disk, with a neutral placeholder — keeps scrolling smooth.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.radius = 0});

  final String? url;
  final BoxFit fit;
  final double radius;

  /// Widget tests turn network images off.
  static bool enabled = true;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: surfaceGrey);
    Widget child;
    if (url == null || url!.isEmpty || !enabled) {
      child = Container(
        color: surfaceGrey,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Color(0xFFBBBBC2)),
      );
    } else {
      child = LayoutBuilder(builder: (context, c) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final w = c.maxWidth.isFinite ? (c.maxWidth * dpr).round() : null;
        return CachedNetworkImage(
          imageUrl: url!,
          fit: fit,
          memCacheWidth: w,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => Container(
            color: surfaceGrey,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: Color(0xFFBBBBC2)),
          ),
        );
      });
    }
    if (radius == 0) return child;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.price, this.was, this.size = 15});

  final String price;
  final String? was;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          price,
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: was != null ? saleRed : ink),
        ),
        if (was != null)
          Text(
            was!,
            style: TextStyle(
              fontSize: size - 3,
              color: muted,
              decoration: TextDecoration.lineThrough,
              decorationColor: muted,
            ),
          ),
      ],
    );
  }
}

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.color = saleRed});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 44, color: muted),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(color: surfaceGrey, shape: BoxShape.circle),
                child: Icon(icon, size: 40, color: muted),
              ),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 99,
    this.min = 1,
    this.canRemove = false,
  });
  final int value;
  final int min;
  final int max;

  /// In the cart, "-" at the minimum becomes a delete button.
  final bool canRemove;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool enabled, int to) => InkResponse(
          onTap: enabled ? () => onChanged(to) : null,
          radius: 20,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: enabled ? ink : const Color(0xFFC4C4CA)),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: surfaceGrey, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canRemove && value <= min)
          btn(Icons.delete_outline, true, min - 1)
        else
          btn(Icons.remove, value > min, value - 1),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        btn(Icons.add, value < max, value + 1),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action, duration: const Duration(seconds: 2)));
}
