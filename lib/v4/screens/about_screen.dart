// Hallmark · screen: about · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S4 R4 V4 · weakest S — the update row states two versions, it no longer points an arrow at one
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/update_controller.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

Future<void> showV4UpdateSheet(
  BuildContext context,
  UpdateController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.v4.surface,
    builder: (_) => _UpdateSheet(controller: controller),
  );
}

class V4AboutScreen extends ConsumerStatefulWidget {
  const V4AboutScreen({super.key});

  @override
  ConsumerState<V4AboutScreen> createState() => _V4AboutScreenState();
}

class _V4AboutScreenState extends ConsumerState<V4AboutScreen> {
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(updateProvider).init();
      if (mounted) setState(() {});
    });
  }

  Future<void> _check() async {
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < const Duration(seconds: 30)) {
      showV4Snack(context, '刚检查过，稍等一下再试');
      return;
    }
    _lastCheck = now;
    final controller = ref.read(updateProvider);
    await controller.checkNow();
    if (!mounted) return;
    switch (controller.phase) {
      case UpdatePhase.latest:
        showV4Snack(context, '已经是最新版本', tone: V4SnackTone.success);
      case UpdatePhase.failed:
        showV4Snack(
          context,
          controller.error ?? '检查失败',
          tone: V4SnackTone.error,
        );
      case UpdatePhase.available:
        await showV4UpdateSheet(context, controller);
      default:
        break;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final controller = ref.watch(updateProvider);
    return V4Page(
      title: '关于',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.sm,
          V4Space.lg,
          V4Space.huge,
        ),
        children: [
          V4Section(
            title: '版本',
            children: [
              V4Tile(
                title: '当前版本',
                detail: controller.installedLabel.isEmpty
                    ? '读取中'
                    : controller.installedLabel,
              ),
              V4Tile(
                title: '检查更新',
                detail: controller.phase == UpdatePhase.checking
                    ? '正在检查'
                    : (controller.phase == UpdatePhase.available
                          ? '有新版本可用'
                          : '每天自动检查一次'),
                onTap: _check,
              ),
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          V4Section(
            title: '关于这个应用',
            children: [
              V4Tile(
                title: 'GlobalOverview',
                detail: '把英文资讯读成自己的词汇和题集',
              ),
              V4Tile(title: '作者', detail: 'ShaDouBuShi、_Null_Ptr'),
              V4Tile(
                title: '数据去向',
                detail: '文章和 AI 请求需要联网；生词、题目和作答只存在本机',
              ),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text(
            '更新包从发布地址下载，安装前会校验文件摘要。',
            style: type.caption.copyWith(color: v4.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _UpdateSheet extends StatelessWidget {
  final UpdateController controller;

  const _UpdateSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    return SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final info = controller.info;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              V4Space.lg,
              V4Space.xl,
              V4Space.lg,
              V4Space.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('发现新版本', style: context.v4Type.sectionTitle),
                    ),
                    if (info != null)
                      Text(
                        'v${displayVersion(info.version)}',
                        style: context.v4Type.label.copyWith(color: v4.brand),
                      ),
                  ],
                ),
                const SizedBox(height: V4Space.lg),
                switch (controller.phase) {
                  UpdatePhase.checking => _status(context, '正在检查'),
                  UpdatePhase.latest => _status(context, '已经是最新版本'),
                  UpdatePhase.installing => _status(context, '已交给系统安装器，按提示完成安装'),
                  UpdatePhase.downloading ||
                  UpdatePhase.verifying => _progress(context),
                  UpdatePhase.failed => _failed(context),
                  _ => _available(context),
                },
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _status(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V4Space.lg),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: V4Space.md),
          Expanded(child: Text(text, style: context.v4Type.label)),
        ],
      ),
    );
  }

  Widget _available(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final info = controller.info;
    final size = info?.size ?? 0;
    final rawVersion = '${info?.version ?? ''}'.trim();
    final target = rawVersion.isEmpty ? '' : 'v${displayVersion(rawVersion)}';
    final hasUpdate = target.isNotEmpty && target != controller.installedLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(controller.installedLabel, style: type.caption),
                  const SizedBox(height: V4Space.xs),
                  if (hasUpdate)
                    Text(
                      '可更新 $target',
                      style: type.label.copyWith(
                        color: v4.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text('已是最新版本', style: type.caption),
                ],
              ),
            ),
            if (size > 0)
              Text(
                '${(size / 1024 / 1024).toStringAsFixed(1)} MB',
                style: type.caption,
              ),
          ],
        ),
        if (info != null && info.notes.trim().isNotEmpty) ...[
          const SizedBox(height: V4Space.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(info.notes, style: type.caption),
            ),
          ),
        ],
        const SizedBox(height: V4Space.xl),
        SizedBox(
          width: double.infinity,
          child: V4PrimaryButton(
            onPressed: controller.downloadAndInstall,
            child: const Text('立即更新'),
          ),
        ),
        const SizedBox(height: V4Space.sm),
        Row(
          children: [
            Expanded(
              child: TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.outline,
                onPressed: () {
                  controller.dismiss();
                  Navigator.of(context).pop();
                },
                child: const Text('稍后'),
              ),
            ),
            const SizedBox(width: V4Space.md),
            Expanded(
              child: TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                onPressed: () {
                  controller.skipVersion();
                  Navigator.of(context).pop();
                },
                child: const Text('跳过这个版本'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final verifying = controller.phase == UpdatePhase.verifying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(V4Radius.control),
          child: LinearProgressIndicator(
            value: verifying ? 1 : controller.progress,
            minHeight: 8,
            backgroundColor: v4.surfaceSubtle,
            valueColor: AlwaysStoppedAnimation(v4.brand),
          ),
        ),
        const SizedBox(height: V4Space.sm),
        Row(
          children: [
            Text(
              verifying
                  ? '正在校验安装包'
                  : '${(controller.progress * 100).toStringAsFixed(0)}%',
              style: type.caption,
            ),
            const Spacer(),
            if (!verifying)
              Text(
                '${(controller.received / 1024 / 1024).toStringAsFixed(1)} / '
                '${(controller.total / 1024 / 1024).toStringAsFixed(1)} MB',
                style: type.caption,
              ),
          ],
        ),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          controller.error ?? '更新失败',
          style: type.label.copyWith(color: v4.error),
        ),
        const SizedBox(height: V4Space.lg),
        SizedBox(
          width: double.infinity,
          child: V4PrimaryButton(
            onPressed: controller.downloadAndInstall,
            child: const Text('重试'),
          ),
        ),
        const SizedBox(height: V4Space.sm),
        SizedBox(
          width: double.infinity,
          child: TButton(
            size: TButtonSize.large,
            variant: TButtonVariant.text,
            onPressed: () {
              controller.dismiss();
              Navigator.of(context).pop();
            },
            child: const Text('稍后再说'),
          ),
        ),
      ],
    );
  }
}
