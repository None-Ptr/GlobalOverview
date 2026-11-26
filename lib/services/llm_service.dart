import 'dart:convert';

import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/prompts.dart';
import 'package:global_overview/v4/services/ai_cost_gate.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
class LlmService {
  final HttpService _http;
  final AppConfigService _cfg;
  LlmService(this._http, this._cfg);

  /// 最近一次请求返回的 usage；接口未提供时为 null。
  Map<String, dynamic>? lastUsage;

  /// 当前生效的模型配置，供成本预估复用同一来源。
  LlmProfile get profile => _cfg.currentProfile;

  /// 送进 prompt 的正文上限（字符）。约等于 3k token 的英文，超出部分多数模型会直接报错或静默截断。
  static const int maxPromptChars = 12000;

  /// 出题/精选这类长生成，20 秒的抓取超时远远不够；模型常要 30–60 秒才吐出完整 JSON。
  static const Duration requestTimeout = Duration(seconds: 90);

  /// 截断过长正文。优先在段落边界断开，避免只切半句话导致题目失真。
  static String clipArticle(String text, {int limit = maxPromptChars}) {
    if (text.length <= limit) return text;
    final cut = text.substring(0, limit);
    final br = cut.lastIndexOf('\n');
    return (br > limit ~/ 2 ? cut.substring(0, br) : cut).trim();
  }

  /// One confirmation point for a batch: the budget check and the sheet.
  Future<void> confirmCost(AiCostEstimate estimate) async {
    final budget = _cfg.aiDailyBudget;
    final spent = budget > 0 ? await AiUsageLedger().spentToday() : 0.0;
    if (!await AiCostGate.confirm(
      estimate,
      spentToday: spent,
      budget: budget,
    )) {
      throw AppException('aiCancelled', '已取消本次 AI 操作');
    }
  }

  Future<String> chat(
    String system,
    String user, {
    double temperature = 0.7,
    String operation = 'AI 操作',
    bool gate = true,
  }) async {
    final p = _cfg.currentProfile;
    // The web bundle has no bundled key; fail with the place to configure one
    // instead of sending an empty Authorization header and showing a 401.
    if (p.apiKey.trim().isEmpty) {
      throw const AppException(
        'missingApiKey',
        '请先在「我的 → AI 模型」填入你自己的 API Key',
      );
    }
    final estimate = AiCostEstimator.estimateRequest(
      system + '\n' + user,
      p.model,
    );
    if (gate) await confirmCost(estimate);
    final url = '${p.baseUrl}/chat/completions';
    final body = {
      'model': p.model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
    };
    lastUsage = null;
    final watch = Stopwatch()..start();
    final Map<String, dynamic> res;
    try {
      res = await _http.postJson(
        url,
        body,
        headers: {'Authorization': 'Bearer ${p.apiKey}'},
        retry: RetryPolicy.llm,
        timeout: requestTimeout,
      );
    } on AppException catch (e) {
      watch.stop();
      await _recordFailure(operation, p, estimate, watch.elapsedMilliseconds);
      throw _readable(e, p);
    }
    watch.stop();
    final choices = res['choices'];
    if (choices is! List || choices.isEmpty) {
      final err = res['error'];
      final msg = err is Map
          ? (err['message'] ?? '$err')
          : (res['message'] ?? '$res');
      throw AppException('llmEmpty', '模型没有返回内容', detail: '$msg');
    }
    final usage = res['usage'];
    lastUsage = usage is Map ? Map<String, dynamic>.from(usage) : null;
    final first = choices.first;
    if (first is! Map || first['message'] is! Map) {
      throw AppException('llmFormat', '模型返回格式异常', detail: '$first');
    }
    final content = ((first['message'] as Map)['content'] ?? '')
        .toString()
        .trim();
    if (content.isEmpty) {
      throw AppException(
        'llmEmpty',
        '模型返回了空内容',
        detail: 'choices[0].message.content 为空',
      );
    }
    await _recordUsage(
      operation,
      p,
      estimate,
      content,
      watch.elapsedMilliseconds,
    );
    return content;
  }

  /// A failed call costs nothing, but it is still a row the reader can audit.
  Future<void> _recordFailure(
    String operation,
    LlmProfile p,
    AiCostEstimate estimate,
    int durationMs,
  ) async {
    try {
      await AiUsageLedger().add(
        AiUsageRecord(
          operation: operation,
          model: p.model,
          inputTokens: estimate.inputTokens,
          outputTokens: 0,
          amount: null,
          currency: estimate.currency,
          at: DateTime.now().millisecondsSinceEpoch,
          durationMs: durationMs,
          status: 'failed',
          estimatedMin: estimate.amountMin,
          estimatedMax: estimate.amountMax,
        ),
      );
    } catch (_) {}
  }

  /// One row in the local usage ledger. Never throws: a missing record must
  /// not turn a successful answer into a failure.
  Future<void> _recordUsage(
    String operation,
    LlmProfile p,
    AiCostEstimate estimate,
    String content,
    int durationMs,
  ) async {
    try {
      final usage = lastUsage;
      final inputTokens =
          (usage?['prompt_tokens'] as num?)?.toInt() ?? estimate.inputTokens;
      final outputTokens =
          (usage?['completion_tokens'] as num?)?.toInt() ??
          (content.length / 4).ceil();
      final price = AiCostEstimator.priceFor(p.model);
      final amount = price == null
          ? null
          : inputTokens / 1000000 * price.inputPerMillion +
                outputTokens / 1000000 * price.outputPerMillion;
      await AiUsageLedger().add(
        AiUsageRecord(
          operation: operation,
          model: p.model,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          amount: amount,
          currency: price?.currency ?? 'CNY',
          at: DateTime.now().millisecondsSinceEpoch,
          durationMs: durationMs,
          status: 'ok',
          estimatedMin: estimate.amountMin,
          estimatedMax: estimate.amountMax,
        ),
      );
    } catch (_) {}
  }

  AppException _readable(AppException e, LlmProfile p) {
    switch (e.code) {
      case 'http401':
        return AppException(
          'llmKey',
          'api key 无效或已失效（401），请在「我的 → LLM 模型」里检查',
          detail: e.detail,
          status: e.status,
        );
      case 'http403':
        return AppException(
          'llmKey',
          '接口拒绝访问（403），请在「我的 → LLM 模型」里检查 key 与 base url',
          detail: e.detail,
          status: e.status,
        );
      case 'http404':
        return AppException(
          'llmUrl',
          '接口地址不存在（404），请检查 base url 是否写全',
          detail: e.detail,
          status: e.status,
        );
      case 'http429':
        return AppException(
          'llmRate',
          '模型接口被限流（429），内置模型是共享额度，建议配置自己的模型',
          detail: e.detail,
          status: e.status,
          retryable: true,
        );
      case 'badJson':
      case 'emptyBody':
        return AppException('llmFormat', '模型返回的不是预期内容', detail: e.detail);
    }
    if (e.retryable) {
      return AppException(
        e.code,
        '${e.message}（模型：${p.name}）',
        detail: e.detail,
        status: e.status,
        retryable: true,
      );
    }
    return e;
  }

  Future<dynamic> structured(
    String system,
    String user, {
    double temperature = 0.3,
    String operation = 'AI 操作',
    bool gate = true,
  }) async {
    final raw = await chat(
      system,
      '$user\n\n${Prompts.jsonOnly}',
      temperature: temperature,
      operation: operation,
      gate: gate,
    );
    return _decode(raw);
  }

  dynamic _decode(String raw) {
    final start = raw.indexOf(RegExp(r'[\{\[]'));
    final end = raw.lastIndexOf(RegExp(r'[\}\]]'));
    if (start >= 0 && end > start) {
      return jsonDecode(raw.substring(start, end + 1));
    }
    return jsonDecode(raw);
  }
}
