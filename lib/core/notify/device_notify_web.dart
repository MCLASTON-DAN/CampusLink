import 'dart:js_interop';

import 'class_reminders.dart';

@JS('campuslinkNotifyStatus')
external JSString? _status();
@JS('campuslinkNotifyAsk')
external JSPromise<JSString>? _ask();
@JS('campuslinkNotify')
external JSPromise<JSBoolean>? _notify(JSString title, JSString body, JSString url);

/// 'granted' | 'denied' | 'default' | 'unsupported'
Future<String> deviceNotifyStatus() async {
  try {
    return _status()?.toDart ?? 'unsupported';
  } catch (_) {
    return 'unsupported';
  }
}

/// Asks the browser for permission. Returns true when allowed.
Future<bool> deviceNotifyAsk() async {
  try {
    final p = _ask();
    if (p == null) return false;
    return (await p.toDart).toDart == 'granted';
  } catch (_) {
    return false;
  }
}

Future<void> deviceNotifyShow(String title, String body, {String? link}) async {
  try {
    final p = _notify(title.toJS, body.toJS, (link ?? '/').toJS);
    if (p != null) await p.toDart;
  } catch (_) {}
}


/// Browsers cannot fire a reminder while the page is closed.
Future<void> deviceEnsureAlertChannel() async {}

bool get deviceCanSchedule => false;
Future<bool> deviceScheduleClassReminders(List<ClassReminder> list, int oldCount) async => false;

Future<bool> deviceScheduleExamReminders(List<ExamReminder> list, int oldCount) async => false;
