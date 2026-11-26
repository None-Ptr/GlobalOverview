// Hallmark · screen: reading-list row · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S4 R4 V4 · weakest S — a two-column index row; time and the difficulty ticks carry the facts
import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_difficulty.dart';

class V4ArticleRow extends StatelessWidget {
  final String title;
  final String source;
  final String meta;

  /// FeedOverview's 0–100 score; the row names its band under the source.
  final int? difficulty;

  final VoidCallback onTap;

  const V4ArticleRow({
    super.key,
    required this.title,
    required this.source,
    required this.meta,
    required this.onTap,
    this.difficulty,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return InkWell(
      onTap: onTap,
      hoverColor: v4.surfaceSubtle,
      focusColor: v4.surfaceSubtle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V4Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.itemTitle,
                  ),
                  const SizedBox(height: V4Space.xs),
                  // Source on the left, the difficulty band on the right of the
                  // same line: what the piece is and how hard it reads, one look.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption,
                        ),
                      ),
                      if (difficulty != null) ...[
                        const SizedBox(width: V4Space.sm),
                        V4Difficulty(score: difficulty),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: V4Space.md),
            // A fact on the right edge, not a decorative chevron: the entry's
            // own time stamp balances the headline instead of trailing it.
            SizedBox(
              width: 120,
              child: Text(
                meta,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.label.copyWith(color: v4.inkSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
