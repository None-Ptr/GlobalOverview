import 'package:global_overview/v4/services/guide_content.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/telescope_icon.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4OnboardingScreen extends StatefulWidget {
  final OnboardingService service;
  final ValueChanged<V4Profile> onComplete;

  const V4OnboardingScreen({
    super.key,
    required this.service,
    required this.onComplete,
  });

  @override
  State<V4OnboardingScreen> createState() => _V4OnboardingScreenState();
}

class _V4OnboardingScreenState extends State<V4OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  V4Level _level = V4Level.highSchool;
  V4Goal _goal = V4Goal.school;
  final Set<String> _interests = {'科技', '科学', '文化', '生活', '教育'};
  int _minutes = 20;

  static const _topics = [
    '新闻',
    '科学',
    '健康',
    '科技',
    '商业',
    '环境',
    '食物',
    '艺术',
    '设计',
    '书籍',
    '文化',
    '英语学习',
    '体育',
    '旅行',
    '教育',
    '政策',
    '生活',
  ];

  static const _levelLabels = {
    V4Level.foundation: ('基础', '借助查词可以读懂一般短文'),
    V4Level.highSchool: ('高中', '能读常见话题的中等长度文章'),
    V4Level.university: ('大学', '准备四六级，想提升长文阅读'),
    V4Level.advanced: ('进阶', '准备考研或雅思托福，关注推理与结构'),
  };

  static const _goalLabels = {
    V4Goal.school: ('课内提升', '跟随课程难度积累阅读量'),
    V4Goal.cet: ('四六级', '熟悉考试阅读与常见题型'),
    V4Goal.postgraduate: ('考研', '训练长难句、推理和篇章结构'),
    V4Goal.ieltsToefl: ('雅思托福', '适应学术文章和快速定位'),
    V4Goal.interest: ('兴趣阅读', '不设考试压力，持续读下去'),
  };

  V4Profile get _profile => V4Profile(
    level: _level,
    goal: _goal,
    interests: _topics.where(_interests.contains).toList(),
    minutes: _minutes,
    completed: true,
  );

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.service.save(_profile);
    if (!mounted) return;
    widget.onComplete(_profile);
  }

  void _next() {
    if (_step < 4) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _toggleInterest(String topic) {
    setState(() {
      if (_interests.contains(topic)) {
        _interests.remove(topic);
      } else if (_interests.length < 5) {
        _interests.add(topic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.sm,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    '第 ' + (_step + 1).toString() + ' 步，共 5 步',
                    style: type.caption,
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('v4-skip'),
                    onPressed: _saving ? null : _finish,
                    child: const Text('跳过'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V4Space.lg),
              child: TProgress.linear(value: (_step + 1) / 5),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  V4Space.lg,
                  V4Space.xxxl,
                  V4Space.lg,
                  V4Space.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_step == 0) ...[
                      V4TelescopeIcon(size: 32, color: v4.brand),
                      const SizedBox(height: V4Space.lg),
                      Text('你现在的英语阅读\n处在哪一步？', style: type.pageTitle),
                      const SizedBox(height: V4Space.sm),
                      Text('选一个起点，之后的推荐和练习会跟着调整。', style: type.label),
                      const SizedBox(height: V4Space.xxl),
                      for (final level in V4Level.values) ...[
                        _choice(
                          key: ValueKey('v4-level-' + level.name),
                          title: _levelLabels[level]!.$1,
                          note: _levelLabels[level]!.$2,
                          selected: _level == level,
                          onTap: () => setState(() => _level = level),
                        ),
                        const SizedBox(height: V4Space.md),
                      ],
                    ],
                    if (_step == 1) ...[
                      Text('你希望阅读\n帮你完成什么？', style: type.pageTitle),
                      const SizedBox(height: V4Space.sm),
                      Text('只影响推荐和默认题型，之后随时可以改。', style: type.label),
                      const SizedBox(height: V4Space.xxl),
                      for (final goal in V4Goal.values) ...[
                        _choice(
                          key: ValueKey('v4-goal-' + goal.name),
                          title: _goalLabels[goal]!.$1,
                          note: _goalLabels[goal]!.$2,
                          selected: _goal == goal,
                          onTap: () => setState(() => _goal = goal),
                        ),
                        const SizedBox(height: V4Space.md),
                      ],
                    ],
                    if (_step == 2) ...[
                      Text('最近想读\n哪些主题？', style: type.pageTitle),
                      const SizedBox(height: V4Space.sm),
                      Text(
                        '最多选 5 个，已选 ' + _interests.length.toString() + ' 个。',
                        style: type.label,
                      ),
                      const SizedBox(height: V4Space.xxl),
                      Wrap(
                        spacing: V4Space.sm,
                        runSpacing: V4Space.sm,
                        children: [
                          for (final topic in _topics)
                            FilterChip(
                              key: ValueKey('v4-topic-' + topic),
                              label: Text(topic),
                              selected: _interests.contains(topic),
                              onSelected: (_) => _toggleInterest(topic),
                              selectedColor: v4.surfaceSubtle,
                              checkmarkColor: v4.brand,
                              side: BorderSide(
                                color: _interests.contains(topic)
                                    ? v4.brand
                                    : v4.rule,
                              ),
                              labelStyle: type.label,
                              backgroundColor: v4.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  V4Radius.control,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (_step == 3) ...[
                      Text('每天愿意留多少时间\n给英语阅读？', style: type.pageTitle),
                      const SizedBox(height: V4Space.sm),
                      Text('用来安排今日阅读量，不固定篇数。', style: type.label),
                      const SizedBox(height: V4Space.xxl),
                      for (final minutes in const [10, 20, 30]) ...[
                        _choice(
                          key: ValueKey('v4-minutes-' + minutes.toString()),
                          title: minutes.toString() + ' 分钟',
                          note: minutes == 10
                              ? '短读一篇，先保持节奏'
                              : (minutes == 20 ? '读完一篇，再复习几个词' : '精读一篇，留出练习时间'),
                          selected: _minutes == minutes,
                          onTap: () => setState(() => _minutes = minutes),
                        ),
                        const SizedBox(height: V4Space.md),
                      ],
                      const SizedBox(height: V4Space.lg),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(V4Space.lg),
                        decoration: BoxDecoration(
                          color: v4.surfaceSubtle,
                          borderRadius: BorderRadius.circular(V4Radius.card),
                        ),
                        child: Text(
                          _levelLabels[_level]!.$1 +
                              '  ' +
                              _goalLabels[_goal]!.$1 +
                              '  每日 ' +
                              _minutes.toString() +
                              ' 分钟',
                          style: type.body,
                        ),
                      ),
                    ],
                    if (_step == 4) ...[
                      Text('这里能做什么', style: type.pageTitle),
                      const SizedBox(height: V4Space.sm),
                      Text(
                        '四件事，随时可以在「我的 → 使用指南」里回看。',
                        style: type.label,
                      ),
                      const SizedBox(height: V4Space.xxl),
                      for (var i = 0; i < featureNotes.length; i++)
                        _guideItem(
                          (i + 1).toString().padLeft(2, '0'),
                          featureNotes[i].title,
                          featureNotes[i].note,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.lg,
                V4Space.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: V4PrimaryButton(
                  key: const ValueKey('v4-next'),
                  onPressed: _saving ? null : _next,
                  child: Text(
                    _step == 4 ? (_saving ? '正在准备' : '生成今日阅读') : '继续',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice({
    required Key key,
    required String title,
    required String note,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(V4Radius.card),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(V4Space.lg),
          decoration: BoxDecoration(
            color: selected ? context.v4.surfaceSubtle : context.v4.surface,
            borderRadius: BorderRadius.circular(V4Radius.card),
            border: Border.all(
              color: selected ? context.v4.brand : context.v4.rule,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.v4Type.itemTitle.copyWith(
                  color: selected ? context.v4.brand : context.v4.ink,
                ),
              ),
              const SizedBox(height: V4Space.xs),
              Text(note, style: context.v4Type.caption),
            ],
          ),
        ),
      ),
    );
  }

  /// A one-line capability note for the closing step. Numbered, because this
  /// is a list of things to find, not a sales sheet.
  Widget _guideItem(String ordinal, String title, String note) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.only(bottom: V4Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              ordinal,
              style: type.caption.copyWith(color: v4.brand),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: type.itemTitle),
                const SizedBox(height: V4Space.xs),
                Text(note, style: type.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
