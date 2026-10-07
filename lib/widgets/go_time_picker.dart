import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 打开美化后的时间选择弹层，返回 null 表示取消。
Future<TimeOfDay?> showGoTimePicker({required BuildContext context, required TimeOfDay initialTime}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Go.scrim,
    builder: (_) => GoTimePickerSheet(initialTime: initialTime),
  );
}

/// 深色玻璃风格时间选择器：大号预览 + 双滚轮 + 常用时段快捷选择。
class GoTimePickerSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  const GoTimePickerSheet({super.key, required this.initialTime});
  @override
  State<GoTimePickerSheet> createState() => _GoTimePickerSheetState();
}

class _GoTimePickerSheetState extends State<GoTimePickerSheet> {
  static const _itemExtent = 46.0;

  static const _presets = <({String label, int hour, int minute})>[
    (label: '早起', hour: 7, minute: 0),
    (label: '午间', hour: 12, minute: 30),
    (label: '晚间', hour: 20, minute: 0),
    (label: '睡前', hour: 22, minute: 30),
  ];

  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;
  late final FixedExtentScrollController _hourCtrl = FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteCtrl = FixedExtentScrollController(initialItem: _minute);

  String _two(int v) => v.toString().padLeft(2, '0');
  String get _time => '${_two(_hour)}:${_two(_minute)}';

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _onWheelChanged() {
    HapticFeedback.selectionClick();
  }

  void _selectPreset(int hour, int minute) {
    HapticFeedback.selectionClick();
    _hourCtrl.animateToItem(hour, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    _minuteCtrl.animateToItem(minute, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    setState(() {
      _hour = hour;
      _minute = minute;
    });
  }

  bool _isPreset(int hour, int minute) => _hour == hour && _minute == minute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + Go.sp8),
      child: Container(
        decoration: BoxDecoration(
          color: Go.glassBgStrong,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Go.rXl)),
          border: Border.all(color: Go.glassBorder, width: 0.5),
          boxShadow: Go.shadow3,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Go.rXl)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp3, Go.sp5, Go.sp5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: Go.r(72), height: Go.r(8), decoration: BoxDecoration(color: Go.outlineStrong, borderRadius: BorderRadius.circular(Go.rFull))),
                  const SizedBox(height: Go.sp3),
                  Row(
                    children: [
                      const Text('提醒时间', style: TextStyle(fontSize: Go.fsTitle, fontWeight: FontWeight.w600, color: Go.onSurface)),
                      const Spacer(),
                      GoIconBtn(icon: 'close', size: Go.r(60), onTap: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: Go.sp2),

                  // —— 预览 ——
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: _two(_hour), style: _numStyle(Go.primary)),
                      TextSpan(text: ' : ', style: _numStyle(Go.onSurface3)),
                      TextSpan(text: _two(_minute), style: _numStyle(Go.secondary)),
                    ]),
                  ),
                  const SizedBox(height: Go.sp1),
                  Text('每天 $_time 提醒你开始学习', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),

                  const SizedBox(height: Go.sp5),

                  // —— 滚轮 ——
                  Container(
                    height: _itemExtent * 5,
                    decoration: BoxDecoration(
                      color: Go.surface1,
                      borderRadius: BorderRadius.circular(Go.rLg),
                      border: Border.all(color: Go.outline, width: 0.5),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: _itemExtent,
                          margin: const EdgeInsets.symmetric(horizontal: Go.sp5),
                          decoration: BoxDecoration(
                            color: Go.primary95,
                            borderRadius: BorderRadius.circular(Go.rMd),
                            border: Border.all(color: Go.primary.withValues(alpha: 0.35), width: 0.5),
                          ),
                        ),
                        _fade(
                          Row(
                            children: [
                              Expanded(child: _wheel(controller: _hourCtrl, count: 24, onChanged: (v) => setState(() => _hour = v))),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: Go.sp1),
                                child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Go.onSurface3)),
                              ),
                              Expanded(child: _wheel(controller: _minuteCtrl, count: 60, onChanged: (v) => setState(() => _minute = v))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Go.sp4),

                  // —— 常用时段 ——
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final p in _presets) ...[
                        if (p != _presets.first) const SizedBox(width: Go.sp3),
                        _presetChip(p.label, '${_two(p.hour)}:${_two(p.minute)}', _isPreset(p.hour, p.minute), () => _selectPreset(p.hour, p.minute)),
                      ],
                    ],
                  ),

                  const SizedBox(height: Go.sp5),
                  Row(
                    children: [
                      Expanded(child: GoBtn(label: '取消', kind: GoBtnKind.tonal, block: true, onTap: () => Navigator.pop(context))),
                      const SizedBox(width: Go.sp4),
                      Expanded(
                        child: GoBtn(
                          label: '确定',
                          block: true,
                          onTap: () => Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _numStyle(Color color) => TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.1,
        color: color,
        letterSpacing: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// 顶部/底部渐隐，让滚轮两侧淡出而非被硬裁。
  Widget _fade(Widget child) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.3, 0.7, 1],
        ).createShader(rect),
        child: child,
      );

  Widget _wheel({required FixedExtentScrollController controller, required int count, required ValueChanged<int> onChanged}) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      perspective: 0.0025,
      diameterRatio: 1.9,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.3,
      onSelectedItemChanged: (i) {
        onChanged(i);
        _onWheelChanged();
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, i) => Center(
          child: Text(_two(i), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Go.onSurface, fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ),
    );
  }

  Widget _presetChip(String label, String time, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
          decoration: BoxDecoration(
            color: active ? Go.primary.withValues(alpha: 0.18) : Go.surface2,
            borderRadius: BorderRadius.circular(Go.rFull),
            border: Border.all(color: active ? Go.primary.withValues(alpha: 0.55) : Go.outline, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: active ? Go.primary : Go.onSurface2)),
              const SizedBox(width: Go.sp2),
              Text(time, style: TextStyle(fontSize: Go.fsCap, color: active ? Go.primary : Go.onSurface3)),
            ],
          ),
        ),
      );
}
