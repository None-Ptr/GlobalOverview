import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/migration_screen.dart';
import 'package:global_overview/v4/screens/onboarding_screen.dart';
import 'package:global_overview/v4/screens/v4_shell.dart';
import 'package:global_overview/v4/services/ai_cost_gate.dart';
import 'package:global_overview/v4/services/migration_service.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/services/theme_mode_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/feature_guide_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _V4Stage { loading, migration, onboarding, shell }

/// 首启只负责分层，不要求配置模型或来源。
class V4Bootstrap extends ConsumerStatefulWidget {
  final OnboardingService service;
  final V4Profile? initialProfile;
  final V4ThemeMode? initialThemeMode;

  const V4Bootstrap({
    super.key,
    required this.service,
    this.initialProfile,
    this.initialThemeMode,
  });

  @override
  ConsumerState<V4Bootstrap> createState() => _V4BootstrapState();
}

class _V4BootstrapState extends ConsumerState<V4Bootstrap> {
  late V4Profile _profile = widget.initialProfile ?? const V4Profile();
  _V4Stage _stage = _V4Stage.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initial = widget.initialThemeMode;
      if (initial != null) {
        ref.read(v4ThemeModeProvider.notifier).seed(initial);
      } else {
        ref.read(v4ThemeModeProvider.notifier).load();
      }
      _prepare();
    });
  }

  /// Set once the four feature notes have been shown; readers who finished
  /// onboarding earlier still get them a single time.
  static const _guideSeenKey = 'v4_feature_guide_seen_v1';

  Future<void> _prepare() async {
    try {
      final migration = V4MigrationService(ref.read(dbProvider));
      final needsMigration = await migration.shouldPrompt();
      if (!mounted) return;
      setState(() {
        _stage = needsMigration
            ? _V4Stage.migration
            : (_profile.completed ? _V4Stage.shell : _V4Stage.onboarding);
      });
      if (!needsMigration && _profile.completed) _maybeShowGuide();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _profile.completed ? _V4Stage.shell : _V4Stage.onboarding;
      });
      if (_profile.completed) _maybeShowGuide();
    }
  }

  Future<void> _maybeShowGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_guideSeenKey) == true) return;
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = AiCostGate.navigatorKey.currentContext;
        // Mark seen only after the sheet actually opens; an early frame with
        // no navigator must not swallow the one-time guide forever.
        if (context == null) return;
        showFeatureGuideSheet(context);
        prefs.setBool(_guideSeenKey, true);
      });
    } catch (_) {}
  }

  Future<void> _markGuideSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_guideSeenKey, true);
    } catch (_) {}
  }

  void _onMigrated(String? backupPath) {
    setState(() {
      _stage = _profile.completed ? _V4Stage.shell : _V4Stage.onboarding;
    });
  }

  void _onOnboarded(V4Profile profile) {
    // The closing onboarding step already showed these notes.
    _markGuideSeen();
    setState(() {
      _profile = profile;
      _stage = _V4Stage.shell;
    });
  }

  void _onWiped() {
    setState(() {
      _profile = const V4Profile();
      _stage = _V4Stage.onboarding;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(v4ThemeModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: AiCostGate.navigatorKey,
      title: 'GlobalOverview',
      theme: V4Theme.light(),
      darkTheme: V4Theme.dark(),
      themeMode: mode.themeMode,
      // On the desk the shell and its screens set their own measure. Only the
      // first-run steps stay at the width their single column was drawn for.
      builder: (context, child) {
        if (!kIsWeb || child == null) return child ?? const SizedBox.shrink();
        if (_stage == _V4Stage.shell) return child;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(child: SizedBox(width: 720, child: child)),
        );
      },
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    switch (_stage) {
      case _V4Stage.loading:
        return const _V4Splash();
      case _V4Stage.migration:
        return V4MigrationScreen(
          store: V4MigrationService(ref.read(dbProvider)),
          onComplete: _onMigrated,
        );
      case _V4Stage.onboarding:
        return V4OnboardingScreen(
          service: widget.service,
          onComplete: _onOnboarded,
        );
      case _V4Stage.shell:
        return V4Shell(profile: _profile, onWiped: _onWiped);
    }
  }
}

class _V4Splash extends StatelessWidget {
  const _V4Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GlobalOverview',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}