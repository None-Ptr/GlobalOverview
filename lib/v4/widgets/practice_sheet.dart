// Hallmark · screen: practice sheet · genre: editorial · theme: custom (observation station) · scope: component
// critique: P4 H5 E5 S4 R4 V4 · weakest S — six controls in one sheet; the count and level now share a line
import 'package:flutter/foundation.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// What the generation sheet hands to the practice service.
class PracticeOptions {
  final List<String> types;
  final int count;
  final String? examLevel;
  final String gradeMode;
  final String instruction;

  /// What this set is for, shown beside it in the article's set record.
  final String label;

  const PracticeOptions({
    required this.types,
    required this.count,
    required this.examLevel,
    required this.gradeMode,
    required this.instruction,
    required this.label,
  });
}

/// [defaultLevel] pre-selects the exam level, so a text's own difficulty
/// answers the question the sheet would otherwise ask.
Future<PracticeOptions?> showPracticeSheet(
  BuildContext context, {
  String? defaultLevel,
}) {
  final selTypes = <String>{'choice'};
  var selCount = 5;
  String? selLevel = QuizService.examLevels.containsKey(defaultLevel)
      ? defaultLevel
      : null;
  var selGrade = 'ai';
  final instruction = TextEditingController();
  final label = TextEditingController();

  Future<PracticeOptions?> open() => showModalBottomSheet<PracticeOptions>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.v4.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(V4Radius.sheet)),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheet) {
            final v4 = sheetContext.v4;
            final type = sheetContext.v4Type;
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: V4Space.xl,
                  right: V4Space.xl,
                  top: V4Space.md,
                  bottom: V4Space.xl + MediaQuery.viewInsetsOf(sheetContext).bottom,
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
                    Text('出题设置', style: type.sectionTitle),
                    const SizedBox(height: V4Space.xl),
                    Text('题型', style: type.label),
                    const SizedBox(height: V4Space.sm),
                    Wrap(
                      spacing: V4Space.sm,
                      runSpacing: V4Space.sm,
                      children: [
                        for (final entry in QuizService.examMap.entries)
                          ChoiceChip(
                            key: ValueKey('practice-type-${entry.key}'),
                            label: Text('${entry.value['label']}'),
                            selected: selTypes.contains(entry.key),
                            onSelected: (on) {
                              setSheet(() {
                                if (on) {
                                  selTypes.add(entry.key);
                                } else {
                                  selTypes.remove(entry.key);
                                }
                              });
                            },
                            selectedColor: v4.surfaceSubtle,
                            showCheckmark: false,
                            side: BorderSide(
                              color: selTypes.contains(entry.key)
                                  ? v4.brand
                                  : v4.rule,
                            ),
                            backgroundColor: v4.surface,
                            labelStyle: type.caption.copyWith(
                              color: selTypes.contains(entry.key)
                                  ? v4.brand
                                  : v4.inkSecondary,
                              fontWeight: selTypes.contains(entry.key)
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(V4Radius.control),
                            ),
                          ),
                      ],
                    ),
                    if (selTypes.isEmpty) ...[
                      const SizedBox(height: V4Space.sm),
                      Text(
                        '至少选一种题型',
                        style: type.caption.copyWith(color: v4.error),
                      ),
                    ],
                    const SizedBox(height: V4Space.xl),
                    // Count and level are one decision, so they share a line.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selTypes.length > 1 ? '题目总数' : '题目数量',
                                style: type.label,
                              ),
                              const SizedBox(height: V4Space.sm),
                              TStepper(
                                value: selCount.toDouble(),
                                min: 1,
                                max: 20,
                                step: 1,
                                size: TStepperSize.small,
                                onChanged: (v) =>
                                    setSheet(() => selCount = v.toInt()),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: V4Space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('难度档位', style: type.label),
                              const SizedBox(height: V4Space.sm),
                              DropdownButtonFormField<String?>(
                                initialValue: selLevel,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: v4.surfaceSubtle,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: V4Space.sm,
                                    vertical: V4Space.sm,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      V4Radius.control,
                                    ),
                                    borderSide: BorderSide(color: v4.rule),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      V4Radius.control,
                                    ),
                                    borderSide: BorderSide(color: v4.rule),
                                  ),
                                ),
                                style: type.body,
                                dropdownColor: v4.surface,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('不限'),
                                  ),
                                  for (final entry
                                      in QuizService.examLevels.entries)
                                    DropdownMenuItem<String?>(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setSheet(() => selLevel = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: V4Space.xl),
                    Text('用途标签', style: type.label),
                    const SizedBox(height: V4Space.sm),
                    TextField(
                      controller: label,
                      maxLines: 1,
                      style: type.body,
                      decoration: InputDecoration(
                        hintText: '比如：考前重做、细节题；留空自动填档位',
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
                    Text('判分方式', style: type.label),
                    const SizedBox(height: V4Space.sm),
                    TRadioGroup<String>.options(
                      value: selGrade,
                      direction: Axis.horizontal,
                      variant: TRadioVariant.inline,
                      options: const [
                        TRadioOption(value: 'ai', label: 'AI 判分'),
                        TRadioOption(value: 'exact', label: '精确'),
                        TRadioOption(value: 'contains', label: '包含'),
                        TRadioOption(value: 'manual', label: '人工'),
                      ],
                      onChanged: (v) => setSheet(() => selGrade = v),
                    ),
                    const SizedBox(height: V4Space.xl),
                    Text('补充要求', style: type.label),
                    const SizedBox(height: V4Space.sm),
                    TextField(
                      controller: instruction,
                      maxLines: 3,
                      style: type.body,
                      decoration: InputDecoration(
                        hintText: '比如：多考细节定位，解析用中文',
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
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: V4Space.md),
                        Expanded(
                          child: V4PrimaryButton(
                            onPressed: selTypes.isEmpty
                                ? null
                                : () => Navigator.of(sheetContext).pop(
                                      PracticeOptions(
                                        types: selTypes.toList(),
                                        count: selCount,
                                        examLevel: selLevel,
                                        gradeMode: selGrade,
                                        instruction: instruction.text.trim(),
                                        label: label.text.trim(),
                                      ),
                                    ),
                            child: const Text('开始生成'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  return open().whenComplete(() {
    instruction.dispose();
    label.dispose();
  });
}

/// One frame of generation. [step] runs 0 to 3: steps below it are done, the
/// step at it is in flight, the rest are pending.
class PracticeProgress {
  final int step;
  final String detail;

  const PracticeProgress(this.step, this.detail);
}

/// The step panel, embedded by the reader over the article while it works.
class PracticeProgressPanel extends StatelessWidget {
  final ValueListenable<PracticeProgress> stage;

  /// Aborts waiting for the model. The in-flight request cannot be recalled,
  /// but its result is dropped.
  final VoidCallback? onCancel;

  const PracticeProgressPanel({super.key, required this.stage, this.onCancel});

  static const _steps = ['读取正文', '准备题目', 'AI 正在出题', '保存题集'];

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(V4Space.xl),
        decoration: BoxDecoration(
          color: v4.surface,
          borderRadius: BorderRadius.circular(V4Radius.card),
          border: Border.all(color: v4.rule),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('生成精读练习', style: type.sectionTitle),
            const SizedBox(height: V4Space.lg),
            ValueListenableBuilder<PracticeProgress>(
              valueListenable: stage,
              builder: (context, value, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: V4Space.md),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: i < value.step
                                  ? Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: v4.success,
                                    )
                                  : i == value.step
                                      ? const CircularProgressIndicator(
                                          strokeWidth: 2,
                                        )
                                      : Icon(
                                          Icons.circle_outlined,
                                          size: 18,
                                          color: v4.rule,
                                        ),
                            ),
                            const SizedBox(width: V4Space.md),
                            Text(
                              _steps[i],
                              style: type.label.copyWith(
                                color: i <= value.step ? v4.ink : v4.inkMuted,
                                fontWeight: i == value.step
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: V4Space.sm),
                    Text(value.detail, style: type.caption),
                    if (onCancel != null) ...[
                      const SizedBox(height: V4Space.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: v4.inkSecondary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: V4Space.sm,
                            ),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text('取消生成', style: type.label),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
