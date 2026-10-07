import 'package:flutter/material.dart';
import 'package:global_overview/services/update_controller.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 弹出更新卡片。自带滑入动画（与 GoTimePickerSheet 同款节奏）。
Future<void> showGoUpdateSheet(BuildContext context, UpdateController c) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Go.scrim,
      builder: (_) => _UpdateSheet(controller: c),
    );

class _UpdateSheet extends StatelessWidget {
  final UpdateController controller;
  const _UpdateSheet({required this.controller});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final info = controller.info;
          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(Go.sp6, Go.sp4, Go.sp6, Go.sp6),
              decoration: const BoxDecoration(
                color: Go.glassBgStrong,
                borderRadius: BorderRadius.vertical(top: Radius.circular(Go.rXl)),
                border: Border(top: BorderSide(color: Go.glassBorder)),
                boxShadow: Go.glassShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: Go.sp10,
                      height: 3,
                      decoration: BoxDecoration(color: Go.outlineStrong, borderRadius: BorderRadius.circular(Go.rFull)),
                    ),
                  ),
                  const SizedBox(height: Go.sp5),
                  Row(
                    children: [
                      const GoIcon('bell', size: 18, color: Go.primary),
                      const SizedBox(width: Go.sp3),
                      Text('发现新版本', style: TextStyle(fontSize: Go.fsH2, fontWeight: FontWeight.w700, color: Go.onSurface)),
                      const Spacer(),
                      if (info != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: Go.sp3, vertical: 2),
                          decoration: BoxDecoration(color: Go.primary95, borderRadius: BorderRadius.circular(Go.rFull)),
                          child: Text('v${info.version}', style: const TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: Go.primary)),
                        ),
                      const SizedBox(width: Go.sp3),
                      GoIconBtn(icon: 'close', size: Go.r(56), onTap: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: Go.sp4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (controller.phase) {
                      UpdatePhase.checking => const _Status(key: ValueKey('checking'), icon: 'refresh', text: '正在检查…', spin: true),
                      UpdatePhase.latest => const _Status(key: ValueKey('latest'), icon: 'check', text: '已经是最新版本了'),
                      UpdatePhase.installing => const _Status(key: ValueKey('installing'), icon: 'check', text: '已交给系统安装器，按提示完成安装'),
                      UpdatePhase.downloading || UpdatePhase.verifying => _progressBlock(),
                      UpdatePhase.failed => _failedBlock(context),
                      _ => _availableBlock(context),
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _availableBlock(BuildContext context) {
    final info = controller.info;
    return Column(
      key: const ValueKey('available'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(controller.installedLabel, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Go.sp3),
              child: Icon(Icons.arrow_forward, size: 14, color: Go.onSurface3),
            ),
            Text('v${info?.version ?? ''}', style: const TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w700, color: Go.primary)),
            const Spacer(),
            if ((info?.size ?? 0) > 0)
              Text('${((info!.size) / 1024 / 1024).toStringAsFixed(1)} MB', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
          ],
        ),
        if ((info?.notes.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: Go.sp4),
          // 说明来自不可信通道（第三方反代），只按纯文本渲染；内容不限长，靠容器滚动兜住。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(
                info!.notes,
                style: const TextStyle(fontSize: Go.fsBodySm, height: Go.lhSnug, color: Go.onSurface2),
              ),
            ),
          ),
        ],
        const SizedBox(height: Go.sp6),
        GoBtn(label: '立即更新', icon: const GoIcon('export', size: 16, color: Go.onPrimary), block: true, onTap: controller.downloadAndInstall),
        const SizedBox(height: Go.sp3),
        Row(
          children: [
            Expanded(child: GoBtn(label: '稍后', kind: GoBtnKind.tonal, onTap: () { controller.dismiss(); Navigator.pop(context); })),
            const SizedBox(width: Go.sp3),
            Expanded(child: GoBtn(label: '跳过此版本', kind: GoBtnKind.text, onTap: () { controller.skipVersion(); Navigator.pop(context); })),
          ],
        ),
      ],
    );
  }

  Widget _progressBlock() {
    final verifying = controller.phase == UpdatePhase.verifying;
    return Column(
      key: const ValueKey('progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: verifying ? 1 : controller.progress),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          builder: (_, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(Go.rFull),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: Go.surfaceVariant,
              valueColor: const AlwaysStoppedAnimation(Go.primary),
            ),
          ),
        ),
        const SizedBox(height: Go.sp3),
        Row(
          children: [
            Text(
              verifying ? '正在校验安装包…' : '${(controller.progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface2),
            ),
            const Spacer(),
            if (!verifying)
              Text(
                '${(controller.received / 1024 / 1024).toStringAsFixed(1)} / ${(controller.total / 1024 / 1024).toStringAsFixed(1)} MB',
                style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3),
              ),
          ],
        ),
      ],
    );
  }

  Widget _failedBlock(BuildContext context) => Column(
        key: const ValueKey('failed'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GoIcon('warning', size: 15, color: Go.error),
              const SizedBox(width: Go.sp3),
              Expanded(
                child: Text(controller.error ?? '更新失败', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.error, height: Go.lhSnug)),
              ),
            ],
          ),
          const SizedBox(height: Go.sp5),
          GoBtn(label: '重试', block: true, onTap: controller.downloadAndInstall),
          const SizedBox(height: Go.sp3),
          GoBtn(label: '稍后再说', kind: GoBtnKind.text, block: true, onTap: () { controller.dismiss(); Navigator.pop(context); }),
        ],
      );
}

class _Status extends StatelessWidget {
  final String icon;
  final String text;
  final bool spin;
  const _Status({super.key, required this.icon, required this.text, this.spin = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Go.sp6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GoIcon(icon, size: 16, color: Go.primary, spin: spin),
            const SizedBox(width: Go.sp3),
            Text(text, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface2)),
          ],
        ),
      );
}
