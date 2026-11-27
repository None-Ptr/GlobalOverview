import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4TranslateFormScreen extends ConsumerStatefulWidget {
  final String? translatorId;

  const V4TranslateFormScreen({super.key, this.translatorId});

  @override
  ConsumerState<V4TranslateFormScreen> createState() =>
      _V4TranslateFormScreenState();
}

class _V4TranslateFormScreenState
    extends ConsumerState<V4TranslateFormScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _headers = TextEditingController();
  final _body = TextEditingController();
  final _resultPath = TextEditingController(text: 'data.translation');
  final _langMap = TextEditingController();
  String _method = 'POST';
  bool _busy = false;

  bool get _editing => widget.translatorId != null;

  @override
  void initState() {
    super.initState();
    if (!_editing) return;
    final hits = ref
        .read(appConfigProvider)
        .translators
        .where((t) => t.id == widget.translatorId)
        .toList();
    if (hits.isEmpty) return;
    final t = hits.first;
    _name.text = t.name;
    _url.text = t.url;
    _method = t.method;
    _headers.text = t.headers;
    _body.text = t.body;
    _resultPath.text = t.resultPath;
    _langMap.text = t.langMap;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _headers.dispose();
    _body.dispose();
    _resultPath.dispose();
    _langMap.dispose();
    super.dispose();
  }

  bool _jsonOk(String raw, String label) {
    if (raw.trim().isEmpty) return true;
    try {
      jsonDecode(raw);
      return true;
    } catch (_) {
      showV4Snack(context, '$label 不是合法 JSON', tone: V4SnackTone.warning);
      return false;
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showV4Snack(context, '给接口起个名字', tone: V4SnackTone.warning);
      return;
    }
    if (_url.text.trim().isEmpty) {
      showV4Snack(context, '填一下请求地址', tone: V4SnackTone.warning);
      return;
    }
    if (!_jsonOk(_headers.text, '请求头')) return;
    if (!_jsonOk(_body.text, '请求体')) return;
    if (!_jsonOk(_langMap.text, '语言映射')) return;
    await ref
        .read(appConfigProvider)
        .upsertTranslator(
          CustomTranslator(
            id: _editing
                ? widget.translatorId!
                : DateTime.now().millisecondsSinceEpoch.toString(),
            name: _name.text.trim(),
            url: _url.text.trim(),
            method: _method,
            headers: _headers.text.trim(),
            body: _body.text.trim(),
            resultPath: _resultPath.text.trim().isEmpty
                ? 'data.translation'
                : _resultPath.text.trim(),
            langMap: _langMap.text.trim(),
          ),
        );
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _delete() async {
    if (!_editing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除接口'),
        content: const Text('删除后会从翻译引擎列表里消失。'),
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
    await ref.read(appConfigProvider).deleteTranslator(widget.translatorId!);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _test() async {
    if (_url.text.trim().isEmpty) {
      showV4Snack(context, '先填请求地址', tone: V4SnackTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final http = ref.read(httpProvider);
      final url = _url.text
          .trim()
          .replaceAll('{text}', Uri.encodeComponent('Hello world'))
          .replaceAll('{target}', 'zh')
          .replaceAll('{lang}', 'zh');
      dynamic res;
      if (_method == 'GET') {
        res = await http.getJson(url);
      } else {
        Map<String, dynamic> body;
        try {
          body = _body.text.trim().isEmpty
              ? {'q': 'Hello world', 'target': 'zh', 'source': 'en'}
              : jsonDecode(
                  _body.text
                      .replaceAll('{text}', 'Hello world')
                      .replaceAll('{lang}', 'zh'),
                );
        } catch (_) {
          body = {'q': 'Hello world', 'target': 'zh', 'source': 'en'};
        }
        res = await http.postJson(url, body);
      }
      final out = '${_extract(res, _resultPath.text.trim())}';
      if (!mounted) return;
      showV4Snack(
        context,
        '返回译文：${out.length > 120 ? out.substring(0, 120) : out}',
      );
    } catch (e) {
      if (!mounted) return;
      showV4Snack(context, '测试失败：$e', tone: V4SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  dynamic _extract(dynamic res, String path) {
    if (path.isEmpty) return res;
    dynamic cur = res;
    for (final segment in path.split('.')) {
      if (cur is Map && cur.containsKey(segment)) {
        cur = cur[segment];
      } else {
        return cur;
      }
    }
    return cur;
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return V4Page(
      title: _editing ? '编辑翻译接口' : '新增翻译接口',
      bottomBar: Row(
        children: [
          Expanded(
            child: TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.outline,
              onPressed: _busy ? null : _test,
              child: Text(_busy ? '测试中' : '测试'),
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
              _field('名称', _name, '比如：腾讯云'),
              _field('请求地址', _url, 'https://.../translate'),
              V4Tile(
                title: '请求方法',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _methodChip('POST'),
                    const SizedBox(width: V4Space.sm),
                    _methodChip('GET'),
                  ],
                ),
              ),
              _field('结果路径', _resultPath, 'data.translation'),
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          V4Section(
            title: '请求细节',
            children: [
              _field('请求头（JSON）', _headers, '{"Authorization": "Bearer xxx"}', lines: 3),
              _field('请求体模板（JSON）', _body, '占位符 {text} {target} {lang}', lines: 3),
              _field('语言映射（JSON）', _langMap, '{"ZH":"zh","EN":"en"}', lines: 3),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text(
            '地址和请求体里可以用 {text}、{target}、{lang}；不填请求体时按 {"q":文字,"target":语言,"source":"en"} 发送。',
            style: type.caption.copyWith(color: v4.inkMuted),
          ),
          if (_editing) ...[
            const SizedBox(height: V4Space.xxl),
            TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.text,
              colorPreset: TButtonColorPreset.danger,
              onPressed: _delete,
              child: const Text('删除这个接口'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _methodChip(String method) {
    return V4Chip(
      label: method,
      selected: _method == method,
      onTap: () => setState(() => _method = method),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    int lines = 1,
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
            maxLines: lines,
            style: type.body,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: type.caption,
              filled: true,
              fillColor: v4.surfaceSubtle,
              contentPadding: const EdgeInsets.all(V4Space.md),
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
