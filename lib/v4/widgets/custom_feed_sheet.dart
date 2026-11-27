// Hallmark · screen: custom feed sheet · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S4 R5 V4 · weakest S — three fields and one action; the address is the fact
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class CustomFeedRequest {
  final String name;
  final String url;
  final String category;

  const CustomFeedRequest({
    required this.name,
    required this.url,
    required this.category,
  });
}

Future<CustomFeedRequest?> showCustomFeedSheet(BuildContext context) {
  return showModalBottomSheet<CustomFeedRequest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.v4.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(V4Radius.sheet)),
    ),
    builder: (_) => const _CustomFeedSheet(),
  );
}

class _CustomFeedSheet extends StatefulWidget {
  const _CustomFeedSheet();

  @override
  State<_CustomFeedSheet> createState() => _CustomFeedSheetState();
}

class _CustomFeedSheetState extends State<_CustomFeedSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _category = '生活';

  @override
  void dispose() {
    _name.dispose();
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

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final ready = _name.text.trim().isNotEmpty && _url.text.trim().isNotEmpty;
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
            Text('添加 RSS 源', style: type.sectionTitle),
            const SizedBox(height: V4Space.xl),
            TextField(
              key: const ValueKey('v4-feed-name'),
              controller: _name,
              maxLines: 1,
              onChanged: (_) => setState(() {}),
              style: type.body,
              decoration: _field(context, '订阅源名称'),
            ),
            const SizedBox(height: V4Space.md),
            TextField(
              key: const ValueKey('v4-feed-url'),
              controller: _url,
              maxLines: 2,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              style: type.body,
              decoration: _field(context, 'https://example.com/feed.xml'),
            ),
            const SizedBox(height: V4Space.md),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: _field(context, '分类'),
              items: [
                for (final label in FeedOverviewService.categories.keys)
                  DropdownMenuItem<String>(value: label, child: Text(label)),
              ],
              onChanged: (v) => setState(() {
                if (v != null) _category = v;
              }),
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
                    onPressed: ready
                        ? () => Navigator.of(context).pop(
                              CustomFeedRequest(
                                name: _name.text.trim(),
                                url: _url.text.trim(),
                                category: _category,
                              ),
                            )
                        : null,
                    child: const Text('添加'),
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
