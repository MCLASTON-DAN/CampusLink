import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/config.dart';
import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';

/// The six reactions. Tap = 👍; press and hold to pick another.
const reactionEmojis = <String, String>{
  'like': '👍',
  'love': '❤️',
  'haha': '😂',
  'wow': '😮',
  'celebrate': '🎉',
  'sad': '😢',
};

/// Talks to react() / reaction_summary() (0028). In demo mode there is only
/// the old single "like".
class SocialApi {
  SocialApi._();
  static final instance = SocialApi._();
  bool get live => AppConfig.hasSupabase;

  Future<List<(String, int, bool)>> summary(String type, String id) async {
    final rows = await Supabase.instance.client.rpc('reaction_summary', params: {'p_type': type, 'p_id': id}) as List;
    return [for (final r in rows.cast<Map>()) ('${r['emoji']}', (r['n'] as num).toInt(), r['mine'] == true)];
  }

  /// Returns my reaction after the change (null = none).
  Future<String?> react(String type, String id, String emoji) async =>
      await Supabase.instance.client.rpc('react', params: {'p_type': type, 'p_id': id, 'p_emoji': emoji}) as String?;

  Future<void> recordAnnouncementViews(List<String> ids) =>
      Supabase.instance.client.rpc('record_announcement_views', params: {'p_ids': ids});

  Future<Map<String, (int, DateTime?)>> seenCounts(List<String> ids) async {
    final rows = await Supabase.instance.client.rpc('announcement_seen_counts', params: {'p_ids': ids}) as List;
    return {
      for (final r in rows.cast<Map>())
        '${r['announcement_id']}': (
          (r['seen'] as num).toInt(),
          r['reminded_at'] == null ? null : DateTime.tryParse('${r['reminded_at']}')
        ),
    };
  }

  Future<int> remindAnnouncement(String id) async =>
      (await Supabase.instance.client.rpc('remind_announcement', params: {'p_id': id}) as num).toInt();
}

/// Names in the picker.
const reactionNames = <String, String>{
  'like': 'Like',
  'love': 'Love',
  'haha': 'Haha',
  'wow': 'Wow',
  'celebrate': 'Celebrate',
  'sad': 'Sad',
};

/// What each reaction is called once chosen ("Liked", "Loved"…).
const reactionWords = <String, String>{
  'like': 'Liked',
  'love': 'Loved',
  'haha': 'Haha',
  'wow': 'Wow',
  'celebrate': 'Celebrated',
  'sad': 'Sad',
};

/// The like button, used everywhere something can be reacted to.
///
/// Tap = like (or undo). Press and hold = pick ❤️ 😂 😮 🎉 😢.
/// * full (post and event pages): "Like" button, the extra-reactions button and
///   the breakdown ("👍❤️ 12").
/// * [compact] (cards in lists): heart and count only, so a whole feed doesn't
///   load a breakdown per card.
/// The main button uses an icon, not an emoji, so it always shows even before
/// the browser has downloaded its emoji font.
class ReactionBar extends ConsumerStatefulWidget {
  const ReactionBar({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.likes,
    required this.liked,
    this.compact = false,
  });
  final String targetType, targetId;
  final int likes;
  final bool liked;
  final bool compact;
  @override
  ConsumerState<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends ConsumerState<ReactionBar> {
  final _api = SocialApi.instance;
  List<(String, int, bool)> _counts = const [];
  String? _mine;
  late int _total = widget.likes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mine = widget.liked ? 'like' : null;
    if (_api.live && !widget.compact) _load();
  }

  @override
  void didUpdateWidget(ReactionBar old) {
    super.didUpdateWidget(old);
    // A refreshed list brings new numbers.
    if (old.likes != widget.likes || old.liked != widget.liked) {
      _total = widget.likes;
      _mine = widget.liked ? (_mine ?? 'like') : null;
    }
  }

  Future<void> _load() async {
    try {
      final c = await _api.summary(widget.targetType, widget.targetId);
      if (!mounted) return;
      setState(() {
        _counts = c;
        _total = c.fold(0, (a, b) => a + b.$2);
        _mine = c.where((x) => x.$3).map((x) => x.$1).firstOrNull;
      });
    } catch (_) {/* keep the numbers we have */}
  }

  Future<void> _react(String emoji) async {
    if (_busy) return;
    final before = _mine;
    setState(() => _busy = true);
    try {
      final String? now;
      if (_api.live) {
        now = await _api.react(widget.targetType, widget.targetId, emoji);
      } else {
        now = await ref.read(communityProvider).toggleLike(widget.targetType, widget.targetId) ? 'like' : null;
      }
      if (!mounted) return;
      setState(() {
        _mine = now;
        _total += (now != null ? 1 : 0) - (before != null ? 1 : 0);
      });
      if (_api.live && !widget.compact) await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString().contains('Visitors') ? 'Visitors can read but not react.' : 'Could not react. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    if (!_api.live) return _react('like');
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy - 56, pos.dx + 300, pos.dy),
      items: [
        for (final e in reactionEmojis.entries)
          PopupMenuItem(
            value: e.key,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Text(e.value, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text(reactionNames[e.key]!),
            ]),
          ),
      ],
    );
    if (chosen != null) _react(chosen);
  }

  /// Heart for "like" or nothing yet, the chosen emoji otherwise.
  Widget _icon(Color? color, double size) => _mine == null || _mine == 'like'
      ? Icon(_mine == null ? Icons.favorite_border_rounded : Icons.favorite_rounded, size: size, color: color)
      : Text(reactionEmojis[_mine] ?? '👍', style: TextStyle(fontSize: size - 2));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final active = _mine == null ? null : Colors.redAccent;

    if (widget.compact) {
      return Semantics(
        button: true,
        label: _mine == null ? 'Like, $_total' : 'Unlike, $_total',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _busy ? null : () => _react(_mine ?? 'like'),
          onLongPress: _busy ? null : _pick,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _icon(active ?? small?.color, 18),
              Text(' $_total', style: small),
            ]),
          ),
        ),
      );
    }

    final top = _counts.take(3).map((x) => reactionEmojis[x.$1] ?? '👍').join();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onLongPress: _busy ? null : _pick,
        child: TextButton.icon(
          onPressed: _busy ? null : () => _react(_mine ?? 'like'),
          style: TextButton.styleFrom(foregroundColor: _mine == null ? c.onSurfaceVariant : Colors.redAccent),
          icon: _icon(active, 20),
          label: Text(_mine == null ? 'Like' : reactionWords[_mine] ?? 'Liked'),
        ),
      ),
      if (_api.live) IconButton(tooltip: 'Other reactions', onPressed: _busy ? null : _pick, icon: const Icon(Icons.add_reaction_outlined, size: 20)),
      if (_total > 0) Text(top.isEmpty ? '$_total' : '$top $_total', style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }
}

/// Comments with one level of replies and @mentions.
class CommentThread extends ConsumerStatefulWidget {
  const CommentThread({super.key, required this.targetType, required this.targetId});
  final String targetType, targetId;
  @override
  ConsumerState<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<CommentThread> {
  List<Comment> _list = [];
  final _c = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await ref.read(communityProvider).comments(widget.targetType, widget.targetId);
      if (mounted) setState(() => (_list = l, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityProvider).addComment(widget.targetType, widget.targetId, text, parentId: _replyTo?.id);
      _c.clear();
      setState(() => _replyTo = null);
      await _load();
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, e.toString().contains('Visitors') ? 'Visitors can read but not comment.' : 'Could not send. Try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(Comment c, bool mine) async {
    final api = ref.read(communityProvider);
    try {
      if (mine) {
        await api.deleteComment(c.id);
      } else {
        await api.moderate(action: 'remove', targetType: 'comment', targetId: c.id, reason: 'Removed by staff for breaking the posting code');
      }
      _load();
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final top = _list.where((c) => c.parentId == null).toList();
    final repliesOf = <String, List<Comment>>{};
    for (final c in _list.where((c) => c.parentId != null)) {
      (repliesOf[c.parentId!] ??= []).add(c);
    }
    // A reply whose parent was removed still shows, as a top comment.
    top.addAll(_list.where((c) => c.parentId != null && !_list.any((p) => p.id == c.parentId)));
    final t = Theme.of(context);

    Widget item(Comment c, {bool reply = false}) {
      final mine = me?.id == c.authorId;
      return Padding(
        padding: EdgeInsets.only(left: reply ? 40 : 0, top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: reply ? 13 : 16, child: Text(c.authorName.isEmpty ? '?' : c.authorName[0].toUpperCase())),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NameWithBadge(c.authorName, c.badge, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  _MentionText(c.body),
                ]),
              ),
              Row(children: [
                TimeStamp(c.createdAt),
                TextButton(
                  onPressed: () {
                    // Replies to a reply attach to the top comment (the database does the same).
                    setState(() => _replyTo = c);
                    _focus.requestFocus();
                  },
                  child: const Text('Reply'),
                ),
                if (mine || (me?.isStaff ?? false))
                  TextButton(onPressed: () => _delete(c, mine), child: Text(mine ? 'Delete' : 'Remove')),
              ]),
            ]),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Comments (${_list.length})', style: t.textTheme.titleMedium),
      Text('Comments always show your real name.', style: t.textTheme.bodySmall),
      if (_loading) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (!_loading && _list.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No comments yet. Start the conversation.', style: t.textTheme.bodySmall)),
      for (final c in top) ...[
        item(c),
        for (final r in repliesOf[c.id] ?? const <Comment>[]) item(r, reply: true),
      ],
      const SizedBox(height: 10),
      if (_replyTo != null)
        Row(children: [
          Expanded(child: Text('Replying to ${_replyTo!.authorName}', style: t.textTheme.bodySmall)),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
        ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _c,
            focusNode: _focus,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: _replyTo == null ? 'Write a comment… use @username to mention' : 'Write a reply',
            ),
          ),
        ),
        IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_rounded)),
      ]),
    ]);
  }
}

/// Body text with @mentions in bold colour.
class _MentionText extends StatelessWidget {
  const _MentionText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final spans = <TextSpan>[];
    var i = 0;
    for (final m in RegExp(r'@[a-zA-Z0-9._]{3,20}').allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(0), style: TextStyle(color: color, fontWeight: FontWeight.w700)));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: DefaultTextStyle.of(context).style, children: spans));
  }
}
