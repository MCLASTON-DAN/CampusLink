import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/community_models.dart';
import '../../data/providers.dart';
import '../../widgets/section.dart';

final _daysProvider = StateProvider.autoDispose<int>((ref) => 30);
final _insightsProvider = FutureProvider.autoDispose<List<PostInsight>>(
    (ref) => ref.watch(communityProvider).postInsights(days: ref.watch(_daysProvider)));

/// View details: how many people opened each post. Each person counts once.
/// Only the office that posted and administrators can see this page's numbers.
class PostInsightsScreen extends ConsumerWidget {
  const PostInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_daysProvider);
    final data = ref.watch(_insightsProvider);
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final nf = NumberFormat.compact();
    return Scaffold(
      appBar: AppBar(title: const Text('View details')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_insightsProvider),
        child: PageBody(maxWidth: 900, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 30, label: Text('30 days')),
              ButtonSegment(value: 90, label: Text('90 days')),
            ],
            selected: {days},
            onSelectionChanged: (v) => ref.read(_daysProvider.notifier).state = v.first,
          ),
          const SizedBox(height: 12),
          ...data.when(
            loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load: $e'))],
            data: (list) {
              if (list.isEmpty) {
                return [
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No posts in this period yet. When your office posts, you will see here how many people opened each one.',
                        textAlign: TextAlign.center),
                  ),
                ];
              }
              final total = list.fold<int>(0, (a, b) => a + b.views);
              final top = list.reduce((a, b) => a.views >= b.views ? a : b);
              Widget stat(String label, String value, IconData icon) => Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(icon, color: s.primary),
                          const SizedBox(height: 6),
                          FittedBox(child: Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                          Text(label, style: t.bodySmall, maxLines: 2),
                        ]),
                      ),
                    ),
                  );
              return [
                Row(children: [
                  stat('Posts', '${list.length}', Icons.article_outlined),
                  stat('People reached', nf.format(total), Icons.visibility_outlined),
                  stat('Average per post', nf.format(total / list.length), Icons.bar_chart_rounded),
                ]),
                const SizedBox(height: 4),
                Text('Most opened: "${top.title}" (${top.views})', style: t.bodySmall),
                const SectionTitle('Each post'),
                for (final p in list)
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/news/${p.postId}'),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text('${p.publisherName} · ${DateFormat('d MMM y, HH:mm').format(p.publishedAt.toLocal())}', style: t.bodySmall),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: top.views == 0 ? 0 : p.views / top.views, minHeight: 6),
                          ),
                          const SizedBox(height: 10),
                          Wrap(spacing: 16, runSpacing: 6, children: [
                            _Num(Icons.visibility_outlined, '${p.views} opened'),
                            _Num(Icons.schedule_rounded, '${p.views24h} in 24 h'),
                            _Num(Icons.date_range_rounded, '${p.views7d} in 7 days'),
                            _Num(Icons.favorite_border_rounded, '${p.likes} likes'),
                            _Num(Icons.chat_bubble_outline_rounded, '${p.comments} comments'),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('Each person is counted once per post. Other students never see these numbers.',
                    style: t.bodySmall, textAlign: TextAlign.center),
              ];
            },
          ),
        ]),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
