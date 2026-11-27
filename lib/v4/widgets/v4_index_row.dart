// Hallmark · screen: settings index row · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S5 R4 V4 · weakest R — a fact on the right edge, never a chevron
import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

/// The settings-page counterpart of V4ArticleRow: title and note on the left,
/// one real fact on the right edge. Nothing points at the tap target.
class V4IndexRow extends StatelessWidget {
  final String title;
  final String? note;
  final String? trailing;
  final VoidCallback onTap;

  const V4IndexRow({
    super.key,
    required this.title,
    required this.onTap,
    this.note,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: V4Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: type.itemTitle),
                    if (note != null && note!.isNotEmpty) ...[
                      const SizedBox(height: V4Space.xs),
                      Text(
                        note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null && trailing!.isNotEmpty) ...[
                const SizedBox(width: V4Space.md),
                SizedBox(
                  width: 96,
                  child: Text(
                    trailing!,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.label.copyWith(color: v4.inkSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
