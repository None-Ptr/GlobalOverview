import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4ReviewScreen extends ConsumerStatefulWidget {
  const V4ReviewScreen({super.key});

  @override
  ConsumerState<V4ReviewScreen> createState() => _V4ReviewScreenState();
}

class _V4ReviewScreenState extends ConsumerState<V4ReviewScreen> {
  List<Map<String, dynamic>> _cards = const [];
  int _idx = 0;
  bool _revealed = false;
  bool _loading = true;
  Map<String, dynamic>? _card;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final svc = ref.read(vocabProvider);
    await svc.syncHeadsFromCache();
    final cards = await svc.getDueCards(50);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _idx = 0;
      _loading = false;
    });
    await _showCurrent();
  }

  Future<void> _showCurrent() async {
    if (_idx >= _cards.length) {
      if (mounted) setState(() => _card = null);
      return;
    }
    final head = '${_cards[_idx]['head']}';
    final rows = await ref
        .read(dbProvider)
        .select(
          'SELECT result FROM word_cache WHERE word = ? OR lemma = ? LIMIT 1',
          [head, head],
        );
    var zh = '';
    final hit = rows.isEmpty ? null : rows.first;
    if (hit != null && hit['result'] != null) {
      try {
        final r = jsonDecode(hit['result'] as String);
        if (r is Map) {
          if (r['kind'] == 'dict') {
            final senses = r['senses'] as List?;
            zh = (senses != null && senses.isNotEmpty && senses.first is Map)
                ? '${senses.first['definition'] ?? ''}'
                : '';
          } else if (r['text'] != null) {
            zh = '${r['text']}';
          }
        }
      } catch (_) {}
    }
    final occs = await ref.read(vocabProvider).getOccurrence(head);
    final sentence = occs.isNotEmpty ? '${occs.first['sentence'] ?? ''}' : '';
    if (!mounted) return;
    setState(() {
      _revealed = false;
      _card = {'head': head, 'zh': zh, 'sentence': sentence};
    });
  }

  Future<void> _answer(int grade) async {
    if (_idx >= _cards.length) return;
    await ref.read(vocabProvider).scheduleReview('${_cards[_idx]['head']}', grade);
    ref.read(vocabRevisionProvider.notifier).bump();
    ref.read(habitProvider).awardVocabReview();
    ref.read(habitRevisionProvider.notifier).bump();
    if (_idx + 1 >= _cards.length) {
      await _load();
      return;
    }
    setState(() => _idx++);
    await _showCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final card = _card;
    return V4Page(
      title: '复习',
      actions: [
        if (_cards.isNotEmpty)
          Text(
            '${_idx + 1} / ${_cards.length}',
            style: context.v4Type.caption,
          ),
        const SizedBox(width: V4Space.sm),
      ],
      bottomBar: card == null ? null : _gradeBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : card == null
          ? Center(
              child: V4Notice(
                title: '暂时没有要复习的词',
                message: '到期生词会在这里排成卡片，读文章时收藏的词会自动加入。',
                action: TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.outline,
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('回到词汇'),
                ),
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _revealed = !_revealed),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  V4Space.lg,
                  V4Space.sm,
                  V4Space.lg,
                  V4Space.lg,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(V4Space.xxl),
                  decoration: BoxDecoration(
                    color: v4.surface,
                    borderRadius: BorderRadius.circular(V4Radius.card),
                    border: Border.all(color: v4.rule),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${card['head']}',
                        textAlign: TextAlign.center,
                        style: context.v4Type.displayNumber,
                      ),
                      const SizedBox(height: V4Space.xl),
                      if (!_revealed)
                        Text('点一下看释义', style: context.v4Type.caption)
                      else ...[
                        if ('${card['zh']}'.isNotEmpty)
                          Text(
                            '${card['zh']}',
                            textAlign: TextAlign.center,
                            style: context.v4Type.body,
                          ),
                        if ('${card['sentence']}'.isNotEmpty) ...[
                          const SizedBox(height: V4Space.lg),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(V4Space.lg),
                            decoration: BoxDecoration(
                              color: v4.surfaceSubtle,
                              borderRadius: BorderRadius.circular(
                                V4Radius.control,
                              ),
                            ),
                            child: Text(
                              '${card['sentence']}',
                              style: context.v4Type.label,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _gradeBar() {
    final v4 = context.v4;
    return Row(
      children: [
        _grade('忘了', v4.error, 1),
        const SizedBox(width: V4Space.sm),
        _grade('模糊', v4.warning, 2),
        const SizedBox(width: V4Space.sm),
        _grade('记得', v4.brand, 3),
        const SizedBox(width: V4Space.sm),
        _grade('轻松', v4.success, 4),
      ],
    );
  }

  Widget _grade(String label, Color color, int grade) {
    return Expanded(
      child: SizedBox(
        height: 48,
        child: TextButton(
          onPressed: () => _answer(grade),
          style: TextButton.styleFrom(
            backgroundColor: color,
            foregroundColor: context.v4.onBrand,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(V4Radius.control),
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
