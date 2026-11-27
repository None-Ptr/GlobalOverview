import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/v4/app_bootstrap.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/services/theme_mode_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The browser has no SQLite plugin; sqflite_common_ffi_web runs the same
  // SQLite inside a shared worker and keeps the database in IndexedDB.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  final appConfig = AppConfigService();
  await appConfig.init();
  final onboarding = OnboardingService();
  final profile = await onboarding.load();
  final themeMode = await V4ThemeModeStore().load();
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWith((ref) => appConfig)],
      child: V4Bootstrap(
        service: onboarding,
        initialProfile: profile,
        initialThemeMode: themeMode,
      ),
    ),
  );
}