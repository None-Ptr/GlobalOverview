import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('自建地址必须是 HTTPS 并规范化为目录', () {
    expect(
      FeedOverviewService.normalizeRootUrl(
        'https://user.github.io/FeedOverview',
      ),
      'https://user.github.io/FeedOverview/',
    );
    expect(
      FeedOverviewService.normalizeRootUrl(
        ' https://user.github.io/FeedOverview/ ',
      ),
      'https://user.github.io/FeedOverview/',
    );
    expect(
      FeedOverviewService.normalizeRootUrl(
        'http://user.github.io/FeedOverview/',
      ),
      isNull,
    );
    expect(
      FeedOverviewService.normalizeRootUrl('user.github.io/FeedOverview'),
      isNull,
    );
    expect(FeedOverviewService.normalizeRootUrl(''), isNull);
  });

  test('自建地址保存后成为根地址，清除后回到官方', () async {
    final service = FeedOverviewService(FakeDb(), HttpService());
    expect(await service.rootUrl(), FeedOverviewService.baseUrl);

    expect(
      await service.setRootUrl('https://user.github.io/FeedOverview'),
      isTrue,
    );
    expect(
      await service.rootUrl(),
      'https://user.github.io/FeedOverview/',
    );

    await service.clearRootUrl();
    expect(await service.rootUrl(), FeedOverviewService.baseUrl);
  });

  test('无效自建地址不写入', () async {
    final service = FeedOverviewService(FakeDb(), HttpService());
    expect(await service.setRootUrl('http://user.github.io/x'), isFalse);
    expect(await service.rootUrl(), FeedOverviewService.baseUrl);
  });
}
