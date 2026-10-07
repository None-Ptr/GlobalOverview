import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/services/update_controller.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/model_form_screen.dart';
import 'package:global_overview/screens/translate_form_screen.dart';
import 'package:global_overview/services/notification_service.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_time_picker.dart';
import 'package:global_overview/widgets/go_ui.dart';
import 'package:global_overview/widgets/go_update_sheet.dart';

class MineScreen extends ConsumerStatefulWidget {
  const MineScreen({super.key});
  @override
  ConsumerState<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends ConsumerState<MineScreen> {
  String _targetLevel = 'CET6';
  final _levels = QuizService.examLevels.keys.toList();

  // —— 学习提醒 ——
  bool _notifEnabled = false;
  int _notifHour = NotificationService.defaultHour;
  int _notifMinute = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadGoal();
      _loadNotif();
      _maybeUpdatePrompt();
    });
  }

  Future<void> _loadNotif() async {
    final ns = await ref.read(notificationProvider).loadSettings();
    if (!mounted) return;
    setState(() {
      _notifEnabled = ns.enabled;
      _notifHour = ns.hour;
      _notifMinute = ns.minute;
    });
  }

  String _fmtTime(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Future<void> _toggleNotif() async {
    final next = !_notifEnabled;
    final notif = ref.read(notificationProvider);
    if (next) {
      final granted = await notif.requestPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未获得通知权限')));
        return;
      }
    }
    await notif.saveSettings(enabled: next, hour: _notifHour, minute: _notifMinute);
    if (mounted) setState(() => _notifEnabled = next);
    ref.read(habitRevisionProvider.notifier).bump(); // 触发首页重排通知
  }

  Future<void> _pickNotifTime() async {
    final t = await showGoTimePicker(context: context, initialTime: TimeOfDay(hour: _notifHour, minute: _notifMinute));
    if (t == null || !mounted) return;
    final notif = ref.read(notificationProvider);
    await notif.saveSettings(enabled: _notifEnabled, hour: t.hour, minute: t.minute);
    if (mounted) {
      setState(() {
        _notifHour = t.hour;
        _notifMinute = t.minute;
      });
    }
    ref.read(habitRevisionProvider.notifier).bump();
  }

  // —— 应用内更新 ——

  /// 入口行副标题：把状态机翻译成一句人话。
  String _updateSub(UpdateController c) => switch (c.phase) {
        UpdatePhase.checking => '正在检查…',
        UpdatePhase.available => '发现 v${c.info?.version ?? ''}',
        UpdatePhase.latest => '已是最新版本',
        UpdatePhase.failed => c.error ?? '检查失败',
        UpdatePhase.downloading => '正在下载…',
        UpdatePhase.verifying => '正在校验…',
        UpdatePhase.installing => '等待安装确认',
        _ => c.installedLabel.isEmpty ? '当前版本' : '当前 ${c.installedLabel}',
      };

  DateTime? _lastManualCheck;

  Future<void> _checkUpdate() async {
    final now = DateTime.now();
    if (_lastManualCheck != null && now.difference(_lastManualCheck!) < const Duration(seconds: 30)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刚检查过，稍等一会儿再试')));
      return;
    }
    _lastManualCheck = now;
    final c = ref.read(updateProvider);
    await c.checkNow();
    if (!mounted) return;
    switch (c.phase) {
      case UpdatePhase.latest:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已是最新版本')));
      case UpdatePhase.failed:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.error ?? '检查失败')));
      case UpdatePhase.available:
        await showGoUpdateSheet(context, c);
      default:
        break;
    }
  }

  /// 启动时静默检查（每天最多一次）；同一版本只弹一次卡片，之后只留红点。
  Future<void> _maybeUpdatePrompt() async {
    final c = ref.read(updateProvider);
    await c.init();
    await c.autoCheck();
    if (!mounted) return;
    if (await c.shouldPrompt() && mounted) {
      await showGoUpdateSheet(context, c);
    }
  }

  /// 立即发一条通知，用来确认通知权限/通道正常（定时是否生效另说）。
  Future<void> _sendTestNotif() async {
    final ok = await ref.read(notificationProvider).sendTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已发送，下拉通知栏查看' : '发送失败：没拿到通知权限')),
    );
  }

  Future<void> _loadGoal() async {
    final r = await ref.read(dbProvider).select("SELECT value FROM kv WHERE key='targetLevel'");
    if (!mounted || r.isEmpty) return;
    var v = r.first['value'] as String? ?? '';
    if (v == '考研') v = 'NCEE';
    if (QuizService.examLevels.containsKey(v)) setState(() => _targetLevel = v);
  }

  Future<void> _setTarget(String lv) async {
    setState(() => _targetLevel = lv);
    await ref.read(dbProvider).execute('INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)', ['targetLevel', lv]);
    ref.read(targetLevelRevisionProvider.notifier).bump();
  }

  // ================= LLM 模型 =================
  Future<void> _switchProfile(String id) => ref.read(appConfigProvider).setCurrentProfile(id);

  Future<void> _openProfileForm({String? id}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ModelFormScreen(profileId: id)));
  }

  Future<void> _deleteProfile(String id, String name) async {
    final ok = await _confirm('删除模型', '确认删除「$name」？');
    if (ok != true) return;
    final cfg = ref.read(appConfigProvider);
    await cfg.setProfiles(cfg.profiles.where((p) => p.id != id).toList());
  }

  // ================= 翻译引擎 =================
  Future<void> _switchEngine(String key) => ref.read(appConfigProvider).setReader(transEngine: key);

  Future<void> _openTranslatorForm({String? id}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TranslateFormScreen(translatorId: id)));
  }

  Future<void> _deleteTranslator(String id, String name) async {
    final ok = await _confirm('删除接口', '确认删除「${name.isEmpty ? '该接口' : name}」？');
    if (ok != true) return;
    await ref.read(appConfigProvider).deleteTranslator(id);
  }

  Future<bool?> _confirm(String title, String content, {String confirmText = '确定'}) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(confirmText)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(targetLevelRevisionProvider, (_, _) => _loadGoal());
    final update = ref.watch(updateProvider);
    final cfg = ref.watch(appConfigProvider);
    final models = cfg.profiles;
    final translators = cfg.translators;

    return GoPage(
      topPad: false,
      child: Column(
        children: [
          const GoAppBar(title: '我的', style: GoAppBarStyle.floating),
          Expanded(
            child: SingleChildScrollView(
              child: GoContent(
                child: GoStagger(
                  spacing: Go.sp8,
                  children: [
                    // —— LLM 模型 ——
                    GoSection(
                      title: 'LLM 模型',
                      children: [
                        _hint('点选模型即可切换当前使用的大模型'),
                        if (models.isNotEmpty)
                          GoCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < models.length; i++)
                                  _selectRow(
                                    icon: 'robot',
                                    title: models[i].name,
                                    sub: '${models[i].baseUrl} · ${models[i].model}',
                                    active: cfg.currentProfileId == models[i].id,
                                    onTap: () => _switchProfile(models[i].id),
                                    onEdit: () => _openProfileForm(id: models[i].id),
                                    onDelete: models.length > 1 ? () => _deleteProfile(models[i].id, models[i].name) : null,
                                    divider: i > 0,
                                  ),
                              ],
                            ),
                          )
                        else
                          _hintCard('尚未配置模型，添加后可启用 AI 解析'),
                        Padding(
                          padding: const EdgeInsets.only(top: Go.sp4),
                          child: GoBtn(label: '＋ 新增模型', kind: GoBtnKind.tonal, block: true, onTap: () => _openProfileForm()),
                        ),
                      ],
                    ),

                    // —— 翻译引擎 ——
                    GoSection(
                      title: '翻译引擎',
                      children: [
                        _hint('阅读时点词翻译所用引擎'),
                        GoCard(
                          child: Wrap(
                            spacing: Go.sp3,
                            runSpacing: Go.sp3,
                            children: [
                              for (final e in TranslateService.engineNames.entries) _chip(e.value, cfg.transEngine == e.key, () => _switchEngine(e.key)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // —— 自定义翻译接口 ——
                    GoSection(
                      title: '自定义翻译接口',
                      children: [
                        _hint('接入第三方翻译 API，选中后即可作为翻译引擎'),
                        if (translators.isNotEmpty)
                          GoCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < translators.length; i++)
                                  _selectRow(
                                    icon: 'translate',
                                    title: translators[i].name.isEmpty ? '未命名接口' : translators[i].name,
                                    sub: '${translators[i].method} ${translators[i].url}',
                                    active: cfg.transEngine == translators[i].id,
                                    onTap: () => _switchEngine(translators[i].id),
                                    onEdit: () => _openTranslatorForm(id: translators[i].id),
                                    onDelete: () => _deleteTranslator(translators[i].id, translators[i].name),
                                    divider: i > 0,
                                  ),
                              ],
                            ),
                          )
                        else
                          _hintCard('尚未配置自定义翻译接口，可添加第三方翻译 API'),
                        Padding(
                          padding: const EdgeInsets.only(top: Go.sp4),
                          child: GoBtn(label: '＋ 新增翻译接口', kind: GoBtnKind.tonal, block: true, onTap: () => _openTranslatorForm()),
                        ),
                      ],
                    ),

                    // —— 抓取设置 ——
                    GoSection(
                      title: '抓取设置',
                      children: [
                        _hint('仅作用于 RSS 与文章正文抓取，不影响 LLM 与翻译接口'),
                        GoCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _navRow(
                                icon: 'settings',
                                title: 'User-Agent',
                                sub: cfg.userAgent.trim().isEmpty ? '内置默认（浏览器标识）' : cfg.userAgent.trim(),
                                onTap: _editFetchUa,
                              ),
                              _navRow(
                                icon: 'plus',
                                title: '附加请求头',
                                sub: cfg.extraHeaders.trim().isEmpty ? '未设置' : cfg.extraHeaders.trim(),
                                onTap: _editFetchHeaders,
                                divider: false,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: Go.sp4),
                          child: GoBtn(
                            label: '恢复默认请求头',
                            kind: GoBtnKind.tonal,
                            block: true,
                            onTap: () async {
                              await ref.read(appConfigProvider).setFetchOptions(userAgent: '', extraHeaders: '');
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),

                    // —— 难度设置 ——
                    GoSection(
                      title: '难度设置',
                      children: [
                        _hint('未指定考试时按此难度出题'),
                        GoCard(
                          child: Wrap(
                            spacing: Go.sp3,
                            runSpacing: Go.sp3,
                            children: [for (final lv in _levels) _chip(lv, _targetLevel == lv, () => _setTarget(lv))],
                          ),
                        ),
                      ],
                    ),

                    // —— 学习提醒 ——
                    GoSection(
                      title: '学习提醒',
                      children: [
                        _hint('本地通知：每日提醒 + 航程预警，可随时关闭'),
                        GoCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _navRow(
                                icon: 'bell',
                                title: '开启提醒',
                                sub: _notifEnabled ? '每日 ${_fmtTime(_notifHour, _notifMinute)} 提醒' : '已关闭',
                                onTap: _toggleNotif,
                                divider: true,
                              ),
                              if (_notifEnabled)
                                _navRow(
                                  icon: 'clock',
                                  title: '提醒时间',
                                  sub: _fmtTime(_notifHour, _notifMinute),
                                  onTap: _pickNotifTime,
                                  divider: true,
                                ),
                              _navRow(
                                icon: 'bell-ring',
                                title: '发送测试通知',
                                sub: '立刻发一条，确认能收到',
                                onTap: _sendTestNotif,
                                divider: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // —— 数据管理 ——
                    GoSection(
                      title: '数据管理',
                      children: [
                        GoCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _navRow(
                                icon: 'book-check',
                                title: '错题本',
                                sub: '查看并改错答错的题目',
                                onTap: () => Navigator.pushNamed(context, '/wrong'),
                                divider: false,
                              ),
                              _navRow(
                                icon: 'trash',
                                title: '清除缓存',
                                sub: '清空抓取列表与词典缓存，保留题目与错题',
                                onTap: () async {
                                  final ok = await _confirm('清除缓存', '将清空抓取列表与词典缓存，题目与错题不受影响。');
                                  if (ok == true) await ref.read(dbProvider).clearCache();
                                  if (mounted) setState(() {});
                                },
                              ),
                              _navRow(
                                icon: 'alert',
                                title: '清空全部数据',
                                sub: '删除文章、题集、错题与计划，保留模型配置',
                                danger: true,
                                onTap: () async {
                                  final ok = await _confirm('清空全部数据', '将删除文章、题集、错题与计划，且不可恢复。模型配置会保留。', confirmText: '清空');
                                  if (ok == true) await ref.read(dbProvider).clearAll();
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // —— 关于 ——
                    GoSection(
                      title: '关于',
                      children: [
                        GoCard(
                          padding: EdgeInsets.zero,
                          child: _navRow(
                            icon: 'refresh',
                            title: '检查更新',
                            sub: _updateSub(update),
                            onTap: _checkUpdate,
                            spin: update.phase == UpdatePhase.checking,
                            dot: update.phase == UpdatePhase.available,
                            highlight: update.phase == UpdatePhase.available,
                            divider: false,
                          ),
                        ),
                      ],
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: Go.sp8),
                      child: Column(
                        children: [
                          const Text(
                            'GlobalOverview · By ShaDouBuShi & _Null_Ptr',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: Go.fsCap, color: Go.onSurfaceDisabled, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: Go.sp1),
                          Text(update.installedLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: Go.fsCap, color: Go.onSurfaceDisabled)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(Go.sp5, 0, Go.sp5, Go.sp3),
        child: Text(text, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
      );

  Widget _hintCard(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp8),
        decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), border: Border.all(color: Go.outline, width: 0.5)),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3)),
      );

  Widget _pill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: Go.primary95, borderRadius: BorderRadius.circular(Go.rFull)),
        child: Text(label, style: const TextStyle(fontSize: Go.fsCap, fontWeight: FontWeight.w600, color: Go.primary)),
      );

  Widget _chip(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp2),
          decoration: BoxDecoration(
            color: active ? Go.primary95 : Go.surface2,
            borderRadius: BorderRadius.circular(Go.rFull),
            border: Border.all(color: active ? Go.primary.withValues(alpha: 0.4) : Go.outline, width: 0.5),
          ),
          child: Text(label, style: TextStyle(fontSize: Go.fsMeta, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? Go.primary : Go.onSurface2)),
        ),
      );

  /// 可选择行：点击即切换当前项，尾部提供编辑/删除。
  Widget _selectRow({
    required String icon,
    required String title,
    String? sub,
    required bool active,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    bool divider = true,
  }) {
    return Column(
      children: [
        if (divider) const Divider(height: 0.5, thickness: 0.5, color: Go.outline),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp3),
            child: Row(
              children: [
                Container(
                  width: Go.r(64),
                  height: Go.r(64),
                  decoration: BoxDecoration(color: active ? Go.primary95 : Go.surface2, borderRadius: BorderRadius.circular(Go.rSm)),
                  child: Center(child: GoIcon(icon, size: Go.r(48), color: active ? Go.primary : Go.onSurface3)),
                ),
                const SizedBox(width: Go.sp4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w600, color: active ? Go.primary : Go.onSurface))),
                          if (active) ...[const SizedBox(width: Go.sp2), _pill('使用中')],
                        ],
                      ),
                      if (sub != null && sub.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
                      ],
                    ],
                  ),
                ),
                if (onEdit != null) _textAction('编辑', onEdit, Go.primary),
                if (onDelete != null) _iconAction('trash', onDelete),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editFetchUa() async {
    final cfg = ref.read(appConfigProvider);
    final v = await _prompt('User-Agent', '留空则使用内置默认值', cfg.userAgent);
    if (v == null) return;
    await cfg.setFetchOptions(userAgent: v.trim());
    if (mounted) setState(() {});
  }

  Future<void> _editFetchHeaders() async {
    final cfg = ref.read(appConfigProvider);
    final v = await _prompt('附加请求头（JSON）', '如 {"Referer":"{url}"}，支持 {url} 与 {host}', cfg.extraHeaders, maxLines: 5);
    if (v == null) return;
    final raw = v.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要是一个 JSON 对象')));
        return;
      }
    }
    await cfg.setFetchOptions(extraHeaders: raw);
    if (mounted) setState(() {});
  }

  Future<String?> _prompt(String title, String hint, String initial, {int maxLines = 1}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint, style: const TextStyle(fontSize: Go.fsCap, color: Go.onSurface3)),
            const SizedBox(height: Go.sp3),
            GoField(controller: ctrl, maxLines: maxLines),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('保存')),
        ],
      ),
    );
  }

  Widget _navRow({
    required String icon,
    required String title,
    String? sub,
    VoidCallback? onTap,
    bool danger = false,
    bool divider = true,
    bool highlight = false,
    bool dot = false,
    bool spin = false,
  }) {
    return Column(
      children: [
        if (divider) const Divider(height: 0.5, thickness: 0.5, color: Go.outline),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp3),
            child: Row(
              children: [
                Container(
                  width: Go.r(64),
                  height: Go.r(64),
                  decoration: BoxDecoration(color: danger ? Go.danger.withValues(alpha: 0.14) : Go.primary95, borderRadius: BorderRadius.circular(Go.rSm)),
                  child: Center(child: GoIcon(icon, size: Go.r(48), color: danger ? Go.danger : Go.primary, spin: spin)),
                ),
                const SizedBox(width: Go.sp4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w500, color: danger ? Go.error : Go.onSurface)),
                      if (sub != null) ...[
                        const SizedBox(height: 1),
                        Text(sub, style: TextStyle(fontSize: Go.fsMeta, color: highlight ? Go.primary : Go.onSurface3)),
                      ],
                    ],
                  ),
                ),
                if (dot)
                  Container(
                    width: Go.sp4,
                    height: Go.sp4,
                    margin: const EdgeInsets.only(right: Go.sp2),
                    decoration: const BoxDecoration(color: Go.primary, shape: BoxShape.circle),
                  ),
                const Icon(Icons.chevron_right, size: 18, color: Go.onSurfaceDisabled),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _textAction(String label, VoidCallback onTap, Color color) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Go.rFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Go.sp3, vertical: Go.sp2),
          child: Text(label, style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: color)),
        ),
      );

  Widget _iconAction(String icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Go.rFull),
        child: Padding(
          padding: const EdgeInsets.all(Go.sp2),
          child: GoIcon(icon, size: Go.r(48), color: Go.danger),
        ),
      );
}
