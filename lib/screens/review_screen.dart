import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 复习页：1:1 对齐 legacy/src/pages/review/review.vue
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<Map<String, dynamic>> _cards = [];
  int _idx = 0;
  bool _revealed = false;
  Map<String, dynamic>? _card;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final svc = ref.read(vocabProvider);
    await svc.syncHeadsFromCache();
    _cards = await svc.getDueCards(50);
    _idx = 0;
    await _showCurrent();
  }

  Future<void> _showCurrent() async {
    _revealed = false;
    if (_idx >= _cards.length) {
      if (mounted) setState(() => _card = null);
      return;
    }
    final c = _cards[_idx];
    final head = '${c['head']}';
    // 只查当前词：一次拉 1000 条 result 会逼近 Android CursorWindow 上限。
    final rows = await ref
        .read(dbProvider)
        .select('SELECT result FROM word_cache WHERE word = ? OR lemma = ? LIMIT 1', [head, head]);
    var zh = '';
    final hit = rows.isEmpty ? null : rows.first;
    if (hit != null && hit['result'] != null) {
      try {
        final r = jsonDecode(hit['result'] as String);
        if (r is Map) {
          if (r['kind'] == 'dict') {
            final senses = r['senses'] as List?;
            zh = (senses != null && senses.isNotEmpty && senses.first is Map) ? (senses.first['definition'] ?? '') : '';
          } else if (r['text'] != null) {
            zh = r['text'];
          }
        }
      } catch (_) {}
    }
    final occs = await ref.read(vocabProvider).getOccurrence('${c['head']}');
    final sentence = occs.isNotEmpty ? (occs.first['sentence'] ?? '') : '';
    if (mounted) setState(() => _card = {'head': c['head'], 'zh': zh, 'sentence': sentence});
  }

  Future<void> _answer(int g) async {
    if (_idx >= _cards.length) return;
    await ref.read(vocabProvider).scheduleReview('${_cards[_idx]['head']}', g);
    ref.read(vocabRevisionProvider.notifier).bump();
    ref.read(habitProvider).awardVocabReview(); // 复习一个词 → 见闻 +2（每日封顶）
    ref.read(habitRevisionProvider.notifier).bump();
    _idx++;
    if (_idx >= _cards.length) {
      await _load();
    } else {
      await _showCurrent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return GoPage(
      topPad: false,
      globe: true,
      globeActive: card == null,
      child: Column(
        children: [
          GoAppBar(
            title: '复习',
            style: GoAppBarStyle.floating,
            leading: GoBack(),
            actions: [Text('${_cards.length} 张', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))],
          ),
          Expanded(
            child: card != null
                ? Padding(
                    padding: const EdgeInsets.all(Go.sp6),
                    child: Column(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _revealed = !_revealed),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(Go.sp10),
                              decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rXl), boxShadow: Go.elev2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${card['head']}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Go.onSurface)),
                                  const SizedBox(height: Go.sp6),
                                  if (_revealed)
                                    Column(
                                      children: [
                                        if ('${card['zh']}'.isNotEmpty) Text('${card['zh']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: Go.fsBody, color: Go.onSurface)),
                                        if ('${card['sentence']}'.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: Go.sp3),
                                            child: Text('“${card['sentence']}”', textAlign: TextAlign.center, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3, height: 1.6, fontStyle: FontStyle.italic)),
                                          ),
                                      ],
                                    )
                                  else
                                    const Text('点击显示释义', style: TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Go.sp6),
                        Row(
                          children: [
                            _grade('忘了', const Color(0xFFA53071), () => _answer(1)),
                            const SizedBox(width: Go.sp3),
                            _grade('模糊', const Color(0xFFE08A2B), () => _answer(2)),
                            const SizedBox(width: Go.sp3),
                            _grade('记得', Go.primary, () => _answer(3)),
                            const SizedBox(width: Go.sp3),
                            _grade('轻松', const Color(0xFF2D9E63), () => _answer(4)),
                          ],
                        ),
                      ],
                    ),
                  )
                : _empty(),
          ),
        ],
      ),
    );
  }

  Widget _grade(String label, Color color, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Go.sp4),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Go.rLg)),
            child: Text(label, style: const TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      );

  Widget _empty() => Center(
        child: GoEmpty(
          icon: 'check',
          title: '太棒了，暂时没有待复习的卡片',
          desc: '去阅读里多沉淀几个生词吧',
          action: GoBtn(label: '返回', kind: GoBtnKind.tonal, onTap: () => Navigator.of(context).maybePop()),
        ),
      );
}
