import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/services/extract_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/tts_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/services/grade_service.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/services/vocab_service.dart';
import 'package:global_overview/services/habit_service.dart';
import 'package:global_overview/services/export_service.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/curate_service.dart';
import 'package:global_overview/services/word_service.dart';

final dbProvider = Provider((ref) => DbService());
/// 这里用 read 而不是 watch：配置变更时不需要重建（HttpService 每次请求时才读配置），
/// 否则每次 notify 都会连带重建整条服务链并泄漏一个未 close 的 http.Client。
final httpProvider = Provider((ref) => HttpService(config: ref.read(appConfigProvider)));
final appConfigProvider = ChangeNotifierProvider<AppConfigService>((ref) => AppConfigService());
final rssProvider = Provider((ref) => RssService(ref.watch(httpProvider)));
final extractProvider = Provider((ref) => ExtractService());
final llmProvider = Provider((ref) => LlmService(ref.watch(httpProvider), ref.read(appConfigProvider)));
final ttsProvider = Provider((ref) => TtsService());
final translateProvider = Provider((ref) => TranslateService(ref.watch(httpProvider), ref.read(appConfigProvider), ref.watch(llmProvider)));
final gradeProvider = Provider((ref) => GradeService(ref.watch(llmProvider), ref.watch(dbProvider)));
final quizProvider = Provider((ref) => QuizService(ref.watch(llmProvider), ref.watch(dbProvider)));
final vocabProvider = Provider((ref) => VocabService(ref.watch(dbProvider), ref.watch(llmProvider)));
final habitProvider = Provider((ref) => HabitService(ref.watch(dbProvider)));
final exportProvider = Provider((ref) => ExportService());
final feedsProvider = Provider((ref) => FeedsService(ref.watch(dbProvider), ref.watch(rssProvider), ref.watch(httpProvider)));
final curateProvider = Provider((ref) => CurateService(ref.watch(llmProvider)));
final wordProvider = Provider((ref) => WordService(ref.watch(dbProvider), ref.watch(translateProvider)));

class ThemeModeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(appConfigProvider).darkMode;
  void set(bool v) {
    ref.read(appConfigProvider).setDarkMode(v);
    state = v;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, bool>(ThemeModeNotifier.new);

/// 当前底部 Tab 索引（0 首页 / 1 阅读 / 2 计划 / 3 词汇 / 4 我的）。
class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(TabIndexNotifier.new);

/// 计划（plan_items）变更信号。
///
/// 计划页是 IndexedStack 里的常驻 Tab，不会重建——任何地方增删计划项后调用
/// [PlanRevisionNotifier.bump]，计划页/阅读页监听后自动刷新。
class PlanRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final planRevisionProvider = NotifierProvider<PlanRevisionNotifier, int>(PlanRevisionNotifier.new);

/// 通用「数据变更信号」：数值每次 +1 即通知监听者刷新。
///
/// 用途：跨页面写入的数据（学习统计 / 词汇 / 全局目标），其所在页面是
/// IndexedStack 常驻 Tab，不会重建，必须靠信号驱动刷新。
class RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// 学习统计变更（交卷后 `habitProvider.recordCompletion`）。
final habitRevisionProvider = NotifierProvider<RevisionNotifier, int>(RevisionNotifier.new);

/// 词汇变更（阅读中点词、复习评分、增删词汇）。
final vocabRevisionProvider = NotifierProvider<RevisionNotifier, int>(RevisionNotifier.new);

/// 全局目标（`kv.targetLevel`）变更，「我的」页与「计划」页双向同步。
final targetLevelRevisionProvider = NotifierProvider<RevisionNotifier, int>(RevisionNotifier.new);
