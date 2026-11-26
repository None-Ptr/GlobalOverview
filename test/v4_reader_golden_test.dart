import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/services/image_cache.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class _GoldenDb extends DbService {
  static const _body = [
    'Reading assessment tools measure different things: how accurately a '
        'student reads, what the student understands, or how difficult a text '
        'is likely to be. A single number rarely captures all three.',
    'A student who reads a passage accurately may still misunderstand it. '
        'Research distinguishes word recognition from the language and '
        'knowledge needed for comprehension. Choose an assessment by the '
        'question it needs to answer.',
    'Lexile measures are the most widely used readability scale in American '
        'schools. They describe a text, not a reader, and they say nothing '
        'about whether the topic is suitable for a particular class.',
    'Running records, by contrast, are taken while a child reads aloud. The '
        'teacher notes every substitution and omission, then uses those notes '
        'to place the child at an instructional level.',
    'Whichever tool a department adopts, the useful question is the same: '
        'what decision will this number change, and who is accountable for it?',
  ];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM plan_items')) return [];
    if (sql.contains('FROM articles')) {
      final blocks = [
        for (final text in _body) {'type': 'p', 'text': text},
      ];
      return [
        {
          'guid': 'g-golden',
          'title': '8 Tools To Measure Reading Levels Of Texts',
          'sourceUrl': 'https://teachthought.com/literacy/reading-levels',
          'html': '<p>body</p>',
          'blocks': _encode(blocks),
          'wordCount': 420,
        },
      ];
    }
    return [];
  }

  String _encode(List<Map<String, String>> blocks) {
    final parts = blocks
        .map((b) => '{"type":"${b['type']}","text":${_quote(b['text']!)}}')
        .join(',');
    return '[$parts]';
  }

  String _quote(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

class _NoImages extends V4ImageCache {
  _NoImages() : super(HttpService());

  @override
  Future<File?> resolve(String url) async => null;
}

Future<void> _loadLiterata() async {
  final loader = FontLoader('Literata');
  for (final path in [
    'assets/fonts/Literata-Regular.ttf',
    'assets/fonts/Literata-SemiBold.ttf',
  ]) {
    final bytes = await File(path).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

  Future<void> _loadPlatformFonts() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
    await _loadFamily('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    final deng = r'C:\Windows\Fonts\Deng.ttf';
    await _loadFamily('Deng', [deng]);
    // TDesign resolves its CJK stack to Roboto off Apple platforms, and some of
    // its text styles keep the raw PingFang family; map both to a font that has
    // glyphs so goldens are readable.
    await _loadFamily('Roboto', [deng]);
    await _loadFamily('PingFang SC', [deng]);
    final icons = await rootBundle.load(
      'packages/tdesign_flutter_icons/fonts/t.ttf',
    );
    await (FontLoader('packages/tdesign_flutter_icons/TIcons')
          ..addFont(Future.value(icons)))
        .load();
  }

Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    any = true;
  }
  if (any) await loader.load();
}

  ThemeData _withUiFont(ThemeData base) {
    final themed = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Deng'),
      // TDesign's button theme replaces the ambient text style with a fontless
      // one, so give it the golden font explicitly.
      textButtonTheme: TextButtonThemeData(
        style: const ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontFamily: 'Deng', fontSize: 14, height: 1.45),
          ),
        ),
      ),
    );
    return themed.mergeExtension(
      const TStepperThemeData(textStyle: TextStyle(fontFamily: 'Deng')),
    );
  }

Widget _app(bool dark) {
  return ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(_GoldenDb()),
      imageCacheProvider.overrideWith((ref) => _NoImages()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withUiFont(V4Theme.light()),
      darkTheme: _withUiFont(V4Theme.dark()),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Deng'),
        child: child!,
      ),
      home: const V4ReaderScreen(articleId: 1),
    ),
  );
}

Future<void> _open(WidgetTester tester, bool dark) async {
  tester.view.physicalSize = const Size(720, 1280);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(dark));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadLiterata();
    await _loadPlatformFonts();
  });

  for (final dark in [false, true]) {
    testWidgets('reader golden ${dark ? 'dark' : 'light'}', (tester) async {
      await _open(tester, dark);
      await expectLater(
        find.byType(V4ReaderScreen),
        matchesGoldenFile('goldens/reader_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }

  testWidgets('reader golden scrolled', (tester) async {
    await _open(tester, false);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    // A short upward nudge brings the bar back with the remaining-time readout.
    await tester.drag(find.byType(ListView), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.textContaining('还剩'), findsOneWidget);
    await expectLater(
      find.byType(V4ReaderScreen),
      matchesGoldenFile('goldens/reader_scrolled.png'),
    );
  });

  testWidgets('reader golden end', (tester) async {
    await _open(tester, false);
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(V4ReaderScreen),
      matchesGoldenFile('goldens/reader_end.png'),
    );
  });

  testWidgets('reader golden settings', (tester) async {
    await _open(tester, false);
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/reader_settings.png'),
    );
  });
}
