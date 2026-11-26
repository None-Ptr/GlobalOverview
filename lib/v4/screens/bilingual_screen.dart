import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/services/article_repository.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';

/// Whole-article translation: every paragraph is translated in order and shown
/// under its source, so a failed paragraph can be retried without losing the
/// ones that already came back.
class V4BilingualScreen extends ConsumerStatefulWidget {
  final V4Article article;

  const V4BilingualScreen({super.key, required this.article});

  @override
  ConsumerState<V4BilingualScreen> createState() => _V4BilingualScreenState();
}

class _V4BilingualScreenState extends ConsumerState<V4BilingualScreen> {
  late final List<String> _paragraphs;
  final _zh = <int, String>{};
  final _failed = <int>{};
  bool _running = true;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _paragraphs = [
      for (final block in widget.article.blocks)
        if (block.type != 'img' && (block.text ?? '').trim().isNotEmpty)
          block.text!.trim(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _run() async {
    for (var i = 0; i < _paragraphs.length; i++) {
      if (!mounted || _cancelled) return;
      if (_zh.containsKey(i) || _failed.contains(i)) continue;
      var text = '';
      try {
        text = await ref.read(translateProvider).translate(_paragraphs[i]);
      } catch (_) {
        text = '';
      }
      if (!mounted || _cancelled) return;
      setState(() {
        if (text.trim().isEmpty) {
          _failed.add(i);
        } else {
          _zh[i] = text;
        }
      });
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _retry(int index) async {
    if (!mounted) return;
    setState(() {
      _failed.remove(index);
      _running = true;
    });
    var text = '';
    try {
      text = await ref.read(translateProvider).translate(_paragraphs[index]);
    } catch (_) {
      text = '';
    }
    if (!mounted) return;
    setState(() {
      if (text.trim().isEmpty) {
        _failed.add(index);
      } else {
        _zh[index] = text;
      }
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return V4Page(
      title: '对照翻译',
      actions: [
        if (_running)
          Text('${_zh.length}/${_paragraphs.length}', style: type.caption),
        const SizedBox(width: V4Space.sm),
      ],
      body: _paragraphs.isEmpty
          ? const V4Notice(
              title: '这篇文章没有正文',
              message: '没有可翻译的段落，可以去原文看看。',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.lg,
                V4Space.huge,
              ),
              itemCount: _paragraphs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: V4Space.lg),
                    child: Text(
                      '机器翻译，仅供理解；译文按段落依次返回。',
                      style: type.caption,
                    ),
                  );
                }
                return _pair(index - 1, v4, type);
              },
            ),
    );
  }

  Widget _pair(int index, V4Palette v4, V4Type type) {
    final zh = _zh[index];
    final failed = _failed.contains(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: V4Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _paragraphs[index],
            style: type.articleBody.copyWith(fontSize: 17, height: 1.7),
          ),
          const SizedBox(height: V4Space.sm),
          if (zh != null)
            Text(
              zh,
              style: type.body.copyWith(color: v4.inkSecondary, height: 1.75),
            )
          else if (failed)
            Row(
              children: [
                Expanded(
                  child: Text('这一段没译出来', style: type.caption),
                ),
                TextButton(
                  onPressed: () => _retry(index),
                  style: TextButton.styleFrom(
                    foregroundColor: v4.brand,
                    minimumSize: const Size(44, 44),
                  ),
                  child: const Text('重试'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final factor in const [0.9, 0.55])
                  Padding(
                    padding: const EdgeInsets.only(bottom: V4Space.sm),
                    child: FractionallySizedBox(
                      widthFactor: factor,
                      child: Container(
                        height: 13,
                        decoration: BoxDecoration(
                          color: v4.surfaceSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
