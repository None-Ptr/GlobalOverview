import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/curate_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';

class _FakeLlm extends LlmService {
  final dynamic response;
  _FakeLlm(this.response) : super(HttpService(), AppConfigService());

  @override
  Future<dynamic> structured(String system, String user, {double temperature = 0.3}) async => response;
}

void main() {
  test('模型没返回段落时，精选结果应为空（不能把原文当作精选版保存）', () async {
    final blocks = [ArticleBlock(type: 'p', text: 'one'), ArticleBlock(type: 'p', text: 'two')];
    final res = await CurateService(_FakeLlm(<dynamic>[])).curate(blocks);
    expect(res, isEmpty);
  });

  test('模型正常返回段落时按其重建', () async {
    final blocks = [ArticleBlock(type: 'p', text: 'one long paragraph')];
    final res = await CurateService(_FakeLlm(['short one', 'short two'])).curate(blocks);
    expect(res.length, 2);
    expect(res.first.text, 'short one');
  });
}
