import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/services/theme_mode_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4AppearanceScreen extends ConsumerStatefulWidget {
  const V4AppearanceScreen({super.key});

  @override
  ConsumerState<V4AppearanceScreen> createState() => _V4AppearanceScreenState();
}

class _V4AppearanceScreenState extends ConsumerState<V4AppearanceScreen> {
  late double _fontSize;
  late double _lineHeight;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    _fontSize = config.fontSize.clamp(16.0, 24.0);
    _lineHeight = const [1.5, 1.8, 2.1].contains(config.lineHeight)
        ? config.lineHeight
        : 1.8;
  }

  Future<void> _setFont(double value) async {
    setState(() => _fontSize = value);
    await ref.read(appConfigProvider).setReader(fontSize: value);
  }

  Future<void> _setLineHeight(double value) async {
    setState(() => _lineHeight = value);
    await ref.read(appConfigProvider).setReader(lineHeight: value);
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final mode = ref.watch(v4ThemeModeProvider);
    return Scaffold(
      backgroundColor: v4.page,
      appBar: AppBar(
        backgroundColor: v4.page,
        elevation: 0,
        title: const Text('外观与阅读'),
      ),
      body: V4Column(
        child: ListView(
        padding: const EdgeInsets.all(V4Space.lg),
        children: [
          Text('主题', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          Container(
            decoration: BoxDecoration(
              color: v4.surface,
              borderRadius: BorderRadius.circular(V4Radius.card),
              border: Border.all(color: v4.rule),
            ),
            child: Column(
              children: [
                for (final option in V4ThemeMode.values) ...[
                  Semantics(
                    selected: option == mode,
                    button: true,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('v4-theme-' + option.name),
                        onTap: () => ref
                            .read(v4ThemeModeProvider.notifier)
                            .setMode(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: V4Space.lg,
                            vertical: V4Space.md,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                option == mode
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 20,
                                color: option == mode ? v4.brand : v4.inkMuted,
                              ),
                              const SizedBox(width: V4Space.md),
                              Text(option.label, style: type.body),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (option != V4ThemeMode.values.last)
                    Divider(height: 1, color: v4.rule),
                ],
              ],
            ),
          ),
          const SizedBox(height: V4Space.xxl),
          Text('阅读默认字号', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          Row(
            children: [
              Text('A', style: type.caption),
              Expanded(
                child: Slider(
                  key: const ValueKey('v4-font-size'),
                  value: _fontSize,
                  min: 16,
                  max: 24,
                  divisions: 4,
                  activeColor: v4.brand,
                  label: _fontSize.round().toString(),
                  onChanged: _setFont,
                ),
              ),
              Text(
                _fontSize.round().toString(),
                style: type.label.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text('行距', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          Row(
            children: [
              for (final option in const [1.5, 1.8, 2.1]) ...[
                Expanded(
                  child: InkWell(
                    key: ValueKey('v4-line-height-' + option.toString()),
                    onTap: () => _setLineHeight(option),
                    borderRadius: BorderRadius.circular(V4Radius.control),
                    child: Container(
                      margin: const EdgeInsets.only(right: V4Space.sm),
                      padding: const EdgeInsets.symmetric(vertical: V4Space.md),
                      decoration: BoxDecoration(
                        color: option == _lineHeight
                            ? v4.surfaceSubtle
                            : v4.surface,
                        borderRadius: BorderRadius.circular(V4Radius.control),
                        border: Border.all(
                          color: option == _lineHeight ? v4.brand : v4.rule,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          option.toString(),
                          style: type.body.copyWith(
                            color: option == _lineHeight
                                ? v4.brand
                                : v4.inkSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: V4Space.xxl),
          Text('预览', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          Row(
            children: [
              Expanded(
                child: _preview(
                  key: const ValueKey('v4-preview-light'),
                  palette: V4Palette.light,
                  label: '浅色',
                ),
              ),
              const SizedBox(width: V4Space.md),
              Expanded(
                child: _preview(
                  key: const ValueKey('v4-preview-dark'),
                  palette: V4Palette.dark,
                  label: '深色',
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(V4Space.lg),
            decoration: BoxDecoration(
              color: v4.surface,
              borderRadius: BorderRadius.circular(V4Radius.card),
              border: Border.all(color: v4.rule),
            ),
            child: Text(
              'The night sky is a map of everything we can still learn.',
              style: type.articleBody.copyWith(
                fontSize: _fontSize,
                height: _lineHeight,
              ),
            ),
          ),
          const SizedBox(height: V4Space.xxl),
          Text('深色模式只改变界面与正文配色，不改变阅读进度和学习记录。', style: type.caption),
        ],
      ),
      ),
    );
  }

  Widget _preview({
    required Key key,
    required V4Palette palette,
    required String label,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(V4Space.md),
      decoration: BoxDecoration(
        color: palette.page,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: palette.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: palette.inkMuted,
            ),
          ),
          const SizedBox(height: V4Space.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(V4Space.sm),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(V4Radius.control),
              border: Border.all(color: palette.rule),
            ),
            child: Text(
              'Aa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(height: V4Space.sm),
          Container(
            width: 28,
            height: 6,
            decoration: BoxDecoration(
              color: palette.brand,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}
