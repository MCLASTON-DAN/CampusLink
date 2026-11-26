import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notify/device_notify.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/exams.dart';
import 'exams_screen.dart';

/// Minutes before each class to remind (0 = off). Saved on this device.
final classReminderMinutesProvider =
    StateNotifierProvider<ClassReminderCtrl, int>((ref) => ClassReminderCtrl());

class ClassReminderCtrl extends StateNotifier<int> {
  ClassReminderCtrl() : super(0) {
    SharedPreferences.getInstance().then((p) {
      if (mounted) state = p.getInt(_key) ?? 0;
    }).catchError((_) {});
  }
  static const _key = 'class_reminder_minutes';
  static const choices = [0, 5, 10, 15, 30, 60];

  /// Returns a message to show if it could not be turned on.
  Future<String?> set(int minutes) async {
    if (minutes > 0) {
      if (!deviceCanSchedule) return 'Class reminders work in the phone app. Browsers can\'t remind you while closed.';
      if (!await deviceNotifyAsk()) {
        return 'Notifications are blocked. Allow them for CampusLink in your phone settings, then try again.';
      }
    }
    state = minutes;
    try {
      (await SharedPreferences.getInstance()).setInt(_key, minutes);
    } catch (_) {}
    return null;
  }
}

/// Keeps the phone's weekly reminders in step with the timetable and setting.
/// Runs on app start, after any timetable change, and on sign-out (clears them).
class ClassReminderSync extends ConsumerStatefulWidget {
  const ClassReminderSync({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ClassReminderSync> createState() => _SyncState();
}

class _SyncState extends ConsumerState<ClassReminderSync> {
  static const _sigKey = 'class_reminder_sig', _countKey = 'class_reminder_count';
  String? _lastSig;

  Future<void> _apply(List<ClassReminder> plan) async {
    final sig = plan.join('|');
    if (sig == _lastSig) return;
    _lastSig = sig;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_sigKey) == sig) return; // already set on this phone
      final ok = await deviceScheduleClassReminders(plan, p.getInt(_countKey) ?? 40);
      if (ok) {
        await p.setString(_sigKey, sig);
        await p.setInt(_countKey, plan.length);
      }
    } catch (_) {}
  }

  String? _lastExamSig;
  Future<void> _applyExams(List<ExamReminder> plan) async {
    final sig = plan.join('|');
    if (sig == _lastExamSig) return;
    _lastExamSig = sig;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString('exam_reminder_sig') == sig) return;
      if (await deviceScheduleExamReminders(plan, p.getInt('exam_reminder_count') ?? 40)) {
        await p.setString('exam_reminder_sig', sig);
        await p.setInt('exam_reminder_count', plan.length);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (deviceCanSchedule) {
      final signedIn = ref.watch(currentUserProvider).valueOrNull != null;
      final minutes = ref.watch(classReminderMinutesProvider);
      final table = signedIn && minutes > 0 ? ref.watch(timetableProvider) : const AsyncData(<TimetableEntry>[]);
      // Only act on real data; a loading or failed timetable leaves reminders as they are.
      if (table case AsyncData(:final value)) {
        final plan = signedIn ? planClassReminders(value, minutes) : const <ClassReminder>[];
        WidgetsBinding.instance.addPostFrameCallback((_) => _apply(plan));
      }
      // Exams: always on when signed in (they matter too much to miss).
      final exams = signedIn ? ref.watch(myExamsProvider) : const AsyncData(<ExamEntry>[]);
      if (exams case AsyncData(:final value)) {
        final plan = planExamReminders(value, DateTime.now());
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyExams(plan));
      }
    }
    return widget.child;
  }
}

/// The setting, for the Me page.
class ClassReminderTile extends ConsumerWidget {
  const ClassReminderTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(classReminderMinutesProvider);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.alarm_rounded),
        title: const Text('Class reminders'),
        subtitle: Text(!deviceCanSchedule
            ? 'Works in the phone app. Browsers can\'t remind you while closed.'
            : m == 0
                ? 'Off'
                : '$m min before each class on your timetable'),
        trailing: DropdownButton<int>(
          value: m,
          underline: const SizedBox.shrink(),
          items: [
            for (final c in ClassReminderCtrl.choices)
              DropdownMenuItem(value: c, child: Text(c == 0 ? 'Off' : c == 60 ? '1 hour' : '$c min')),
          ],
          onChanged: !deviceCanSchedule
              ? null
              : (v) async {
                  final msg = await ref.read(classReminderMinutesProvider.notifier).set(v ?? 0);
                  if (msg != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
        ),
      ),
    );
  }
}
