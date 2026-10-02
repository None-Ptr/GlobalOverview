import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/theme/app_theme.dart';
import 'package:global_overview/widgets/go_ui.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/widgets/bottom_nav.dart';
import 'package:global_overview/screens/home_screen.dart';
import 'package:global_overview/screens/reading_screen.dart';
import 'package:global_overview/screens/plan_screen.dart';
import 'package:global_overview/screens/vocab_screen.dart';
import 'package:global_overview/screens/mine_screen.dart';
import 'package:global_overview/screens/article_screen.dart';
import 'package:global_overview/screens/quiz_screen.dart';
import 'package:global_overview/screens/wrong_screen.dart';
import 'package:global_overview/screens/export_screen.dart';
import 'package:global_overview/screens/model_form_screen.dart';
import 'package:global_overview/screens/translate_form_screen.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});
  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  // Tab 顺序对齐原 BottomNav.vue：首页 / 阅读 / 计划 / 词汇 / 我的
  static const _tabs = <Widget>[
    HomeScreen(),
    ReadingScreen(),
    PlanScreen(),
    VocabScreen(),
    MineScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(themeModeProvider);
    final index = ref.watch(tabIndexProvider);
    return MaterialApp(
      title: 'GlobalOverview',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: GoBackdrop(child: IndexedStack(index: index, children: _tabs)),
        bottomNavigationBar: BottomNav(currentIndex: index, onTap: (i) => ref.read(tabIndexProvider.notifier).set(i)),
      ),
      routes: {
        '/article': (c) => const ArticleScreen(),
        '/quiz': (c) => const QuizScreen(),
        '/wrong': (c) => const WrongScreen(),
        '/export': (c) => const ExportScreen(),
        '/model-form': (c) => const ModelFormScreen(),
        '/translate-form': (c) => const TranslateFormScreen(),
      },
    );
  }
}
