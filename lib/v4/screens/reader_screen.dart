// Hallmark · screen: reader · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S5 R5 V4 · weakest P — tone without an argument; the lede and marginal ordinals carry the observation-log idea
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/habit_service.dart';
import 'package:global_overview/services/share_service.dart';
import 'package:global_overview/services/tts_service.dart';
import 'package:global_overview/v4/screens/bilingual_screen.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/services/article_repository.dart';
import 'package:global_overview/v4/services/practice_service.dart';
import 'package:global_overview/v4/services/text_probe.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/article_image.dart';
import 'package:global_overview/v4/widgets/practice_sheet.dart';
import 'package:global_overview/v4/widgets/set_label_sheet.dart';
import 'package:global_overview/v4/widgets/sentence_sheet.dart';
import 'package:global_overview/v4/widgets/telescope_icon.dart';
import 'package:global_overview/v4/widgets/v4_difficulty.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:global_overview/v4/widgets/word_card.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class V4ReaderScreen extends ConsumerStatefulWidget {
  final int articleId;
  const V4ReaderScreen({super.key, required this.articleId});

  @override
  ConsumerState<V4ReaderScreen> createState() => _V4ReaderScreenState();
}

class _V4ReaderScreenState extends ConsumerState<V4ReaderScreen> {
  static const _measure = 640.0;
  static const _gutter = 24.0;
  static const _minSize = 16.0;
  static const _maxSize = 24.0;
  static const _preview =
      'Reading is a conversation between you and the page.';

  V4Article? _article;
  bool _loading = true;
  bool _inPlan = false;
  bool _completed = false;
  bool _awarding = false;
  bool _generating = false;
  bool _curating = false;
  bool _showCurated = false;
  int _curatedWords = 0;
  int _practiceRun = 0;
  List<Map<String, dynamic>> _sets = const [];
  bool _focus = false;
  /// A notifier rather than state: the bar collapses while the reader
  /// scrolls, and rebuilding the whole article for that would drop frames.
  final _barVisible = ValueNotifier<bool>(true);
  double _lastOffset = 0;
  String _selection = '';
  String? _error;
  double _fontSize = 18;
  double _lineHeight = 1.75;
  final _scroll = ScrollController();
  final _progress = ValueNotifier<double>(0);
  final _speaking = ValueNotifier<bool>(false);
  final _practiceStage = ValueNotifier<PracticeProgress>(
    const PracticeProgress(0, ''),
  );
  final _selectionKey = GlobalKey<SelectionAreaState>();
  TtsService? _tts;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    _fontSize = config.fontSize;
    _lineHeight = config.lineHeight;
    _scroll.addListener(_trackProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_trackProgress);
    _scroll.dispose();
    _progress.dispose();
    _practiceStage.dispose();
    _barVisible.dispose();
    _tts?.playing.removeListener(_syncSpeaking);
    _speaking.dispose();
    super.dispose();
  }

  void _trackProgress() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final max = position.maxScrollExtent;
    final value = max <= 0 ? 1.0 : (position.pixels / max).clamp(0.0, 1.0);
    if ((value - _progress.value).abs() > 0.002) _progress.value = value;

    final pixels = position.pixels;
    final delta = pixels - _lastOffset;
    _lastOffset = pixels;
    if (_focus) return;
    final nearEnd = max > 0 && pixels >= max - 240;
    if (delta > 8 && pixels > 120 && !nearEnd && _barVisible.value) {
      _barVisible.value = false;
    } else if (delta < -8 && !_barVisible.value) {
      _barVisible.value = true;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final article = await V4ArticleRepository(
        ref.read(dbProvider),
      ).load(widget.articleId);
      // Plan membership and past sets are independent: fetch them together
      // so the first paint waits for one round trip, not three.
      final [plan, sets] = await Future.wait([
        ref.read(dbProvider).select(
          'SELECT articleId FROM plan_items WHERE articleId = ?',
          [widget.articleId],
        ),
        _loadSets(),
      ]);
      if (!mounted) return;
      setState(() {
        _article = article;
        _inPlan = plan.isNotEmpty;
        _sets = sets;
        _showCurated = article.hasCurated;
        _curatedWords = _countWords(article.curated);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _trackProgress());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '文章内容暂时不可用';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadSets() async {
    try {
      return await ref.read(quizProvider).listSetsForArticle(widget.articleId);
    } catch (_) {
      return const [];
    }
  }

  String get _host {
    final url = _article?.sourceUrl ?? '';
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return 'GlobalOverview';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// The blocks currently on screen: the curated version when one exists and
  /// is selected, the original otherwise.
  List<ArticleBlock> _currentBlocks(V4Article article) =>
      _showCurated && article.hasCurated ? article.curated : article.blocks;

  static int _countWords(List<ArticleBlock> blocks) => RegExp(
    r"[A-Za-z]+(?:['-][A-Za-z]+)*",
  ).allMatches(blocks.where((b) => b.type != 'img').map((b) => b.text ?? '').join(' ')).length;

  String get _plainText {
    final article = _article;
    if (article == null) return '';
    return _currentBlocks(article)
        .where((block) => block.type != 'img')
        .map((block) => (block.text ?? '').trim())
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  Future<void> _openOriginal() async {
    final article = _article;
    if (article == null || article.sourceUrl.isEmpty) return;
    final ok = await launchUrl(
      Uri.parse(article.sourceUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      showV4Snack(context, '无法打开原文链接', tone: V4SnackTone.warning);
    }
  }

  /// The piece as a message: title, then either the source link or, for text
  /// the reader imported themselves, the opening of the body — a link is the
  /// only thing worth sending when there is one.
  Future<void> _shareArticle() async {
    final article = _article;
    if (article == null) return;
    final lines = <String>[article.title];
    if (article.sourceUrl.isNotEmpty) {
      lines.add(article.sourceUrl);
    } else {
      final body = _plainText;
      if (body.isNotEmpty) {
        lines.add(
          body.length > 200 ? '${body.substring(0, 200).trimRight()}…' : body,
        );
      }
    }
    final outcome = await const ShareService().shareText(
      text: lines.join('\n\n'),
      subject: article.title,
    );
    if (!mounted) return;
    if (outcome == ShareOutcome.copied) {
      showV4Snack(context, '这台设备没有分享面板，已复制全文');
    } else if (outcome == ShareOutcome.failed) {
      showV4Snack(context, '没能分享，请重试', tone: V4SnackTone.warning);
    }
  }

  Future<void> _togglePlan() async {
    final db = ref.read(dbProvider);
    try {
      if (_inPlan) {
        await db.execute('DELETE FROM plan_items WHERE articleId = ?', [
          widget.articleId,
        ]);
      } else {
        await db.execute(
          'INSERT OR REPLACE INTO plan_items (articleId, addedAt) VALUES (?,?)',
          [widget.articleId, DateTime.now().millisecondsSinceEpoch],
        );
      }
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '操作没成功，请重试', tone: V4SnackTone.error);
      return;
    }
    if (!mounted) return;
    setState(() => _inPlan = !_inPlan);
    ref.read(planRevisionProvider.notifier).bump();
    showV4Snack(
      context,
      _inPlan ? '已加入精读单' : '已移出精读单',
      tone: V4SnackTone.success,
    );
  }

  Future<void> _markRead() async {
    final article = _article;
    if (article == null || _awarding || _completed) return;
    setState(() => _awarding = true);
    try {
      final counted = await ref.read(habitProvider).awardRead(article.guid);
      if (!mounted) return;
      setState(() {
        _awarding = false;
        _completed = true;
      });
      ref.read(habitRevisionProvider.notifier).bump();
      if (!counted) {
        showV4Snack(context, '今天已经记过这篇了');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _awarding = false);
      showV4Snack(context, '没记上，请重试', tone: V4SnackTone.error);
    }
  }

  Future<void> _startPractice() async {
    final article = _article;
    if (article == null || _generating) return;
    final options = await showPracticeSheet(
      context,
      defaultLevel: V4Difficulty.tierOf(article.difficulty)?.level,
    );
    if (options == null || !mounted) return;
    // Captured before any await: the widget can be gone by the time the model
    // answers, but the navigator it came from is still valid.
    final navigator = Navigator.of(context);
    final run = ++_practiceRun;
    setState(() => _generating = true);
    _practiceStage.value = const PracticeProgress(0, '正在读取正文');
    try {
      final setId = await V4PracticeService(
        ref.read(dbProvider),
        ref.read(quizProvider),
      ).generate(
        articleId: article.id,
        title: article.title,
        types: options.types,
        count: options.count,
        examLevel: options.examLevel,
        gradeMode: options.gradeMode,
        instruction: options.instruction,
        label: options.label,
        onProgress: (step, detail) {
          if (mounted && run == _practiceRun) {
            _practiceStage.value = PracticeProgress(step, detail);
          }
        },
      );
      if (!mounted || run != _practiceRun) return;
      // A generated set makes the article part of the study plan, so it can be
      // found again from 精读单 even when it was never added by hand.
      if (!_inPlan) {
        try {
          await ref.read(dbProvider).execute(
            'INSERT OR REPLACE INTO plan_items (articleId, addedAt) VALUES (?,?)',
            [article.id, DateTime.now().millisecondsSinceEpoch],
          );
          ref.read(planRevisionProvider.notifier).bump();
          if (mounted) setState(() => _inPlan = true);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _generating = false);
      await navigator.push(
        MaterialPageRoute(builder: (_) => V4QuizScreen(setId: setId)),
      );
      if (!mounted || run != _practiceRun) return;
      final sets = await _loadSets();
      if (mounted) setState(() => _sets = sets);
    } catch (e) {
      if (!mounted || run != _practiceRun) return;
      setState(() => _generating = false);
      if (e is AppException && e.code == 'aiCancelled') return;
      showV4Snack(context, errText(e), tone: V4SnackTone.error);
    }
  }

  /// Leaves the progress overlay without waiting for the model. The request
  /// keeps running in the background; [_practiceRun] makes its result inert.
  void _cancelPractice() {
    _practiceRun++;
    _practiceStage.value = const PracticeProgress(0, '');
    setState(() => _generating = false);
  }

  /// Asks the model for a tightened version of this article and stores it.
  /// The cost gate runs inside the call, so the reader confirms first.
  Future<void> _curate() async {
    final article = _article;
    if (article == null || _curating) return;
    setState(() => _curating = true);
    try {
      final blocks = await ref.read(curateProvider).curate(article.blocks);
      if (!mounted) return;
      if (blocks.isEmpty) {
        setState(() => _curating = false);
        showV4Snack(
          context,
          '这次没有生成精选版，请重试',
          tone: V4SnackTone.warning,
        );
        return;
      }
      await ref.read(dbProvider).saveCurated(
        article.id,
        blocks.map((b) => b.toJson()).toList(),
      );
      final fresh = await V4ArticleRepository(
        ref.read(dbProvider),
      ).load(article.id);
      if (!mounted) return;
      setState(() {
        _article = fresh;
        _showCurated = fresh.hasCurated;
        _curatedWords = _countWords(fresh.curated);
        _curating = false;
      });
      showV4Snack(context, '精选版已生成', tone: V4SnackTone.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _curating = false);
      if (e is AppException && e.code == 'aiCancelled') return;
      showV4Snack(context, errText(e), tone: V4SnackTone.error);
    }
  }

  Future<void> _clearCurated() async {
    final article = _article;
    if (article == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除精选版'),
        content: const Text('原文会保留，之后可以重新生成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(dbProvider).clearCurated(article.id);
    final fresh = await V4ArticleRepository(ref.read(dbProvider)).load(article.id);
    if (!mounted) return;
    setState(() {
      _article = fresh;
      _showCurated = false;
      _curatedWords = 0;
    });
    showV4Snack(context, '已删除精选版');
  }

  /// Blocks the page while the model works; the cost sheet has already asked.
  Widget _curatingOverlay() {
    final v4 = context.v4;
    final type = context.v4Type;
    return Positioned.fill(
      child: ColoredBox(
        color: v4.surface.withValues(alpha: 0.94),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.all(V4Space.xl),
              decoration: BoxDecoration(
                color: v4.surface,
                borderRadius: BorderRadius.circular(V4Radius.card),
                border: Border.all(color: v4.rule),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: V4Space.md),
                  Expanded(
                    child: Text('正在生成精选版', style: type.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _listen() async {
    final tts = ref.read(ttsProvider);
    if (_tts != tts) {
      _tts?.playing.removeListener(_syncSpeaking);
      _tts = tts;
      tts.playing.addListener(_syncSpeaking);
    }
    if (tts.isPlaying) {
      await tts.stop();
      return;
    }
    final text = _plainText;
    if (text.isEmpty) return;
    try {
      await tts.speak(text);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '这台设备暂时无法朗读', tone: V4SnackTone.warning);
    }
  }

  void _syncSpeaking() {
    if (mounted) _speaking.value = _tts?.isPlaying ?? false;
  }

  /// P10: tap a word, keep the sentence it came from.
  Future<void> _openWord(WordHit hit, String paragraph, int index) async {
    final article = _article;
    if (article == null) return;
    // A tap also collapses the selection; clear it so no stale toolbar lingers.
    _selectionKey.currentState?.selectableRegion.clearSelection();
    await showWordCard(
      context,
      word: hit.word,
      sentence: sentenceAt(paragraph, hit.start, hit.end),
      articleGuid: article.guid,
      articleTitle: article.title,
      sourceLabel: _host,
      paraIndex: index,
      tokIndex: hit.start,
    );
  }

  /// The toolbar works on the sentence around the selection, so a long-press
  /// that grabs one word still translates a whole sentence.
  String _sentenceForSelection() {
    final article = _article;
    final selection = _selection;
    if (article == null || selection.isEmpty) return selection;
    for (final block in article.blocks) {
      final text = block.text ?? '';
      final index = text.indexOf(selection);
      if (index < 0) continue;
      return sentenceAt(text, index, index + selection.length);
    }
    return selection;
  }

  int _paragraphOf(String text) {
    final article = _article;
    if (article == null) return 0;
    for (var i = 0; i < article.blocks.length; i++) {
      if ((article.blocks[i].text ?? '').contains(text)) return i;
    }
    return 0;
  }

  Widget _selectionToolbar(BuildContext context, SelectableRegionState state) {
    final items = <ContextMenuButtonItem>[...state.contextMenuButtonItems];
    if (_selection.isNotEmpty) {
      items.add(
        ContextMenuButtonItem(
          label: '翻译',
          onPressed: () {
            state.hideToolbar();
            _openSentence(_sentenceForSelection());
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '收藏',
          onPressed: () {
            state.hideToolbar();
            _saveSentence(_sentenceForSelection());
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _openSentence(String sentence) async {
    final article = _article;
    if (article == null || sentence.isEmpty) return;
    await showSentenceSheet(
      context,
      sentence: sentence,
      articleGuid: article.guid,
      articleTitle: article.title,
      sourceLabel: _host,
      paraIndex: _paragraphOf(sentence),
      sentences: sentenceCount(sentence),
    );
  }

  Future<void> _saveSentence(String sentence) async {
    final article = _article;
    if (article == null || sentence.isEmpty) return;
    try {
      await ref
          .read(vocabProvider)
          .saveSentence(
            sentence,
            article.guid,
            article.title,
            _host,
            _paragraphOf(sentence),
            0,
          );
      ref.read(vocabRevisionProvider.notifier).bump();
      if (!mounted) return;
      showV4Snack(context, '已收藏这句', tone: V4SnackTone.success);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '没收藏上，请重试', tone: V4SnackTone.error);
    }
  }

  void _openBilingual() {
    final article = _article;
    if (article == null) return;
    // Translate what is on screen, not whichever version happens to be stored.
    final shown = V4Article(
      id: article.id,
      guid: article.guid,
      title: article.title,
      sourceUrl: article.sourceUrl,
      blocks: _currentBlocks(article),
      wordCount: article.wordCount,
      isCondensed: article.isCondensed,
      difficulty: article.difficulty,
      curated: article.curated,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => V4BilingualScreen(article: shown)),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.v4.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(V4Radius.sheet),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final v4 = sheetContext.v4;
          final type = sheetContext.v4Type;
          final cfg = ref.read(appConfigProvider);
          String signed(int v) => v > 0 ? '+$v' : '$v';
          void apply({double? size, double? height}) {
            if (size != null) _fontSize = size;
            if (height != null) _lineHeight = height;
            if (mounted) setState(() {});
            ref
                .read(appConfigProvider)
                .setReader(fontSize: size, lineHeight: height);
            setSheet(() {});
          }

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                V4Space.xl,
                V4Space.md,
                V4Space.xl,
                V4Space.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: v4.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: V4Space.lg),
                  Row(
                    children: [
                      Text('阅读设置', style: type.itemTitle),
                      const Spacer(),
                      TButton(
                        size: TButtonSize.small,
                        variant: TButtonVariant.text,
                        onPressed: () => apply(size: 18, height: 1.75),
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                  const SizedBox(height: V4Space.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(V4Space.lg),
                    decoration: BoxDecoration(
                      color: v4.surfaceSubtle,
                      borderRadius: BorderRadius.circular(V4Radius.control),
                    ),
                    child: Text(
                      _preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: type.articleBody.copyWith(
                        fontSize: _fontSize,
                        height: _lineHeight,
                      ),
                    ),
                  ),
                  const SizedBox(height: V4Space.lg),
                  Row(
                    children: [
                      Text('字号', style: type.label),
                      const Spacer(),
                      TStepper(
                        value: _fontSize,
                        min: _minSize,
                        max: _maxSize,
                        step: 2,
                        size: TStepperSize.small,
                        onChanged: (value) => apply(size: value.toDouble()),
                      ),
                    ],
                  ),
                  const SizedBox(height: V4Space.lg),
                  Text('行距', style: type.label),
                  const SizedBox(height: V4Space.sm),
                  TRadioGroup<double>.options(
                    value: _nearestHeight(),
                    direction: Axis.horizontal,
                    variant: TRadioVariant.inline,
                    options: const [
                      TRadioOption(value: 1.5, label: '紧凑'),
                      TRadioOption(value: 1.8, label: '标准'),
                      TRadioOption(value: 2.1, label: '宽松'),
                    ],
                    onChanged: (value) => apply(height: value),
                  ),
                  const SizedBox(height: V4Space.xxl),
                  Text('朗读', style: type.itemTitle),
                  const SizedBox(height: V4Space.md),
                  Row(
                    children: [
                      Text('语音', style: type.label),
                      const Spacer(),
                      DropdownButton<String>(
                        value: AppConfigService.ttsVoices.containsKey(
                          cfg.ttsVoice,
                        )
                            ? cfg.ttsVoice
                            : AppConfigService.defaultTtsVoice,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: v4.surface,
                        style: type.label,
                        items: [
                          for (final entry
                              in AppConfigService.ttsVoices.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          cfg.setTts(voice: value);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: V4Space.md),
                  Text('语速', style: type.label),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: cfg.ttsRate.toDouble(),
                          min: -50,
                          max: 50,
                          divisions: 10,
                          label: signed(cfg.ttsRate),
                          onChanged: (value) {
                            cfg.setTts(rate: value.round());
                            setSheet(() {});
                          },
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          signed(cfg.ttsRate),
                          textAlign: TextAlign.right,
                          style: type.caption,
                        ),
                      ),
                    ],
                  ),
                  Text('语调', style: type.label),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: cfg.ttsPitch.toDouble(),
                          min: -50,
                          max: 50,
                          divisions: 10,
                          label: signed(cfg.ttsPitch),
                          onChanged: (value) {
                            cfg.setTts(pitch: value.round());
                            setSheet(() {});
                          },
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          signed(cfg.ttsPitch),
                          textAlign: TextAlign.right,
                          style: type.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _nearestHeight() {
    const options = [1.5, 1.8, 2.1];
    var best = options.first;
    for (final option in options) {
      if ((option - _lineHeight).abs() < (best - _lineHeight).abs()) {
        best = option;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    return Scaffold(
      backgroundColor: v4.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!_focus)
              ValueListenableBuilder<bool>(
                valueListenable: _barVisible,
                builder: (_, visible, _) => _barSlot(visible),
              ),
            if (!_focus) _progressLine(),
            Expanded(
              child: Stack(
                children: [
                  _content(),
                  if (_focus) _focusExit(),
                  if (_curating) _curatingOverlay(),
                  if (_generating) _practiceOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _focus ? null : _bottomBar(),
    );
  }

  /// Collapses upward on downward scroll, returns on any upward nudge.
  Widget _barSlot(bool visible) {
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1 : 0),
      duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: child,
        ),
      ),
      child: SizedBox(height: 48, child: _bar()),
    );
  }

  Widget _bar() {
    final v4 = context.v4;
    final ready = _article != null;
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 104),
          child: Center(child: _readout()),
        ),
        Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            const Spacer(),
            IconButton(
              tooltip: '阅读设置',
              onPressed: ready ? _openSettings : null,
              icon: Icon(Icons.format_size, color: v4.inkSecondary),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: Icon(Icons.more_horiz, color: v4.inkSecondary),
              onSelected: (value) {
                if (value == 'focus') setState(() => _focus = true);
                if (value == 'translate') _openBilingual();
                if (value == 'original') _openOriginal();
                if (value == 'share') _shareArticle();
                if (value == 'curate') _curate();
                if (value == 'clearCurated') _clearCurated();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'focus', child: Text('聚焦模式')),
                if (ready)
                  PopupMenuItem(
                    value: 'curate',
                    child: Text(
                      _article?.hasCurated == true ? '重新精选' : 'AI 精选',
                    ),
                  ),
                if (ready && _article?.hasCurated == true)
                  const PopupMenuItem(
                    value: 'clearCurated',
                    child: Text('删除精选版'),
                  ),
                if (ready)
                  const PopupMenuItem(value: 'translate', child: Text('全文翻译')),
                if (ready)
                  const PopupMenuItem(value: 'original', child: Text('打开原文')),
                if (ready)
                  const PopupMenuItem(value: 'share', child: Text('分享这篇文章')),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _readout() {
    final article = _article;
    if (article == null) return const SizedBox.shrink();
    final type = context.v4Type;
    final v4 = context.v4;
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, value, _) {
        final total = article.readingMinutes;
        var label = '';
        if (total > 0 && value >= 0.95) {
          label = '已读完';
        } else if (total > 0 && value >= 0.12) {
          final left = (total * (1 - value)).ceil().clamp(1, total);
          label = '还剩 $left 分钟';
        }
        return AnimatedSwitcher(
          duration: animate
              ? const Duration(milliseconds: 120)
              : Duration.zero,
          child: Text(
            label,
            key: ValueKey(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.caption.copyWith(color: v4.inkMuted),
          ),
        );
      },
    );
  }

  Widget _progressLine() {
    final v4 = context.v4;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _measure),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: SizedBox(
            height: 2,
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (context, value, _) {
                return Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: v4.rule)),
                    if (_article != null)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: value,
                            heightFactor: 1,
                            child: ColoredBox(color: v4.brand),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _practiceOverlay() {
    final v4 = context.v4;
    return Positioned.fill(
      child: ColoredBox(
        color: v4.surface.withValues(alpha: 0.94),
        child: Center(
          child: PracticeProgressPanel(
            stage: _practiceStage,
            onCancel: _cancelPractice,
          ),
        ),
      ),
    );
  }

  Widget _focusExit() {
    final v4 = context.v4;
    return Positioned(
      top: V4Space.sm,
      right: V4Space.md,
      child: Material(
        color: v4.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: v4.rule),
        ),
        child: IconButton(
          tooltip: '退出聚焦',
          onPressed: () => setState(() => _focus = false),
          icon: Icon(Icons.close, size: 20, color: v4.inkSecondary),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) return _skeleton();
    if (_error != null) return _errorState();
    final article = _article;
    if (article == null) return const SizedBox.shrink();
    return SelectionArea(
      key: _selectionKey,
      onSelectionChanged: (content) {
        _selection = content?.plainText.trim() ?? '';
      },
      contextMenuBuilder: _selectionToolbar,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: V4Space.xxl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _measure),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                child: _column(article),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(V4Article article) {
    final v4 = context.v4;
    final type = context.v4Type;
    final shown = _currentBlocks(article);
    final words = _showCurated && article.hasCurated
        ? _curatedWords
        : article.wordCount;
    final minutes = words <= 0 ? 0 : (words / 200).ceil().clamp(1, 999);
    var ledeSeen = false;
    var bodyCount = 0;
    final blocks = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final block = shown[i];
      if (block.type == 'img' && (block.src ?? '').trim().isNotEmpty) {
        blocks.add(_block(block, index: i));
        continue;
      }
      final hasText = (block.text ?? '').trim().isNotEmpty;
      if (!hasText) {
        blocks.add(const SizedBox.shrink());
        continue;
      }
      if (!ledeSeen) {
        ledeSeen = true;
        blocks.add(_ledeBlock(block.text ?? '', index: i));
      } else {
        bodyCount += 1;
        blocks.add(_block(block, number: bodyCount, index: i));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: V4Space.xxl),
        Text(
          _host,
          style: type.caption.copyWith(
            color: v4.inkSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: V4Space.xs),
        Wrap(
          spacing: V4Space.md,
          runSpacing: V4Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (article.isCondensed) _tag('精简版'),
            if (_showCurated && article.hasCurated) _tag('AI 精选'),
            if (words > 0) Text('$words 词', style: type.caption),
            if (minutes > 0) Text('约 $minutes 分钟', style: type.caption),
            if (article.difficulty != null)
              V4Difficulty(score: article.difficulty),
          ],
        ),
        if (article.hasCurated) ...[
          const SizedBox(height: V4Space.sm),
          _sourceSwitch(),
        ],
        const SizedBox(height: V4Space.lg),
        Container(height: 1, color: v4.rule),
        const SizedBox(height: V4Space.xl),
        Text(article.title, style: type.articleTitle),
        const SizedBox(height: V4Space.xxl),
        if (!article.hasText)
          Padding(
            padding: const EdgeInsets.only(bottom: V4Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这篇文章没有正文', style: type.itemTitle),
                const SizedBox(height: V4Space.xs),
                Text('抓取时可能只拿到了标题，可以去原文看看。', style: type.label),
              ],
            ),
          )
        else ...[
          ...blocks,
          _endBlock(article),
        ],
      ],
    );
  }

  /// Two versions of the same piece: the source text and the tightened one.
  Widget _sourceSwitch() {
    final v4 = context.v4;
    final type = context.v4Type;
    Widget chip(String label, ValueKey key, bool on, VoidCallback tap) {
      return ChoiceChip(
        key: key,
        label: Text(label),
        selected: on,
        onSelected: (_) => tap(),
        selectedColor: v4.surfaceSubtle,
        showCheckmark: false,
        side: BorderSide(color: on ? v4.brand : v4.rule),
        backgroundColor: v4.surface,
        labelStyle: type.caption.copyWith(
          color: on ? v4.brand : v4.inkSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V4Radius.control),
        ),
      );
    }

    return Wrap(
      spacing: V4Space.sm,
      children: [
        chip(
          '原文',
          const ValueKey('v4-reader-original'),
          !_showCurated,
          () => setState(() => _showCurated = false),
        ),
        chip(
          '精选',
          const ValueKey('v4-reader-curated'),
          _showCurated,
          () => setState(() => _showCurated = true),
        ),
      ],
    );
  }

  Widget _endBlock(V4Article article) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.only(top: V4Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 48, height: 2, color: v4.inkMuted),
          const SizedBox(height: V4Space.lg),
          // The work done on this piece comes first; the daily check-in and
          // the outbound link sit below it like a colophon.
          if (_sets.isNotEmpty) ...[
            Text('题集记录', style: type.sectionTitle),
            const SizedBox(height: V4Space.xs),
            Text('长按一条可改用途标签', style: type.caption),
            const SizedBox(height: V4Space.sm),
            for (var i = 0; i < _sets.length; i++) ...[
              if (i > 0) Divider(height: 1, color: v4.rule),
              _setRow(_sets[i]),
            ],
            const SizedBox(height: V4Space.xxl),
          ],
          if (_completed)
            Row(
              children: [
                Icon(Icons.check_circle, size: 20, color: v4.success),
                const SizedBox(width: V4Space.sm),
                Expanded(
                  child: Text(
                    '已记入今天，+${HabitService.xpRead} 见闻',
                    style: type.label.copyWith(color: v4.ink),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: Text('今天的阅读，记一笔', style: type.label)),
                TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.outline,
                  onPressed: _awarding ? null : _markRead,
                  child: Text(_awarding ? '记录中' : '读完了'),
                ),
              ],
            ),
          if (article.sourceUrl.isNotEmpty) ...[
            const SizedBox(height: V4Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openOriginal,
                style: TextButton.styleFrom(
                  foregroundColor: v4.inkSecondary,
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('打开原文'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A dated index row: the set's own time and size on the left, the real
  /// answer count on the right edge. No chevron; the facts carry the row.
  Widget _setRow(Map<String, dynamic> set) {
    final v4 = context.v4;
    final type = context.v4Type;
    final id = (set['id'] as num?)?.toInt();
    final at = (set['createdAt'] as num?)?.toInt() ?? 0;
    final count = (set['questionCount'] as num?)?.toInt() ?? 0;
    final attempts = (set['attempts'] as num?)?.toInt() ?? 0;
    final correct = (set['correctAttempts'] as num?)?.toInt() ?? 0;
    final label = '${set['label'] ?? ''}'.trim();
    final right = label.isNotEmpty
        ? label
        : (attempts == 0 ? '未作答' : '正确 $correct / $attempts');
    return InkWell(
      onTap: id == null ? null : () => _openSet(id),
      onLongPress: id == null ? null : () => _editSetLabel(id, label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V4Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_setDate(at), style: type.itemTitle),
                  const SizedBox(height: V4Space.xs),
                  Text(
                    attempts > 0
                        ? '$count 题  作答 $attempts 次  正确 $correct 次'
                        : '$count 题',
                    style: type.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: V4Space.md),
            SizedBox(
              width: 96,
              child: Text(
                right,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.label.copyWith(color: v4.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSet(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => V4QuizScreen(setId: id)),
    );
    final sets = await _loadSets();
    if (mounted) setState(() => _sets = sets);
  }

  Future<void> _editSetLabel(int id, String current) async {
    final next = await showSetLabelSheet(context, current: current);
    if (next == null || !mounted) return;
    try {
      await ref.read(quizProvider).setSetLabel(id, next);
      final sets = await _loadSets();
      if (mounted) setState(() => _sets = sets);
    } catch (_) {
      if (mounted) {
        showV4Snack(context, '没改上，请重试', tone: V4SnackTone.error);
      }
    }
  }

  static String _setDate(int ms) {
    if (ms <= 0) return '时间未知';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.month}月${d.day}日 ${two(d.hour)}:${two(d.minute)}';
  }

  /// FeedOverview previews often open with a literal "Why it is here:" label.
  /// Pull it out of the paragraph so the lede's own line can carry it once.
  int _ledePrefixLength(String text) {
    final match = RegExp(
      r'^why\s+it\s+is\s+here\s*:?\s*',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null || match.end >= text.length) return 0;
    return match.end;
  }

  /// The first paragraph is the article's note to the reader. Set apart as a
  /// field note: a hairline in the brand tone, the telescope mark, the lede in
  /// the reading face. One accent on the page, nothing else competing.
  Widget _ledeBlock(String raw, {required int index}) {
    final v4 = context.v4;
    final type = context.v4Type;
    final source = raw.trim();
    final prefix = _ledePrefixLength(source);
    final visible = prefix == 0 ? source : source.substring(prefix);
    final offset = source.length - visible.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: V4Space.xxl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: v4.surfaceSubtle,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(V4Radius.card),
          ),
          border: Border(left: BorderSide(color: v4.brand, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            V4Space.lg,
            V4Space.lg,
            V4Space.lg,
            V4Space.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  V4TelescopeIcon(size: 15, color: v4.brand),
                  const SizedBox(width: V4Space.sm),
                  Flexible(
                    child: Text(
                      'Why it is here:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.label.copyWith(
                        fontFamily: V4Fonts.reading,
                        color: v4.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: V4Space.md),
              _TappableText(
                text: visible,
                style: type.articleLead.copyWith(
                  fontSize: _fontSize + 1,
                  height: _lineHeight - 0.05,
                ),
                onWordTap: (hit) => _openWord(
                  WordHit(hit.word, hit.start + offset, hit.end + offset),
                  source,
                  index,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(ArticleBlock block, {int? number, int index = 0}) {
    final src = block.src?.trim() ?? '';
    final text = block.text?.trim() ?? '';
    if (block.type == 'img' && src.isNotEmpty) {
      final alt = block.alt?.trim() ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: V4Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            V4ArticleImage(url: src, alt: block.alt),
            if (alt.isNotEmpty) ...[
              const SizedBox(height: V4Space.sm),
              Text(alt, style: context.v4Type.caption),
            ],
          ],
        ),
      );
    }
    if (text.isEmpty) return const SizedBox.shrink();
    final type = context.v4Type;
    final v4 = context.v4;
    final body = _TappableText(
      text: block.text ?? '',
      style: type.articleBody.copyWith(
        fontSize: _fontSize,
        height: _lineHeight,
      ),
      onWordTap: (hit) => _openWord(hit, block.text ?? '', index),
    );
    // The ordinal is a marginal marker, not part of the prose: excluded from
    // selection and baseline-aligned to the first line, never a drop cap.
    final Widget content = number == null
        ? body
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectionContainer.disabled(
                child: SizedBox(
                  width: 24,
                  child: Text(
                    number.toString().padLeft(2, '0'),
                    textAlign: TextAlign.right,
                    style: type.caption.copyWith(
                      fontFamily: V4Fonts.reading,
                      color: v4.inkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: V4Space.sm),
              Expanded(child: body),
            ],
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: V4Space.xl),
      child: content,
    );
  }

  Widget _tag(String label) {
    final v4 = context.v4;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: V4Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: v4.surfaceSubtle,
        borderRadius: BorderRadius.circular(V4Radius.control),
      ),
      child: Text(
        label,
        style: context.v4Type.caption.copyWith(color: v4.inkSecondary),
      ),
    );
  }

  Widget _bottomBar() {
    final v4 = context.v4;
    final ready = _article != null;
    return Container(
      decoration: BoxDecoration(
        color: v4.surface,
        border: Border(top: BorderSide(color: v4.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            V4Space.xs,
            V4Space.sm,
            V4Space.lg,
            V4Space.sm,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: _inPlan ? '移出精读单' : '加入精读单',
                onPressed: ready ? _togglePlan : null,
                icon: Icon(
                  _inPlan ? Icons.bookmark : Icons.bookmark_border,
                  color: ready
                      ? (_inPlan ? v4.brand : v4.inkSecondary)
                      : v4.rule,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _speaking,
                builder: (context, playing, _) {
                  return IconButton(
                    tooltip: playing ? '停止朗读' : '朗读全文',
                    onPressed: ready && _article!.hasText ? _listen : null,
                    icon: Icon(
                      playing ? Icons.stop_circle_outlined : Icons.volume_up,
                      color: ready ? v4.inkSecondary : v4.rule,
                    ),
                  );
                },
              ),
              const SizedBox(width: V4Space.sm),
              Expanded(
                child: V4PrimaryButton(
                  onPressed: ready && _article!.hasText && !_generating
                      ? _startPractice
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      V4TelescopeIcon(size: 18, color: v4.onBrand),
                      const SizedBox(width: V4Space.sm),
                      Flexible(
                        child: Text(
                          _generating ? '生成中' : '生成精读练习',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeleton() {
    final v4 = context.v4;
    Widget line(double factor, double height, {double gap = V4Space.md}) {
      return Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: factor,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: v4.surfaceSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: V4Space.huge),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _measure),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: V4Space.xxl),
                  line(0.24, 12, gap: V4Space.sm),
                  line(0.4, 12, gap: V4Space.lg),
                  Container(height: 1, color: v4.rule),
                  const SizedBox(height: V4Space.xl),
                  line(0.92, 26, gap: V4Space.sm),
                  line(0.58, 26, gap: V4Space.xxl),
                  for (final factor in const [0.98, 0.92, 0.97, 0.86, 0.99])
                    line(factor, 15, gap: V4Space.md),
                  const SizedBox(height: V4Space.sm),
                  for (final factor in const [0.95, 0.9, 0.62])
                    line(factor, 15, gap: V4Space.md),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState() {
    final type = context.v4Type;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(V4Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('文章暂时打不开', style: type.sectionTitle),
            const SizedBox(height: V4Space.sm),
            Text(_error!, textAlign: TextAlign.center, style: type.label),
            const SizedBox(height: V4Space.xl),
            V4PrimaryButton(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A paragraph that reports the word under the finger. The tap position is
/// mapped through the paragraph's own layout, so the word matches what the
/// reader actually sees at any font size.
class _TappableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final void Function(WordHit hit) onWordTap;

  const _TappableText({
    required this.text,
    required this.style,
    required this.onWordTap,
  });

  @override
  State<_TappableText> createState() => _TappableTextState();
}

class _TappableTextState extends State<_TappableText> {
  final _key = GlobalKey();
  Offset? _downAt;
  DateTime? _downTime;

  /// `Text` can wrap its paragraph in extra render objects, so walk down to the
  /// one that knows how characters map to pixels.
  RenderParagraph? _paragraphOf(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderParagraph) return root;
    RenderParagraph? hit;
    root.visitChildren((child) {
      hit ??= _paragraphOf(child);
    });
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    // A [Listener] observes raw pointer events without joining the gesture
    // arena, so SelectableRegion's long-press / drag selection still works.
    // Only a short, stationary tap is treated as "tap a word".
    return Listener(
      onPointerDown: (e) {
        _downAt = e.position;
        _downTime = DateTime.now();
      },
      onPointerUp: (e) {
        final down = _downAt;
        final started = _downTime;
        _downAt = null;
        _downTime = null;
        if (down == null || started == null) return;
        if ((e.position - down).distance > 12) return;
        if (DateTime.now().difference(started).inMilliseconds > 500) return;
        final paragraph = _paragraphOf(_key.currentContext?.findRenderObject());
        if (paragraph == null) return;
        final position = paragraph.getPositionForOffset(
          paragraph.globalToLocal(e.position),
        );
        final hit = wordAt(widget.text, position.offset);
        if (hit != null) widget.onWordTap(hit);
      },
      onPointerCancel: (_) {
        _downAt = null;
        _downTime = null;
      },
      child: Text(widget.text, key: _key, style: widget.style),
    );
  }
}
