import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/section.dart';
import '../community/events_screens.dart';
import '../community/more_screens.dart';
import '../community/news_screen.dart';

/// Feed: everything people publish, in one scrollable place.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Feed'),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'News'), Tab(text: 'Events'), Tab(text: 'Surveys')],
            ),
          ),
          body: const TabBarView(children: [
            NewsScreen(embedded: true),
            EventsListScreen(embedded: true),
            SurveysScreen(embedded: true),
          ]),
        ),
      );
}

/// Campus: finding places and getting help.
class CampusHubScreen extends ConsumerWidget {
  const CampusHubScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(myRequestsProvider).valueOrNull?.where((r) => r.status != RequestStatus.resolved && r.status != RequestStatus.closed).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Campus')),
      body: PageBody(children: [
        _SearchEntry(onTap: () => context.push('/where')),
        const SectionTitle('Find your way'),
        TileGrid(children: [
          ActionTile(icon: Icons.map_rounded, title: 'Campus map', subtitle: 'Offices on the map, open or closed now', color: const Color(0xFF0EA5E9), onTap: () => context.push('/map')),
          ActionTile(icon: Icons.apartment_rounded, title: 'Offices', subtitle: 'What each office does and what to bring', color: const Color(0xFF14B8A6), onTap: () => context.push('/directory')),
          ActionTile(icon: Icons.location_city_rounded, title: 'Campuses', subtitle: 'Where each campus is', color: const Color(0xFF6366F1), onTap: () => context.push('/campuses')),
        ]),
        const SectionTitle('Get help'),
        TileGrid(children: [
          ActionTile(icon: Icons.support_agent_rounded, title: 'Help requests', subtitle: 'Ask an office and track the answer', color: const Color(0xFFF97316), badge: open > 0 ? '$open' : null, onTap: () => context.push('/requests')),
          ActionTile(icon: Icons.inventory_2_rounded, title: 'Lost & found', subtitle: 'Items kept by offices. Prove it is yours', color: const Color(0xFFDB2777), onTap: () => context.push('/lostfound')),
          ActionTile(icon: Icons.campaign_rounded, title: 'Announcements', subtitle: 'Official notices for your faculty and year', color: const Color(0xFF3B2DB3), onTap: () => context.push('/announcements')),
          ActionTile(icon: Icons.groups_2_rounded, title: 'Clubs & feedback', subtitle: 'Join clubs, tell the university what to fix', color: const Color(0xFF059669), onTap: () => context.push('/engage')),
        ]),
      ]),
    );
  }
}

/// Study: learning with other people.
class StudyHubScreen extends StatelessWidget {
  const StudyHubScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Study')),
        body: PageBody(children: [
          const SectionTitle('Learn together'),
          TileGrid(children: [
            ActionTile(icon: Icons.school_rounded, title: 'Tutors', subtitle: 'Fair ratings from real lessons, prices per module', color: const Color(0xFF1E88E5), onTap: () => context.push('/tutors')),
            ActionTile(icon: Icons.groups_rounded, title: 'Study groups', subtitle: 'Join or start a group for your course', color: const Color(0xFF059669), onTap: () => context.push('/groups')),
            ActionTile(icon: Icons.assignment_ind_rounded, title: 'My lessons', subtitle: 'Requests, confirmations and reviews', color: const Color(0xFF7C3AED), onTap: () => context.push('/tutors/mine')),
          ]),
          const SectionTitle('Your week'),
          TileGrid(children: [
            ActionTile(icon: Icons.calendar_month_rounded, title: 'Timetable', subtitle: 'Your classes. Import from Excel or CSV', color: const Color(0xFF3B2DB3), onTap: () => context.go('/timetable')),
            ActionTile(icon: Icons.event_note_rounded, title: 'Exams', subtitle: 'Real dates, clashes and reminders', color: const Color(0xFFB91C1C), onTap: () => context.go('/exams')),
            ActionTile(icon: Icons.menu_book_rounded, title: 'Course units', subtitle: 'Notices from your lecturers, only for your units', color: const Color(0xFFF97316), onTap: () => context.go('/courses')),
            ActionTile(icon: Icons.handshake_rounded, title: 'First-year buddy', subtitle: 'Get matched with a senior mentor', color: const Color(0xFFF59E0B), onTap: () => context.push('/buddy')),
            ActionTile(icon: Icons.monitor_heart_rounded, title: 'Campus pulse', subtitle: 'Quick anonymous polls', color: const Color(0xFFDB2777), onTap: () => context.push('/pulse')),
          ]),
        ]),
      );
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(Icons.search_rounded, color: s.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('Where do I go to… pay fees, get a transcript', style: TextStyle(color: s.onSurfaceVariant))),
          ]),
        ),
      ),
    );
  }
}

// Re-exported so the router file stays tidy.
typedef CommunityHub = CommunityHubScreen;
