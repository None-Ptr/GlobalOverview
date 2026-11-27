// Hallmark · screen: import sheet · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S4 R5 V4 · weakest S — two ways in, one action out; no wizard, no progress theatre
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class ImportRequest {
  final bool byUrl;
  final String title;
  final String body;
  final String url;

  const ImportRequest({
    required this.byUrl,
    required this.title,
    required this.body,
    required this.url,
  });
}

/// One sheet, two ways in. The category stays 我的导入 so imported work is
/// visible in the reading list without becoming another settings screen.
Future<ImportRequest?> showImportSheet(BuildContext context) {
  return showModalBottomSheet<ImportRequest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.v4.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(V4Radius.sheet)),
    ),
    builder: (_) => const _ImportSheet(),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  bool _byUrl = false;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _url.dispose();
    super.dispose();
  }

  InputDecoration _field(BuildContext context, String hint) {
    final v4 = context.v4;
    return InputDecoration(
      hintText: hint,
      hintStyle: context.v4Type.caption,
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
    );
  }

  Widget _modeChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required ValueKey key,
    required VoidCallback onTap,
  }) {
    final v4 = context.v4;
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: v4.surfaceSubtle,
      showCheckmark: false,
      side: BorderSide(color: selected ? v4.brand : v4.rule),
      backgroundColor: v4.surface,
      labelStyle: context.v4Type.caption.copyWith(
        color: selected ? v4.brand : v4.inkSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V4Radius.control),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final ready = _byUrl
        ? _url.text.trim().isNotEmpty
        : _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: V4Space.xl,
          right: V4Space.xl,
          top: V4Space.md,
          bottom: V4Space.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: v4.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: V4Space.lg),
            Text('导入文章', style: type.sectionTitle),
            const SizedBox(height: V4Space.xl),
            Row(
              children: [
                _modeChip(
                  context: context,
                  label: '粘贴正文',
                  selected: !_byUrl,
                  key: const ValueKey('v4-import-paste'),
                  onTap: () => setState(() => _byUrl = false),
                ),
                const SizedBox(width: V4Space.sm),
                _modeChip(
                  context: context,
                  label: '文章网址',
                  selected: _byUrl,
                  key: const ValueKey('v4-import-url'),
                  onTap: () => setState(() => _byUrl = true),
                ),
              ],
            ),
            const SizedBox(height: V4Space.xl),
            if (_byUrl)
              TextField(
                key: const ValueKey('v4-import-url-field'),
                controller: _url,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                style: type.body,
                decoration: _field(context, 'https://example.com/article'),
              )
            else ...[
              TextField(
                key: const ValueKey('v4-import-title-field'),
                controller: _title,
                maxLines: 1,
                onChanged: (_) => setState(() {}),
                style: type.body,
                decoration: _field(context, '文章标题'),
              ),
              const SizedBox(height: V4Space.md),
              TextField(
                key: const ValueKey('v4-import-body-field'),
                controller: _body,
                maxLines: 6,
                minLines: 4,
                onChanged: (_) => setState(() {}),
                style: type.body,
                decoration: _field(context, '把正文粘贴到这里，空行分段'),
              ),
            ],
            const SizedBox(height: V4Space.xl),
            Row(
              children: [
                Expanded(
                  child: TButton(
                    size: TButtonSize.large,
                    variant: TButtonVariant.text,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: V4Space.md),
                Expanded(
                  child: V4PrimaryButton(
                    onPressed: ready
                        ? () => Navigator.of(context).pop(
                              ImportRequest(
                                byUrl: _byUrl,
                                title: _title.text.trim(),
                                body: _body.text.trim(),
                                url: _url.text.trim(),
                              ),
                            )
                        : null,
                    child: const Text('导入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
