// Hallmark · screen: shell · genre: editorial · theme: custom (observation station) · scope: app · viewport: wide
// critique: P4 H5 E5 S4 R4 V4 · weakest V — the shell only decides where the four destinations live, nothing else
import 'package:flutter/material.dart';
import 'package:global_overview/v4/screens/learning_screen.dart';
import 'package:global_overview/v4/screens/mine_screen.dart';
import 'package:global_overview/v4/screens/reading_screen.dart';
import 'package:global_overview/v4/screens/today_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_bottom_nav.dart';
import 'package:global_overview/v4/widgets/v4_top_nav.dart';

class V4Shell extends StatefulWidget {
  final V4Profile profile;
  final VoidCallback? onWiped;
  const V4Shell({super.key, required this.profile, this.onWiped});

  @override
  State<V4Shell> createState() => _V4ShellState();
}

class _V4ShellState extends State<V4Shell> {
  int _index = 0;

  /// Built once. IndexedStack reuses the same widget instances, so switching
  /// tabs no longer rebuilds the other three screens on every tap.
  late List<Widget> _tabs = _buildTabs();

  List<Widget> _buildTabs() => [
        V4TodayScreen(
          profile: widget.profile,
          onOpenReading: () => setState(() => _index = 1),
        ),
        V4ReadingScreen(profile: widget.profile),
        const V4LearningScreen(),
        V4MineScreen(profile: widget.profile, onWiped: widget.onWiped),
      ];

  @override
  void didUpdateWidget(covariant V4Shell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile ||
        oldWidget.onWiped != widget.onWiped) {
      _tabs = _buildTabs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = V4Layout.isWide(context);
    void select(int index) => setState(() => _index = index);
    return Scaffold(
      backgroundColor: context.v4.page,
      body: Column(
        children: [
          if (wide) V4TopNav(currentIndex: _index, onTap: select),
          Expanded(child: IndexedStack(index: _index, children: _tabs)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : V4BottomNav(currentIndex: _index, onTap: select),
    );
  }
}
