// Hallmark · screen: difficulty reading · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S4 R5 V4 · weakest S — four ticks and one word; the scale is a reading taken off the article, not a badge
import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

/// FeedOverview scores every entry 0–100. Four bands, named the way a Chinese
/// learner names a text rather than the way a test names a level.
enum V4DifficultyTier {
  foundation('基础', 'SHSEE'),
  school('高中', 'NCEE'),
  college('大学', 'CET6'),
  advanced('进阶', 'IELTS');

  /// Shown in the app.
  final String label;

  /// The exam level this band pre-selects when generating practice.
  final String level;

  const V4DifficultyTier(this.label, this.level);
}

/// A reading off the difficulty scale: four ascending ticks, the current band
/// filled in the brand tone, then the band's own word. Null score renders
/// nothing — an unknown difficulty is not a zero.
class V4Difficulty extends StatelessWidget {
  final int? score;

  /// The tick scale. Off in index rows, where the word alone carries it.
  final bool showScale;

  const V4Difficulty({
    super.key,
    required this.score,
    this.showScale = true,
  });

  static V4DifficultyTier? tierOf(int? score) {
    if (score == null) return null;
    if (score <= 51) return V4DifficultyTier.foundation;
    if (score <= 62) return V4DifficultyTier.school;
    if (score <= 74) return V4DifficultyTier.college;
    return V4DifficultyTier.advanced;
  }

  @override
  Widget build(BuildContext context) {
    final tier = tierOf(score);
    if (tier == null) return const SizedBox.shrink();
    final v4 = context.v4;
    final type = context.v4Type;
    final filled = tier.index + 1;
    return Semantics(
      label: '难度 ${tier.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showScale) ...[
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: 3,
                  height: 4 + i * 3,
                  decoration: BoxDecoration(
                    color: i < filled ? v4.brand : v4.rule,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            const SizedBox(width: V4Space.xs),
          ],
          Text(tier.label, style: type.caption),
        ],
      ),
    );
  }
}
