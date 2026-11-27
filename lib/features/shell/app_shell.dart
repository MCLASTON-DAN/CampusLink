import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon, this.selectedIcon, this.prefixes);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final List<String> prefixes; // pages that belong to this section
}

// Five calm sections. Everything else lives inside one of them.
const _dests = [
  _Dest('/home', 'Home', Icons.home_outlined, Icons.home_rounded, ['/home']),
  _Dest('/feed', 'Feed', Icons.dynamic_feed_outlined, Icons.dynamic_feed_rounded,
      ['/feed', '/news', '/events', '/surveys']),
  _Dest('/campus', 'Campus', Icons.explore_outlined, Icons.explore_rounded,
      ['/campus', '/where', '/map', '/directory', '/campuses', '/requests', '/lostfound', '/announcements', '/engage']),
  _Dest('/study', 'Study', Icons.school_outlined, Icons.school_rounded,
      ['/study', '/tutors', '/groups', '/timetable', '/exams', '/buddy', '/pulse', '/courses']),
  _Dest('/profile', 'Me', Icons.person_outline_rounded, Icons.person_rounded,
      ['/profile', '/community', '/members', '/reports', '/moderation', '/install', '/notifications', '/tutor-reports', '/tutor-checks', '/insights', '/dashboard']),
];

/// Responsive scaffold: bottom bar on phones, nav rail on tablets/desktop/web.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  int get _index {
    final i = _dests.indexWhere((d) => d.prefixes.any(location.startsWith));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ScreenSize.of(context);
    final wide = size >= ScreenSize.expanded;
    final demo = ref.watch(isDemoModeProvider);

    final body = Column(
      children: [
        if (demo)
          Material(
            color: Brand.amber.withValues(alpha: 0.16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.science_rounded, size: 16, color: Brand.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Demo mode – data is stored on this device only. Connect Supabase to go live.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: child),
        const OfflineBanner(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => context.go(_dests[i].path),
              extended: size == ScreenSize.large,
              labelType: size == ScreenSize.large ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 8),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: Brand.primaryGradient, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.hub_rounded, color: Colors.white),
                ),
              ),
              destinations: [
                for (final d in _dests)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: body),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_dests[i].path),
        destinations: [
          for (final d in _dests)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}


/// Shows when any list on screen is the saved copy, not fresh data.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(offlineSinceProvider);
    if (since.isEmpty) return const SizedBox.shrink();
    final oldest = since.values.reduce((a, b) => a.isBefore(b) ? a : b);
    final mins = DateTime.now().difference(oldest).inMinutes;
    final age = mins < 1 ? 'just now' : mins < 60 ? '$mins min ago' : mins < 1440 ? '${mins ~/ 60} h ago' : '${mins ~/ 1440} days ago';
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.inverseSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: s.onInverseSurface),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Offline · showing what you saw $age',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: s.onInverseSurface, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => retryOffline(ref),
            child: Text('Try again', style: TextStyle(color: s.inversePrimary)),
          ),
        ]),
      ),
    );
  }
}
