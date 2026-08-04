import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class DailyNotificationSettings {
  const DailyNotificationSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;
}

class NotificationQuote {
  const NotificationQuote({required this.text, required this.author, this.id});

  final String text;
  final String author;
  final String? id;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _enabledKey = 'daily_quote_notification_enabled';
  static const _hourKey = 'daily_quote_notification_hour';
  static const _minuteKey = 'daily_quote_notification_minute';
  static const _firstNotificationId = 8100;
  static const _notificationCount = 7;
  static const _channelId = 'daily_healing_quotes';
  static const _channelName = '매일 명언';
  static const _channelDescription = '설정한 시각에 힐링 하이의 명언을 알려드려요.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;

    tz_data.initializeTimeZones();
    try {
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone));
    } catch (error) {
      debugPrint('기기 시간대 확인 실패, Asia/Seoul을 사용합니다: $error');
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    }

    const androidSettings = AndroidInitializationSettings('launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<DailyNotificationSettings> loadSettings() async {
    return DailyNotificationSettings(
      enabled: await _preferences.getBool(_enabledKey) ?? false,
      hour: await _preferences.getInt(_hourKey) ?? 8,
      minute: await _preferences.getInt(_minuteKey) ?? 0,
    );
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (!isSupported) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? true;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        ) ??
        false;
  }

  Future<List<NotificationQuote>> loadQuotes(SupabaseClient client) async {
    final response = await client
        .from('quotes')
        .select('id, text_kr, resoner_kr')
        .limit(100);

    final quotes = response
        .map((row) {
          final text = row['text_kr']?.toString().trim() ?? '';
          if (text.isEmpty) return null;
          final author = row['resoner_kr']?.toString().trim() ?? '';
          return NotificationQuote(
            id: row['id']?.toString(),
            text: text,
            author: author.isEmpty ? '오늘의 명언' : author,
          );
        })
        .whereType<NotificationQuote>()
        .toList();

    if (quotes.isEmpty) {
      throw StateError('알림에 사용할 명언이 없습니다.');
    }

    quotes.shuffle(Random());
    return quotes;
  }

  Future<void> enable({
    required int hour,
    required int minute,
    required List<NotificationQuote> quotes,
  }) async {
    await _scheduleWeeklyRotation(hour: hour, minute: minute, quotes: quotes);
    await _saveSettings(enabled: true, hour: hour, minute: minute);
  }

  Future<void> updateTime({
    required bool enabled,
    required int hour,
    required int minute,
    List<NotificationQuote>? quotes,
  }) async {
    if (enabled) {
      if (quotes == null || quotes.isEmpty) {
        throw ArgumentError('활성화된 알림의 시각 변경에는 명언이 필요합니다.');
      }
      await _scheduleWeeklyRotation(hour: hour, minute: minute, quotes: quotes);
    }
    await _saveSettings(enabled: enabled, hour: hour, minute: minute);
  }

  Future<void> disable({required int hour, required int minute}) async {
    await initialize();
    await _cancelScheduledQuotes();
    await _saveSettings(enabled: false, hour: hour, minute: minute);
  }

  Future<void> refreshIfEnabled(SupabaseClient client) async {
    final settings = await loadSettings();
    if (!settings.enabled || !isSupported) return;

    final quotes = await loadQuotes(client);
    await _scheduleWeeklyRotation(
      hour: settings.hour,
      minute: settings.minute,
      quotes: quotes,
    );
  }

  Future<void> _scheduleWeeklyRotation({
    required int hour,
    required int minute,
    required List<NotificationQuote> quotes,
  }) async {
    await initialize();
    if (!isSupported) {
      throw UnsupportedError('이 기기에서는 알림을 지원하지 않습니다.');
    }
    if (quotes.isEmpty) throw StateError('알림에 사용할 명언이 없습니다.');

    await _cancelScheduledQuotes();
    final firstDate = _nextDateAt(hour, minute);

    for (var index = 0; index < _notificationCount; index++) {
      final scheduledDate = tz.TZDateTime(
        tz.local,
        firstDate.year,
        firstDate.month,
        firstDate.day + index,
        hour,
        minute,
      );
      final quote = quotes[index % quotes.length];
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            quote.text,
            contentTitle: quote.author,
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );

      await _plugin.zonedSchedule(
        _firstNotificationId + index,
        quote.author,
        quote.text,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: quote.id,
      );
    }
  }

  tz.TZDateTime _nextDateAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  Future<void> _cancelScheduledQuotes() async {
    for (var index = 0; index < _notificationCount; index++) {
      await _plugin.cancel(_firstNotificationId + index);
    }
  }

  Future<void> _saveSettings({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await Future.wait([
      _preferences.setBool(_enabledKey, enabled),
      _preferences.setInt(_hourKey, hour),
      _preferences.setInt(_minuteKey, minute),
    ]);
  }
}
