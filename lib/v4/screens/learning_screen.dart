import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/plan_screen.dart';
import 'package:global_overview/v4/screens/vocab_screen.dart';
import 'package:global_overview/v4/screens/wrong_screen.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4LearningScreen extends ConsumerStatefulWidget {
  const V4LearningScreen({super.key});

  @override
  ConsumerState<V4LearningScreen> createState() => _V4LearningScreenState();
}

class _V4LearningScreenState extends ConsumerState<V4LearningScreen> {
  int _due = 0;
  int _plans = 0;
  int _wrong = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final db = ref.read(dbProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final results = await Future.wait([
        db.select('SELECT COUNT(*) AS c FROM vocab_head WHERE fsrs_due <= ?', [
          now,
        ]),
        db.select('SELECT COUNT(*) AS c FROM plan_items'),
        db.select(
          'SELECT COUNT(DISTINCT questionId) AS c FROM answers WHERE wrong = 1',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _due = (results[0].first['c'] as int?) ?? 0;
        _plans = (results[1].first['c'] as int?) ?? 0;
        _wrong = (results[2].first['c'] as int?) ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget child) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => child));
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return SafeArea(
      bottom: false,
      child: V4Column(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.md,
          V4Space.lg,
          V4Space.xxxl,
        ),
        children: [
          Text('学习', style: type.pageTitle),
          const SizedBox(height: V4Space.sm),
          Text('今天到期 ' + _due.toString() + ' 个生词', style: type.label),
          const SizedBox(height: V4Space.xxl),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(V4Space.xl),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            _studyRow(
              title: '待复习',
              detail: _due == 0 ? '今天没有到期生词' : _due.toString() + ' 个生词已到复习时间',
              action: '去复习',
              onTap: () => _open(const V4VocabScreen(initialFilter: 'due')),
              primary: true,
            ),
            Divider(height: 1, color: v4.rule),
            _studyRow(
              title: '精读单',
              detail: _plans == 0
                  ? '还没有加入精读单的文章'
                  : _plans.toString() + ' 篇文章等待深入阅读',
              action: '查看',
              onTap: () => _open(const V4PlanScreen()),
            ),
            Divider(height: 1, color: v4.rule),
            _studyRow(
              title: '错题本',
              detail: _wrong == 0
                  ? '现在没有待重做的错题'
                  : _wrong.toString() + ' 道错题可以重做',
              action: '查看',
              onTap: () => _open(const V4WrongScreen()),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _studyRow({
    required String title,
    required String detail,
    required String action,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V4Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.v4Type.itemTitle),
                const SizedBox(height: V4Space.xs),
                Text(detail, style: context.v4Type.caption),
              ],
            ),
          ),
          const SizedBox(width: V4Space.md),
          if (primary)
            V4PrimaryButton(
              onPressed: onTap,
              child: Text(action),
            )
          else
            TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}
