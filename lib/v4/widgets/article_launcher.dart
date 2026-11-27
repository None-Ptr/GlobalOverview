import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';

/// M1/M2 过渡入口：优先使用 FeedOverview 精简正文，缺失时回退原站抓取。
Future<void> openV4Article(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final guid = item['guid'] as String?;
  final link = item['link'] as String? ?? '';
  final title = item['title'] as String? ?? '未命名文章';
  final sourceUrl = item['sourceUrl'] as String? ?? '';
  final navigator = Navigator.of(context);
  if (guid == null || guid.isEmpty) {
    showV4Snack(context, '这篇文章缺少稳定链接，暂时无法打开', tone: V4SnackTone.warning);
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Dialog(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('正在准备文章正文')),
          ],
        ),
      ),
    ),
  );

  try {
    var articleId = 0;
    if (sourceUrl.startsWith(FeedOverviewService.baseUrl)) {
      articleId = await FeedOverviewService(
        ref.read(dbProvider),
        ref.read(httpProvider),
      ).captureArticle(item);
    } else {
      final svc = ref.read(feedsProvider);
      var captured = await svc.captureArticle(guid, link, title);
      if (!captured.fresh && await svc.looksUnusable(captured.id)) {
        captured = await svc.captureArticle(guid, link, title, force: true);
      }
      articleId = captured.id;
    }
    navigator.pop();
    await navigator.push(
      MaterialPageRoute(builder: (_) => V4ReaderScreen(articleId: articleId)),
    );
  } catch (e) {
    navigator.pop();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('文章暂时打不开'),
        content: Text(errText(e)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
