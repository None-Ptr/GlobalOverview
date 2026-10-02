import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 底部 TabBar，逐项对齐原 `BottomNav.vue`：
/// 5 个 Tab（首页/阅读/计划/词汇/我的），玻璃底 + 圆角胶囊，选中态 primary95 底、主色图标与文字。
class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _tabs = [
    (key: 'home', text: '首页'),
    (key: 'reading', text: '阅读'),
    (key: 'plan', text: '计划'),
    (key: 'words', text: '词汇'),
    (key: 'mine', text: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    // 必须显式给定高度：否则 Row 内的子项在不受限高度下会撑满整屏，
    // 导致 Scaffold 的 bottomNavigationBar 占满全高、body 被挤成 0（内容整体消失）。
    return SizedBox(
      height: Go.navH + bottom,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.only(left: Go.sp4, right: Go.sp4, top: Go.sp2, bottom: Go.sp2 + bottom),
            decoration: BoxDecoration(
              color: Go.surfaceRaised.withValues(alpha: 0.9),
              border: const Border(top: BorderSide(color: Go.outline, width: 0.5)),
              boxShadow: Go.navShadow,
            ),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: Center(child: _pill(_tabs[i].key, _tabs[i].text, currentIndex == i)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String key, String text, bool on) {
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      height: Go.r(64),
      padding: const EdgeInsets.symmetric(horizontal: Go.sp5),
      decoration: BoxDecoration(
        color: on ? Go.primary95 : Colors.transparent,
        borderRadius: BorderRadius.circular(Go.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GoIcon(key, size: Go.r(40), color: on ? Go.primary : Go.onSurface3),
          const SizedBox(width: Go.sp2),
          Text(
            text,
            style: TextStyle(
              fontSize: Go.fsMeta,
              height: 1.2,
              fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              color: on ? Go.primary : Go.onSurface3,
            ),
          ),
        ],
      ),
    );
    return on ? GoGlowPulse(color: Go.primary, child: pill) : pill;
  }
}
