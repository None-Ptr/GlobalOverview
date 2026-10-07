import 'package:flutter/material.dart';
import 'package:global_overview/theme/go_tokens.dart';

/// name → Material 图标映射。
///
/// 选型三原则（2026-10-07 全表重挑）：
/// 1. **语义准**：图标要指向它标注的那件事（原先 `reading`/`words` 共用列表图标、
///    `target` 用定位针、`copy` 用回形针、`brain` 用调色板都属此类错配）。
/// 2. **风格统一**：默认走 Material 的 `_outlined` 线形族，与 App 的线描视觉一致；
///    只有「勾选」「加号」这类需要笔画压过底色的才用实心。
/// 3. **不重复**：同屏可能并列出现的语义必须给不同字形（如底部导航的 阅读/词汇）。
IconData goIcon(String name) {
  switch (name) {
    // —— 底部导航 ——
    case 'home':
      return Icons.home_outlined;
    case 'reading':
      return Icons.article_outlined; // 时文列表，与「词汇」区分
    case 'plan':
      return Icons.calendar_today_outlined;
    case 'words':
    case 'vocab':
      return Icons.menu_book_outlined; // 词汇本
    case 'mine':
      return Icons.person_outline;

    // —— 习惯 / 成就 ——
    case 'trophy':
      return Icons.emoji_events_outlined;
    case 'flame':
      return Icons.local_fire_department_outlined; // 连续航行
    case 'lock':
      return Icons.lock_outline;
    case 'check':
      return Icons.check;
    case 'quiz':
      return Icons.quiz_outlined; // 测验/累计测验
    case 'target':
      return Icons.track_changes; // 目标

    // —— 通用动作 ——
    case 'arrow-left':
      return Icons.arrow_back;
    case 'plus':
      return Icons.add;
    case 'menu':
      return Icons.menu;
    case 'bookmark':
      return Icons.bookmark_border; // 加入计划
    case 'star':
      return Icons.star_border; // 收藏/见闻
    case 'settings':
      return Icons.settings_outlined;
    case 'search':
      return Icons.search;
    case 'refresh':
      return Icons.refresh;
    case 'trash':
      return Icons.delete_outline;
    case 'chevron-right':
      return Icons.chevron_right;
    case 'close':
      return Icons.close;
    case 'eye':
      return Icons.visibility_outlined; // 显示密钥
    case 'eye-off':
      return Icons.visibility_off_outlined;

    // —— 提醒 / 警示 ——
    case 'bell':
      return Icons.notifications_none; // 提醒开关
    case 'bell-ring':
      return Icons.notifications_active; // 立刻发一条
    case 'clock':
      return Icons.schedule; // 提醒时间
    case 'warning':
    case 'alert':
      return Icons.error_outline;

    // —— 内容 / AI ——
    case 'robot':
      return Icons.smart_toy_outlined;
    case 'sparkle':
      return Icons.auto_awesome;
    case 'book':
    case 'book-open':
      return Icons.auto_stories_outlined;
    case 'book-check':
      return Icons.fact_check_outlined; // 错题本
    case 'rss':
      return Icons.rss_feed;
    case 'translate':
      return Icons.translate;
    case 'tts':
      return Icons.volume_up_outlined;
    case 'stop':
      return Icons.stop_circle_outlined;

    // —— 数据 ——
    case 'copy':
      return Icons.content_copy;
    case 'export':
      return Icons.file_download_outlined;
    case 'brain':
      return Icons.psychology_outlined;

    default:
      return Icons.help_outline;
  }
}

/// 统一图标组件，size 以 dp 计（对应 rpx 的一半）。
class GoIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final bool spin;
  const GoIcon(this.name, {super.key, this.size = 12, this.color, this.spin = false});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(goIcon(name), size: size, color: color ?? Go.onSurface2);
    if (!spin) return icon;
    return _Spin(child: icon);
  }
}

class _Spin extends StatefulWidget {
  final Widget child;
  const _Spin({required this.child});
  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}
