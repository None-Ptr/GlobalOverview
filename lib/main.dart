import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/app.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appConfig = AppConfigService();
  await appConfig.init();
  runApp(ProviderScope(
    overrides: [appConfigProvider.overrideWith((ref) => appConfig)],
    child: const MyApp(),
  ));
}
