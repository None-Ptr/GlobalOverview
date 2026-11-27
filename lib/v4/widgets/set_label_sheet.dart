// Hallmark · screen: set label sheet · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S4 R5 V4 · weakest S — one field and two actions; this is a name, not a form
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// Returns the new label, or null when the sheet was dismissed. An empty
/// string is a deliberate clear, not a cancel.
Future<String?> showSetLabelSheet(
  BuildContext context, {
  required String current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.v4.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(V4Radius.sheet)),
    ),
    builder: (sheetContext) => _SetLabelSheet(current: current),
  );
}

class _SetLabelSheet extends StatefulWidget {
  final String current;
  const _SetLabelSheet({required this.current});

  @override
  State<_SetLabelSheet> createState() => _SetLabelSheetState();
}

class _SetLabelSheetState extends State<_SetLabelSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
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
              Text('用途标签', style: type.sectionTitle),
              const SizedBox(height: V4Space.xs),
              Text('给这套题一个好认的名字。', style: type.label),
              const SizedBox(height: V4Space.xl),
              TextField(
                controller: _controller,
                maxLines: 1,
                style: type.body,
                onSubmitted: (v) => Navigator.of(context).pop(_clean(v)),
                decoration: InputDecoration(
                  hintText: '比如：考前重做',
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
                      onPressed: () =>
                          Navigator.of(context).pop(_clean(_controller.text)),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _clean(String raw) {
  final text = raw.trim();
  return text.length > 16 ? text.substring(0, 16) : text;
}
