import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notify/device_notify.dart';
import '../../data/community_models.dart';
import '../../data/providers.dart';
import '../../widgets/section.dart';

const _prefKey = 'campuslink.notify.enabled';

/// Has this person allowed pop-up notifications on THIS device?
final deviceNotifyProvider = StateNotifierProvider<DeviceNotifyCtrl, bool>((ref) => DeviceNotifyCtrl());

class DeviceNotifyCtrl extends StateNotifier<bool> {
  DeviceNotifyCtrl() : super(false) {
    _load();
  }
  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final on = p.getBool(_prefKey) ?? false;
      state = on && await deviceNotifyStatus() == 'granted';
    } catch (_) {}
  }

  /// Returns a message to show when it could not be turned on.
  Future<String?> set(bool on) async {
    if (on) {
      final ok = await deviceNotifyAsk();
      if (!ok) {
        return (await deviceNotifyStatus()) == 'unsupported'
            ? 'This device or browser does not support notifications.'
            : 'Notifications are blocked. Allow them for CampusLink in your device or browser settings, then try again.';
      }
    }
    state = on;
    try {
      (await SharedPreferences.getInstance()).setBool(_prefKey, on);
    } catch (_) {}
    return null;
  }
}

/// Listens for new notifications while the app is open and pops them up.
class NotificationHost extends ConsumerStatefulWidget {
  const NotificationHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<NotificationHost> createState() => _HostState();
}

class _HostState extends ConsumerState<NotificationHost> {
  StreamSubscription<AppNotification>? _sub;
  String? _forUser;

  void _listen(String? userId) {
    if (userId == _forUser) return;
    _forUser = userId;
    _sub?.cancel();
    _sub = null;
    if (userId == null) return;
    // Counted once a day for the admin dashboard (numbers only, never names).
    ref.read(communityProvider).touchActivity();
    _sub = ref.read(communityProvider).newNotifications().listen((n) {
      ref.invalidate(notificationsProvider);
      if (n.kind == 'course') ref.invalidate(courseNoticesProvider);
      if (n.kind == 'access') {
        // My role or office changed: reload who I am and what I may see, now.
        ref.read(repositoryProvider).reloadMe();
        ref.invalidate(myHandledOfficesProvider);
        ref.invalidate(myMembershipsProvider);
        ref.invalidate(myRequestsProvider);
      }
      if (ref.read(deviceNotifyProvider)) {
        deviceNotifyShow(n.title, n.body, link: n.link);
      } else if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(n.title),
          action: n.link == null ? null : SnackBarAction(label: 'Open', onPressed: () => context.push(n.link!)),
        ));
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    _listen(user?.id);
    return widget.child;
  }
}

/// Bell with the number of unread notifications.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text(n > 9 ? '9+' : '$n'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  Timer? _markTimer;

  @override
  void dispose() {
    _markTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Opening the inbox marks everything as read (after a short moment so the
    // person still sees which ones were new).
    _markTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await ref.read(communityProvider).markNotificationsRead();
        if (mounted) ref.invalidate(notificationsProvider);
      } catch (_) {}
    });
  }

  static IconData _icon(String kind) => switch (kind) {
        'course' => Icons.menu_book_rounded,
        'event' => Icons.event_rounded,
        'tutor' => Icons.school_rounded,
        'request' => Icons.support_agent_rounded,
        'office' => Icons.badge_rounded,
        _ => Icons.campaign_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(notificationsProvider);
    final on = ref.watch(deviceNotifyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: PageBody(maxWidth: 760, children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_rounded),
              title: const Text('Pop-up notifications on this device'),
              subtitle: const Text('Uses your device\'s own notification sound.'),
              value: on,
              onChanged: (v) async {
                final msg = await ref.read(deviceNotifyProvider.notifier).set(v);
                if (msg != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          ...list.when(
            loading: () => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load: $e'))],
            data: (items) => items.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Nothing yet. Course notices from your lecturers, official notices, '
                          'major events and replies to your requests will appear here.',
                          textAlign: TextAlign.center),
                    ),
                  ]
                : [
                    for (final n in items)
                      Card(
                        color: n.read ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                        child: ListTile(
                          leading: Icon(_icon(n.kind),
                              color: n.priority == 'urgent' ? Colors.red : Theme.of(context).colorScheme.primary),
                          title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                          subtitle: Text(
                            [if (n.body.isNotEmpty) n.body, DateFormat('EEE d MMM, HH:mm').format(n.createdAt.toLocal())]
                                .join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: n.body.isNotEmpty,
                          onTap: n.link == null ? null : () => context.push(n.link!),
                        ),
                      ),
                  ],
          ),
        ]),
      ),
    );
  }
}
