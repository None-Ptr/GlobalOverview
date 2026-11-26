import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/v4/services/data_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:open_filex/open_filex.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4DataScreen extends ConsumerStatefulWidget {
  final VoidCallback? onWiped;

  const V4DataScreen({super.key, this.onWiped});

  @override
  ConsumerState<V4DataScreen> createState() => _V4DataScreenState();
}

class _V4DataScreenState extends ConsumerState<V4DataScreen> {
  V4DataSummary? _summary;
  V4BackupInfo? _backup;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  V4DataService get _service => V4DataService(ref.read(dbProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final service = _service;
      final summary = await service.summary();
      final backup = await service.backupInfo();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _backup = backup;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summary = null;
        _backup = null;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _toast(String message, {V4SnackTone tone = V4SnackTone.plain}) {
    if (!mounted) return;
    showV4Snack(context, message, tone: tone);
  }

  Future<void> _export() async {
    if (_busy) return;
    if (_summary == null || !_summary!.hasLearningData) {
      _toast('还没有学习记录可以导出');
      return;
    }
    setState(() => _busy = true);
    try {
      final path = await _service.saveBackup();
      if (!mounted) return;
      if (path == null) {
        _toast('备份已下载到浏览器');
        return;
      }
      final result = await OpenFilex.open(path);
      _toast(
        result.type == ResultType.done ? '已导出学习数据' : '已保存到应用目录：$path',
      );
    } catch (_) {
      _toast('导出失败，学习数据仍保留在本机');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final raw = await _service.readBackup();
      if (!mounted) return;
      if (raw == null || raw.trim().isEmpty) {
        _toast('没有找到备份文件，先导出一份');
        return;
      }
      final ok = await _confirm(
        title: '恢复学习数据',
        message: '会用这份备份覆盖本机的生词、题集、作答与错题，当前记录无法找回。',
        confirmLabel: '恢复',
      );
      if (!ok || !mounted) return;
      final result = await _service.importBackup(raw);
      await _load();
      if (!mounted) return;
      _toast(
        result.rows > 0
            ? '已恢复 ${result.rows} 条记录${result.profile ? '，学习档案也回来了' : ''}'
            : '备份里没有可恢复的记录',
      );
    } catch (e) {
      if (!mounted) return;
      _toast(
        e is AppException ? errText(e) : '恢复失败，本机记录没有被改动',
        tone: V4SnackTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearCache() async {
    final ok = await _confirm(
      title: '清理文章缓存',
      message: '将清除已缓存的文章正文、配图与词条缓存，阅读列表、精读单和题集记录保留。',
      confirmLabel: '清理',
    );
    if (!ok) return;
    try {
      await _service.clearArticleCache();
      await ref.read(imageCacheProvider).clear();
    } catch (_) {
      _toast('清理失败，缓存仍保留在本机');
      return;
    }
    await _load();
    _toast('文章缓存已清理');
  }

  Future<void> _deleteBackup() async {
    final ok = await _confirm(
      title: '删除 V3 备份',
      message: '备份文件删除后无法恢复，学习记录本身不受影响。',
      confirmLabel: '删除',
    );
    if (!ok) return;
    await _service.deleteBackup();
    await _load();
    _toast('V3 备份已删除');
  }

  Future<void> _wipe() async {
    final typed = await _confirmWipe();
    if (!typed) return;
    final confirmed = await _confirm(
      title: '最后确认',
      message: '生词、题集、作答与错题将被永久删除，无法恢复。',
      confirmLabel: '永久删除',
    );
    if (!confirmed) return;
    try {
      await _service.clearLearningData();
    } catch (_) {
      await _load();
      _toast('清空未完成，已保留剩余数据');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onWiped?.call();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _confirmWipe() async {
    var canWipe = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('清空学习数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('生词、题集、作答与错题都会被删除，无法恢复。请输入“清空”确认。'),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('v4-wipe-input'),
                onChanged: (value) =>
                    setDialogState(() => canWipe = value.trim() == '清空'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              key: const ValueKey('v4-wipe-confirm'),
              onPressed: canWipe
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('清空'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      appBar: AppBar(
        backgroundColor: v4.page,
        elevation: 0,
        title: const Text('数据管理'),
      ),
      body: V4Column(
        child: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(V4Space.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('暂时无法读取本机数据', style: type.sectionTitle),
                    const SizedBox(height: V4Space.sm),
                    Text('学习记录没有被修改，可以重试。', style: type.label),
                    const SizedBox(height: V4Space.lg),
                    V4PrimaryButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(V4Space.lg),
              children: [
                Text('学习数据', style: type.sectionTitle),
                const SizedBox(height: V4Space.sm),
                Container(
                  padding: const EdgeInsets.all(V4Space.lg),
                  decoration: BoxDecoration(
                    color: v4.surface,
                    borderRadius: BorderRadius.circular(V4Radius.card),
                    border: Border.all(color: v4.rule),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _summary == null
                            ? '暂无学习数据'
                            : '生词 ${_summary!.vocabWords}，题集 ${_summary!.questionSets}，作答 ${_summary!.answers}，错题 ${_summary!.wrongAnswers}',
                        style: type.body,
                      ),
                      const SizedBox(height: V4Space.lg),
                      Wrap(
                        spacing: V4Space.sm,
                        runSpacing: V4Space.sm,
                        children: [
                          TButton(
                            size: TButtonSize.large,
                            key: const ValueKey('v4-data-export'),
                            variant: TButtonVariant.outline,
                            onPressed: _busy ? null : _export,
                            child: const Text('导出备份'),
                          ),
                          TButton(
                            size: TButtonSize.large,
                            key: const ValueKey('v4-data-import'),
                            variant: TButtonVariant.text,
                            onPressed: _busy ? null : _import,
                            child: const Text('恢复备份'),
                          ),
                        ],
                      ),
                      const SizedBox(height: V4Space.sm),
                      Text(
                        '备份是一份 JSON，换机或重装后可以整份带回来。',
                        style: type.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V4Space.xxl),
                Text('文章缓存', style: type.sectionTitle),
                const SizedBox(height: V4Space.sm),
                _row(
                  context,
                  title: '已缓存内容',
                  detail: _summary?.cacheLabel ?? '0 KB',
                  action: '清理',
                  onTap: _clearCache,
                ),
                Divider(height: 1, color: v4.rule),
                const SizedBox(height: V4Space.xxl),
                Text('V3 迁移备份', style: type.sectionTitle),
                const SizedBox(height: V4Space.sm),
                if (_backup == null)
                  Text('没有迁移备份', style: type.label)
                else
                  _row(
                    context,
                    title: '备份文件',
                    detail:
                        (_backup!.modified == null
                            ? '时间未知'
                            : '${_backup!.modified!.year}-${_backup!.modified!.month}-${_backup!.modified!.day}') +
                        '  ' +
                        _backup!.sizeLabel,
                    action: '删除',
                    onTap: _deleteBackup,
                  ),
                const SizedBox(height: V4Space.xxl),
                Text('危险区', style: type.sectionTitle),
                const SizedBox(height: V4Space.sm),
                _row(
                  context,
                  title: '清空学习数据',
                  detail: '删除生词、题集、作答与错题，并回到首启。',
                  action: '清空',
                  danger: true,
                  onTap: _wipe,
                ),
              ],
            ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String detail,
    required String action,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V4Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: type.itemTitle),
                const SizedBox(height: V4Space.xs),
                Text(detail, style: type.caption),
              ],
            ),
          ),
          const SizedBox(width: V4Space.md),
          TextButton(
            onPressed: onTap,
            child: Text(
              action,
              style: TextStyle(color: danger ? v4.error : v4.brand),
            ),
          ),
        ],
      ),
    );
  }
}
