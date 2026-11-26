import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/v4/screens/model_form_screen.dart';
import 'package:global_overview/v4/screens/translate_form_screen.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4ModelScreen extends ConsumerWidget {
  const V4ModelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    final v4 = context.v4;
    final type = context.v4Type;
    final profiles = cfg.profiles;
    final translators = cfg.translators;

    return V4Page(
      title: 'AI 模型',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.sm,
          V4Space.lg,
          V4Space.huge,
        ),
        children: [
          V4Section(
            title: '模型',
            hint: profiles.isEmpty ? null : '点一行切换当前使用的模型',
            children: [
              if (profiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(V4Space.lg),
                  child: Text('还没有配置模型，添加后 AI 解析、出题和整理才能用', style: type.caption),
                ),
              for (final p in profiles)
                _ModelTile(
                  profile: p,
                  active: cfg.currentProfileId == p.id,
                  canDelete: profiles.length > 1,
                  onTap: () => cfg.setCurrentProfile(p.id),
                  onEdit: () => _open(
                    context,
                    V4ModelFormScreen(profileId: p.id),
                  ),
                  onDelete: () => _confirmDelete(context, ref, p),
                ),
              Padding(
                padding: const EdgeInsets.all(V4Space.md),
                child: TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.outline,
                  onPressed: () => _open(context, const V4ModelFormScreen()),
                  child: const Text('新增模型'),
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          V4Section(
            title: '翻译引擎',
            hint: '阅读时点词用的翻译服务',
            children: [
              Padding(
                padding: const EdgeInsets.all(V4Space.lg),
                child: Wrap(
                  spacing: V4Space.sm,
                  runSpacing: V4Space.sm,
                  children: [
                    for (final entry in TranslateService.engineNames.entries)
                      V4Chip(
                        label: entry.value,
                        selected: cfg.transEngine == entry.key,
                        onTap: () => cfg.setReader(transEngine: entry.key),
                      ),
                    for (final t in translators)
                      V4Chip(
                        label: t.name.isEmpty ? '未命名接口' : t.name,
                        selected: cfg.transEngine == t.id,
                        onTap: () => cfg.setReader(transEngine: t.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          V4Section(
            title: '自定义翻译接口',
            hint: '接第三方翻译 API，保存后可以当引擎选中',
            children: [
              if (translators.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(V4Space.lg),
                  child: Text('还没有接口，可以接腾讯云、有道这类服务', style: type.caption),
                ),
              for (final t in translators)
                V4Tile(
                  title: t.name.isEmpty ? '未命名接口' : t.name,
                  detail: '${t.method} ${t.url}',
                  trailing: PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _open(
                          context,
                          V4TranslateFormScreen(translatorId: t.id),
                        );
                      }
                      if (value == 'delete') {
                        _confirmDeleteTranslator(context, ref, t);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(V4Space.md),
                child: TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.outline,
                  onPressed: () =>
                      _open(context, const V4TranslateFormScreen()),
                  child: const Text('新增翻译接口'),
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text(
            '模型密钥和接口配置只保存在本机。',
            style: type.caption.copyWith(color: v4.inkMuted),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget child) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => child));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LlmProfile profile,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('删除「${profile.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final cfg = ref.read(appConfigProvider);
    await cfg.setProfiles(
      cfg.profiles.where((p) => p.id != profile.id).toList(),
    );
  }

  Future<void> _confirmDeleteTranslator(
    BuildContext context,
    WidgetRef ref,
    CustomTranslator translator,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除接口'),
        content: Text('删除「${translator.name.isEmpty ? '该接口' : translator.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appConfigProvider).deleteTranslator(translator.id);
  }
}

class _ModelTile extends StatelessWidget {
  final LlmProfile profile;
  final bool active;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ModelTile({
    required this.profile,
    required this.active,
    required this.canDelete,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V4Space.lg,
          vertical: V4Space.md,
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: active ? v4.brand : v4.inkMuted,
            ),
            const SizedBox(width: V4Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.itemTitle.copyWith(
                      color: active ? v4.brand : v4.ink,
                    ),
                  ),
                  const SizedBox(height: V4Space.xs),
                  Text(
                    '${profile.model}，${profile.baseUrl}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete' && canDelete) onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: canDelete,
                  child: Text(canDelete ? '删除' : '至少留一个模型'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
