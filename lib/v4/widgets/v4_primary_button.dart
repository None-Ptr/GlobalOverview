import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// The one primary call to action.
///
/// TDesign paints a filled primary label with `textColorAnti`, which in the
/// dark palette resolves to near-white — unreadable on the light dark-mode
/// brand. The label and any untinted icon are forced to the palette's on-brand
/// ink instead. Disabled buttons keep TDesign's own colours, because the
/// disabled fill is a dark slate where the anti colour is correct.
class V4PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final TButtonSize size;

  const V4PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = TButtonSize.large,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final label = onPressed == null
        ? child
        : DefaultTextStyle.merge(
            style: TextStyle(color: v4.onBrand),
            child: IconTheme.merge(
              data: IconThemeData(color: v4.onBrand),
              child: child,
            ),
          );
    return TButton(
      size: size,
      colorPreset: TButtonColorPreset.primary,
      onPressed: onPressed,
      child: label,
    );
  }
}
