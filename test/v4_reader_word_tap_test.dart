import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/services/word_service.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';

class _WordDb extends DbService {
  final writes = <String>[];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM articles')) {
      return [
        {
          'guid': 'g-1',
          'title': 'A readable article',
          'sourceUrl': 'https://example.com/a',
          'html': '<p>body</p>',
          'blocks': '[{"type":"p","text":"First paragraph."}]',
          'wordCount': 120,
        },
      ];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add(sql);
  }

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    writes.add(sql);
    return 1;
  }
}

class _FakeWord extends WordService {
  _FakeWord()
    : super(
        DbService(),
        TranslateService(
          HttpService(),
          AppConfigService(),
          LlmService(HttpService(), AppConfigService()),
        ),
      );

  @override
  Future<String> lookup(String word, {String mode = 'en2zh'}) async =>
      '释义:$word';
}

Future<void> _open(WidgetTester tester, _WordDb db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        wordProvider.overrideWithValue(_FakeWord()),
      ],
      child: MaterialApp(
        theme: V4Theme.light(),
        home: const V4ReaderScreen(articleId: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('点正文里的词，词卡给出释义和原句', (tester) async {
    final db = _WordDb();
    await _open(tester, db);

    final paragraph = find.text('First paragraph.');
    await tester.tapAt(tester.getTopLeft(paragraph) + const Offset(6, 8));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('释义:First'), findsOneWidget);
    expect(find.text('加入生词本'), findsOneWidget);
  });

  testWidgets('长按选中正文后，工具栏出现翻译与收藏', (tester) async {
    final db = _WordDb();
    await _open(tester, db);

    final paragraph = find.text('First paragraph.');
    final start = tester.getTopLeft(paragraph) + const Offset(4, 8);
    // A real long press holds DOWN before moving; this is what SelectableRegion
    // needs to enter selection mode (something adb swipe cannot simulate).
    final pointer = await tester.createGesture();
    await pointer.down(start);
    await tester.pump(const Duration(milliseconds: 600));
    await pointer.moveTo(start + const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await pointer.up();
    await tester.pumpAndSettle();

    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('词卡可以把词和原句写进生词本，并变成已加入', (tester) async {
    final db = _WordDb();
    await _open(tester, db);

    final paragraph = find.text('First paragraph.');
    await tester.tapAt(tester.getTopLeft(paragraph) + const Offset(6, 8));
    await tester.pumpAndSettle();

    await tester.tap(find.text('加入生词本'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      db.writes.any((sql) => sql.contains('INTO vocab_occ')),
      isTrue,
    );
    expect(find.text('加入生词本'), findsNothing);
    expect(find.text('已加入生词本'), findsWidgets);
  });
}
