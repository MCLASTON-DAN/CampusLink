import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/community_models.dart';
import '../../data/providers.dart';
import '../../widgets/section.dart';

final _overviewProvider = FutureProvider.autoDispose<AdminOverview>((ref) => ref.watch(communityProvider).adminOverview());

/// The platform at a glance, for staff and the super admin.
/// Every "needs attention" number is a button to the place to deal with it.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_overviewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_overviewProvider),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(24), child: Text('$e'.replaceFirst('Exception: ', ''))),
          ]),
          data: (o) => PageBody(maxWidth: 1000, children: [
            const SectionTitle('People'),
            _Tiles([
              ('Members', o.n('users_total'), '+${o.n('users_new_7d')} this week', Icons.people_alt_rounded, null),
              ('Active today', o.n('active_today'), 'opened the app', Icons.bolt_rounded, null),
              ('Active this week', o.n('active_7d'), 'different people', Icons.calendar_view_week_rounded, null),
            ]),
            const SizedBox(height: 12),
            _ActiveChart(o.dailyActive),
            const SectionTitle('Needs attention'),
            _Tiles([
              ('Reported content', o.n('open_reports'), 'waiting for a decision', Icons.flag_rounded, '/reports'),
              ('Tutor reports', o.n('open_tutor_reports'), 'open', Icons.report_gmailerrorred_rounded, '/tutor-reports'),
              ('Major event requests', o.n('major_requests'), 'need your approval', Icons.star_rounded, '/events/requests'),
              ('Lost & found claims', o.n('pending_claims'), 'pending', Icons.inventory_2_rounded, '/lostfound'),
              ('Help requests', o.n('open_help'), 'open or in progress', Icons.support_agent_rounded, '/requests'),
              ('Terms ending', o.n('terms_ending_14d'), 'in the next 14 days', Icons.badge_rounded, '/members'),
            ], highlight: true),
            const SectionTitle('News this week'),
            _Tiles([
              ('Posts', o.n('posts_7d'), 'published', Icons.article_rounded, '/insights'),
              ('Post opens', o.n('views_7d'), 'each person once', Icons.visibility_rounded, '/insights'),
              ('Upcoming events', o.n('upcoming_events'), 'from today', Icons.event_rounded, '/feed?tab=1'),
            ]),
            if (o.topPosts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  const ListTile(title: Text('Most opened this week', style: TextStyle(fontWeight: FontWeight.w700))),
                  for (final (i, p) in o.topPosts.indexed)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                      title: Text(p.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text('${p.$3}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => context.push('/news/${p.$1}'),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Text('Counts only. The dashboard never shows who opened the app or what any one person read.',
                style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles(this.items, {this.highlight = false});
  final List<(String, int, String, IconData, String?)> items;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (label, n, sub, icon, route) in items)
          SizedBox(
            width: w,
            child: Card(
              margin: EdgeInsets.zero,
              color: highlight && n > 0 ? s.errorContainer.withValues(alpha: 0.5) : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: route == null ? null : () => context.push(route),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(icon, size: 20, color: highlight && n > 0 ? s.error : s.primary),
                      const Spacer(),
                      if (route != null) Icon(Icons.chevron_right_rounded, size: 18, color: s.outline),
                    ]),
                    const SizedBox(height: 8),
                    Text(NumberFormat.compact().format(n), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(label, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(sub, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

/// Bars for the last 14 days of active users.
class _ActiveChart extends StatelessWidget {
  const _ActiveChart(this.days);
  final List<(DateTime, int)> days;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final max = days.fold<int>(1, (a, b) => b.$2 > a ? b.$2 : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Active people, last 14 days', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (d, n) in days)
                Expanded(
                  child: Tooltip(
                    message: '${DateFormat('EEE d MMM').format(d)}: $n',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (n > 0) FittedBox(child: Text('$n', style: t.labelSmall)),
                        const SizedBox(height: 2),
                        Container(
                          height: 90 * n / max + 2,
                          decoration: BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(4)),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            if (days.isNotEmpty) Text(DateFormat('d MMM').format(days.first.$1), style: t.labelSmall),
            const Spacer(),
            Text('Today', style: t.labelSmall),
          ]),
        ]),
      ),
    );
  }
}
