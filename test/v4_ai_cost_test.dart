import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('免费模型给出 Token 与零金额区间', () {
    final estimate = AiCostEstimator.estimateQuiz(
      articleText: List.filled(4000, 'a').join(),
      count: 5,
      model: 'glm-4.7-flash',
    );
    expect(estimate.inputTokens, greaterThan(0));
    expect(estimate.outputMax, greaterThan(estimate.outputMin));
    expect(estimate.hasPrice, isTrue);
    expect(estimate.amountMin, 0);
    expect(estimate.amountMax, 0);
  });

  test('未知模型不猜测金额', () {
    final estimate = AiCostEstimator.estimateQuiz(
      articleText: 'short article',
      count: 3,
      model: 'some-custom-model',
    );
    expect(estimate.hasPrice, isFalse);
    expect(estimate.amountMin, isNull);
  });

  test('用量账本按时间倒序保存并可恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final ledger = AiUsageLedger();
    await ledger.add(
      AiUsageRecord(
        operation: '生成 5 道练习',
        model: 'glm-4.7-flash',
        inputTokens: 600,
        outputTokens: 900,
        amount: 0,
        at: 1000,
      ),
    );
    await ledger.add(
      AiUsageRecord(
        operation: '判分',
        model: 'glm-4.7-flash',
        inputTokens: 300,
        outputTokens: 100,
        amount: 0,
        at: 2000,
      ),
    );
    final rows = await ledger.list();
    expect(rows.length, 2);
    expect(rows.first.operation, '判分');
  });
}
