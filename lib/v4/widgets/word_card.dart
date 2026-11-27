import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';

/// P10: word card. Word and its sentence paint immediately, the definition
/// fills in from cache or the translate engine, and saving writes one
/// occurrence so the sentence travels with the word into the vocabulary book.
Future<void> showWordCard(
  BuildContext context, {
  required String word,
  required String sentence,
  required String articleGuid,
  required String articleTitle,
  required String sourceLabel,
  required int paraIndex,
  required int tokIndex,
}) {
  final v4 = context.v4;
  final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: v4.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(V4Radius.sheet),
      ),
    ),
    builder: (_) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: _WordCard(
        word: word,
        sentence: sentence,
        articleGuid: articleGuid,
        articleTitle: articleTitle,
        sourceLabel: sourceLabel,
        paraIndex: paraIndex,
        tokIndex: tokIndex,
      ),
    ),
  );
}

class _WordCard extends ConsumerStatefulWidget {
  final String word;
  final String sentence;
  final String articleGuid;
  final String articleTitle;
  final String sourceLabel;
  final int paraIndex;
  final int tokIndex;

  const _WordCard({
    required this.word,
    required this.sentence,
    required this.articleGuid,
    required this.articleTitle,
    required this.sourceLabel,
    required this.paraIndex,
    required this.tokIndex,
  });

  @override
  ConsumerState<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends ConsumerState<_WordCard> {
  bool _loading = true;
  bool _failed = false;
  bool _added = false;
  bool _adding = false;
  String _definition = '';
  String _phonetic = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final lemma = widget.word.toLowerCase();
    var definition = '';
    var phonetic = '';
    try {
      final rows = await ref
          .read(dbProvider)
          .select(
            'SELECT result FROM word_cache WHERE word = ? OR lemma = ? LIMIT 1',
            [lemma, lemma],
          );
      if (rows.isNotEmpty && rows.first['result'] != null) {
        final parsed = _parseResult('${rows.first['result']}');
        definition = parsed.definition;
        phonetic = parsed.phonetic;
      }
    } catch (_) {}
    if (definition.isEmpty) {
      try {
        definition = await ref.read(wordProvider).lookup(widget.word);
      } catch (_) {
        definition = '';
      }
    }
    var added = false;
    try {
      final rows = await ref
          .read(dbProvider)
          .select('SELECT head FROM vocab_head WHERE head = ?', [lemma]);
      added = rows.isNotEmpty;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _definition = definition;
      _phonetic = phonetic;
      _added = added;
      _loading = false;
      _failed = definition.trim().isEmpty;
    });
  }

  /// Legacy rows hold `{"kind":"dict","phonetic":...,"senses":[...]}`; newer
  /// rows hold the plain translation string.
  ({String phonetic, String definition}) _parseResult(String raw) {
    final text = raw.trim();
    if (!text.startsWith('{')) return (phonetic: '', definition: text);
    try {
      final map = jsonDecode(text);
      if (map is! Map) return (phonetic: '', definition: text);
      final phonetic = '${map['phonetic'] ?? ''}';
      if (map['kind'] == 'dict') {
        final senses = map['senses'];
        if (senses is List) {
          final lines = <String>[];
          for (final sense in senses.whereType<Map>()) {
            final pos = '${sense['pos'] ?? ''}'.trim();
            final definition = '${sense['definition'] ?? ''}'.trim();
            if (definition.isEmpty) continue;
            lines.add(pos.isEmpty ? definition : '$pos $definition');
          }
          return (phonetic: phonetic, definition: lines.join('\n'));
        }
      }
      return (phonetic: phonetic, definition: '${map['text'] ?? ''}');
    } catch (_) {
      return (phonetic: '', definition: text);
    }
  }

  Future<void> _add() async {
    if (_adding || _added) return;
    setState(() => _adding = true);
    try {
      await ref
          .read(vocabProvider)
          .recordOccurrence(
            widget.word,
            widget.sentence,
            widget.articleGuid,
            widget.articleTitle,
            widget.sourceLabel,
            widget.paraIndex,
            widget.tokIndex,
          );
      ref.read(vocabRevisionProvider.notifier).bump();
      if (!mounted) return;
      setState(() {
        _adding = false;
        _added = true;
      });
      showV4Snack(context, '已加入生词本', tone: V4SnackTone.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
      showV4Snack(context, '没加进去，请重试', tone: V4SnackTone.error);
    }
  }

  Future<void> _speak() async {
    try {
      await ref.read(ttsProvider).speak(widget.word);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '这台设备暂时无法发音', tone: V4SnackTone.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.word,
                        style: type.articleTitle.copyWith(fontSize: 26),
                      ),
                      if (_phonetic.isNotEmpty) ...[
                        const SizedBox(height: V4Space.xs),
                        Text('/$_phonetic/', style: type.caption),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '朗读单词',
                  onPressed: _speak,
                  icon: Icon(Icons.volume_up, color: v4.inkSecondary),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, color: v4.inkSecondary),
                ),
              ],
            ),
            const SizedBox(height: V4Space.md),
            _definitionBlock(v4, type),
            if (widget.sentence.isNotEmpty) ...[
              const SizedBox(height: V4Space.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(V4Space.lg),
                decoration: BoxDecoration(
                  color: v4.surfaceSubtle,
                  borderRadius: BorderRadius.circular(V4Radius.control),
                ),
                child: _sentence(v4, type),
              ),
            ],
            const SizedBox(height: V4Space.xl),
            SizedBox(
              width: double.infinity,
              child: V4PrimaryButton(
                onPressed: _added || _adding ? null : _add,
                child: Text(
                  _added ? '已加入生词本' : (_adding ? '加入中' : '加入生词本'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _definitionBlock(V4Palette v4, V4Type type) {
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final factor in const [0.9, 0.62])
            Padding(
              padding: const EdgeInsets.only(bottom: V4Space.sm),
              child: FractionallySizedBox(
                widthFactor: factor,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: v4.surfaceSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    if (_failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('暂时无法查询释义', style: type.label),
          const SizedBox(height: V4Space.xs),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              foregroundColor: v4.brand,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重试'),
          ),
        ],
      );
    }
    return Text(_definition, style: type.body);
  }

  Widget _sentence(V4Palette v4, V4Type type) {
    final base = type.articleBody.copyWith(fontSize: 17, height: 1.7);
    final text = widget.sentence;
    final hit = text.toLowerCase().indexOf(widget.word.toLowerCase());
    if (hit < 0) return Text(text, style: base);
    final end = hit + widget.word.length;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, hit)),
          TextSpan(
            text: text.substring(hit, end),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              backgroundColor: v4.brand.withValues(alpha: 0.16),
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      style: base,
    );
  }
}
