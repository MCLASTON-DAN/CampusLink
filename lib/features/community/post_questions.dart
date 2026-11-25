import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';

final postQuestionsProvider =
    FutureProvider.autoDispose.family<List<PostQuestion>, String>((ref, postId) => ref.watch(communityProvider).postQuestions(postId));

// ---------------------------------------------------------------- composer

/// One question being written in the composer.
class DraftQuestion {
  DraftQuestion(this.kind)
      : prompt = TextEditingController(),
        options = [TextEditingController(), TextEditingController()];
  String kind; // poll | quiz
  final TextEditingController prompt;
  final List<TextEditingController> options;
  int? correct;

  PostQuestion toQuestion() => PostQuestion(
        kind: kind,
        prompt: prompt.text,
        options: [for (final o in options) o.text],
        correctIndex: kind == 'quiz' ? correct : null,
      );

  void dispose() {
    prompt.dispose();
    for (final o in options) {
      o.dispose();
    }
  }
}

/// "Add a poll or quiz" block for the post composer. Up to 5 questions.
class QuestionsEditor extends StatefulWidget {
  const QuestionsEditor({super.key, required this.drafts, this.locked = false});
  final List<DraftQuestion> drafts;

  /// After the post is published, the questions can't be changed (only retried).
  final bool locked;
  @override
  State<QuestionsEditor> createState() => _QuestionsEditorState();
}

class _QuestionsEditorState extends State<QuestionsEditor> {
  List<DraftQuestion> get d => widget.drafts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < d.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('Question ${i + 1}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 'poll', label: Text('Poll'), icon: Icon(Icons.bar_chart_rounded, size: 16)),
                    ButtonSegment(value: 'quiz', label: Text('Quiz'), icon: Icon(Icons.quiz_outlined, size: 16)),
                  ],
                  selected: {d[i].kind},
                  onSelectionChanged: widget.locked ? null : (v) => setState(() => d[i].kind = v.first),
                ),
                const Spacer(),
                if (!widget.locked)
                  IconButton(
                    tooltip: 'Remove question',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => setState(() => d.removeAt(i).dispose()),
                  ),
              ]),
              TextField(
                controller: d[i].prompt,
                enabled: !widget.locked,
                maxLength: 200,
                decoration: InputDecoration(
                    labelText: d[i].kind == 'quiz' ? 'Quiz question' : 'Poll question',
                    hintText: d[i].kind == 'quiz' ? 'Which year was Cavendish founded?' : 'Which day suits the career fair?'),
              ),
              if (d[i].kind == 'quiz')
                Text('Tap the circle next to the right answer.', style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
              for (var j = 0; j < d[i].options.length; j++)
                Row(children: [
                  if (d[i].kind == 'quiz')
                    IconButton(
                      tooltip: 'This is the right answer',
                      onPressed: widget.locked ? null : () => setState(() => d[i].correct = j),
                      icon: Icon(
                        d[i].correct == j ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: d[i].correct == j ? const Color(0xFF14A44D) : null,
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: d[i].options[j],
                      enabled: !widget.locked,
                      decoration: InputDecoration(labelText: 'Choice ${j + 1}', isDense: true),
                    ),
                  ),
                  if (!widget.locked && d[i].options.length > 2)
                    IconButton(
                      tooltip: 'Remove choice',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        d[i].options.removeAt(j).dispose();
                        if (d[i].correct == j) d[i].correct = null;
                        if ((d[i].correct ?? -1) > j) d[i].correct = d[i].correct! - 1;
                      }),
                    ),
                ]),
              if (!widget.locked && d[i].options.length < 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => d[i].options.add(TextEditingController())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a choice'),
                  ),
                ),
            ]),
          ),
        ),
      if (!widget.locked && d.length < 5)
        OutlinedButton.icon(
          onPressed: () => setState(() => d.add(DraftQuestion(d.isEmpty ? 'poll' : d.last.kind))),
          icon: const Icon(Icons.add_chart_rounded),
          label: Text(d.isEmpty ? 'Add a poll or quiz (optional)' : 'Add another question (${d.length}/5)'),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- reading a post

/// The questions under a post. Answer once; then see results.
class PostQuestionsSection extends ConsumerWidget {
  const PostQuestionsSection({super.key, required this.postId});
  final String postId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qs = ref.watch(postQuestionsProvider(postId));
    return qs.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(), // the post still reads fine without them
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final quiz = list.where((q) => q.isQuiz).toList();
        final done = quiz.where((q) => q.answered).toList();
        final right = done.where((q) => q.myAnswer == q.correctIndex).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final q in list) _QuestionCard(postId: postId, q: q),
          if (quiz.length > 1 && done.length == quiz.length)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.emoji_events_rounded),
                title: Text('You got $right out of ${quiz.length}'),
                subtitle: Text(right == quiz.length ? 'Perfect score!' : 'Nice try. The right answers are shown in green.'),
              ),
            ),
        ]);
      },
    );
  }
}

class _QuestionCard extends ConsumerStatefulWidget {
  const _QuestionCard({required this.postId, required this.q});
  final String postId;
  final PostQuestion q;
  @override
  ConsumerState<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<_QuestionCard> {
  bool _busy = false;

  Future<void> _answer(int i) async {
    setState(() => _busy = true);
    try {
      await ref.read(communityProvider).answerQuestion(widget.q.id, i);
      ref.invalidate(postQuestionsProvider(widget.postId));
    } on CommunityException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not send your answer. Check your connection and try again.')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    const green = Color(0xFF14A44D), red = Color(0xFFE0245E);
    final showResults = q.counts != null; // you answered, or you wrote the post
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(q.isQuiz ? Icons.quiz_outlined : Icons.bar_chart_rounded, size: 18, color: s.primary),
            const SizedBox(width: 6),
            Text(q.isQuiz ? 'QUIZ' : 'POLL', style: t.labelSmall?.copyWith(color: s.primary, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const Spacer(),
            Text('${q.total} ${q.total == 1 ? 'answer' : 'answers'}', style: t.labelSmall),
          ]),
          const SizedBox(height: 6),
          Text(q.prompt, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: showResults
                  ? _ResultBar(
                      label: q.options[i],
                      count: q.counts![i],
                      total: q.total,
                      mine: q.myAnswer == i,
                      color: !q.isQuiz
                          ? s.primary
                          : i == q.correctIndex
                              ? green
                              : q.myAnswer == i
                                  ? red
                                  : s.outlineVariant,
                      mark: !q.isQuiz
                          ? null
                          : i == q.correctIndex
                              ? Icons.check_circle_rounded
                              : q.myAnswer == i
                                  ? Icons.cancel_rounded
                                  : null,
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                      onPressed: _busy ? null : () => _answer(i),
                      child: Text(q.options[i]),
                    ),
            ),
          if (!showResults)
            Text(q.isQuiz ? 'Pick one. You get one try, then see the answer.' : 'Pick one to see what others chose.',
                style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
          if (showResults && q.isQuiz && q.answered)
            Text(q.myAnswer == q.correctIndex ? 'Correct! 🎉' : 'Not quite. The right answer is in green.',
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: q.myAnswer == q.correctIndex ? green : red)),
        ]),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.label, required this.count, required this.total, required this.mine, required this.color, this.mark});
  final String label;
  final int count, total;
  final bool mine;
  final Color color;
  final IconData? mark;
  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(children: [
        Positioned.fill(child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)),
        Positioned.fill(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: pct,
            child: Container(color: color.withValues(alpha: 0.28)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            if (mark != null) ...[Icon(mark, size: 18, color: color), const SizedBox(width: 6)],
            Expanded(
              child: Text(label + (mine ? '  · your answer' : ''),
                  style: t.bodyMedium?.copyWith(fontWeight: mine ? FontWeight.w700 : FontWeight.w500)),
            ),
            Text('${(pct * 100).round()}%', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}
