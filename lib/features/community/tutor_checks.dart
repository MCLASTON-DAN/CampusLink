import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart';

final myGradeProofsProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).myGradeProofs());
final gradeProofQueueProvider = FutureProvider.autoDispose((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(communityProvider).gradeProofQueue();
});
final _myTutorCardProvider = FutureProvider.autoDispose((ref) => ref.watch(communityProvider).myTutorCard());

const _levelColors = [Color(0xFF64748B), Color(0xFF0EA5E9), Color(0xFF059669), Color(0xFF0095F6)];

/// "Level 2 · Grade-checked" chip. Tap to see what the levels mean.
class TutorLevelChip extends StatelessWidget {
  const TutorLevelChip(this.card, {super.key});
  final TutorCard card;
  @override
  Widget build(BuildContext context) {
    final c = _levelColors[card.levelNo - 1];
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showTutorLevels(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text('Level ${card.levelNo} · ${card.level} · ${card.lessons} lessons',
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }
}

Future<void> showTutorLevels(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tutor levels', style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final (i, t, d) in [
              (1, 'New', 'Grades typed in by the tutor, not checked yet. Found only by searching their name or @username.'),
              (2, 'Grade-checked', 'A lecturer or staff member saw their results slip. Suggested to students for those units.'),
              (3, 'Experienced', '10+ confirmed lessons, rating 4.0+, AND results: 5+ students reported, and enough of them scored 60+ that it isn\'t luck.'),
              (4, 'Expert ✔', '30+ lessons, rating 4.3+ from 5+ students, no upheld reports, and strong results from 10+ students. Gets the blue tick. It cannot be bought.'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                    backgroundColor: _levelColors[i - 1].withValues(alpha: 0.15),
                    child: Text('$i', style: TextStyle(color: _levelColors[i - 1], fontWeight: FontWeight.w800))),
                title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(d),
              ),
          ]),
        ),
      ),
    );

// ------------------------------------------------------------ the tutor's side

/// In "My tutor profile": each saved unit, its check status, and a button to
/// send a results slip.
class GradeCheckPanel extends ConsumerWidget {
  const GradeCheckPanel({super.key});

  Future<void> _send(BuildContext context, WidgetRef ref, TutorModule m) async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'], withData: true);
    final f = res?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    try {
      await ref.read(communityProvider).sendGradeProof(
          courseCode: m.courseCode, grade: m.grade ?? '', bytes: f.bytes!, extension: f.extension ?? 'jpg');
      ref.invalidate(myGradeProofsProvider);
      if (context.mounted) showSnack(context, 'Sent. A lecturer of ${m.courseCode} or staff will check it.');
    } on CommunityException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } catch (_) {
      if (context.mounted) showSnack(context, 'Could not send. Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(_myTutorCardProvider).valueOrNull;
    final proofs = ref.watch(myGradeProofsProvider).valueOrNull ?? const <GradeProof>[];
    if (card == null || card.modules.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Get suggested to students', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            TutorLevelChip(card),
          ]),
          const SizedBox(height: 4),
          const Text('You can teach now: people find you by your name or @username. '
              'To be suggested to every student taking a unit, send a photo or PDF of your results for it. '
              'Only you, staff and that unit\'s lecturers can see it, and it is deleted once checked.'),
          const SizedBox(height: 8),
          for (final m in card.modules)
            Builder(builder: (_) {
              final last = proofs.where((p) => p.courseCode == normCode(m.courseCode)).firstOrNull;
              final (icon, color, text) = m.gradeChecked
                  ? (Icons.verified_rounded, const Color(0xFF14A44D), 'Grade ${m.grade} checked ✓ – you are suggested')
                  : last?.pending == true
                      ? (Icons.hourglass_top_rounded, const Color(0xFFF2780C), 'Waiting for a check (sent ${friendlyDate(last!.createdAt)})')
                      : last?.status == 'rejected'
                          ? (Icons.error_outline_rounded, const Color(0xFFE0245E), 'Not accepted: ${last!.reason ?? ''}')
                          : (Icons.help_outline_rounded, Colors.grey, 'Grade ${m.grade ?? '?'} not checked yet');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: color),
                title: Text(m.courseCode, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(text),
                trailing: m.gradeChecked || last?.pending == true
                    ? null
                    : TextButton(onPressed: () => _send(context, ref, m), child: const Text('Send slip')),
              );
            }),
        ]),
      ),
    );
  }
}

/// Call after saving the tutor profile so the panel shows the saved units.
void refreshGradeCheckPanel(WidgetRef ref) {
  ref.invalidate(_myTutorCardProvider);
  ref.invalidate(myGradeProofsProvider);
}

// ------------------------------------------------------------ the reviewer's side

class GradeChecksScreen extends ConsumerWidget {
  const GradeChecksScreen({super.key});

  Future<void> _view(BuildContext context, WidgetRef ref, GradeProof p) async {
    try {
      final link = await ref.read(communityProvider).gradeProofLink(p.filePath);
      if (!context.mounted) return;
      if (link.startsWith('data:image')) {
        openPictureViewer(context, link);
      } else if (link.startsWith('data:')) {
        // Demo PDF: show it is there; real PDFs open in the browser.
        showSnack(context, 'PDF slip (${(base64Decode(link.split(',').last).length / 1024).round()} KB) – opens in the browser in the live app.');
      } else {
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      }
    } on CommunityException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, GradeProof p, bool approve) async {
    String? reason;
    if (!approve) {
      final c = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Not accepted: ${p.courseCode}'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'Why? The tutor sees this', hintText: 'e.g. The slip does not show BDA2207, or the name is cut off'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Send')),
          ],
        ),
      );
      if (reason == null) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Approve ${p.tutorName}?'),
          content: Text('You saw a results slip showing grade ${p.grade} in ${p.courseCode} for this student. '
              'They will be suggested to students for this unit.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(communityProvider).reviewGradeProof(p.id, approve: approve, reason: reason);
      ref.invalidate(gradeProofQueueProvider);
      ref.invalidate(tutorCardsProvider);
      if (context.mounted) showSnack(context, approve ? 'Approved. The slip was deleted.' : 'Sent back with your reason.');
    } on CommunityException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grade checks'), actions: [
        IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(gradeProofQueueProvider), icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: AsyncBody(
        value: ref.watch(gradeProofQueueProvider),
        onRetry: () => ref.invalidate(gradeProofQueueProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'Nothing to check',
                subtitle: 'Tutors\' results slips for your units show here. Staff see all units.')
            : ListView(padding: const EdgeInsets.all(12), children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Open the slip. Approve only if it clearly shows this student\'s name, the unit and the grade. '
                      'Slips are deleted after you decide.'),
                ),
                for (final p in list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text('${p.tutorName} · ${p.courseCode}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          if (p.overdue) const StatusChip('Waiting 3+ days', color: Color(0xFFE0245E)),
                        ]),
                        Text('Says they got: ${p.grade} · sent ${DateFormat('d MMM, HH:mm').format(p.createdAt.toLocal())}'),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                              onPressed: () => _view(context, ref, p),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Open slip')),
                          FilledButton.icon(
                              onPressed: () => _decide(context, ref, p, true),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Approve')),
                          TextButton(onPressed: () => _decide(context, ref, p, false), child: const Text('Not accepted')),
                        ]),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}


/// How a tutor's students did: share in each grade band. Shown only from 5
/// reports, so one lucky student never looks like "100%".
class OutcomeBar extends StatelessWidget {
  const OutcomeBar(this.card, {super.key});
  final TutorCard card;
  static const _colors = [Color(0xFFE0245E), Color(0xFFF2780C), Color(0xFFEAB308), Color(0xFF14A44D), Color(0xFF0095F6)];
  @override
  Widget build(BuildContext context) {
    final b = card.outcomeBands;
    final t = Theme.of(context).textTheme;
    if (b == null) {
      return Text(
          card.outcomeReports == 0
              ? 'Student results: none reported yet'
              : 'Student results: ${card.outcomeReports} reported – shown from 5',
          style: t.bodySmall);
    }
    final n = b.fold<int>(0, (a, x) => a + x);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('How $n students did after lessons', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          for (var i = 0; i < 5; i++)
            if (b[i] > 0) Expanded(flex: b[i], child: Container(height: 12, color: _colors[i])),
        ]),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 10, children: [
        for (var i = 0; i < 5; i++)
          Text('${outcomeBandLabels[i]}: ${(b[i] * 100 / n).round()}%', style: t.bodySmall?.copyWith(color: _colors[i])),
      ]),
    ]);
  }
}

/// Student: which band did you get in this unit? Returns the band or null.
Future<int?> pickOutcomeBand(BuildContext context, String courseCode, {int? current}) => showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('Your final result in $courseCode', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Coursework and exam together. Only totals are shown – nobody sees yours, not even the tutor.'),
          ),
          for (var i = 4; i >= 0; i--)
            ListTile(
              leading: Icon(current == i ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(outcomeBandLabels[i]),
              onTap: () => Navigator.pop(sheet, i),
            ),
        ]),
      ),
    );
