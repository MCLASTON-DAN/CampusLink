import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';

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
                final t = TextEditingController(), d = TextEditingController(), w = TextEditingController(), s = TextEditingController();
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
            ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'Nothing listed', subtitle: 'Only offices post found items.')
            : ListView(padding: const EdgeInsets.all(12), children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('To get an item back, say something only the owner knows. The office checks before handing it over.'),
                ),
                for (final i in list)
                  Card(
                    child: ListTile(
                      title: Text(i.title),
                      subtitle: Text('${i.description}\nFound: ${i.foundWhere}\nKept at: ${i.storedAt}'),
                      isThreeLine: true,
                      trailing: i.status != 'held'
                          ? const StatusChip('Returned', color: Colors.green)
                          : i.myClaimStatus != null
                              ? StatusChip('Claim ${i.myClaimStatus}', color: Colors.orange)
                              : mems.isNotEmpty
                                  ? TextButton(onPressed: () => context.push('/lostfound/${i.id}'), child: const Text('Claims'))
                                  : FilledButton(
                                      onPressed: () async {
                                        final p = await _prompt(context, 'Proof this is yours', min: 15, hint: 'Colour, marks, what is inside…');
                                        if (p == null || !context.mounted) return;
                                        await _run(context, () => api.claimItem(i.id, p), ok: 'Sent. The office will check.');
                                        ref.invalidate(lostFoundProvider);
                                      },
                                      child: const Text('This is mine')),
                    ),
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
                                setState(() => _f = api.claimsFor(widget.itemId));
                                ref.invalidate(lostFoundProvider);
                              }),
                          IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.redAccent),
                              onPressed: () async {
                                await _run(context, () => api.decideClaim(c.id, approve: false));
                                setState(() => _f = api.claimsFor(widget.itemId));
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
  const SurveysScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive && m.can('surveys')).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Surveys')),
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
class TutorsScreen extends ConsumerWidget {
  const TutorsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,###');
    return Scaffold(
      appBar: AppBar(title: const Text('Tutors'), actions: [
        IconButton(icon: const Icon(Icons.assignment_ind_outlined), tooltip: 'My lessons', onPressed: () => context.push('/tutors/mine')),
      ]),
      body: AsyncBody(
        value: ref.watch(tutorCardsProvider),
        onRetry: () => ref.invalidate(tutorCardsProvider),
        builder: (list) => ListView(padding: const EdgeInsets.all(12), children: [
          const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Scores are fair: a few reviews count less. Only students who had a confirmed lesson can review. Blue tick = verified by many reviews.')),
          if (list.isEmpty) const EmptyState(icon: Icons.school_outlined, title: 'No tutors yet'),
          for (final t in list)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: NameWithBadge(t.name, t.verified ? 'blue' : null, style: Theme.of(context).textTheme.titleMedium)),
                    const Spacer(),
                    if (t.reviews > 0) Text('★ ${t.score.toStringAsFixed(2)}  (${t.reviews})', style: const TextStyle(fontWeight: FontWeight.w700)) else const Text('No reviews yet'),
                  ]),
                  if (t.bio.isNotEmpty) Text(t.bio),
                  if (t.availability.isNotEmpty) Text('Free: ${t.availability}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  for (final m in t.modules)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m.courseCode}${m.courseName == null ? '' : ' · ${m.courseName}'}'),
                      subtitle: Text('UGX ${fmt.format(m.priceUgx)} per hour${m.grade == null ? '' : ' · grade ${m.grade}'}'),
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
        ]),
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
          if (list.isEmpty) const EmptyState(icon: Icons.inbox_rounded, title: 'No lessons yet'),
          for (final r in list)
            Card(
              child: ListTile(
                title: Text('${r.courseCode} · ${r.studentId == me?.id ? 'with ${r.tutorName}' : 'student ${r.studentName}'}'),
                subtitle: Text('${r.message}\nStatus: ${r.status}'),
                isThreeLine: true,
                trailing: _actions(context, r, me?.id, api, refresh),
              ),
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
  final _mods = <(TextEditingController, TextEditingController)>[];
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
          _mods.add((TextEditingController(text: m.courseCode), TextEditingController(text: '${m.priceUgx}')));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My tutor profile')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _bio, maxLines: 3, decoration: const InputDecoration(labelText: 'About you')),
          TextField(controller: _avail, decoration: const InputDecoration(labelText: 'When are you free?')),
          TextField(controller: _contact, decoration: const InputDecoration(labelText: 'WhatsApp number (optional, shown to students)')),
          const SizedBox(height: 12),
          const Text('Modules and price per hour'),
          for (final m in _mods)
            Row(children: [
              Expanded(child: TextField(controller: m.$1, decoration: const InputDecoration(labelText: 'Course code'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: m.$2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'UGX / hour'))),
            ]),
          TextButton.icon(onPressed: () => setState(() => _mods.add((TextEditingController(), TextEditingController()))), icon: const Icon(Icons.add), label: const Text('Add module')),
          FilledButton(
            onPressed: () async {
              await _run(context, () async {
                await ref.read(communityProvider).saveMyTutorProfile(
                      bio: _bio.text,
                      contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
                      availability: _avail.text,
                      modules: [
                        for (final m in _mods.where((m) => m.$1.text.trim().isNotEmpty))
                          TutorModule(id: '', courseCode: m.$1.text, priceUgx: int.tryParse(m.$2.text.trim()) ?? 0),
                      ],
                    );
                ref.invalidate(tutorCardsProvider);
                if (context.mounted) context.pop();
              });
            },
            child: const Text('Save'),
          ),
        ]),
      );
}

// ------------------------------------------------------------ moderation
class ModerationLogScreen extends ConsumerWidget {
  const ModerationLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Removal log')),
        body: AsyncBody(
          value: ref.watch(moderationLogProvider),
          builder: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.verified_outlined, title: 'Nothing has been removed', subtitle: 'Every removal shows here, with who did it and why. It cannot be erased.')
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final m in list)
                    Card(child: ListTile(title: Text('${m.action == 'remove' ? 'Removed' : 'Restored'} ${m.targetType}: ${m.targetTitle}'), subtitle: Text('By ${m.actorName} · ${friendlyDate(m.createdAt)}\nReason: ${m.reason}'), isThreeLine: true)),
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
                      child: ListTile(
                        title: Text('${r.targetType}: ${r.targetTitle}'),
                        subtitle: Text(r.reason),
                        trailing: r.targetType == 'post' ? TextButton(onPressed: () => context.push('/news/${r.targetId}'), child: const Text('Open')) : null,
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
    if (allowed.isEmpty) return Scaffold(appBar: AppBar(title: const Text('Office members')), body: const EmptyState(icon: Icons.lock_outline, title: 'Not allowed'));
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
            return Column(children: [
              for (final m in s.data!)
                Card(
                  child: ListTile(
                    title: Text('${m.userName ?? 'Student'} · ${m.positionTitle}'),
                    subtitle: Text(m.isActive ? '${m.daysLeft} days left (ends ${DateFormat('d MMM y').format(m.expiresAt)})' : 'Term ended'),
                    trailing: m.isActive
                        ? TextButton(
                            onPressed: () async {
                              await _run(context, () => api.endTerm(m.id), ok: 'Term ended');
                              reload();
                            },
                            child: const Text('End term'))
                        : null,
                  ),
                ),
            ]);
          },
        ),
      ]),
    );
  }

  Future<bool> _appoint(BuildContext context, CommunityApi api, String pubId) async {
    final num = TextEditingController(), title = TextEditingController();
    final scopes = <String>{'news', 'events'};
    int months = 12;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Appoint a member'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: num, decoration: const InputDecoration(labelText: 'Student number')),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Position, e.g. Minister of ICT')),
              DropdownButtonFormField<int>(
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
    var done = false;
    await _run(context, () async {
      await api.appointMember(publisherId: pubId, studentNumber: num.text, positionTitle: title.text, scopes: scopes.toList(), expiresAt: DateTime.now().add(Duration(days: months * 30)));
      done = true;
    }, ok: 'Appointed');
    return done;
  }
}

final _publishersProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).publishers());
