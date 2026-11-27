import 'package:flutter/material.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/widgets/cost_sheet.dart';

/// 全局 AI 成本门禁。没有可用 Navigator 时直接放行，方便单元测试与后台任务。
class AiCostGate {
  AiCostGate._();
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// [spentToday] and [budget] are in the ledger's currency. A non-zero
  /// [budget] turns the sheet into a warning once today's spend reaches it.
  static Future<bool> confirm(
    AiCostEstimate estimate, {
    double spentToday = 0,
    double budget = 0,
  }) async {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return true;
      final over = budget > 0 && spentToday >= budget;
      return await showAiCostSheet(
        context,
        estimate,
        budgetNote: over
            ? '今日已用 ¥${spentToday.toStringAsFixed(2)}，达到或超过上限 ¥${budget.toStringAsFixed(2)}。继续会产生额外费用。'
            : null,
      );
    } catch (_) {
      // 非 Widget 测试或后台任务没有 Flutter Binding，此时不阻断模型调用。
      return true;
    }
  }
}
