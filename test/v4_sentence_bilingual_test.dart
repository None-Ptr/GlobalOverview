import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/v4/screens/bilingual_screen.dart';
import 'package:global_overview/v4/services/article_repository.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/sentence_sheet.dart';

class _Db extends DbService {
  final writes = <String>[];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async => [];

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add(sql);
  }
}

class _FakeTranslate extends TranslateService {
  _FakeTranslate()
    : super(
        HttpService(),
        AppConfigService(),
        LlmService(HttpService(), AppConfigService()),
      );

  @override
  Future<String> translate(String text, {String from = 'en', String to = 'zh'}) async =>
      '译:$text';
}

final _article = V4Article(
  id: 1,
  guid: 'g-1',
  title: 'A readable article',
  sourceUrl: 'https://example.com/a',
  blocks: [
    ArticleBlock(type: 'p', text: 'Hello world.'),
    ArticleBlock(type: 'p', text: 'Second one.'),
  ],
  wordCount: 10,
  isCondensed: false,
);

void main() {
  testWidgets('全文翻译按段落给出译文', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [translateProvider.overrideWithValue(_FakeTranslate())],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: V4BilingualScreen(article: _article),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('对照翻译'), findsOneWidget);
    expect(find.text('Hello world.'), findsOneWidget);
    expect(find.text('译:Hello world.'), findsOneWidget);
    expect(find.text('译:Second one.'), findsOneWidget);
  });

  testWidgets('取句弹层给出原句与译文，并能收藏', (tester) async {
    final db = _Db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          translateProvider.overrideWithValue(_FakeTranslate()),
        ],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showSentenceSheet(
                    context,
                    sentence: 'Hello world.',
                    articleGuid: 'g-1',
                    articleTitle: 'A readable article',
                    sourceLabel: 'example.com',
                    paraIndex: 0,
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('原句'), findsOneWidget);
    expect(find.text('Hello world.'), findsOneWidget);
    expect(find.text('译:Hello world.'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      db.writes.any((sql) => sql.contains('INTO vocab_sentence')),
      isTrue,
    );
    expect(find.text('已收藏'), findsOneWidget);
  });
}
