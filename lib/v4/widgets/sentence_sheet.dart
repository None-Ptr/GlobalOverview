import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';

/// P11: sentence sheet. Opens with the sentence and its translation, and lets
/// the reader listen, save it, or retry a translation that failed.
Future<void> showSentenceSheet(
  BuildContext context, {
  required String sentence,
  required String articleGuid,
  required String articleTitle,
  required String sourceLabel,
  required int paraIndex,
  int sentences = 1,
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
      child: _SentenceSheet(
        sentence: sentence,
        articleGuid: articleGuid,
        articleTitle: articleTitle,
        sourceLabel: sourceLabel,
        paraIndex: paraIndex,
        sentences: sentences,
      ),
    ),
  );
}

class _SentenceSheet extends ConsumerStatefulWidget {
  final String sentence;
  final String articleGuid;
  final String articleTitle;
  final String sourceLabel;
  final int paraIndex;
  final int sentences;

  const _SentenceSheet({
    required this.sentence,
    required this.articleGuid,
    required this.articleTitle,
    required this.sourceLabel,
    required this.paraIndex,
    required this.sentences,
  });

  @override
  ConsumerState<_SentenceSheet> createState() => _SentenceSheetState();
}

class _SentenceSheetState extends ConsumerState<_SentenceSheet> {
  bool _loading = true;
  bool _failed = false;
  bool _saved = false;
  String _translation = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _translate());
  }

  Future<void> _translate() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    var text = '';
    try {
      text = await ref.read(translateProvider).translate(widget.sentence);
    } catch (_) {
      text = '';
    }
    if (!mounted) return;
    setState(() {
      _translation = text;
      _loading = false;
      _failed = text.trim().isEmpty;
    });
  }

  Future<void> _listen() async {
    try {
      await ref.read(ttsProvider).speak(widget.sentence);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '这台设备暂时无法朗读', tone: V4SnackTone.warning);
    }
  }

  Future<void> _save() async {
    if (_saved) return;
    try {
      await ref
          .read(vocabProvider)
          .saveSentence(
            widget.sentence,
            widget.articleGuid,
            widget.articleTitle,
            widget.sourceLabel,
            widget.paraIndex,
            0,
          );
      ref.read(vocabRevisionProvider.notifier).bump();
      if (!mounted) return;
      setState(() => _saved = true);
      showV4Snack(context, '已收藏到句子', tone: V4SnackTone.success);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '没收藏上，请重试', tone: V4SnackTone.error);
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
              children: [
                Text('原句', style: type.label),
                if (widget.sentences > 1) ...[
                  const SizedBox(width: V4Space.sm),
                  Text('已选 ${widget.sentences} 句', style: type.caption),
                ],
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, color: v4.inkSecondary),
                ),
              ],
            ),
            Text(
              widget.sentence,
              style: type.articleBody.copyWith(fontSize: 17, height: 1.7),
            ),
            const SizedBox(height: V4Space.lg),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _listen,
                  style: TextButton.styleFrom(
                    foregroundColor: v4.inkSecondary,
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: const Text('朗读'),
                ),
                TextButton.icon(
                  onPressed: _save,
                  style: TextButton.styleFrom(
                    foregroundColor: _saved ? v4.success : v4.inkSecondary,
                    minimumSize: const Size(44, 44),
                  ),
                  icon: Icon(
                    _saved ? Icons.bookmark : Icons.bookmark_border,
                    size: 18,
                  ),
                  label: Text(_saved ? '已收藏' : '收藏'),
                ),
              ],
            ),
            Divider(height: 1, color: v4.rule),
            const SizedBox(height: V4Space.lg),
            Text('译文', style: type.label),
            const SizedBox(height: V4Space.sm),
            _translationBlock(v4, type),
          ],
        ),
      ),
    );
  }

  Widget _translationBlock(V4Palette v4, V4Type type) {
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final factor in const [0.94, 0.86, 0.5])
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
      );
    }
    if (_failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('这句没译出来', style: type.body),
          const SizedBox(height: V4Space.xs),
          TextButton(
            onPressed: _translate,
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
    return Text(_translation, style: type.body);
  }
}
