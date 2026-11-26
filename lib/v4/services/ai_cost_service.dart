import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiPrice {
  final double inputPerMillion;
  final double outputPerMillion;
  final String currency;
  const AiPrice(this.inputPerMillion, this.outputPerMillion, this.currency);
}

class AiCostEstimate {
  final String model;
  final int inputTokens;
  final int outputMin;
  final int outputMax;
  final double? amountMin;
  final double? amountMax;
  final String currency;
  const AiCostEstimate({
    required this.model,
    required this.inputTokens,
    required this.outputMin,
    required this.outputMax,
    this.amountMin,
    this.amountMax,
    this.currency = 'CNY',
  });
  bool get hasPrice => amountMin != null && amountMax != null;
}

class AiUsageRecord {
  final String operation;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final double? amount;
  final String currency;
  final int at;

  /// Wall time of the request; 0 when it failed before a response.
  final int durationMs;

  /// 'ok' or 'failed'.
  final String status;

  /// Estimated range shown before the call, kept for the after-the-fact diff.
  final double? estimatedMin;
  final double? estimatedMax;

  const AiUsageRecord({
    required this.operation,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    this.amount,
    this.currency = 'CNY',
    required this.at,
    this.durationMs = 0,
    this.status = 'ok',
    this.estimatedMin,
    this.estimatedMax,
  });
  Map<String, dynamic> toJson() => {
    'operation': operation,
    'model': model,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'amount': amount,
    'currency': currency,
    'at': at,
    'durationMs': durationMs,
    'status': status,
    'estimatedMin': estimatedMin,
    'estimatedMax': estimatedMax,
  };
  factory AiUsageRecord.fromJson(Map<String, dynamic> json) => AiUsageRecord(
    operation: json['operation'] as String? ?? 'AI 操作',
    model: json['model'] as String? ?? '未知模型',
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    amount: (json['amount'] as num?)?.toDouble(),
    currency: json['currency'] as String? ?? 'CNY',
    at: (json['at'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'ok',
    estimatedMin: (json['estimatedMin'] as num?)?.toDouble(),
    estimatedMax: (json['estimatedMax'] as num?)?.toDouble(),
  );
}

class AiCostEstimator {
  static AiPrice? priceFor(String model) {
    final m = model.toLowerCase();
    if (m.contains('glm-4.7-flash') || m.contains('glm-4-flash')) {
      return const AiPrice(0, 0, 'CNY');
    }
    return null;
  }

  static AiCostEstimate estimateRequest(String inputText, String model) {
    final chars = inputText.length > 24000 ? 24000 : inputText.length;
    final input = (chars / 4).ceil() + 200;
    final price = priceFor(model);
    return AiCostEstimate(
      model: model,
      inputTokens: input,
      outputMin: 200,
      outputMax: 1400,
      amountMin: price == null
          ? null
          : (input / 1000000 * price.inputPerMillion) +
                (200 / 1000000 * price.outputPerMillion),
      amountMax: price == null
          ? null
          : (input / 1000000 * price.inputPerMillion) +
                (1400 / 1000000 * price.outputPerMillion),
      currency: price?.currency ?? 'CNY',
    );
  }

  static AiCostEstimate estimateQuiz({
    required String articleText,
    required int count,
    required String model,
  }) {
    final chars = articleText.length > 12000 ? 12000 : articleText.length;
    final input = (chars / 4).ceil() + 500;
    final min = 120 * count + 180;
    final max = 320 * count + 420;
    final price = priceFor(model);
    return AiCostEstimate(
      model: model,
      inputTokens: input,
      outputMin: min,
      outputMax: max,
      amountMin: price == null
          ? null
          : (input / 1000000 * price.inputPerMillion) +
                (min / 1000000 * price.outputPerMillion),
      amountMax: price == null
          ? null
          : (input / 1000000 * price.inputPerMillion) +
                (max / 1000000 * price.outputPerMillion),
      currency: price?.currency ?? 'CNY',
    );
  }

  /// A grading batch is one confirmation for N short answers.
  static AiCostEstimate estimateGrading({
    required String inputText,
    required int count,
    required String model,
  }) {
    final chars = inputText.length > 24000 ? 24000 : inputText.length;
    final input = (chars / 4).ceil() + 120;
    final min = 60 * count + 100;
    final max = 160 * count + 200;
    final price = priceFor(model);
    return AiCostEstimate(
      model: model,
      inputTokens: input,
      outputMin: min,
      outputMax: max,
      amountMin: price == null
          ? null
          : (input / 1000000 * price.inputPerMillion) +
                (min / 1000000 * price.outputPerMillion),
      amountMax: price == null
          ? null
          : (input / 1000000 * price.inputPerMillion) +
                (max / 1000000 * price.outputPerMillion),
      currency: price?.currency ?? 'CNY',
    );
  }
}

class AiUsageLedger {
  static const key = 'v4_ai_usage_ledger';

  /// Everything spent today, in the ledger's currency. Used by the soft cap.
  Future<double> spentToday() async {
    final rows = await list();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    var sum = 0.0;
    for (final row in rows) {
      if (row.at < start || row.status != 'ok') continue;
      sum += row.amount ?? 0;
    }
    return sum;
  }

  Future<List<AiUsageRecord>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as List;
      return data
          .whereType<Map>()
          .map((e) => AiUsageRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
    } catch (_) {
      return [];
    }
  }

  Future<void> add(AiUsageRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await list();
    records.insert(0, record);
    final capped = records.take(200).toList();
    await prefs.setString(
      key,
      jsonEncode(capped.map((e) => e.toJson()).toList()),
    );
  }
}
