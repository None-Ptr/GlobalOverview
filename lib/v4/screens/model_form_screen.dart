import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4ModelFormScreen extends ConsumerStatefulWidget {
  final String? profileId;

  const V4ModelFormScreen({super.key, this.profileId});

  @override
  ConsumerState<V4ModelFormScreen> createState() => _V4ModelFormScreenState();
}

class _V4ModelFormScreenState extends ConsumerState<V4ModelFormScreen> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  String _builtinKey = '';
  bool _reveal = false;
  bool _busy = false;

  bool get _editing => widget.profileId != null;
  bool get _isBuiltin =>
      _editing && widget.profileId == AppConfigService.builtinProfileId;

  @override
  void initState() {
    super.initState();
    if (!_editing) return;
    final hits = ref
        .read(appConfigProvider)
        .profiles
        .where((p) => p.id == widget.profileId)
        .toList();
    if (hits.isEmpty) return;
    final profile = hits.first;
    _name.text = profile.name;
    _baseUrl.text = profile.baseUrl;
    _model.text = profile.model;
    if (_isBuiltin) {
      // The preset key stays in the profile; the form never loads it.
      _builtinKey = profile.apiKey;
    } else {
      _apiKey.text = profile.apiKey;
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
      showV4Snack(context, '给模型起个名字', tone: V4SnackTone.warning);
      return;
    }
    final cfg = ref.read(appConfigProvider);
    final record = LlmProfile(
      id: _editing
          ? widget.profileId!
          : DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      apiKey: _isBuiltin ? _builtinKey : _apiKey.text.trim(),
      model: _model.text.trim(),
    );
    final list = [...cfg.profiles];
    final index = list.indexWhere((p) => p.id == record.id);
    if (index >= 0) {
      list[index] = record;
    } else {
      list.add(record);
    }
    await cfg.setProfiles(list);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _test() async {
    final key = _isBuiltin ? _builtinKey : _apiKey.text.trim();
    if (_baseUrl.text.trim().isEmpty || key.isEmpty) {
      showV4Snack(context, '先填地址和密钥', tone: V4SnackTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final base = _baseUrl.text.trim().replaceAll(RegExp(r'/$'), '');
      await ref.read(httpProvider).getJson(
        '$base/models',
        headers: {'Authorization': 'Bearer $key'},
      );
      if (!mounted) return;
      showV4Snack(context, '连接成功', tone: V4SnackTone.success);
    } catch (e) {
      if (!mounted) return;
      showV4Snack(context, '连接失败：$e', tone: V4SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return V4Page(
      title: _editing ? '编辑模型' : '新增模型',
      bottomBar: Row(
        children: [
          Expanded(
            child: TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.outline,
              onPressed: _busy ? null : _test,
              child: Text(_busy ? '测试中' : '测试连接'),
            ),
          ),
          const SizedBox(width: V4Space.md),
          Expanded(
            child: V4PrimaryButton(
              onPressed: _busy ? null : _save,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.sm,
          V4Space.lg,
          V4Space.huge,
        ),
        children: [
          V4Section(
            title: '基本信息',
            children: [
              _field('名称', _name, '比如：日常用的 GPT'),
              _field('API 地址', _baseUrl, 'https://api.openai.com/v1'),
              _field('模型', _model, 'gpt-4o'),
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          V4Section(
            title: '密钥',
            children: [
              if (_isBuiltin)
                Padding(
                  padding: const EdgeInsets.all(V4Space.lg),
                  child: Text('内置模型使用预设密钥，无需填写。', style: type.label),
                )
              else ...[
                _field('API Key', _apiKey, 'sk-...', obscure: !_reveal),
                V4Tile(
                  title: _reveal ? '隐藏密钥' : '显示密钥',
                  onTap: () => setState(() => _reveal = !_reveal),
                ),
              ],
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text(
            '密钥只写在本机配置里，不会上传到任何服务器。',
            style: type.caption.copyWith(color: v4.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
  }) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.all(V4Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: type.label),
          const SizedBox(height: V4Space.sm),
          TextField(
            controller: controller,
            obscureText: obscure,
            style: type.body,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: type.caption,
              filled: true,
              fillColor: v4.surfaceSubtle,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: V4Space.md,
                vertical: V4Space.md,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.rule),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.rule),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V4Radius.control),
                borderSide: BorderSide(color: v4.brand, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
