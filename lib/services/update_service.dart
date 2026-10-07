import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 校验和不匹配：极端情况下才可能发生（下载被截断/中间人改包），绝不安装。
class UpdateChecksumException implements Exception {
  const UpdateChecksumException();
  @override
  String toString() => '安装包校验未通过';
}

/// 远端版本契约（`version.json` 的解析结果），字段由 `tool/release.ps1` 生成。
class UpdateInfo {
  final String version;
  final int versionCode;
  final String url;
  final String sha256;
  final int size;
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
  });

  /// 宽松解析：任何字段缺失/类型不对都返回 null，一份坏 JSON 不该让检查更新崩掉。
  static UpdateInfo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final url = raw['url'];
    final sha = raw['sha256'];
    if (version is! String || url is! String || sha is! String) return null;
    if (!UpdateService.urlAllowed(url)) return null;
    final vc = raw['versionCode'];
    final size = raw['size'];
    final notes = raw['notes'];
    return UpdateInfo(
      version: version,
      versionCode: vc is int ? vc : int.tryParse('$vc') ?? 0,
      url: url,
      sha256: sha.toLowerCase().trim(),
      size: size is int ? size : int.tryParse('$size') ?? 0,
      notes: notes is String ? notes : '',
    );
  }
}

/// 应用内更新：检查 → 下载 → 校验 → 交给系统安装器。
///
/// 通道：GitHub Release 的免 API 固定链接 `releases/latest/download/<固定资产名>`，
/// 不走 `api.github.com`（国内不稳）。三类第三方反代只作为**通道**，安全边界是
/// Android 的 APK 签名校验（所有版本共用 legacy/key.jks），sha256 只负责完整性。
class UpdateService {
  static const _owner = 'None-Ptr';
  static const _repo = 'GlobalOverview';
  static const _releaseBase = 'https://github.com/$_owner/$_repo/releases/latest/download';

  /// 元数据固定链接（资产名必须固定，见 tool/release.ps1）。
  static const jsonUrl = '$_releaseBase/version.json';

  /// 直连（不过反代）的标记。
  static const _direct = '';

  /// 反代 host，path-prefix 形式：`https://<host>/<完整原始 URL>`。顺序按本机实测速度排。
  static const mirrorHosts = <String>[
    'gh.acmsz.top',
    'gh-proxy.com',
    'gh.felicity.ac.cn',
    'github.dpik.top',
    'gh.jjj.gv.uy',
    'github.chenc.dev',
    'github.mxw.qzz.io',
    'tvv.tw',
    'gitproxy.mrhjx.cn',
    'cdn.akaere.online',
    'jiashu.1win.eu.org',
    'github-proxy.memory-echoes.cn',
    'cdn.gh-proxy.com',
    'gh.inkchills.cn',
    'ghproxy.net',
  ];

  /// 测试环境默认不联网/不碰平台通道（widget 测试里没有真实网络与插件）。
  /// 服务自身的单测把它置 false 并注入假的 [http.Client] 来测端点逻辑。
  static bool offline = Platform.environment.containsKey('FLUTTER_TEST');

  static const _kOkHost = 'update_ok_host';
  static const _kDead = 'update_dead_hosts';
  static const _kIgnored = 'update_ignored_vc';
  static const _kPrompted = 'update_prompted_vc';
  static const _kLastCheck = 'update_last_check_ms';

  static const cooldown = Duration(minutes: 30);

  /// 单端点超时。3s 是按本机（PC）实测定的，但真机实测里唯一能通的镜像
  /// `gh.acmsz.top` 要 2.2~2.9s——贴着 3s 就会变成偶发失败，故放宽到 5s。
  static Duration endpointTimeout = const Duration(seconds: 5);
  static const _probeBudget = 3;
  static const _downloadBudget = 3;

  /// 诊断钩子：每次端点探测后回调（host, 耗时 ms, 结果）。生产环境为 null。
  static void Function(String host, int ms, String result)? onProbe;

  /// 可注入的 http 客户端（单测用）；注入后由调用方负责生命周期。
  final http.Client? client;
  UpdateService({this.client});

  http.Client _open() => client ?? http.Client();

  void _close(http.Client c) {
    if (client == null) c.close();
  }

  String? _versionName;
  int _versionCode = -1;

  /// 安装包的版本号（真相源 = 安装包本身，不需要人工维护常量）。
  Future<String> installedVersion() async {
    if (_versionName != null) return _versionName!;
    try {
      final pi = await PackageInfo.fromPlatform();
      _versionName = pi.version;
      _versionCode = int.tryParse(pi.buildNumber) ?? 0;
    } catch (_) {
      _versionName = '0.0.0';
      _versionCode = 0;
    }
    return _versionName!;
  }

  Future<int> installedVersionCode() async {
    if (_versionCode >= 0) return _versionCode;
    await installedVersion();
    return _versionCode < 0 ? 0 : _versionCode;
  }

  // ——— 设置读写 ———

  Future<int> lastCheckMs() async {
    if (offline) return 0;
    return (await SharedPreferences.getInstance()).getInt(_kLastCheck) ?? 0;
  }

  Future<void> markChecked() async {
    if (offline) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  Future<int> ignoredVersionCode() async {
    if (offline) return 0;
    return (await SharedPreferences.getInstance()).getInt(_kIgnored) ?? 0;
  }

  Future<void> ignoreVersion(int versionCode) async {
    if (offline) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kIgnored, versionCode);
  }

  Future<int> promptedVersionCode() async {
    if (offline) return 0;
    return (await SharedPreferences.getInstance()).getInt(_kPrompted) ?? 0;
  }

  Future<void> markPrompted(int versionCode) async {
    if (offline) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kPrompted, versionCode);
  }

  /// 记忆上次成功的端点，下次优先它（失败者进冷却期，见 [_deadHosts]）。
  Future<String> _okHost() async {
    if (offline) return _direct;
    return (await SharedPreferences.getInstance()).getString(_kOkHost) ?? _direct;
  }

  Future<void> _rememberHost(String host) async {
    if (offline) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kOkHost, host);
  }

  Future<Map<String, int>> _deadHosts() async {
    if (offline) return {};
    final raw = (await SharedPreferences.getInstance()).getString(_kDead);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      final now = DateTime.now().millisecondsSinceEpoch;
      return {
        for (final e in m.entries)
          if (e.value is int && (e.value as int) > now) '${e.key}': e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _markDead(Iterable<String> hosts) async {
    if (offline) return;
    final sp = await SharedPreferences.getInstance();
    final m = await _deadHosts();
    final until = DateTime.now().add(cooldown).millisecondsSinceEpoch;
    for (final h in hosts) {
      m[h] = until;
    }
    await sp.setString(_kDead, jsonEncode(m));
  }

  // ——— 检查 ———

  static Uri _via(String host, String url) =>
      Uri.parse(host == _direct ? url : 'https://$host/$url');

  /// `url` 只允许 https 且 host 在内置名单里，避免代理把用户引到任意站点。
  static bool urlAllowed(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return false;
    final h = u.host.toLowerCase();
    return h == 'github.com' || h == 'objects.githubusercontent.com' || mirrorHosts.contains(h);
  }

  List<String> _orderedHosts(String okHost, Map<String, int> dead) {
    final all = <String>[_direct, ...mirrorHosts];
    final ordered = <String>[
      if (all.contains(okHost)) okHost,
      ...all.where((h) => h != okHost),
    ];
    return ordered.where((h) => !dead.containsKey(h)).toList();
  }

  /// 检查是否有新版本。返回 null 表示**检查失败**（调用方决定是否提示）。
  /// 返回的 `UpdateInfo` 只管"远端有什么"，是否有更新由 [hasUpdate] 判断。
  Future<UpdateInfo?> fetch() async {
    if (offline) return null;
    final hosts = _orderedHosts(await _okHost(), await _deadHosts());
    if (hosts.isEmpty) return null;
    final client = _open();
    final tried = <String>[];
    // 只要拿到 HTTP 响应就算这个端点「活着」——404 只说明远端还没发布资产，
    // 不代表通道不通，不该进冷却（否则会把能用的端点白关 30 分钟）。
    final alive = <String>{};
    try {
      for (final host in hosts.take(_probeBudget)) {
        tried.add(host);
        final tick = DateTime.now();
        try {
          final res = await client.get(_via(host, jsonUrl)).timeout(endpointTimeout);
          alive.add(host);
          onProbe?.call(host, DateTime.now().difference(tick).inMilliseconds, 'HTTP ${res.statusCode}');
          if (res.statusCode != 200) continue;
          final info = UpdateInfo.tryParse(jsonDecode(utf8.decode(res.bodyBytes)));
          if (info == null) continue; // 坏 JSON：端点活着，但内容不可信
          await _rememberHost(host);
          return info;
        } catch (e) {
          onProbe?.call(host, DateTime.now().difference(tick).inMilliseconds, '失败 ${e.runtimeType}');
        }
      }
      await _markDead(tried.where((h) => !alive.contains(h)));
      return null;
    } finally {
      _close(client);
    }
  }

  /// 是否更新：优先比 `versionCode`（整型，无歧义）；一方缺字段时回退比三段版本号；
  /// 两边都读不出来就**不提示**（保守优先，宁可漏报不要无限提示）。
  static bool isNewer({
    required int remoteCode,
    required String remoteVersion,
    required int installedCode,
    required String installedVersion,
  }) {
    if (remoteCode > 0 && installedCode > 0) return remoteCode > installedCode;
    final a = _semver(remoteVersion);
    final b = _semver(installedVersion);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  Future<bool> hasUpdate(UpdateInfo info) async => isNewer(
        remoteCode: info.versionCode,
        remoteVersion: info.version,
        installedCode: await installedVersionCode(),
        installedVersion: await installedVersion(),
      );

  /// 容忍 `V3.0` / `v3.5` / `3.5.0` 这类历史写法，补 0 成三段。
  static List<int>? _semver(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    s = s.split('+').first.split('-').first;
    final parts = s.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    while (out.length < 3) {
      out.add(0);
    }
    return out;
  }

  // ——— 下载 ———

  /// 流式下载 + 边下边算 sha256；校验不过就删文件并抛异常，**绝不交给安装器**。
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!urlAllowed(info.url)) throw const UpdateChecksumException();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/GlobalOverview.apk');
    // 下载不做冷却过滤：优先沿用记住的端点，不行再直连/逐个镜像，最多试 3 个。
    final hosts = _orderedHosts(await _okHost(), const <String, int>{}).take(_downloadBudget).toList();

    Object? lastError;
    for (final host in hosts) {
      try {
        await _downloadFrom(host, info, file, onProgress);
        return file;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is UpdateChecksumException) throw lastError;
    throw Exception('下载失败：$lastError');
  }

  Future<void> _downloadFrom(
    String host,
    UpdateInfo info,
    File file,
    void Function(int, int)? onProgress,
  ) async {
    final client = _open();
    try {
      final res = await client.send(http.Request('GET', _via(host, info.url))).timeout(endpointTimeout);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? info.size;
      final out = file.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var got = 0;
      var lastTick = 0;
      try {
        await for (final chunk in res.stream) {
          got += chunk.length;
          hasher.add(chunk);
          out.add(chunk);
          final now = DateTime.now().millisecondsSinceEpoch;
          if (onProgress != null && (now - lastTick > 200 || got == total)) {
            lastTick = now;
            onProgress(got, total);
          }
        }
      } finally {
        hasher.close();
        await out.flush();
        await out.close();
      }
      onProgress?.call(got, total);
      if (digest.value.toString() != info.sha256) {
        await file.delete();
        throw const UpdateChecksumException();
      }
      if (info.size > 0 && got != info.size) {
        await file.delete();
        throw const UpdateChecksumException();
      }
    } finally {
      _close(client);
    }
  }

  // ——— 安装 ———

  /// Android 8+ 需要「允许安装未知应用」授权，未授权时系统设置页由
  /// [requestInstallPermission] 打开。
  Future<bool> canInstallPackages() async {
    if (offline) return false;
    if (!Platform.isAndroid) return true;
    return Permission.requestInstallPackages.isGranted;
  }

  Future<bool> requestInstallPermission() async {
    if (offline) return false;
    if (!Platform.isAndroid) return true;
    final s = await Permission.requestInstallPackages.request();
    return s.isGranted;
  }

  /// 拉起系统安装器。返回 null 表示已交给安装器，否则返回错误描述。
  Future<String?> install(File apk) async {
    if (offline) return '测试环境不安装';
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    return r.type == ResultType.done ? null : r.message;
  }
}

/// 供 `sha256.startChunkedConversion` 收集结果（省掉一个 convert 依赖）。
class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
