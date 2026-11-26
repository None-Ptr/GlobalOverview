// Hallmark · screen: mine · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S4 R4 V4 · weakest S — the settings index still reads like a list of links; give it facts
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/about_screen.dart';
import 'package:global_overview/v4/screens/appearance_screen.dart';
import 'package:global_overview/v4/screens/data_screen.dart';
import 'package:global_overview/v4/screens/fetch_screen.dart';
import 'package:global_overview/v4/screens/guide_screen.dart';
import 'package:global_overview/v4/screens/model_screen.dart';
import 'package:global_overview/v4/screens/preferences_screen.dart';
import 'package:global_overview/v4/screens/source_screen.dart';
import 'package:global_overview/v4/screens/usage_ledger_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/services/profile_labels.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_index_row.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';

class V4MineScreen extends ConsumerStatefulWidget {
  final V4Profile profile;
  final VoidCallback? onWiped;

  const V4MineScreen({super.key, required this.profile, this.onWiped});

  @override
  ConsumerState<V4MineScreen> createState() => _V4MineScreenState();
}

class _V4MineScreenState extends ConsumerState<V4MineScreen> {
  String? _modelName;
  int? _usageCount;
  double? _fontSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeUpdate();
      _loadFacts();
    });
  }

  /// Right-edge facts come from local state; nothing is invented for the sake
  /// of filling a column.
  Future<void> _loadFacts() async {
    final config = ref.read(appConfigProvider);
    final records = await AiUsageLedger().list();
    if (!mounted) return;
    setState(() {
      _modelName = config.currentProfile.model;
      _usageCount = records.length;
      _fontSize = config.fontSize;
    });
  }

  Future<void> _maybeUpdate() async {
    final controller = ref.read(updateProvider);
    await controller.init();
    await controller.autoCheck();
    if (!mounted) return;
    if (await controller.shouldPrompt() && mounted) {
      await showV4UpdateSheet(context, controller);
    }
  }

  void _push(Widget child) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => child));
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return SafeArea(
      bottom: false,
      child: V4Column(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.md,
          V4Space.lg,
          V4Space.xxxl,
        ),
        children: [
          Text('我的', style: type.pageTitle),
          const SizedBox(height: V4Space.lg),
          Container(
            padding: const EdgeInsets.all(V4Space.xl),
            decoration: BoxDecoration(
              color: v4.surfaceSubtle,
              borderRadius: BorderRadius.circular(V4Radius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v4LevelLabel(widget.profile.level) +
                      '  ' +
                      v4GoalLabel(widget.profile.goal),
                  style: type.itemTitle,
                ),
                const SizedBox(height: V4Space.xs),
                Text(
                  '每日 ' + widget.profile.minutes.toString() + ' 分钟',
                  style: type.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: V4Space.xxl),
          Text('阅读与来源', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          _group([
            V4IndexRow(
              title: '来源与加速',
              note: 'FeedOverview 与分类来源',
              trailing: '加速',
              onTap: () => _push(const V4SourceScreen()),
            ),
            V4IndexRow(
              title: '抓取设置',
              note: 'User-Agent 与附加请求头',
              onTap: () => _push(const V4FetchScreen()),
            ),
            V4IndexRow(
              title: '外观与阅读',
              note: '深浅色、字号与行距',
              trailing: _fontSize == null ? null : '${_fontSize!.toInt()}px',
              onTap: () => _push(const V4AppearanceScreen()),
            ),
          ]),
          const SizedBox(height: V4Space.xxl),
          Text('学习与 AI', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          _group([
            V4IndexRow(
              title: '学习偏好',
              note: '出题难度、每日提醒与出题预设',
              trailing: '${widget.profile.minutes} 分钟',
              onTap: () => _push(const V4PreferencesScreen()),
            ),
            V4IndexRow(
              title: 'AI 模型',
              note: '模型、翻译引擎与自定义接口',
              trailing: _modelName,
              onTap: () => _push(const V4ModelScreen()),
            ),
            V4IndexRow(
              title: 'AI 用量',
              note: 'Token 与费用记录',
              trailing: _usageCount == null ? null : '$_usageCount 条',
              onTap: () => _push(const V4UsageLedgerScreen()),
            ),
          ]),
          const SizedBox(height: V4Space.xxl),
          Text('数据与关于', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          _group([
            V4IndexRow(
              title: '数据管理',
              note: '导出、缓存与备份',
              onTap: () => _push(V4DataScreen(onWiped: widget.onWiped)),
            ),
            V4IndexRow(
              title: '使用指南',
              note: '四组功能的入口与用法',
              trailing: '4 节',
              onTap: () => _push(const V4GuideScreen()),
            ),
            V4IndexRow(
              title: '关于',
              note: '版本与更新',
              onTap: () => _push(const V4AboutScreen()),
            ),
          ]),
          const SizedBox(height: V4Space.xxl),
          Text(
            'GlobalOverview 不需要账号。文章和 AI 服务需要联网，生词、题目与作答只保存在本机。',
            style: type.caption,
          ),
        ],
      ),
      ),
    );
  }

  Widget _group(List<Widget> cells) {
    final v4 = context.v4;
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, color: v4.rule));
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V4Space.lg),
          child: cells[i],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}
