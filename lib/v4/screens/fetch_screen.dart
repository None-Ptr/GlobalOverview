import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4FetchScreen extends ConsumerStatefulWidget {
  const V4FetchScreen({super.key});

  @override
  ConsumerState<V4FetchScreen> createState() => _V4FetchScreenState();
}

class _V4FetchScreenState extends ConsumerState<V4FetchScreen> {
  final _agent = TextEditingController();
  final _headers = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(appConfigProvider);
    _agent.text = cfg.userAgent;
    _headers.text = cfg.extraHeaders;
  }

  @override
  void dispose() {
    _agent.dispose();
    _headers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _headers.text.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException();
      } catch (_) {
        showV4Snack(context, '附加请求头要是一个 JSON 对象', tone: V4SnackTone.warning);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await ref.read(appConfigProvider).setFetchOptions(
        userAgent: _agent.text.trim(),
        extraHeaders: raw,
      );
      if (!mounted) return;
      showV4Snack(context, '已保存', tone: V4SnackTone.success);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    await ref.read(appConfigProvider).setFetchOptions(
      userAgent: '',
      extraHeaders: '',
    );
    if (!mounted) return;
    setState(() {
      _agent.clear();
      _headers.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return V4Page(
      title: '抓取设置',
      bottomBar: Row(
        children: [
          Expanded(
            child: TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.outline,
              onPressed: _busy ? null : _reset,
              child: const Text('恢复默认'),
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
            title: 'User-Agent',
            hint: '留空则用内置的浏览器标识',
            children: [
              _field(_agent, '留空使用内置默认值', 1),
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          V4Section(
            title: '附加请求头',
            hint: 'JSON 对象，支持 {url} 和 {host} 占位符',
            children: [
              _field(_headers, '{"Referer": "{url}"}', 5),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text(
            '只影响 RSS 和正文抓取，不影响 AI 与翻译接口。',
            style: type.caption.copyWith(color: v4.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint, int lines) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.all(V4Space.lg),
      child: TextField(
        controller: controller,
        maxLines: lines,
        style: type.label,
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
    );
  }
}
