import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/telescope_icon.dart';

class V4BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const V4BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const labels = ['今日', '阅读', '学习', '我的'];

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: v4.surface,
        border: Border(top: BorderSide(color: v4.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    selected: currentIndex == i,
                    button: true,
                    label: labels[i],
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _icon(i, currentIndex == i, v4),
                          const SizedBox(height: 2),
                          Text(
                            labels[i],
                            style: type.caption.copyWith(
                              color: currentIndex == i ? v4.brand : v4.inkMuted,
                              fontWeight: currentIndex == i
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(int index, bool active, V4Palette v4) {
    final color = active ? v4.brand : v4.inkMuted;
    switch (index) {
      case 0:
        return V4TelescopeIcon(size: 22, color: color, semanticsLabel: null);
      case 1:
        return Icon(Icons.public_outlined, size: 22, color: color);
      case 2:
        return Icon(Icons.menu_book_outlined, size: 22, color: color);
      default:
        return Icon(Icons.person_outline, size: 22, color: color);
    }
  }
}
