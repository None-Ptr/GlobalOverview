import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/notification_service.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4PreferencesScreen extends ConsumerStatefulWidget {
  const V4PreferencesScreen({super.key});

  @override
  ConsumerState<V4PreferencesScreen> createState() =>
      _V4PreferencesScreenState();
}

class _V4PreferencesScreenState extends ConsumerState<V4PreferencesScreen> {
  List<Map<String, dynamic>> _presets = const [];
  String _level = 'CET6';
  String _activePresetId = '';
  bool _reminder = false;
  int _hour = NotificationService.defaultHour;
  int _minute = 0;
  bool _loading = true;

  List<String> get _levels => QuizService.examLevels.keys.toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final level = await db.select("SELECT value FROM kv WHERE key='targetLevel'");
    final active = await db.select(
      "SELECT value FROM kv WHERE key='activePresetId'",
    );
    final presets = await db.select('SELECT * FROM presets ORDER BY id ASC');
    final settings = await ref.read(notificationProvider).loadSettings();
    if (!mounted) return;
    setState(() {
      var value = level.isEmpty ? 'CET6' : '${level.first['value']}';
      if (value == '考研') value = 'NCEE';
      _level = QuizService.examLevels.containsKey(value) ? value : 'CET6';
      _activePresetId = active.isEmpty ? '' : '${active.first['value']}';
      _presets = presets;
      _reminder = settings.enabled;
      _hour = settings.hour;
      _minute = settings.minute;
      _loading = false;
    });
  }

  String get _time =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  Future<void> _setLevel(String level) async {
    setState(() => _level = level);
    await ref.read(dbProvider).execute(
      'INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)',
      ['targetLevel', level],
    );
    ref.read(targetLevelRevisionProvider.notifier).bump();
  }

  Future<void> _toggleReminder(bool on) async {
    final notifier = ref.read(notificationProvider);
    if (on) {
      final granted = await notifier.requestPermission();
      if (!mounted) return;
      if (!granted) {
        showV4Snack(context, '没有拿到通知权限', tone: V4SnackTone.warning);
        return;
      }
    }
    await notifier.saveSettings(
      enabled: on,
      hour: _hour,
      minute: _minute,
    );
    if (!mounted) return;
    setState(() => _reminder = on);
    ref.read(habitRevisionProvider.notifier).bump();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null || !mounted) return;
    await ref.read(notificationProvider).saveSettings(
      enabled: _reminder,
      hour: picked.hour,
      minute: picked.minute,
    );
    if (!mounted) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
    ref.read(habitRevisionProvider.notifier).bump();
  }

  Future<void> _sendTest() async {
    final ok = await ref.read(notificationProvider).sendTest();
    if (!mounted) return;
    showV4Snack(
      context,
      ok ? '已发送，下拉通知栏看看' : '发送失败，先打开通知权限',
      tone: ok ? V4SnackTone.success : V4SnackTone.error,
    );
  }

  Future<void> _selectPreset(Map<String, dynamic> preset) async {
    final id = '${preset['id']}';
    setState(() => _activePresetId = id);
    await ref.read(dbProvider).execute(
      'INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)',
      ['activePresetId', id],
    );
  }

  Future<void> _deletePreset(Map<String, dynamic> preset) async {
    final id = '${preset['id']}';
    await ref.read(dbProvider).execute('DELETE FROM presets WHERE id = ?', [
      preset['id'],
    ]);
    if (_activePresetId == id) {
      await ref.read(dbProvider).execute(
        "DELETE FROM kv WHERE key='activePresetId'",
      );
    }
    await _load();
  }

  Future<void> _createPreset() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.v4.surface,
      builder: (_) => const _PresetSheet(),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return V4Page(
      title: '学习偏好',
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.lg,
                V4Space.huge,
              ),
              children: [
                V4Section(
                  title: '出题难度',
                  hint: '没有指定考试的题集按这个档位出题',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(V4Space.lg),
                      child: Wrap(
                        spacing: V4Space.sm,
                        runSpacing: V4Space.sm,
                        children: [
                          for (final level in _levels)
                            V4Chip(
                              label: level,
                              selected: _level == level,
                              onTap: () => _setLevel(level),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: V4Space.xxl),
                V4Section(
                  title: '每日提醒',
                  children: [
                    MergeSemantics(
                      child: V4Tile(
                        title: '提醒我复习',
                        detail: _reminder ? '每天 $_time 提醒一次' : '已关闭',
                        trailing: Switch(
                          value: _reminder,
                          onChanged: _toggleReminder,
                        ),
                      ),
                    ),
                    if (_reminder)
                      V4Tile(
                        title: '提醒时间',
                        detail: _time,
                        onTap: _pickTime,
                      ),
                    V4Tile(
                      title: '发一条测试通知',
                      detail: '确认通知权限和通道正常',
                      onTap: _sendTest,
                    ),
                  ],
                ),
                const SizedBox(height: V4Space.xxl),
                V4Section(
                  title: '出题预设',
                  hint: '生成题集时按选中的预设决定题型和题量',
                  children: [
                    if (_presets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(V4Space.lg),
                        child: Text('还没有预设，生成题集时用默认的 5 道选择题', style: type.caption),
                      ),
                    for (final preset in _presets)
                      _PresetTile(
                        preset: preset,
                        active: _activePresetId == '${preset['id']}',
                        onTap: () => _selectPreset(preset),
                        onDelete: () => _deletePreset(preset),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(V4Space.md),
                      child: TButton(
                        size: TButtonSize.large,
                        variant: TButtonVariant.outline,
                        onPressed: _createPreset,
                        child: const Text('新建预设'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: V4Space.lg),
                Text(
                  '预设只影响出题，不改动已经生成的题集。',
                  style: type.caption.copyWith(color: v4.inkMuted),
                ),
              ],
            ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final Map<String, dynamic> preset;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PresetTile({
    required this.preset,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final config = preset['config'] as String?;
    var types = <String>[];
    var count = 5;
    if (config != null && config.isNotEmpty) {
      try {
        final decoded = jsonDecode(config) as Map;
        final raw = decoded['types'];
        if (raw is List) types = raw.map((e) => '$e').toList();
        if (raw is String) types = raw.split(',').map((e) => e.trim()).toList();
        count = int.tryParse('${decoded['count']}') ?? 5;
      } catch (_) {}
    }
    final detail = types.isEmpty
        ? '$count 道题'
        : '${types.map(_typeLabel).join('、')}，$count 道';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V4Space.lg,
          vertical: V4Space.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${preset['name'] ?? '未命名'}',
                          style: type.itemTitle.copyWith(
                            color: active ? v4.brand : v4.ink,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: V4Space.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: V4Space.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: v4.surfaceSubtle,
                            borderRadius: BorderRadius.circular(
                              V4Radius.control,
                            ),
                          ),
                          child: Text(
                            '使用中',
                            style: type.caption.copyWith(color: v4.brand),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: V4Space.xs),
                  Text(detail, style: type.caption),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除预设',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: v4.error),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String raw) =>
      {'choice': '选择题', 'fill': '填空题', 'shortAnswer': '简答题'}[raw] ?? raw;
}

class _PresetSheet extends ConsumerStatefulWidget {
  const _PresetSheet();

  @override
  ConsumerState<_PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends ConsumerState<_PresetSheet> {
  final _name = TextEditingController();
  final _count = TextEditingController(text: '5');
  final Set<String> _types = {'choice'};

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showV4Snack(context, '给预设起个名字', tone: V4SnackTone.warning);
      return;
    }
    if (_types.isEmpty) {
      showV4Snack(context, '至少选一种题型', tone: V4SnackTone.warning);
      return;
    }
    final config = jsonEncode({
      'types': _types.toList(),
      'count': int.tryParse(_count.text.trim()) ?? 5,
    });
    await ref.read(dbProvider).insertReturnId(
      'INSERT INTO presets (name, config) VALUES (?,?)',
      [name, config],
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: V4Space.lg,
        right: V4Space.lg,
        top: V4Space.xl,
        bottom: V4Space.xl + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('新建出题预设', style: type.sectionTitle),
          const SizedBox(height: V4Space.lg),
          TextField(
            controller: _name,
            style: type.body,
            decoration: InputDecoration(
              labelText: '名称',
              labelStyle: type.caption,
              filled: true,
              fillColor: v4.surfaceSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.rule),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.rule),
              ),
            ),
          ),
          const SizedBox(height: V4Space.lg),
          Text('题型', style: type.label),
          const SizedBox(height: V4Space.sm),
          Wrap(
            spacing: V4Space.sm,
            runSpacing: V4Space.sm,
            children: [
              for (final entry in const {
                'choice': '选择题',
                'fill': '填空题',
                'shortAnswer': '简答题',
              }.entries)
                _typeChip(entry.key, entry.value),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          TextField(
            controller: _count,
            keyboardType: TextInputType.number,
            style: type.body,
            decoration: InputDecoration(
              labelText: '题量',
              labelStyle: type.caption,
              filled: true,
              fillColor: v4.surfaceSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.rule),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.rule),
              ),
            ),
          ),
          const SizedBox(height: V4Space.xl),
          Row(
            children: [
              Expanded(
                child: TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.outline,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: V4Space.md),
              Expanded(
                child: V4PrimaryButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String key, String label) {
    return V4Chip(
      label: label,
      selected: _types.contains(key),
      onTap: () => setState(() {
        if (_types.contains(key)) {
          _types.remove(key);
        } else {
          _types.add(key);
        }
      }),
    );
  }
}
