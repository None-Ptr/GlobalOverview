// Hallmark · screen: feature guide sheet · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S4 R5 V4 · weakest S — the same four notes as the first run, offered once and dismissible
import 'package:global_overview/v4/screens/guide_screen.dart';
import 'package:global_overview/v4/services/guide_content.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// Shown once to readers who finished onboarding before these features existed.
Future<void> showFeatureGuideSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.v4.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(V4Radius.sheet)),
    ),
    builder: (_) => const _FeatureGuideSheet(),
  );
}

class _FeatureGuideSheet extends StatelessWidget {
  const _FeatureGuideSheet();

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.xl,
          V4Space.md,
          V4Space.xl,
          V4Space.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: v4.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: V4Space.lg),
            Text('这几件事，现在可以做', style: type.sectionTitle),
            const SizedBox(height: V4Space.xs),
            Text(
              '之后在「我的 → 使用指南」里也能找到。',
              style: type.label,
            ),
            const SizedBox(height: V4Space.xl),
            for (var i = 0; i < featureNotes.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: V4Space.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: type.caption.copyWith(color: v4.brand),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(featureNotes[i].title, style: type.itemTitle),
                          const SizedBox(height: V4Space.xs),
                          Text(featureNotes[i].note, style: type.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TButton(
                    size: TButtonSize.large,
                    variant: TButtonVariant.text,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ),
                const SizedBox(width: V4Space.md),
                Expanded(
                  child: V4PrimaryButton(
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => const V4GuideScreen(),
                        ),
                      );
                    },
                    child: const Text('看使用指南'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
