import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 模型表单页：1:1 对齐 legacy/src/pages/model-form/model-form.vue
class ModelFormScreen extends ConsumerStatefulWidget {
  final String? profileId;
  const ModelFormScreen({super.key, this.profileId});
  @override
  ConsumerState<ModelFormScreen> createState() => _ModelFormScreenState();
}

class _ModelFormScreenState extends ConsumerState<ModelFormScreen> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _showKey = false;
  bool _busy = false;

  bool get _isEdit => widget.profileId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = ref.read(appConfigProvider).profiles.where((x) => x.id == widget.profileId).toList();
      if (p.isNotEmpty) {
        _name.text = p.first.name;
        _baseUrl.text = p.first.baseUrl;
        _model.text = p.first.model;
        _apiKey.text = p.first.apiKey;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写名称')));
      return;
    }
    final cfg = ref.read(appConfigProvider);
    final record = LlmProfile(
      id: _isEdit ? widget.profileId! : DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
    );
    final list = [...cfg.profiles];
    final i = list.indexWhere((x) => x.id == record.id);
    if (i >= 0) {
      list[i] = record;
    } else {
      list.add(record);
    }
    await cfg.setProfiles(list);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _testConn() async {
    if (_baseUrl.text.trim().isEmpty || _apiKey.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填写地址与密钥')));
      return;
    }
    setState(() => _busy = true);
    try {
      final url = '${_baseUrl.text.trim().replaceAll(RegExp(r'/$'), '')}/models';
      await ref.read(httpProvider).getJson(url, headers: {'Authorization': 'Bearer ${_apiKey.text.trim()}'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('连接成功')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoPage(
      topPad: false,
      child: Column(
        children: [
          GoAppBar(
            title: _isEdit ? '编辑模型' : '新增模型',
            style: GoAppBarStyle.floating,
            leading: GoBack(),
            actions: [GestureDetector(onTap: _busy ? null : _save, child: const Text('保存', style: TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w600, color: Go.primary)))],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Go.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GoSection(title: '基本信息', children: [
                    GoCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _field('名称', _name, '如：我的 GPT'),
                          _field('API 地址', _baseUrl, 'https://api.openai.com/v1'),
                          _field('模型', _model, 'gpt-4o / claude-3-5-sonnet', last: true),
                        ],
                      ),
                    ),
                  ]),
                  GoSection(title: '密钥', children: [
                    GoCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _field('API Key', _apiKey, 'sk-...', obscure: !_showKey, last: true),
                          InkWell(
                            onTap: () => setState(() => _showKey = !_showKey),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GoIcon(_showKey ? 'eye-off' : 'eye', size: 15, color: Go.primary),
                                  const SizedBox(width: Go.sp2),
                                  Text(_showKey ? '隐藏密钥' : '显示密钥', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.primary)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(Go.sp3, Go.sp3, Go.sp3, 0),
                      child: Text('密钥仅保存在本机，不会上传到任何服务器。', style: TextStyle(fontSize: Go.fsCap, color: Go.onSurface3, height: 1.5)),
                    ),
                  ]),
                  GoBtn(label: '测试连接', kind: GoBtnKind.tonal, block: true, onTap: _busy ? null : _testConn),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint, {bool obscure = false, bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Go.outline, width: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, fontWeight: FontWeight.w500)),
          const SizedBox(height: Go.sp2),
          GoField(controller: c, hint: hint, obscure: obscure),
        ],
      ),
    );
  }
}
