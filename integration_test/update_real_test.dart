import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/update_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 真机「更新链路」冒烟测试：跑在设备上、打真实网络，不依赖任何点击注入。
///
///   flutter test integration_test/update_real_test.dart -d 127.0.0.1:7555
///
/// 远端还没发布 `version.json` 时，只验证「探测 3 个端点、按时失败」；
/// 一旦发布了新版本，同一个测试会把 下载 → sha256 校验 → 唤起安装器 全跑一遍。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('检查更新走真实网络', (tester) async {
    UpdateService.offline = false; // 设备上要真联网（单测里默认短路）
    UpdateService.onProbe = (host, ms, r) => debugPrint('[update-e2e] 探测 ${host.isEmpty ? "github.com 直连" : host} → $r（${ms}ms）');
    final s = UpdateService();

    final sw = Stopwatch()..start();
    var info = await s.fetch();
    sw.stop();
    debugPrint('[update-e2e] fetch 用时 ${sw.elapsedMilliseconds}ms → '
        '${info == null ? "null（远端没有 version.json：资产名不对或还没发布）" : "${info.version} / code ${info.versionCode} / ${info.size} 字节 / sha ${info.sha256.substring(0, 8)}…"}');
    expect(sw.elapsedMilliseconds, lessThan(20000), reason: '冷启动只探 3 个端点，各自 3s 超时');

    if (info == null) {
      // 关键诊断：是"手机网络慢"还是"根本不通"。清掉冷却后用 10s 超时复测同一批端点。
      debugPrint('[update-e2e] 3s 超时下全灭，改用 10s 超时复测（清掉冷却）');
      final sp = await SharedPreferences.getInstance();
      await sp.remove('update_dead_hosts');
      await sp.setString('update_ok_host', '');
      UpdateService.endpointTimeout = const Duration(seconds: 10);
      final sw2 = Stopwatch()..start();
      info = await s.fetch();
      sw2.stop();
      debugPrint('[update-e2e] 10s 超时下用时 ${sw2.elapsedMilliseconds}ms → ${info == null ? "仍然 null（设备到 GitHub 确实不通）" : "成功 ${info.version}"}');
    }

    if (info == null) {
      debugPrint('[update-e2e] 远端暂无发布或网络不通，跳过下载链路（发布后用同一条命令复跑）');
      return;
    }

    expect(info.sha256.length, 64, reason: 'sha256 必须是完整十六进制');
    expect(UpdateService.urlAllowed(info.url), isTrue);

    if (!await s.hasUpdate(info)) {
      debugPrint('[update-e2e] 远端版本不高于本机，跳过下载');
      return;
    }
    debugPrint('[update-e2e] 发现新版本，开始下载…');

    var lastPct = -1;
    final file = await s.download(info, onProgress: (got, total) {
      final pct = total > 0 ? (got * 100 ~/ total) : 0;
      if (pct != lastPct && pct % 20 == 0) {
        lastPct = pct;
        debugPrint('[update-e2e] 下载 $pct%');
      }
    });
    debugPrint('[update-e2e] 下载完成且 sha256 校验通过：${await file.length()} 字节');

    final granted = await s.canInstallPackages();
    debugPrint('[update-e2e] 已授权「安装未知应用」= $granted');
    if (!granted) {
      await s.requestInstallPermission(); // 会跳系统设置页
      return;
    }
    final err = await s.install(file);
    debugPrint('[update-e2e] 唤起安装器：${err ?? "已交给系统"}');
    expect(err, isNull, reason: '下载并校验通过后必须能唤起系统安装器');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
