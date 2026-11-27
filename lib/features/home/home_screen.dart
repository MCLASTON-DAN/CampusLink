import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications.dart';
import '../../widgets/media.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../account/interests.dart';
import '../../widgets/section.dart';
import '../community/events_screens.dart';
import '../community/news_screen.dart';
import '../install/install_screen.dart';

/// Home: what matters today, in the order a student needs it.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final timetable = ref.watch(timetableProvider);
    final posts = ref.watch(postsProvider(null));
    final events = ref.watch(eventListProvider);
    final announcements = ref.watch(announcementsProvider);

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final firstName = (user?.fullName ?? '').split(' ').first;
    final today = DateTime.now().weekday;
    final todayClasses = (timetable.valueOrNull ?? const <TimetableEntry>[])
        .where((e) => e.dayOfWeek == today)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    // SafeArea keeps the greeting below the phone's clock/battery bar.
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsProvider);
          ref.invalidate(timetableProvider);
          ref.invalidate(postsProvider(null));
          ref.invalidate(eventListProvider);
          ref.invalidate(featuredEventsProvider);
        },
        child: PageBody(children: [
          // Greeting
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 14),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(friendlyDay(DateTime.now()), style: t.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                          '$greeting${firstName.isEmpty ? '' : ', $firstName'}',
                          style: t.headlineSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              const NotificationBell(),
              const SizedBox(width: 4),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go('/profile'),
                child: ClipOval(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: user?.avatarPath != null
                        ? NetPicture(user!.avatarPath!, alwaysLoad: true)
                        : Container(
                            color: s.primary.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child: Text(
                                firstName.isEmpty
                                    ? '?'
                                    : firstName[0].toUpperCase(),
                                style: TextStyle(
                                    color: s.primary,
                                    fontWeight: FontWeight.w900)),
                          ),
                  ),
                ),
              ),
            ]),
          ),

          // Search
          Card(
            child: InkWell(
              onTap: () => context.go('/where'),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Icon(Icons.search_rounded, color: s.primary),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('Where do I go to…',
                          style: TextStyle(color: s.onSurfaceVariant))),
                ]),
              ),
            ),
          ),

          if (shouldSuggestInstall()) ...[
            const SizedBox(height: 12),
            const _InstallBanner()
          ],

          // Quick actions
          const SizedBox(height: 18),
          const _QuickActions(),

          // Major events (max 2, from 24h before)
          const SizedBox(height: 8),
          const FeaturedEventsBanner(),

          // Today
          if (todayClasses.isNotEmpty) ...[
            SectionTitle('Today · ${dayName(today)}',
                action: 'Timetable', onAction: () => context.go('/timetable')),
            SizedBox(
              // Grows with the student's text-size setting so nothing is cut off.
              height: 122 *
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: todayClasses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final c = todayClasses[i];
                  return SizedBox(
                    width: 220,
                    child: Card(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                            border: Border(
                                left: BorderSide(color: Brand.teal, width: 4))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${c.startTime} – ${c.endTime}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Brand.teal)),
                              const SizedBox(height: 4),
                              Text(c.courseName ?? c.courseCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.titleSmall),
                              Text('${c.courseCode} · ${c.room ?? ''}',
                                  style: t.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // News
          SectionTitle('Latest news',
              action: 'See all', onAction: () => context.go('/feed')),
          AsyncBody(
            value: posts,
            onRetry: () => ref.invalidate(postsProvider(null)),
            builder: (list) => list.isEmpty
                ? const _Quiet('No news yet. Verified offices will post here.')
                : _ResponsiveRow(children: [
                    for (final p in list.take(6)) PostCard(p, compact: true)
                  ]),
          ),

          // Events
          SectionTitle('Coming up',
              action: 'All events', onAction: () => context.go('/feed?tab=1')),
          AsyncBody(
            value: events,
            onRetry: () => ref.invalidate(eventListProvider),
            builder: (list) {
              final now = DateTime.now();
              final up = list
                  .where(
                      (e) => e.status == 'published' && e.startsAt.isAfter(now))
                  .toList()
                ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
              if (up.isEmpty) return const _Quiet('No upcoming events.');
              // Events matching the topics they follow come first (within the
              // next 2 weeks, so nothing far away hides tomorrow's event).
              final likes = user?.interests ?? const <String>[];
              if (likes.isNotEmpty) {
                final soon = now.add(const Duration(days: 14));
                bool match(CampusEvent e) => e.startsAt.isBefore(soon) && matchesInterests('${e.title} ${e.topic ?? ''} ${e.description}', likes);
                final picked = [...up.where(match), ...up.where((e) => !match(e))];
                up
                  ..clear()
                  ..addAll(picked);
              }
              return TileGrid(children: [
                for (final e in up.take(3)) EventCard(e, compact: true)
              ]);
            },
          ),

          // Announcements
          SectionTitle('Announcements',
              action: 'See all', onAction: () => context.go('/announcements')),
          AsyncBody(
            value: announcements,
            onRetry: () => ref.invalidate(announcementsProvider),
            builder: (list) => list.isEmpty
                ? const _Quiet('No announcements.')
                : Card(
                    child: Column(children: [
                      for (final (i, a) in list.take(3).indexed) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          onTap: () => context.go('/announcements'),
                          leading: CircleAvatar(
                            backgroundColor: categoryColor(a.category)
                                .withValues(alpha: 0.12),
                            child: Icon(categoryIcon(a.category),
                                color: categoryColor(a.category), size: 20),
                          ),
                          title: Text(a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall),
                          subtitle: TimeStamp(a.createdAt),
                          trailing: a.isPinned
                              ? const Icon(Icons.push_pin_rounded,
                                  size: 18, color: Brand.coral)
                              : null,
                        ),
                      ],
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

String friendlyDay(DateTime d) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String dayName(int weekday) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ][weekday - 1];

class _QuickActions extends StatelessWidget {
  const _QuickActions();
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.map_rounded, 'Map', '/map', const Color(0xFF0EA5E9)),
      (
        Icons.support_agent_rounded,
        'Get help',
        '/requests',
        const Color(0xFFF97316)
      ),
      (Icons.school_rounded, 'Tutors', '/tutors', const Color(0xFF1E88E5)),
      (
        Icons.inventory_2_rounded,
        'Lost & found',
        '/lostfound',
        const Color(0xFFDB2777)
      ),
      (Icons.poll_rounded, 'Surveys', '/feed?tab=2', const Color(0xFF7C3AED)),
      (
        Icons.calendar_month_rounded,
        'Timetable',
        '/timetable',
        const Color(0xFF059669)
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      // Phones scroll sideways; wider screens show all six evenly.
      final fits = c.maxWidth >= 6 * 92;
      final children = [
        for (final it in items)
          SizedBox(
            width: fits ? c.maxWidth / 6 : 84,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => it.$3.startsWith('/feed') || it.$3 == '/timetable'
                  ? context.go(it.$3)
                  : context.push(it.$3),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: it.$4.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(it.$1, color: it.$4),
                  ),
                  const SizedBox(height: 6),
                  Text(it.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium),
                ]),
              ),
            ),
          ),
      ];
      return fits
          ? Row(children: children)
          : SizedBox(
              height: 92 *
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6),
              child: ListView(
                  scrollDirection: Axis.horizontal, children: children),
            );
    });
  }
}

/// Phones: a sideways carousel. Bigger screens: a neat grid.
class _ResponsiveRow extends StatelessWidget {
  const _ResponsiveRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 700 && isWideLayout(context, 700)) {
          final cols = c.maxWidth >= 1000 ? 3 : 2;
          const gap = 12.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final ch in children.take(cols * 2))
              SizedBox(width: w, child: ch)
          ]);
        }
        final w = (c.maxWidth * 0.82).clamp(240.0, 340.0);
        return SizedBox(
          height: w * 9 / 16 +
              190 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
                width: w,
                child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: children[i])),
          ),
        );
      });
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      );
}

class _InstallBanner extends StatefulWidget {
  const _InstallBanner();
  @override
  State<_InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<_InstallBanner> {
  static bool _hidden = false; // hidden for this visit once closed
  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return GradientCard(
      gradient: Brand.primaryGradient,
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      radius: 16,
      onTap: () => context.push('/install'),
      child: Row(children: [
        const Icon(Icons.install_mobile_rounded, color: Colors.white),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Install CampusLink for a faster, full-screen app',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: 'Not now',
          onPressed: () => setState(() => _hidden = true),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ]),
    );
  }
}
