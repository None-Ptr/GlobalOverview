import 'package:flutter/foundation.dart';
import 'package:global_overview/services/update_service.dart';

enum UpdatePhase {
  idle,

  /// 正在检查远端
  checking,

  /// 已是最新
  latest,

  /// 有新版待用户决定
  available,

  /// 下载中
  downloading,

  /// 校验中（下载完的 sha256 比对阶段）
  verifying,

  /// 已交给系统安装器
  installing,

  /// 失败（[error] 有说明）
  failed,
}

/// 更新流程的界面状态机：策略（每天一次、只弹一次、跳过此版本）都在这里，
/// 页面只负责渲染 [phase]。
class UpdateController extends ChangeNotifier {
  final UpdateService service;
  UpdateController(this.service);

  UpdatePhase phase = UpdatePhase.idle;
  UpdateInfo? info;
  String? error;
  int received = 0;
  int total = 0;
  String installedLabel = '';

  double get progress => total > 0 ? (received / total).clamp(0, 1) : 0;

  /// 自动检查是否过期（每天最多一次）。
  static const _autoInterval = Duration(hours: 24);

  Future<void> init() async {
    final v = await service.installedVersion();
    installedLabel = 'v$v';
    notifyListeners();
  }

  Future<bool> _dueForAutoCheck() async {
    final last = await service.lastCheckMs();
    if (last == 0) return true;
    return DateTime.now().millisecondsSinceEpoch - last > _autoInterval.inMilliseconds;
  }

  /// 启动时的静默检查：失败**不打扰**用户，只记冷却。
  Future<void> autoCheck() async {
    if (!await _dueForAutoCheck()) return;
    await _check(manual: false);
  }

  /// 手动检查：失败要说清原因，且不受「每天一次」限制。
  Future<void> checkNow() => _check(manual: true);

  Future<void> _check({required bool manual}) async {
    if (phase == UpdatePhase.checking || phase == UpdatePhase.downloading) return;
    phase = UpdatePhase.checking;
    error = null;
    notifyListeners();
    // 手动检查时给动效一点最短展示时间，避免瞬间闪完看不出发生了什么。
    final started = DateTime.now();
    final remote = await service.fetch();
    if (manual) {
      final elapsed = DateTime.now().difference(started);
      const minShow = Duration(milliseconds: 600);
      if (elapsed < minShow) await Future<void>.delayed(minShow - elapsed);
    }
    await service.markChecked();
    if (remote == null) {
      phase = manual ? UpdatePhase.failed : UpdatePhase.idle;
      error = manual ? '检查失败，换个线路再试试' : null;
      notifyListeners();
      return;
    }
    final ignored = await service.ignoredVersionCode();
    info = remote;
    final newer = await service.hasUpdate(remote);
    phase = newer && remote.versionCode != ignored ? UpdatePhase.available : UpdatePhase.latest;
    notifyListeners();
  }

  /// 首次发现某个版本才弹一次卡片，之后只留入口行上的红点。
  Future<bool> shouldPrompt() async {
    if (phase != UpdatePhase.available) return false;
    final vc = info?.versionCode ?? 0;
    if (vc == 0) return false;
    if (await service.promptedVersionCode() == vc) return false;
    await service.markPrompted(vc);
    return true;
  }

  /// 稍后：关掉卡片，本会话不再弹（红点仍在）。
  void dismiss() {
    if (phase == UpdatePhase.available) {
      phase = UpdatePhase.idle;
      notifyListeners();
    }
  }

  /// 跳过此版本：除非出现更高版本号，否则不再提示。
  Future<void> skipVersion() async {
    final vc = info?.versionCode ?? 0;
    if (vc > 0) await service.ignoreVersion(vc);
    phase = UpdatePhase.idle;
    notifyListeners();
  }

  /// 下载 → 校验 → 唤起安装器。未知来源未授权时先引导用户去系统设置。
  Future<void> downloadAndInstall() async {
    final target = info;
    if (target == null) return;
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.verifying) return;
    phase = UpdatePhase.downloading;
    error = null;
    received = 0;
    total = target.size;
    notifyListeners();
    try {
      final file = await service.download(
        target,
        onProgress: (got, sum) {
          received = got;
          total = sum;
          notifyListeners();
        },
      );
      phase = UpdatePhase.verifying;
      notifyListeners();
      if (!await service.canInstallPackages()) {
        final granted = await service.requestInstallPermission();
        if (!granted) {
          phase = UpdatePhase.failed;
          error = '需要在系统设置里允许本应用「安装未知应用」';
          notifyListeners();
          return;
        }
      }
      final err = await service.install(file);
      if (err != null) {
        phase = UpdatePhase.failed;
        error = err;
      } else {
        phase = UpdatePhase.installing;
      }
      notifyListeners();
    } on UpdateChecksumException {
      phase = UpdatePhase.failed;
      error = '安装包校验未通过，已丢弃（可换个线路重试）';
      notifyListeners();
    } catch (e) {
      phase = UpdatePhase.failed;
      error = '下载失败：$e';
      notifyListeners();
    }
  }
}
