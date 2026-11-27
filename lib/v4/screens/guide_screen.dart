// Hallmark · screen: guide · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S5 R4 V4 · weakest R — a plain index of where things live; no tour, no arrows
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4GuideScreen extends StatelessWidget {
  const V4GuideScreen({super.key});

  static const _sections = <({String title, List<(String, String)> items})>[
    (
      title: '阅读',
      items: [
        ('导入文章', '阅读页右上角的 +。粘贴标题和正文，或输入文章网址，和订阅文章排在一起。'),
        ('自定义 RSS', '我的 → 来源与加速 → 自定义 RSS。可以添加、单独刷新、移除。'),
        ('难度刻度', '文章头部右缘的四格刻度；列表行也显示档位，出题时会预选对应档位。'),
        ('AI 精选', '阅读器右上角「更多 → AI 精选」。生成后可切回原文，也可以删除重来。'),
      ],
    ),
    (
      title: '练习',
      items: [
        ('生成精读练习', '阅读器底部按钮。题型可多选，再设定题数、难度、判分方式和用途标签。'),
        ('判定方式', '精确、包含、AI、人工。AI 判分失败会挂起可重判；人工题可以手动判对错。'),
        ('题集记录', '文章末尾按时间列出历次题集；长按一条可以改用途标签。'),
      ],
    ),
    (
      title: '词汇与复习',
      items: [
        ('点词查词', '阅读器里点任意单词，可加入生词本；长按可整句翻译。'),
        ('生词本整理', '词汇页的「AI 整理」，把查过的词按主题分组并补全词条。'),
        ('复习与错题', '学习页的复习卡和错题本；错题支持重判和全部重做。'),
      ],
    ),
    (
      title: 'AI 与数据',
      items: [
        ('模型与用量', '我的 → AI 模型 配置模型；AI 用量 记录每次调用的 Token 与费用。'),
        ('本机数据', '我的 → 数据管理。可导出、清缓存、备份；文章与 AI 请求需要联网。'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      appBar: AppBar(
        backgroundColor: v4.page,
        elevation: 0,
        title: const Text('使用指南'),
      ),
      body: V4Column(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.sm,
          V4Space.lg,
          V4Space.huge,
        ),
        children: [
          Text('四组功能，以及它们藏在哪。', style: type.label),
          const SizedBox(height: V4Space.xxl),
          for (final section in _sections) ...[
            Text(section.title, style: type.sectionTitle),
            const SizedBox(height: V4Space.sm),
            for (var i = 0; i < section.items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: v4.rule),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: V4Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.items[i].$1, style: type.itemTitle),
                    const SizedBox(height: V4Space.xs),
                    Text(section.items[i].$2, style: type.label),
                  ],
                ),
              ),
            ],
            const SizedBox(height: V4Space.xxl),
          ],
        ],
      ),
      ),
    );
  }
}
