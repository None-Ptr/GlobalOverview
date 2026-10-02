import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 翻译接口表单页：1:1 对齐 legacy/src/pages/translate-form/translate-form.vue
class TranslateFormScreen extends ConsumerStatefulWidget {
  final String? translatorId;
  const TranslateFormScreen({super.key, this.translatorId});
  @override
  ConsumerState<TranslateFormScreen> createState() => _TranslateFormScreenState();
}

class _TranslateFormScreenState extends ConsumerState<TranslateFormScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _headers = TextEditingController();
  final _body = TextEditingController();
  final _resultPath = TextEditingController(text: 'data.translation');
  final _langMap = TextEditingController();
  String _method = 'POST';
  bool _busy = false;

  bool get _isEdit => widget.translatorId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final cfg = ref.read(appConfigProvider).translators.where((x) => x.id == widget.translatorId).toList();
      if (cfg.isNotEmpty) {
        final c = cfg.first;
        _name.text = c.name;
        _url.text = c.url;
        _method = c.method;
        _headers.text = c.headers;
        _body.text = c.body;
        _resultPath.text = c.resultPath;
        _langMap.text = c.langMap;
      }
    }
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

  bool _validJson(String s, String label) {
    if (s.trim().isEmpty) return true;
    try {
      jsonDecode(s);
      return true;
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label不是合法 JSON')));
      return false;
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写名称')));
      return;
    }
    if (_url.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写请求地址')));
      return;
    }
    if (!_validJson(_headers.text, '请求头')) return;
    if (!_validJson(_body.text, '请求体')) return;
    if (!_validJson(_langMap.text, '语言映射')) return;
    await ref.read(appConfigProvider).upsertTranslator(CustomTranslator(
          id: _isEdit ? widget.translatorId! : DateTime.now().millisecondsSinceEpoch.toString(),
          name: _name.text.trim(),
          url: _url.text.trim(),
          method: _method,
          headers: _headers.text.trim(),
          body: _body.text.trim(),
          resultPath: _resultPath.text.trim().isEmpty ? 'data.translation' : _resultPath.text.trim(),
          langMap: _langMap.text.trim(),
        ));
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _remove() async {
    if (!_isEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除接口'),
        content: const Text('删除后将从翻译引擎列表移除，确定？'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))],
      ),
    );
    if (ok != true) return;
    await ref.read(appConfigProvider).deleteTranslator(widget.translatorId!);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _testConn() async {
    if (_url.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填写请求地址')));
      return;
    }
    setState(() => _busy = true);
    try {
      final http = ref.read(httpProvider);
      final url = _url.text.trim().replaceAll('{text}', Uri.encodeComponent('Hello world')).replaceAll('{target}', 'zh').replaceAll('{lang}', 'zh');
      dynamic res;
      if (_method == 'GET') {
        res = await http.getJson(url);
      } else {
        Map<String, dynamic> body;
        try {
          body = _body.text.trim().isEmpty ? {'q': 'Hello world', 'target': 'zh', 'source': 'en'} : jsonDecode(_body.text.replaceAll('{text}', 'Hello world').replaceAll('{lang}', 'zh'));
        } catch (_) {
          body = {'q': 'Hello world', 'target': 'zh', 'source': 'en'};
        }
        res = await http.postJson(url, body);
      }
      final out = _extract(res, _resultPath.text.trim());
      final brief = '$out';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('返回译文：${brief.length > 120 ? brief.substring(0, 120) : brief}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('测试失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  dynamic _extract(dynamic res, String path) {
    if (path.isEmpty) return res;
    dynamic cur = res;
    for (final seg in path.split('.')) {
      if (cur is Map && cur.containsKey(seg)) {
        cur = cur[seg];
      } else {
        return cur;
      }
    }
    return cur;
  }

  @override
  Widget build(BuildContext context) {
    return GoPage(
      topPad: false,
      child: Column(
        children: [
          GoAppBar(
            title: _isEdit ? '编辑翻译接口' : '新增翻译接口',
            style: GoAppBarStyle.floating,
            leading: GoBack(),
            actions: [GestureDetector(onTap: _save, child: const Text('保存', style: TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w600, color: Go.primary)))],
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
                          _field('名称', GoField(controller: _name, hint: '如：腾讯云 / 有道')),
                          _field('请求地址', GoField(controller: _url, hint: 'https://.../translate')),
                          _field('请求方法', Row(children: [
                            for (final m in ['POST', 'GET']) ...[
                              GestureDetector(
                                onTap: () => setState(() => _method = m),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp1),
                                  decoration: BoxDecoration(color: _method == m ? Go.primary : Go.surface2, borderRadius: BorderRadius.circular(Go.rFull), border: Border.all(color: _method == m ? Go.primary : Go.outline, width: 0.5)),
                                  child: Text(m, style: TextStyle(fontSize: Go.fsMeta, color: _method == m ? Go.onPrimary : Go.onSurface2)),
                                ),
                              ),
                              const SizedBox(width: Go.sp2),
                            ],
                          ]), last: true),
                        ],
                      ),
                    ),
                  ]),
                  GoSection(title: '请求与响应', children: [
                    GoCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _field('结果提取路径（JSON）', GoField(controller: _resultPath, hint: '如 data.translation / data.choices[0].text')),
                          _field('请求头（JSON，可选）', GoField(controller: _headers, hint: '如 {"Authorization": "Bearer xxx"}', maxLines: 4)),
                          _field('请求体模板（JSON，可选）', GoField(controller: _body, hint: '占位符 {text} {target} {lang}', maxLines: 4)),
                          _field('目标语言映射（JSON，可选）', GoField(controller: _langMap, hint: '如 {"ZH":"zh","EN":"en"}', maxLines: 4), last: true),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(Go.sp3, Go.sp3, Go.sp3, 0),
                      child: Text('URL 支持 {text} {target} {lang} 占位符；不填请求体时按 {"q":文字, "target":语言, "source":"en"} 发送。', style: TextStyle(fontSize: Go.fsCap, color: Go.onSurface3, height: 1.5)),
                    ),
                  ]),
                  GoBtn(label: '测试', kind: GoBtnKind.tonal, block: true, onTap: _busy ? null : _testConn),
                  if (_isEdit) ...[
                    const SizedBox(height: Go.sp4),
                    GoBtn(label: '删除接口', kind: GoBtnKind.text, block: true, onTap: _remove),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, Widget child, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Go.outline, width: 0.5))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, fontWeight: FontWeight.w500)),
            const SizedBox(height: Go.sp2),
            child,
          ],
        ),
      );
}
