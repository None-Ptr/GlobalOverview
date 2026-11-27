// Hallmark · screen: top nav · genre: editorial · theme: custom (observation station) · scope: app · viewport: wide
// critique: P4 H5 E4 S4 R4 V4 · weakest E — four destinations do not earn a rail, so the desk gets one rule and one wordmark
import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/telescope_icon.dart';

/// Desk chrome: wordmark, the four destinations, one rule under them. The
/// bottom bar is the phone's answer to the same question.
class V4TopNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const V4TopNav({super.key, required this.currentIndex, required this.onTap});

  static const labels = ['今日', '阅读', '学习', '我的'];

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: v4.rule)),
      ),
      child: Material(
        color: v4.surface,
        child: SizedBox(
          height: 64,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: V4Layout.content),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V4Space.xxxl,
                ),
                child: Row(
                  children: [
                    V4TelescopeIcon(
                      size: 22,
                      color: v4.ink,
                      semanticsLabel: null,
                    ),
                    const SizedBox(width: V4Space.sm),
                    Text('GlobalOverview', style: type.itemTitle),
                    const SizedBox(width: V4Space.huge),
                    for (var i = 0; i < labels.length; i++)
                      _NavTab(
                        label: labels[i],
                        active: currentIndex == i,
                        onTap: () => onTap(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final color = widget.active
        ? v4.ink
        : (_hover ? v4.ink : v4.inkSecondary);
    return Semantics(
      selected: widget.active,
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: v4.surfaceSubtle,
          focusColor: v4.surfaceSubtle,
          borderRadius: BorderRadius.circular(V4Radius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V4Space.lg,
              vertical: V4Space.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: type.label.copyWith(
                    color: color,
                    fontWeight: widget.active
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 20,
                  height: 2,
                  color: widget.active ? v4.brand : v4.surface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
