import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/person_picker.dart';
import '../../widgets/common.dart';
import 'tutor_checks.dart';

Future<void> _run(BuildContext context, Future<void> Function() f, {String? ok}) async {
  try {
    await f();
    if (ok != null && context.mounted) showSnack(context, ok);
  } on CommunityException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  }
}

Future<String?> _prompt(BuildContext context, String title, {int min = 1, String? hint}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(hintText: hint, helperText: 'At least $min letters')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ],
    ),
  );
  if (ok != true) return null;
  if (c.text.trim().length < min) {
    if (context.mounted) showSnack(context, 'Please write at least $min letters.');
    return null;
  }
  return c.text.trim();
}

// ------------------------------------------------------------ hub
class CommunityHubScreen extends ConsumerWidget {
  const CommunityHubScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive).toList();
    Widget tile(IconData i, String t, String s, String path) =>
        Card(child: ListTile(leading: Icon(i), title: Text(t), subtitle: Text(s), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(path)));
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        tile(Icons.newspaper_rounded, 'Campus news', 'Verified posts and clarifications', '/news'),
        tile(Icons.event_rounded, 'Events', 'Countdowns, speakers, online links', '/events'),
        tile(Icons.map_rounded, 'Campus map', 'Offices, hours, directions', '/map'),
        tile(Icons.location_city_rounded, 'Campuses', 'Where each campus is', '/campuses'),
        tile(Icons.inventory_2_rounded, 'Lost & found', 'Items held by offices', '/lostfound'),
        tile(Icons.poll_rounded, 'Surveys', 'Anonymous, one answer each', '/surveys'),
        tile(Icons.school_rounded, 'Tutors', 'Fair ratings, real reviews', '/tutors'),
        tile(Icons.gavel_rounded, 'Removal log', 'Everything removed, and why', '/moderation'),
        if (mems.isNotEmpty || (me?.isStaff ?? false)) ...[
          const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 4), child: Text('For offices')),
          if (mems.any((m) => m.can('manage_members')) || (me?.isSuperAdmin ?? false))
            tile(Icons.badge_rounded, 'Office members', 'Appoint people, up to 12 months', '/members'),
          if (me?.isStaff ?? false) tile(Icons.flag_rounded, 'Reports', 'What students flagged', '/reports'),
          if (me?.isSuperAdmin ?? false) tile(Icons.approval_rounded, 'Major event requests', 'Super admin only', '/events/requests'),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------ lost & found
class LostFoundScreen extends ConsumerWidget {
  const LostFoundScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(communityProvider);
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive && m.can('lost_found')).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Lost & found')),
      floatingActionButton: mems.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
              onPressed: () async {
                final t = TextEditingController(), d = TextEditingController(), w = TextEditingController(), s = TextEditingController(text: kLostFoundDropOff);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Item found'),
                    content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(controller: t, decoration: const InputDecoration(labelText: 'What is it?')),
                        TextField(controller: d, decoration: const InputDecoration(labelText: 'Description (leave out secret details)')),
                        TextField(controller: w, decoration: const InputDecoration(labelText: 'Found where?')),
                        TextField(controller: s, decoration: const InputDecoration(labelText: 'Kept at (office)')),
                      ]),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await _run(context, () => api.addLostFound(publisherId: mems.first.publisherId, title: t.text, description: d.text, foundWhere: w.text, storedAt: s.text));
                ref.invalidate(lostFoundProvider);
              },
            ),
      body: AsyncBody(
        value: ref.watch(lostFoundProvider),
        onRetry: () => ref.invalidate(lostFoundProvider),
        builder: (list) => list.isEmpty
            ? ListView(padding: const EdgeInsets.all(12), children: const [
                _HandInNotice(),
                EmptyState(icon: Icons.inventory_2_outlined, title: 'Nothing listed', subtitle: 'Only offices post found items.'),
              ])
            : ListView(padding: const EdgeInsets.all(12), children: [
                const _HandInNotice(),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('To get an item back, say something only the owner knows. The office checks before handing it over.'),
                ),
                for (final i in list)
                  Card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ListTile(
                      title: Text(i.title),
                      subtitle: Text('${i.description}\nFound: ${i.foundWhere}\nKept at: ${i.storedAt}'),
                      isThreeLine: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: i.status != 'held'
                          ? const StatusChip('Returned', color: Colors.green)
                          : i.myClaimStatus != null
                              ? StatusChip('Claim ${i.myClaimStatus}', color: Colors.orange)
                              : mems.isNotEmpty
                                  ? TextButton(onPressed: () => context.push('/lostfound/${i.id}'), child: const Text('Claims'))
                                  : FilledButton(
                                      onPressed: () async {
                                        final p = await _prompt(context, 'Proof this is yours', min: 20, hint: 'Colour, marks, what is inside…');
                                        if (p == null || !context.mounted) return;
                                        await _run(context, () => api.claimItem(i.id, p), ok: 'Sent. The office will check.');
                                        ref.invalidate(lostFoundProvider);
                                      },
                                      child: const Text('This is mine')),
                    ),
                    ]),
                  ),
              ]),
      ),
    );
  }
}

class ClaimsScreen extends ConsumerStatefulWidget {
  const ClaimsScreen({super.key, required this.itemId});
  final String itemId;
  @override
  ConsumerState<ClaimsScreen> createState() => _ClaimsState();
}

class _ClaimsState extends ConsumerState<ClaimsScreen> {
  late Future<List<LostFoundClaim>> _f = ref.read(communityProvider).claimsFor(widget.itemId);
  @override
  Widget build(BuildContext context) {
    final api = ref.read(communityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Claims')),
      body: FutureBuilder(
        future: _f,
        builder: (_, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final l = s.data!;
          if (l.isEmpty) return const EmptyState(icon: Icons.inbox_rounded, title: 'No claims yet');
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final c in l)
              Card(
                child: ListTile(
                  title: Text(c.claimantName),
                  subtitle: Text('Proof: ${c.proof}\nStatus: ${c.status}'),
                  isThreeLine: true,
                  trailing: c.status == 'pending'
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () async {
                                await _run(context, () => api.decideClaim(c.id, approve: true));
                                if (mounted) setState(() => _f = api.claimsFor(widget.itemId));
                                ref.invalidate(lostFoundProvider);
                              }),
                          IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.redAccent),
                              onPressed: () async {
                                await _run(context, () => api.decideClaim(c.id, approve: false));
                                if (mounted) setState(() => _f = api.claimsFor(widget.itemId));
                              }),
                        ])
                      : null,
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------ surveys
class SurveysScreen extends ConsumerWidget {
  const SurveysScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive && m.can('surveys')).toList();
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Surveys')),
      floatingActionButton: mems.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Survey'),
              onPressed: () async {
                await context.push('/surveys/new');
                ref.invalidate(surveysProvider);
              }),
      body: AsyncBody(
        value: ref.watch(surveysProvider),
        onRetry: () => ref.invalidate(surveysProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.poll_outlined, title: 'No surveys right now')
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final s in list)
                  Card(
                    child: ListTile(
                      title: Text(s.title),
                      subtitle: Text('${s.publisherName}\n${s.purpose}\nCloses ${DateFormat('d MMM').format(s.closesAt)}'),
                      isThreeLine: true,
                      trailing: s.takenByMe
                          ? const StatusChip('Done', color: Colors.green)
                          : s.isOpen
                              ? const Icon(Icons.chevron_right)
                              : const StatusChip('Closed', color: Colors.grey),
                      onTap: () async {
                        if (s.mine || !s.isOpen || s.takenByMe) {
                          if (s.mine || s.takenByMe) {
                            context.push('/surveys/${s.id}/results');
                          }
                          return;
                        }
                        await context.push('/surveys/${s.id}');
                        ref.invalidate(surveysProvider);
                      },
                    ),
                  ),
              ]),
      ),
    );
  }
}

class TakeSurveyScreen extends ConsumerStatefulWidget {
  const TakeSurveyScreen({super.key, required this.surveyId});
  final String surveyId;
  @override
  ConsumerState<TakeSurveyScreen> createState() => _TakeState();
}

class _TakeState extends ConsumerState<TakeSurveyScreen> {
  final _ans = <String, dynamic>{};
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(surveysProvider).valueOrNull?.where((x) => x.id == widget.surveyId).firstOrNull;
    if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Your answers are anonymous. Nobody can see who said what. You can answer once.'))),
        for (final q in s.questions) ...[
          const SizedBox(height: 14),
          Text(q.prompt, style: Theme.of(context).textTheme.titleSmall),
          if (q.kind == 'single' || q.kind == 'scale')
            for (final o in (q.kind == 'scale' && q.options.isEmpty ? ['1', '2', '3', '4', '5'] : q.options))
              RadioListTile<String>(dense: true, title: Text(o), value: o, groupValue: _ans[q.id] as String?, onChanged: (v) => setState(() => _ans[q.id] = v))
          else if (q.kind == 'multi')
            for (final o in q.options)
              CheckboxListTile(
                dense: true,
                title: Text(o),
                value: ((_ans[q.id] as List?) ?? []).contains(o),
                onChanged: (v) => setState(() {
                  final l = List<String>.from((_ans[q.id] as List?) ?? []);
                  v == true ? l.add(o) : l.remove(o);
                  _ans[q.id] = l;
                }),
              )
          else
            TextField(maxLines: 3, onChanged: (v) => _ans[q.id] = v),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            await _run(context, () => ref.read(communityProvider).submitSurvey(s.id, _ans), ok: 'Thank you!');
            if (context.mounted) context.pop();
          },
          child: const Text('Send answers'),
        ),
      ]),
    );
  }
}

class SurveyResultsScreen extends ConsumerWidget {
  const SurveyResultsScreen({super.key, required this.surveyId});
  final String surveyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(surveysProvider).valueOrNull?.where((x) => x.id == surveyId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(s?.title ?? 'Results')),
      body: FutureBuilder(
        future: ref.read(communityProvider).surveyResults(surveyId),
        builder: (_, snap) {
          if (snap.hasError) return EmptyState(icon: Icons.lock_clock, title: 'Results hidden', subtitle: 'They show after 5 people have answered, so nobody can be identified.\n${snap.error is CommunityException ? (snap.error as CommunityException).message : ''}');
          if (!snap.hasData || s == null) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const EmptyState(icon: Icons.lock_clock, title: 'Results hidden', subtitle: 'They show after 5 people have answered.');
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final q in s.questions) ...[
              Text(q.prompt, style: Theme.of(context).textTheme.titleSmall),
              for (final r in rows.where((r) => r.questionId == q.id))
                ListTile(dense: true, title: Text(r.answer), trailing: Text('${r.n}')),
              const SizedBox(height: 10),
            ],
          ]);
        },
      ),
    );
  }
}

class CreateSurveyScreen extends ConsumerStatefulWidget {
  const CreateSurveyScreen({super.key});
  @override
  ConsumerState<CreateSurveyScreen> createState() => _CreateSurveyState();
}

class _CreateSurveyState extends ConsumerState<CreateSurveyScreen> {
  final _title = TextEditingController(), _purpose = TextEditingController();
  final _qs = <(TextEditingController, TextEditingController, String)>[];
  DateTime _closes = DateTime.now().add(const Duration(days: 7));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New survey')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 8),
        TextField(controller: _purpose, maxLines: 2, decoration: const InputDecoration(labelText: 'Why are you asking? (students see this)')),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Closes ${DateFormat('d MMM y').format(_closes)}'),
            trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _closes, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                  if (d != null) setState(() => _closes = d);
                },
                child: const Text('Change'))),
        for (var i = 0; i < _qs.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                TextField(controller: _qs[i].$1, decoration: InputDecoration(labelText: 'Question ${i + 1}')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
            initialValue: _qs[i].$3,
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('Pick one')),
                    DropdownMenuItem(value: 'multi', child: Text('Pick many')),
                    DropdownMenuItem(value: 'scale', child: Text('Scale 1-5')),
                    DropdownMenuItem(value: 'text', child: Text('Written answer')),
                  ],
                  onChanged: (v) => setState(() => _qs[i] = (_qs[i].$1, _qs[i].$2, v ?? 'single')),
                ),
                if (_qs[i].$3 == 'single' || _qs[i].$3 == 'multi')
                  TextField(controller: _qs[i].$2, decoration: const InputDecoration(labelText: 'Options, separated by commas')),
              ]),
            ),
          ),
        TextButton.icon(
            onPressed: _qs.length >= 15 ? null : () => setState(() => _qs.add((TextEditingController(), TextEditingController(), 'single'))),
            icon: const Icon(Icons.add),
            label: Text('Add question (${_qs.length}/15)')),
        FilledButton(
          onPressed: () async {
            final mem = (ref.read(myMembershipsProvider).valueOrNull ?? []).firstWhere((m) => m.isActive && m.can('surveys'));
            if (_title.text.trim().length < 5) return showSnack(context, 'Give the survey a title (5+ letters).');
            if (_purpose.text.trim().length < 30) return showSnack(context, 'Explain why you are asking (30+ letters). Students see this.');
            if (_qs.isEmpty || _qs.any((q) => q.$1.text.trim().length < 3)) return showSnack(context, 'Add at least one question, each 3+ letters.');
            if (_qs.any((q) => (q.$3 == 'single' || q.$3 == 'multi') && q.$2.text.split(',').where((o) => o.trim().isNotEmpty).length < 2)) {
              return showSnack(context, 'Pick-one and pick-many questions need at least 2 options.');
            }
            final qs = [
              for (var i = 0; i < _qs.length; i++)
                SurveyQuestion(
                  id: '',
                  position: i + 1,
                  prompt: _qs[i].$1.text.trim(),
                  kind: _qs[i].$3,
                  options: _qs[i].$3 == 'scale' || _qs[i].$3 == 'text' ? const [] : _qs[i].$2.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                ),
            ];
            await _run(context, () async {
              await ref.read(communityProvider).createSurvey(publisherId: mem.publisherId, title: _title.text, purpose: _purpose.text, closesAt: _closes, questions: qs);
              if (context.mounted) context.pop();
            });
          },
          child: const Text('Open survey'),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ tutors
class TutorsScreen extends ConsumerStatefulWidget {
  const TutorsScreen({super.key});
  @override
  ConsumerState<TutorsScreen> createState() => _TutorsScreenState();
}

class _TutorsScreenState extends ConsumerState<TutorsScreen> {
  final _q = TextEditingController();
  String get _query => _q.text.trim().toLowerCase().replaceFirst('@', '');

  /// Search finds any tutor (also New ones) by name, @username or unit.
  bool _matches(TutorCard t) {
    final q = _query;
    if (q.isEmpty) return true;
    final code = normCode(q).toLowerCase();
    return t.name.toLowerCase().contains(q) ||
        (t.username ?? '').toLowerCase().contains(q) ||
        t.modules.any((m) => m.courseCode.toLowerCase().contains(code) || (m.courseName ?? '').toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    final searching = _query.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Tutors'), actions: [
        IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'What the levels mean', onPressed: () => showTutorLevels(context)),
        IconButton(icon: const Icon(Icons.assignment_ind_outlined), tooltip: 'My lessons', onPressed: () => context.push('/tutors/mine')),
      ]),
      body: AsyncBody(
        value: ref.watch(tutorCardsProvider),
        onRetry: () => ref.invalidate(tutorCardsProvider),
        builder: (all) {
          // Suggestions: level 2+ only, showing only the units that were checked.
          // Search: everyone who matches, with every unit and a clear label.
          final list = searching ? all.where(_matches).toList() : all.where((t) => t.suggested).toList();
          return ListView(padding: const EdgeInsets.all(12), children: [
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search a name, @username or unit (e.g. BDA2207)',
                suffixIcon: searching
                    ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_q.clear))
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Showing every tutor who matches, including new ones whose grades are not checked yet.'
                  : 'Suggested tutors: a lecturer or staff member checked their results. Search to find anyone else.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              EmptyState(
                icon: Icons.school_outlined,
                title: searching ? 'No tutor matches' : 'No suggested tutors yet',
                subtitle: searching ? null : 'Tutors appear here once their grades are checked. Search to find new tutors.',
              ),
            for (final t in list)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      NameWithBadge(t.name, t.verified ? 'blue' : null, style: Theme.of(context).textTheme.titleMedium),
                      if ((t.username ?? '').isNotEmpty) Text('@${t.username}', style: Theme.of(context).textTheme.bodySmall),
                      if (t.reviews > 0) Text('★ ${t.score.toStringAsFixed(2)}  (${t.reviews})', style: const TextStyle(fontWeight: FontWeight.w700)) else const Text('No reviews yet'),
                      TutorLevelChip(t),
                    ]),
                    if (t.levelNo == 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('New tutor: grades are typed in by the tutor and not checked yet.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                      ),
                    if (t.bio.isNotEmpty) Text(t.bio),
                    if (t.availability.isNotEmpty) Text('Free: ${t.availability}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    OutcomeBar(t),
                    const SizedBox(height: 6),
                    for (final m in t.modules.where((m) => searching || m.gradeChecked))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(m.gradeChecked ? Icons.verified_rounded : Icons.help_outline_rounded,
                            color: m.gradeChecked ? const Color(0xFF14A44D) : Colors.grey, size: 20),
                        title: Text('${m.courseCode}${m.courseName == null ? '' : ' · ${m.courseName}'}'),
                        subtitle: Text('UGX ${fmt.format(m.priceUgx)} per hour'
                            '${m.grade == null ? '' : m.gradeChecked ? ' · grade ${m.grade} (checked)' : ' · says grade ${m.grade} (not checked)'}'),
                        trailing: TextButton(
                          onPressed: () async {
                            final msg = await _prompt(context, 'Message to ${t.name}', min: 5, hint: 'When are you free? What do you need help with?');
                            if (msg == null || !context.mounted) return;
                            await _run(context, () => ref.read(communityProvider).requestTutor(tutorId: t.tutorId, courseCode: m.courseCode, message: msg), ok: 'Request sent');
                          },
                          child: const Text('Ask'),
                        ),
                      ),
                    if ((t.contact ?? '').isNotEmpty)
                      TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse('https://wa.me/${t.contact!.replaceAll(RegExp(r'[^0-9]'), '')}')),
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('WhatsApp')),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class MyLessonsScreen extends ConsumerWidget {
  const MyLessonsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final api = ref.read(communityProvider);
    void refresh() => ref.invalidate(myTutorRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My lessons')),
      body: AsyncBody(
        value: ref.watch(myTutorRequestsProvider),
        builder: (list) => ListView(padding: const EdgeInsets.all(12), children: [
          if (me?.isTutor == true || true)
            OutlinedButton.icon(onPressed: () => context.push('/tutors/profile'), icon: const Icon(Icons.edit), label: const Text('My tutor profile & prices')),
          if (ref.watch(_myCardProvider).valueOrNull case final c?)
            Card(child: Padding(padding: const EdgeInsets.all(12), child: OutcomeBar(c))),
          if (list.isEmpty) const EmptyState(icon: Icons.inbox_rounded, title: 'No lessons yet'),
          for (final r in list)
            Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ListTile(
                  title: Text('${r.courseCode} · ${r.studentId == me?.id ? 'with ${r.tutorName}' : 'student ${r.studentName}'}'),
                  subtitle: Text('${r.message}\nStatus: ${r.status}'),
                  isThreeLine: true,
                  trailing: _actions(context, r, me?.id, api, refresh),
                ),
                if (r.status == 'completed')
                  _ResultRow(r: r, me: me?.id),
                if (r.studentId == me?.id && (r.status == 'accepted' || r.status == 'completed'))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => reportTutorDialog(context, api, tutorId: r.tutorId, tutorName: r.tutorName),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Report this tutor'),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget? _actions(BuildContext context, TutorRequest r, String? me, CommunityApi api, VoidCallback refresh) {
    final isTutor = r.tutorId == me;
    if (isTutor && r.status == 'pending') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () async { await _run(context, () => api.answerTutorRequest(r.id, accept: true)); refresh(); }),
        IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent), onPressed: () async { await _run(context, () => api.answerTutorRequest(r.id, accept: false)); refresh(); }),
      ]);
    }
    if (!isTutor && r.status == 'accepted') {
      return TextButton(onPressed: () async { await _run(context, () => api.confirmLesson(r.id), ok: 'Lesson confirmed'); refresh(); }, child: const Text('It happened'));
    }
    if (!isTutor && r.status == 'completed' && !r.reviewed) {
      return TextButton(
        onPressed: () async {
          int stars = 5;
          final c = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, set) => AlertDialog(
                title: const Text('Rate this lesson'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 1; i <= 5; i++) IconButton(icon: Icon(i <= stars ? Icons.star : Icons.star_border, color: Colors.amber), onPressed: () => set(() => stars = i)),
                  ]),
                  TextField(controller: c, decoration: const InputDecoration(labelText: 'Comment (optional)')),
                ]),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send'))],
              ),
            ),
          );
          if (ok != true || !context.mounted) return;
          await _run(context, () => api.reviewTutor(requestId: r.id, rating: stars, comment: c.text), ok: 'Thanks for reviewing');
          refresh();
        },
        child: const Text('Review'),
      );
    }
    return null;
  }
}

class TutorProfileEditScreen extends ConsumerStatefulWidget {
  const TutorProfileEditScreen({super.key});
  @override
  ConsumerState<TutorProfileEditScreen> createState() => _TutorEditState();
}

class _TutorEditState extends ConsumerState<TutorProfileEditScreen> {
  final _bio = TextEditingController(), _contact = TextEditingController(), _avail = TextEditingController();
  final _mods = <(TextEditingController, TextEditingController, TextEditingController)>[];
  @override
  void initState() {
    super.initState();
    ref.read(communityProvider).myTutorCard().then((c) {
      if (c == null || !mounted) return;
      setState(() {
        _bio.text = c.bio;
        _contact.text = c.contact ?? '';
        _avail.text = c.availability;
        for (final m in c.modules) {
          _mods.add((TextEditingController(text: m.courseCode), TextEditingController(text: '${m.priceUgx}'), TextEditingController(text: m.grade ?? '')));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My tutor profile')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.4),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('To appear as a tutor you must:\n'
                  '• be in year 2 or above (set your year in Me → Edit details),\n'
                  '• write at least 40 characters about yourself,\n'
                  '• give the grade you got in each unit you teach.\n'
                  'You can teach straight away; people find you by name or @username. '
                  'Send your results slip for a unit to be suggested to every student taking it.'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(controller: _bio, maxLines: 3, maxLength: 600, decoration: const InputDecoration(labelText: 'About you (40+ characters)')),
          TextField(controller: _avail, decoration: const InputDecoration(labelText: 'When are you free?')),
          TextField(controller: _contact, decoration: const InputDecoration(labelText: 'WhatsApp number (optional, shown to students)')),
          const SizedBox(height: 12),
          const Text('Modules and price per hour'),
          for (final m in _mods)
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: m.$1, decoration: const InputDecoration(labelText: 'Unit code'))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: m.$3, decoration: const InputDecoration(labelText: 'Your grade'))),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: TextField(controller: m.$2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'UGX / hour'))),
            ]),
          TextButton.icon(onPressed: () => setState(() => _mods.add((TextEditingController(), TextEditingController(), TextEditingController()))), icon: const Icon(Icons.add), label: const Text('Add module')),
          FilledButton(
            onPressed: () async {
              await _run(context, () async {
                await ref.read(communityProvider).saveMyTutorProfile(
                      bio: _bio.text,
                      contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
                      availability: _avail.text,
                      modules: [
                        for (final m in _mods.where((m) => m.$1.text.trim().isNotEmpty))
                          TutorModule(id: '', courseCode: m.$1.text.trim().toUpperCase(), grade: m.$3.text.trim().isEmpty ? null : m.$3.text.trim(), priceUgx: (int.tryParse(m.$2.text.trim().replaceAll(',', '')) ?? 0).clamp(0, 500000)),
                      ],
                    );
                ref.invalidate(tutorCardsProvider);
                refreshGradeCheckPanel(ref);
                if (context.mounted) showSnack(context, 'Saved. Now send a results slip for each unit to get suggested.');
              });
            },
            child: const Text('Save'),
          ),
          const SizedBox(height: 16),
          const GradeCheckPanel(),
        ]),
      );
}

// ------------------------------------------------------------ moderation
final _officeHistoryProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).officeHistory());

/// Public accountability: content removed, and office terms that ended early
/// or by removal, each with the reason.
class ModerationLogScreen extends ConsumerWidget {
  const ModerationLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Public record'),
            bottom: const TabBar(tabs: [Tab(text: 'Removed content'), Tab(text: 'Office changes')]),
          ),
          body: TabBarView(children: [
            AsyncBody(
              value: ref.watch(moderationLogProvider),
              builder: (list) => list.isEmpty
                  ? const EmptyState(icon: Icons.verified_outlined, title: 'Nothing has been removed', subtitle: 'Every removal shows here, with who did it and why. It cannot be erased.')
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final m in list)
                        Card(child: ListTile(title: Text('${m.action == 'remove' ? 'Removed' : 'Restored'} ${m.targetType}: ${m.targetTitle}'), subtitle: Text('By ${m.actorName} · ${friendlyDate(m.createdAt)}\nReason: ${m.reason}'), isThreeLine: true)),
                    ]),
            ),
            AsyncBody(
              value: ref.watch(_officeHistoryProvider),
              builder: (list) => list.isEmpty
                  ? const EmptyState(icon: Icons.badge_outlined, title: 'No early endings', subtitle: 'When someone leaves office early or is removed, it shows here with the reason.')
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final m in list)
                        Card(
                          child: ListTile(
                            leading: Icon(m.endKind == 'removed' ? Icons.gpp_bad_rounded : Icons.logout_rounded,
                                color: m.endKind == 'removed' ? const Color(0xFFE0245E) : null),
                            title: Text('${m.userName ?? 'Member'} · ${m.positionTitle}'),
                            subtitle: Text([
                              '${m.endKind == 'removed' ? 'Removed from office' : 'Ended term early'} · ${m.publisherName}',
                              if (m.revokedAt != null) DateFormat('d MMM y').format(m.revokedAt!.toLocal()),
                              if (m.endReason != null) 'Reason: ${m.endReason}',
                            ].join('\n')),
                            isThreeLine: true,
                          ),
                        ),
                    ]),
            ),
          ]),
        ),
      );
}

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: AsyncBody(
          value: ref.watch(_reportsProvider),
          builder: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.flag_outlined, title: 'No open reports')
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final r in list)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ListTile(
                            title: Text('${r.targetType}: ${r.targetTitle}'),
                            subtitle: Text('Reason: ${r.reason}\n${friendlyDate(r.createdAt)}'),
                            isThreeLine: true,
                          ),
                          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
                            if (r.targetType != 'comment')
                              TextButton(
                                onPressed: () => context.push(r.targetType == 'event' ? '/events/${r.targetId}' : '/news/${r.targetId}'),
                                child: const Text('Open'),
                              ),
                            TextButton(
                              onPressed: () async {
                                await _run(context, () => ref.read(communityProvider).closeReport(r.id, actioned: false), ok: 'Report dismissed');
                                ref.invalidate(_reportsProvider);
                              },
                              child: const Text('Dismiss'),
                            ),
                            FilledButton.tonal(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Remove this content?'),
                                    content: Text('It will be hidden and listed in the Public record with the reason:\n"${r.reason}"'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                    ],
                                  ),
                                );
                                if (ok != true || !context.mounted) return;
                                final api = ref.read(communityProvider);
                                final reason = r.reason.length >= 20 ? r.reason : 'Reported by students: ${r.reason}';
                                await _run(context, () async {
                                  await api.moderate(action: 'remove', targetType: r.targetType, targetId: r.targetId, reason: reason);
                                  await api.closeReport(r.id, actioned: true);
                                }, ok: 'Removed');
                                ref.invalidate(_reportsProvider);
                              },
                              child: const Text('Remove content'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                ]),
        ),
      );
}

final _reportsProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).openReports());

// ------------------------------------------------------------ members
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});
  @override
  ConsumerState<MembersScreen> createState() => _MembersState();
}

class _MembersState extends ConsumerState<MembersScreen> {
  String? _pub;
  Future<List<Membership>>? _f;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final api = ref.read(communityProvider);
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive && m.can('manage_members')).toList();
    final pubs = ref.watch(_publishersProvider).valueOrNull ?? [];
    final allowed = (me?.isSuperAdmin ?? false) ? pubs : pubs.where((p) => mems.any((m) => m.publisherId == p.id)).toList();
    final pubsState = ref.watch(_publishersProvider);
    final memsState = ref.watch(myMembershipsProvider);
    if (pubsState.isLoading || memsState.isLoading || me == null) {
      return Scaffold(appBar: AppBar(title: const Text('Office members')), body: const Center(child: CircularProgressIndicator()));
    }
    if (pubsState.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Office members')),
        body: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Could not load offices',
          subtitle: 'Check your internet and try again.',
          action: FilledButton(onPressed: () => ref.invalidate(_publishersProvider), child: const Text('Try again')),
        ),
      );
    }
    if (allowed.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Office members')),
        body: const EmptyState(icon: Icons.lock_outline, title: 'Not allowed', subtitle: 'Only office managers and the super admin can appoint members.'),
      );
    }
    _pub ??= allowed.first.id;
    _f ??= api.membersOf(_pub!);
    void reload() => setState(() => _f = api.membersOf(_pub!));
    return Scaffold(
      appBar: AppBar(title: const Text('Office members')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Appoint'),
        onPressed: () async {
          final ok = await _appoint(context, api, _pub!);
          if (ok) reload();
        },
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
            initialValue: _pub,
          decoration: const InputDecoration(labelText: 'Office'),
          items: [for (final p in allowed) DropdownMenuItem(value: p.id, child: Text(p.name))],
          onChanged: (v) => setState(() {
            _pub = v;
            _f = api.membersOf(v!);
          }),
        ),
        const SizedBox(height: 8),
        FutureBuilder(
          future: _f,
          builder: (_, s) {
            if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
            final list = s.data!;
            final active = list.where((m) => m.state == 'active').toList();
            final past = list.where((m) => m.state != 'active').toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (active.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nobody in office yet. Tap Appoint.')),
              for (final m in active) _MemberCard(m: m, superAdmin: me.isSuperAdmin, api: api, onChanged: reload),
              if (past.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Past members', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final m in past) _MemberCard(m: m, superAdmin: me.isSuperAdmin, api: api, onChanged: reload),
              ],
            ]);
          },
        ),
      ]),
    );
  }

  Future<bool> _appoint(BuildContext context, CommunityApi api, String pubId) async {
    final person = await pickPerson(context, api, title: 'Who are you appointing?');
    if (person == null || !context.mounted) return false;
    final title = TextEditingController();
    final scopes = <String>{'news', 'events'};
    int months = 12;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Appoint ${person.fullName}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PersonAvatar(name: person.fullName, url: person.avatar),
                title: NameWithBadge(person.fullName, person.badge),
                subtitle: Text(person.username == null ? '' : '@${person.username}'),
              ),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Position, e.g. Minister of ICT')),
              DropdownButtonFormField<int>(
                isExpanded: true,
            initialValue: months,
                decoration: const InputDecoration(labelText: 'Term'),
                items: [for (final m in [3, 6, 9, 12]) DropdownMenuItem(value: m, child: Text('$m months'))],
                onChanged: (v) => set(() => months = v ?? 12),
              ),
              for (final e in kScopeLabels.entries)
                CheckboxListTile(dense: true, title: Text(e.value), value: scopes.contains(e.key), onChanged: (v) => set(() => v == true ? scopes.add(e.key) : scopes.remove(e.key))),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Appoint'))],
        ),
      ),
    );
    if (ok != true || !context.mounted) return false;
    if (title.text.trim().length < 3 || title.text.trim().length > 80) {
      showSnack(context, 'Position must be 3–80 letters.');
      return false;
    }
    if (scopes.isEmpty) {
      showSnack(context, 'Tick at least one thing they may do.');
      return false;
    }
    var done = false;
    await _run(context, () async {
      await api.appointMember(publisherId: pubId, userId: person.id, positionTitle: title.text, scopes: scopes.toList(), expiresAt: DateTime.now().add(Duration(days: months * 30)));
      done = true;
    }, ok: 'Appointed');
    return done;
  }
}

final _publishersProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).publishers());

/// One office member: status, and the actions allowed for them.
class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.m, required this.superAdmin, required this.api, required this.onChanged});
  final Membership m;
  final bool superAdmin;
  final CommunityApi api;
  final VoidCallback onChanged;

  static const _earlyReasons = ['Resigned', 'Reshuffle', 'Graduated / left the university', 'Health or personal reasons'];

  Future<void> _renew(BuildContext context) async {
    int months = 6;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Renew ${m.userName ?? 'term'}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Now ends ${DateFormat('d MMM y').format(m.expiresAt)}. A term can reach at most 12 months from today.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final x in [3, 6, 12]) ChoiceChip(label: Text('$x months from today'), selected: months == x, onSelected: (_) => set(() => months = x)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Renew')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => api.renewTerm(m.id, DateTime.now().add(Duration(days: months * 30))), ok: 'Term renewed');
    onChanged();
  }

  Future<void> _endEarly(BuildContext context) async {
    var pick = _earlyReasons.first;
    final other = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('End term early'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m.userName} stops being ${m.positionTitle} now. Their badge goes away. Their old posts stay.'),
              const SizedBox(height: 8),
              for (final r in [..._earlyReasons, 'Other'])
                RadioListTile<String>(value: r, groupValue: pick, onChanged: (v) => set(() => pick = v!), title: Text(r), dense: true, contentPadding: EdgeInsets.zero),
              if (pick == 'Other') TextField(controller: other, decoration: const InputDecoration(labelText: 'Reason')),
              const SizedBox(height: 6),
              const Text('The reason is shown publicly in the record.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End term')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final reason = pick == 'Other' ? other.text : pick;
    await _run(context, () => api.endTerm(m.id, kind: 'early', reason: reason), ok: 'Term ended');
    onChanged();
  }

  Future<void> _remove(BuildContext context) async {
    final why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gpp_bad_rounded, color: Colors.red),
        title: const Text('Remove for misconduct'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m.userName} will be removed as ${m.positionTitle} immediately.'),
            const SizedBox(height: 8),
            const Text('Everyone will see "Removed from office" and the reason you write. Keep it factual and respectful: '
                'what rule was broken and what was decided. Do not include private or medical details.'),
            const SizedBox(height: 12),
            TextField(
              controller: why,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Public reason (20+ characters)', alignLabelWithHint: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (why.text.trim().length < 20) {
      showSnack(context, 'Please write a reason of at least 20 characters.');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: Text('This cannot be undone. To give ${m.userName} the role again later, appoint them again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, remove'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await _run(context, () => api.endTerm(m.id, kind: 'removed', reason: why.text), ok: 'Removed from office');
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (label, color) = switch (m.state) {
      'active' => (m.daysLeft <= 14 ? 'Ends in ${m.daysLeft} days' : 'In office · ${m.daysLeft} days left', m.daysLeft <= 14 ? const Color(0xFFF59E0B) : const Color(0xFF14A44D)),
      'ended' => ('Term ended ${DateFormat('d MMM y').format(m.expiresAt)}', const Color(0xFF64748B)),
      'removed' => ('Removed from office', const Color(0xFFE0245E)),
      _ => ('Ended early', const Color(0xFF64748B)),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            PersonAvatar(name: m.userName ?? '?'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NameWithBadge(m.userName ?? 'Member', m.state == 'active' ? m.badge : null, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text([m.positionTitle, if (m.username != null) '@${m.username}'].join(' · '), style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          if (m.endReason != null) ...[
            const SizedBox(height: 6),
            Text('Reason: ${m.endReason}', style: t.bodySmall),
          ],
          if (m.state == 'active')
            Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
              TextButton(onPressed: () => _renew(context), child: const Text('Renew')),
              TextButton(onPressed: () => _endEarly(context), child: const Text('End early')),
              if (superAdmin)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _remove(context),
                  child: const Text('Remove for misconduct'),
                ),
            ]),
        ]),
      ),
    );
  }
}


/// Lets a student report a tutor they had a lesson with.
Future<void> reportTutorDialog(BuildContext context, CommunityApi api,
    {required String tutorId, required String tutorName}) async {
  var reason = 'no_show';
  final details = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('Report $tutorName'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Staff review every report. Your name is not shown to the tutor.'),
            const SizedBox(height: 8),
            for (final e in tutorReportReasons.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: reason,
                onChanged: (v) => set(() => reason = v!),
                title: Text(e.value),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            TextField(
              controller: details,
              minLines: 3,
              maxLines: 6,
              maxLength: 600,
              decoration: const InputDecoration(labelText: 'What happened?', alignLabelWithHint: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send report')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  if (details.text.trim().length < 10) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please explain in at least 10 characters.')));
    return;
  }
  await _run(context, () => api.reportTutor(tutorId: tutorId, reason: reason, details: details.text),
      ok: 'Report sent. Thank you.');
}

/// Staff view: who is reported, how often and for what (as a share of all their reports).
class TutorReportsScreen extends ConsumerWidget {
  const TutorReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutor reports')),
      body: AsyncBody(
        value: ref.watch(tutorReportSummaryProvider),
        onRetry: () => ref.invalidate(tutorReportSummaryProvider),
        builder: (rows) {
          final byTutor = <String, List<TutorReportRow>>{};
          for (final r in rows) {
            byTutor.putIfAbsent(r.tutorId, () => []).add(r);
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            const Text('A tutor with open reports from 3 or more different students is hidden from the tutor list '
                'until you decide. Uphold = the reports were right. Dismiss = they were not.'),
            const SizedBox(height: 8),
            if (byTutor.isEmpty) const EmptyState(icon: Icons.verified_user_outlined, title: 'No tutor reports'),
            for (final e in byTutor.entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value.first.tutorName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${e.value.first.total} reports from ${e.value.first.reporters} students · ${e.value.first.open} open'
                        '${e.value.first.reporters >= 3 && e.value.first.open > 0 ? ' · HIDDEN FROM LIST' : ''}'),
                    const SizedBox(height: 10),
                    for (final r in e.value) ...[
                      Row(children: [
                        Expanded(child: Text(tutorReportReasons[r.reason] ?? r.reason)),
                        Text('${r.pct.toStringAsFixed(0)}% (${r.n})', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.pct / 100,
                          minHeight: 8,
                          color: r.reason == 'harassment' ? Colors.red : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (e.value.first.open > 0)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                          onPressed: () async {
                            await _run(context, () => ref.read(communityProvider).closeTutorReports(e.key, upheld: false), ok: 'Dismissed');
                            ref.invalidate(tutorReportSummaryProvider);
                          },
                          child: const Text('Dismiss'),
                        ),
                        FilledButton(
                          onPressed: () async {
                            await _run(context, () => ref.read(communityProvider).closeTutorReports(e.key, upheld: true), ok: 'Upheld');
                            ref.invalidate(tutorReportSummaryProvider);
                          },
                          child: const Text('Uphold'),
                        ),
                      ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}


/// Where found items are handed in. One place, so owners know where to look.
const kLostFoundDropOff = 'Guild office';

class _HandInNotice extends StatelessWidget {
  const _HandInNotice();
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: const ListTile(
          leading: Icon(Icons.volunteer_activism_rounded),
          title: Text('Found something? Take it to the $kLostFoundDropOff.'),
          subtitle: Text('They keep it safe, list it here, and check the owner before handing it back. '
              'Lost something? Check here first, then ask at the $kLostFoundDropOff.'),
        ),
      );
}


final _myCardProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).myTutorCard());
final _myOutcomesProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).myOutcomes());

/// Under a completed lesson: the student shares their band; the tutor can ask.
class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.r, required this.me});
  final TutorRequest r;
  final String? me;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(communityProvider);
    if (r.tutorId == me) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Ask how it went'),
          onPressed: () => _run(context, () => api.askProgress(r.id), ok: 'Asked. They can share their grade band.'),
        ),
      );
    }
    final mine = ref.watch(_myOutcomesProvider).valueOrNull?['${r.tutorId}|${normCode(r.courseCode)}'];
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        icon: Icon(mine == null ? Icons.grading_rounded : Icons.check_circle_rounded, size: 18),
        label: Text(mine == null ? 'Share my result' : 'Your result: ${outcomeBandLabels[mine]} (change)'),
        onPressed: () async {
          final band = await pickOutcomeBand(context, r.courseCode, current: mine);
          if (band == null || !context.mounted) return;
          await _run(context, () => api.reportOutcome(tutorId: r.tutorId, courseCode: r.courseCode, band: band), ok: 'Thanks – it helps others pick good tutors.');
          ref.invalidate(_myOutcomesProvider);
        },
      ),
    );
  }
}
