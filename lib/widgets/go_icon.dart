import 'package:flutter/material.dart';
import 'package:global_overview/theme/go_tokens.dart';

/// name → Material 图标映射，语义对齐原 `GoIcon.vue` 的 uni-icons 映射表。
IconData goIcon(String name) {
  switch (name) {
    case 'home':
      return Icons.home_outlined;
    case 'reading':
      return Icons.format_list_bulleted;
    case 'plan':
      return Icons.calendar_today_outlined;
    case 'words':
    case 'vocab':
      return Icons.format_list_bulleted;
    case 'mine':
      return Icons.person_outline;
    case 'trophy':
      return Icons.military_tech_outlined;
    case 'flame':
      return Icons.local_fire_department_outlined;
    case 'lock':
      return Icons.lock_outline;
    case 'check':
      return Icons.check;
    case 'arrow-left':
      return Icons.arrow_back;
    case 'plus':
      return Icons.add;
    case 'menu':
      return Icons.menu;
    case 'bookmark':
    case 'star':
      return Icons.star_outline;
    case 'settings':
      return Icons.settings_outlined;
    case 'robot':
      return Icons.chat_bubble_outline;
    case 'sparkle':
      return Icons.auto_awesome;
    case 'trash':
      return Icons.delete_outline;
    case 'target':
      return Icons.location_on_outlined;
    case 'search':
      return Icons.search;
    case 'rss':
      return Icons.rss_feed_outlined;
    case 'book-check':
      return Icons.check_box_outlined;
    case 'alert':
      return Icons.info_outline;
    case 'book':
    case 'book-open':
      return Icons.edit_note;
    case 'refresh':
      return Icons.refresh;
    case 'copy':
      return Icons.attach_file;
    case 'export':
      return Icons.upload_outlined;
    case 'brain':
      return Icons.palette_outlined;
    case 'translate':
      return Icons.translate;
    case 'tts':
      return Icons.volume_up_outlined;
    case 'stop':
      return Icons.stop_circle_outlined;
    case 'chevron-right':
      return Icons.chevron_right;
    case 'close':
      return Icons.close;
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
