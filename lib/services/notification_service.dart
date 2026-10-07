import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 本地提醒服务：每日学习提醒 + 航程预警。
///
/// 全部本地调度、无服务端；用户可随时关闭。
///
/// 闹钟模式：优先 `exactAllowWhileIdle`（Android 12+ 需 `SCHEDULE_EXACT_ALARM`
/// 授权），拿不到授权就退回 `inexactAllowWhileIdle`。非精确闹钟会被系统批量
/// 延迟（最长可达一小时），是「提醒不准时/像没生效」的常见原因。
///
/// 时区处理：不依赖设备时区名，直接把「本地时间」换算成 UTC 再按 `tz.UTC` 调度，
/// `matchDateTimeComponents: DateTimeComponents.time` 让它在每天同一本地时刻重复
/// （中国无夏令时，偏移恒定；有 DST 的地区会随季节偏移一小时，可接受）。
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// 测试环境直接短路：widget 测试里没有通知/SharedPreferences 的平台通道，
  /// 否则会抛 MissingPluginException（与 AppConfigService 的 Keystore 处理同理）。
  static final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

  static const _dailyId = 1001;
  static const _riskId = 1002;
  static const _testId = 1003;
  static const _channelId = 'study_reminder';
  static const _riskHour = 21;
  static const _riskMinute = 30;

  static const _kEnabled = 'notif_enabled';
  static const _kHour = 'notif_hour';
  static const _kMinute = 'notif_minute';
  static const defaultHour = 20;

  Future<void> init() async {
    if (_inTest || _inited) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(settings: const InitializationSettings(android: android, iOS: darwin));
    _inited = true;
  }

  /// 请求通知权限（Android 13+ 需运行时授权）。返回是否已授权。
  ///
  /// 同时申请「精确闹钟」能力（Android 12+ 默认关闭）：拿不到也不阻塞，
  /// 只是退化为系统的非精确批量闹钟。
  Future<bool> requestPermission() async {
    if (_inTest) return false;
    await init();
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;
    if (granted) {
      try {
        if (await android?.canScheduleExactNotifications() == false) {
          await android?.requestExactAlarmsPermission();
        }
      } catch (_) {
        // 个别 ROM 没有该入口，忽略即可。
      }
    }
    return granted;
  }

  /// 精确闹钟是否可用。不可用时退回非精确模式（系统会批量延迟投递）。
  Future<AndroidScheduleMode> _mode() async {
    if (!Platform.isAndroid) return AndroidScheduleMode.exactAllowWhileIdle;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ok = await android?.canScheduleExactNotifications() ?? false;
      return ok ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  Future<({bool enabled, int hour, int minute})> loadSettings() async {
    if (_inTest) return (enabled: false, hour: defaultHour, minute: 0);
    final sp = await SharedPreferences.getInstance();
    return (
      enabled: sp.getBool(_kEnabled) ?? false,
      hour: sp.getInt(_kHour) ?? defaultHour,
      minute: sp.getInt(_kMinute) ?? 0,
    );
  }

  Future<void> saveSettings({required bool enabled, required int hour, required int minute}) async {
    if (_inTest) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, enabled);
    await sp.setInt(_kHour, hour);
    await sp.setInt(_kMinute, minute);
  }

  /// 依据设置与当前学习状态重排通知（幂等，可在首页刷新、App 回到前台时调用）。
  /// [doneToday] 已达标时，航程预警顺延到明天，避免误报。
  ///
  /// 每次都先 `cancelAll` 再重排：设备改过系统时间后（时区/时钟跳变，AlarmManager
  /// 里已排的闹钟会错位甚至永远不触发），重排是唯一可靠的纠偏手段。
  Future<void> apply({
    required bool enabled,
    required int hour,
    required int minute,
    required bool doneToday,
    required int streak,
  }) async {
    if (_inTest) return;
    await init();
    await _plugin.cancelAll();
    if (!enabled) return;

    final mode = await _mode();
    await _daily(_dailyId, hour, minute, 0, '今天还没开始', '花 10 分钟读一篇，攒点见闻吧', mode);
    if (streak > 0) {
      await _daily(
        _riskId,
        _riskHour,
        _riskMinute,
        doneToday ? 1 : 0,
        '航程要断了',
        streak > 1 ? '别让 $streak 天航程断掉，来 5 分钟就够' : '今天还差一点见闻，来 5 分钟就够',
        mode,
      );
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '学习提醒',
      channelDescription: '每日学习提醒与航程预警',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// 立即发一条提醒，用来确认权限/通道能正常送达（与「开启提醒」开关无关，
  /// 也不能拿它判断定时是否生效——定时要靠系统闹钟）。
  Future<bool> sendTest() async {
    if (_inTest) return false;
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.requestNotificationsPermission() != true) return false;
    }
    await _plugin.show(
      id: _testId,
      title: '提醒可以送达',
      body: '看到这条通知，说明通知权限与通道都正常。每日提醒到点会像这样弹出。',
      notificationDetails: _details,
    );
    return true;
  }

  Future<void> _daily(
    int id,
    int hour,
    int minute,
    int addDays,
    String title,
    String body,
    AndroidScheduleMode mode,
  ) async {
    final now = DateTime.now();
    var fire = DateTime(now.year, now.month, now.day, hour, minute).add(Duration(days: addDays));
    if (addDays == 0 && !fire.isAfter(now)) fire = fire.add(const Duration(days: 1));
    final at = tz.TZDateTime.from(fire.toUtc(), tz.UTC);

    Future<void> schedule(AndroidScheduleMode m) => _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: m,
      matchDateTimeComponents: DateTimeComponents.time, // 每日同一时刻重复
    );

    try {
      await schedule(mode);
    } on PlatformException {
      // 精确闹钟权限中途被撤销等情况：退回非精确模式，至少别丢提醒。
      if (mode == AndroidScheduleMode.inexactAllowWhileIdle) rethrow;
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
}
