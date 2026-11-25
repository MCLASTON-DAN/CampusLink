import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'class_reminders.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;
var _granted = false;
var _id = 0;

bool get _supported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux || Platform.isWindows);

Future<void> _init() async {
  if (_ready || !_supported) return;
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_stat_campuslink'),
    iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
    macOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
    linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    windows: WindowsInitializationSettings(
      appName: 'CampusLink',
      appUserModelId: 'ug.ac.cavendish.campuslink',
      guid: '6f1c3a52-6d1b-4f7e-9a40-3c6b2b8e1d11',
    ),
  );
  await _plugin.initialize(settings);
  _ready = true;
}

Future<String> deviceNotifyStatus() async {
  if (!_supported) return 'unsupported';
  try {
    await _init();
    if (Platform.isAndroid) {
      final ok = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return ok == true ? 'granted' : 'default';
    }
    return _granted ? 'granted' : 'default';
  } catch (_) {
    return 'unsupported';
  }
}

Future<bool> deviceNotifyAsk() async {
  if (!_supported) return false;
  try {
    await _init();
    bool? ok = true;
    if (Platform.isAndroid) {
      ok = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      ok = await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      ok = await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    _granted = ok ?? false;
    return _granted;
  } catch (_) {
    return false;
  }
}

/// Shows a notification with the device's default sound.
Future<void> deviceNotifyShow(String title, String body, {String? link}) async {
  if (!_supported) return;
  try {
    await _init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'campuslink_updates',
        'CampusLink updates',
        channelDescription: 'Course notices, official notices, events and requests',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true, // uses the phone's chosen notification sound
      ),
      iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true, presentBanner: true),
      macOS: DarwinNotificationDetails(presentSound: true, presentAlert: true, presentBanner: true),
      linux: LinuxNotificationDetails(),
    );
    await _plugin.show(_id++, title, body, details, payload: link);
  } catch (_) {}
}

/// Can this device fire a reminder while the app is closed?
bool get deviceCanSchedule => _supported && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

bool _tzReady = false;

/// Replaces all class reminders with [list]. [oldCount] is how many were set last time.
Future<bool> deviceScheduleClassReminders(List<ClassReminder> list, int oldCount) async {
  if (!deviceCanSchedule) return false;
  try {
    await _init();
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    // Classes run on Kampala time, wherever the phone is set.
    final kla = tz.getLocation('Africa/Kampala');
    for (var i = 0; i < oldCount; i++) {
      await _plugin.cancel(reminderIdBase + i);
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'campuslink_classes',
        'Class reminders',
        channelDescription: 'A heads-up before each class on your timetable',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true, presentBanner: true),
      macOS: DarwinNotificationDetails(presentSound: true, presentAlert: true, presentBanner: true),
    );
    final now = tz.TZDateTime.now(kla);
    for (final r in list) {
      var when = tz.TZDateTime(kla, now.year, now.month, now.day, r.hour, r.minute);
      while (when.weekday != r.weekday || !when.isAfter(now)) {
        when = when.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(r.id, r.title, r.body, when, details,
          // Inexact needs no special permission; it may be a minute or two late.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: '/timetable');
    }
    return true;
  } catch (_) {
    return false;
  }
}
