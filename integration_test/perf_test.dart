import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/vocab_screen.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/services/vocab_service.dart';
import 'package:global_overview/theme/app_theme.dart';
import 'package:global_overview/widgets/bottom_nav.dart';
import 'package:global_overview/widgets/go_ui.dart';

// 播种规模（模拟重度使用者）
const int _seedQ = 600; // 题目数
const int _seedHeads = 300; // 词条数
const int _occPer = 6; // 每个词条的出现次数

double _avg(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
double _pct(List<double> v, double p) =>
    v.isEmpty ? 0 : v[(v.length * p).toInt().clamp(0, v.length - 1)];

/// 渲染指定页面 [frames] 帧，返回 FrameTiming（UI 线程 build+paint 耗时）。
Future<List<FrameTiming>> _measureFrames(WidgetTester tester, Widget app, {int frames = 90}) async {
  await tester.pumpWidget(app);
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 400)); // 等陆地 GeoJSON 载入
  final t = <FrameTiming>[];
  void cb(List<FrameTiming> x) => t.addAll(x);
  WidgetsBinding.instance.addTimingsCallback(cb);
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  WidgetsBinding.instance.removeTimingsCallback(cb);
  return t;
}

/// 旧实现：错题本 / 错题导出的“全表 + 内存过滤”。
Future<int> _oldWrongList(DbService db) async {
  final questions = await db.select('SELECT * FROM questions ORDER BY id ASC');
  final answers = await db.select('SELECT * FROM answers ORDER BY gradedAt DESC');
  final latest = <int, Map<String, dynamic>>{};
  for (final a in answers) {
    latest.putIfAbsent(a['questionId'] as int, () => a);
  }
  final out = <Map<String, dynamic>>[];
  for (final q in questions) {
    final a = latest[q['id'] as int];
    if (a == null) continue;
    if ((a['wrong'] as int? ?? 0) != 1 && a['status'] != 'pending') continue;
    out.add(q);
  }
  return out.length;
}

/// 旧实现：recordOccurrence 的 4 次往返（先 SELECT 存在性）。
Future<void> _oldRecord(DbService db, String word, String guid, int ti) async {
  final lemma = word.toLowerCase().trim();
  final now = DateTime.now().millisecondsSinceEpoch;
  final exist = await db.select(
      'SELECT id FROM vocab_occ WHERE word = ? AND articleGuid = ? AND paraIndex = ? AND tokIndex = ?',
      [word, guid, 0, ti]);
  if (exist.isNotEmpty) return;
  await db.execute(
      'INSERT OR IGNORE INTO vocab_occ (word, lemma, articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, at) VALUES (?,?,?,?,?,?,?,?,?)',
      [word, lemma, guid, 'T', 'S', 'sentence $word', 0, ti, now]);
  final rows = await db.select('SELECT head FROM vocab_head WHERE head = ?', [lemma]);
  if (rows.isEmpty) {
    await db.execute(
        'INSERT INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due, fsrs_s, fsrs_d) VALUES (?,?,?,?,?,?,?,?,?)',
        [lemma, 'word', now, now, 1, 0, now, 0.0, 0.0]);
  } else {
    await db.execute('UPDATE vocab_head SET occCount = occCount + 1, lastSeen = ? WHERE head = ?', [now, lemma]);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final db = DbService();

  setUpAll(() async {
    await db.database;
    // 词条 + 出现记录
    for (var i = 0; i < _seedHeads; i++) {
      final h = 'zzperf_$i';
      await db.execute(
        'INSERT OR REPLACE INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due, fsrs_s, fsrs_d) VALUES (?,?,?,?,?,?,?,?,?)',
        [h, 'word', i, 100000 - i, _occPer, 0, 0, 0.0, 0.0],
      );
      for (var k = 0; k < _occPer; k++) {
        await db.execute(
          'INSERT OR REPLACE INTO vocab_occ (word, lemma, articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, at) VALUES (?,?,?,?,?,?,?,?,?)',
          [h, h, 'g${i % 40}', 'Title', 'Src', 'A sample sentence containing $h number $k here.', 0, k, i * 100 + k],
        );
      }
    }
    // 题目 + 作答（约 35% 最终判错 → 错题本规模）
    for (var i = 0; i < _seedQ; i++) {
      await db.execute(
        'INSERT OR REPLACE INTO questions (id, setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [i + 1, 1, 'choice', 'exact', 'Question ${i + 1}', '["A","B"]', '["A"]', 'analysis', 'quote', i],
      );
      final wrong = (i % 100) < 35 ? 1 : 0; // 约 35% 错
      await db.execute(
        'INSERT OR REPLACE INTO answers (questionId, draft, final, correct, wrong, status, comment, gradedAt) VALUES (?,?,?,?,?,?,?,?)',
        [i + 1, null, 'my answer ${i + 1}', wrong == 1 ? 0 : 1, wrong, 'graded', 'c', 1000 + i],
      );
    }
  });

  tearDownAll(() async {
    await db.execute("DELETE FROM vocab_head WHERE head LIKE 'zzperf_%' OR head LIKE 'zzold_%' OR head LIKE 'zznew_%'");
    await db.execute("DELETE FROM vocab_occ WHERE lemma LIKE 'zzperf_%' OR lemma LIKE 'zzold_%' OR lemma LIKE 'zznew_%'");
    await db.execute('DELETE FROM answers WHERE gradedAt >= 1000 AND gradedAt < 100000');
    await db.execute('DELETE FROM questions WHERE setId = 1 AND prompt LIKE \'Question %\'');
  });

  testWidgets('优化前 vs 优化后（同一设备同一数据）', (tester) async {
    final vocab = VocabService(db, LlmService(HttpService(), AppConfigService()));
    final quiz = QuizService(LlmService(HttpService(), AppConfigService()), db);

    // === A) 错题列表查询 ===
    final swA1 = Stopwatch()..start();
    final oldRows = await _oldWrongList(db);
    swA1.stop();
    final swA2 = Stopwatch()..start();
    final newRows = (await quiz.loadWrongList()).length;
    swA2.stop();
    debugPrint('CMP wrong-list  BEFORE=${swA1.elapsedMicroseconds / 1000}ms(rows $oldRows, 全表 SELECT* questions+answers)'
        '  AFTER=${swA2.elapsedMicroseconds / 1000}ms(rows $newRows, 受限 JOIN)');

    // === B) 词汇页 vocab_occ 读取（全表拉取 vs GROUP BY 聚合）===
    final swB1 = Stopwatch()..start();
    final occAll = await db.select(
        'SELECT articleGuid, articleTitle, sourceLabel, sentence, lemma FROM vocab_occ ORDER BY at DESC');
    swB1.stop();
    final swB2 = Stopwatch()..start();
    final agg = await db.select(
        'SELECT lemma, COUNT(DISTINCT articleGuid) AS c, MAX(at) AS m, sentence FROM vocab_occ GROUP BY lemma');
    swB2.stop();
    debugPrint('CMP getHeads occ  BEFORE=${swB1.elapsedMicroseconds / 1000}ms(rows ${occAll.length}, 全表)'
        '  AFTER=${swB2.elapsedMicroseconds / 1000}ms(rows ${agg.length}, GROUP BY)');

    // 整体 getHeads（新实现）
    final swB3 = Stopwatch()..start();
    final heads = await vocab.getHeads();
    swB3.stop();
    debugPrint('CMP getHeads full  AFTER=${swB3.elapsedMilliseconds}ms(rows ${heads.length})');

    // === C) recordOccurrence 每次点词的写库往返 ===
    const n = 200;
    final swC1 = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      await _oldRecord(db, 'zzold_$i', 'go', i);
    }
    swC1.stop();
    final swC2 = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      await vocab.recordOccurrence('zznew_$i', 'sentence', 'gn', 'T', 'S', 0, i);
    }
    swC2.stop();
    debugPrint('CMP recordOcc  x$n  BEFORE=${swC1.elapsedMicroseconds / 1000}ms(4 往返)'
        '  AFTER=${swC2.elapsedMicroseconds / 1000}ms(3 往返, 合并存在性 SELECT)');

    // === D) getOccurrence（复合索引 (lemma,at) vs 单列 lemma）===
    final swD1 = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await vocab.getOccurrence('zzperf_$i');
    }
    swD1.stop();
    // 退回单列索引模拟“优化前”
    await db.execute('DROP INDEX IF EXISTS idx_vocab_occ_lemma_at');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_vocab_occ_lemma ON vocab_occ(lemma)');
    final swD2 = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await vocab.getOccurrence('zzperf_$i');
    }
    swD2.stop();
    // 恢复复合索引
    await db.execute('DROP INDEX IF EXISTS idx_vocab_occ_lemma');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_vocab_occ_lemma_at ON vocab_occ(lemma, at)');
    debugPrint('CMP getOccurrence x200  BEFORE=${swD2.elapsedMicroseconds / 1000}ms(单列 lemma 索引)'
        '  AFTER=${swD1.elapsedMicroseconds / 1000}ms(复合 (lemma,at), 免临时排序)');

    // === E) 词汇列表滚动帧耗时 ===
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: VocabScreen()),
    ));
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    WidgetsBinding.instance.addTimingsCallback(onTimings);
    for (var round = 0; round < 4; round++) {
      await tester.fling(find.byType(Scrollable).first, const Offset(0, -900), 3000);
      for (var f = 0; f < 25; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    WidgetsBinding.instance.removeTimingsCallback(onTimings);
    final build = timings.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList()..sort();
    final raster = timings.map((t) => t.rasterDuration.inMicroseconds / 1000.0).toList()..sort();
    debugPrint('PERF frames=${timings.length} build avg=${_avg(build).toStringAsFixed(2)} '
        'p90=${_pct(build, 0.9).toStringAsFixed(2)} max=${build.isEmpty ? 0 : build.last.toStringAsFixed(2)}ms | '
        'raster avg=${_avg(raster).toStringAsFixed(2)} p90=${_pct(raster, 0.9).toStringAsFixed(2)} '
        'max=${raster.isEmpty ? 0 : raster.last.toStringAsFixed(2)}ms | '
        'missed(>16.7ms)=${build.where((x) => x > 16.67).length}/${raster.where((x) => x > 16.67).length}');

    // === F) 地球背景每帧渲染成本（首页默认激活；UI 线程 paint）===
    Widget darkPage(bool active) => MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: GoPage(globe: true, globeActive: active, child: const SizedBox.expand()),
        );
    final gOn = (await _measureFrames(tester, darkPage(true)))
        .map((t) => t.buildDuration.inMicroseconds / 1000.0)
        .toList()
      ..sort();
    final gOff = (await _measureFrames(tester, darkPage(false)))
        .map((t) => t.buildDuration.inMicroseconds / 1000.0)
        .toList()
      ..sort();
    debugPrint('CMP globe  ON=${_avg(gOn).toStringAsFixed(2)}ms(avg)/${_pct(gOn, 0.9).toStringAsFixed(2)}ms(p90)  '
        'OFF=${_avg(gOff).toStringAsFixed(2)}ms(avg)/${_pct(gOff, 0.9).toStringAsFixed(2)}ms(p90)');

    // === G) 常驻底部导航（玻璃模糊 + 激活项脉冲）每帧成本 ===
    Future<List<double>> navFrames(Widget bar) async {
      final t = await _measureFrames(
        tester,
        MaterialApp(
          theme: buildDarkTheme(),
          home: Scaffold(body: const SizedBox.expand(), bottomNavigationBar: bar),
        ),
      );
      return t.map((x) => x.buildDuration.inMicroseconds / 1000.0).toList();
    }

    final navOn = await navFrames(BottomNav(currentIndex: 0, onTap: (_) {}));
    final navBare = await navFrames(const SizedBox(height: 80));
    debugPrint('CMP bottomnav ON=${_avg(navOn).toStringAsFixed(2)}ms(avg)/${_pct(navOn, 0.9).toStringAsFixed(2)}ms(p90)  '
        'BARE=${_avg(navBare).toStringAsFixed(2)}ms(avg)/${_pct(navBare, 0.9).toStringAsFixed(2)}ms(p90)');
  });
}
