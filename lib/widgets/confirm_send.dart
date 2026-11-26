import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "Read before you send" — only where a mistake is costly: it reaches many
/// people, or it is official. Shows the message as people will see it, who it
/// reaches, and a short checklist. Send stays locked until the person ticks
/// that they read it through. Returns true to send.
///
/// Not used for chat, comments, likes or RSVPs: friction there helps no one.
Future<bool> confirmBeforeSending(
  BuildContext context, {
  required String title,
  required String preview,
  required String reach,
  List<String> checks = const ['Names, dates, times and places are right', 'Spelling is right', 'It is fair and true'],
  String sendLabel = 'Send',
}) async {
  var read = false;
  final ok = await showModalBottomSheet<bool>(
    useRootNavigator: true, // above the tab bar, never under it
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setS) {
        final s = Theme.of(sheet).colorScheme;
        final t = Theme.of(sheet).textTheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.9),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Read it once more', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.groups_rounded, size: 18, color: s.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(reach, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: s.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s.outlineVariant),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (preview.trim().isNotEmpty) ...[const SizedBox(height: 6), Text(preview)],
                  ]),
                ),
                const SizedBox(height: 12),
                for (final c in checks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.check_circle_outline_rounded, size: 18, color: s.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c)),
                    ]),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: read,
                  onChanged: (v) => setS(() => read = v ?? false),
                  title: const Text('I have read it through, and it is correct'),
                ),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Go back and fix'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(onPressed: read ? () => Navigator.pop(sheet, true) : null, child: Text(sendLabel))),
                ]),
              ]),
            ),
          ),
        );
      },
    ),
  );
  return ok == true;
}

/// Asks why something is retracted or cancelled (shown to everyone). Null = cancelled.
Future<String?> askReason(BuildContext context, {required String title, required String hint, String action = 'Retract'}) {
  final c = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Everyone will see this reason, and it is kept in the public record.'),
          const SizedBox(height: 8),
          TextField(controller: c, maxLength: 300, maxLines: 3, decoration: InputDecoration(labelText: 'Reason', hintText: hint, errorText: error)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => c.text.trim().length < 10
                ? setS(() => error = 'Say what was wrong (at least 10 letters).')
                : Navigator.pop(ctx, c.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

/// "Edited · 26 Nov, 14:05" — shown on anything changed after publishing.
class EditedMark extends StatelessWidget {
  const EditedMark(this.at, {super.key});
  final DateTime? at;
  @override
  Widget build(BuildContext context) {
    if (at == null) return const SizedBox.shrink();
    return Text('Edited · ${DateFormat('d MMM, HH:mm').format(at!.toLocal())}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

/// Red notice that replaces wrong information: "Retracted: reason".
class RetractedBanner extends StatelessWidget {
  const RetractedBanner({super.key, required this.word, required this.reason, this.by});
  final String word; // Retracted | Cancelled
  final String? reason, by;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: s.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.report_rounded, color: s.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text('$word${by == null ? '' : ' by $by'}: ${reason ?? ''}',
              style: TextStyle(color: s.onErrorContainer, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
