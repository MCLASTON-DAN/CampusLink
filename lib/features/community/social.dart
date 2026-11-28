import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/config.dart';
import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';

/// Talks to react() / reaction_summary() (0028). In demo mode there is only
/// the old single "like".
class SocialApi {
  SocialApi._();
  static final instance = SocialApi._();
  bool get live => AppConfig.hasSupabase;


  /// Returns my reaction after the change (null = none).

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

/// The ♡ like button (Instagram style), used on posts, events and comments.
///
/// Tap the heart to like or unlike. Tap the count to see who liked it.
/// * full: "♡ Like" and "12 likes" (post and event pages)
/// * [compact]: small heart and number (cards and comments)
/// [LikeButtonState.like] lets a double-tap on a picture like it too.
class LikeButton extends ConsumerStatefulWidget {
  const LikeButton({
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
  ConsumerState<LikeButton> createState() => LikeButtonState();
}

class LikeButtonState extends ConsumerState<LikeButton> {
  late bool _liked = widget.liked;
  late int _count = widget.likes;
  bool _busy = false;

  @override
  void didUpdateWidget(LikeButton old) {
    super.didUpdateWidget(old);
    // A refreshed list brings new numbers.
    if (old.likes != widget.likes || old.liked != widget.liked) {
      _liked = widget.liked;
      _count = widget.likes;
    }
  }

  /// Double-tap: like (never unlike).
  Future<void> like() async {
    if (!_liked) await _toggle();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    // Show it straight away, like Instagram; undo if the server says no.
    setState(() {
      _busy = true;
      _liked = !_liked;
      _count += _liked ? 1 : -1;
    });
    try {
      final now = await ref.read(communityProvider).toggleLike(widget.targetType, widget.targetId);
      if (mounted && now != _liked) {
        setState(() {
          _liked = now;
          _count += now ? 1 : -1;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !_liked;
        _count += _liked ? 1 : -1;
      });
      showSnack(context, e.toString().contains('Visitors') ? 'Visitors can read but not like.' : 'Could not like. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showLikers() {
    if (_count == 0) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => LikersSheet(targetType: widget.targetType, targetId: widget.targetId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final heart = Icon(
      _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: _liked ? Colors.redAccent : (widget.compact ? t.bodySmall?.color : null),
      size: widget.compact ? 18 : 24,
    );
    final countText = widget.compact ? '$_count' : '$_count ${_count == 1 ? 'like' : 'likes'}';

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: _liked ? 'Unlike' : 'Like',
        child: InkResponse(
          radius: widget.compact ? 18 : 22,
          onTap: _toggle,
          child: Padding(padding: EdgeInsets.all(widget.compact ? 6 : 8), child: heart),
        ),
      ),
      if (_count > 0 || !widget.compact)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _count == 0 ? null : _showLikers,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Text(
              _count == 0 ? 'Like' : countText,
              style: widget.compact ? t.bodySmall : t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
    ]);
  }
}

/// "Liked by": everyone who liked something, newest first.
class LikersSheet extends ConsumerWidget {
  const LikersSheet({super.key, required this.targetType, required this.targetId});
  final String targetType, targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: FutureBuilder<List<Liker>>(
          future: ref.read(communityProvider).likers(targetType, targetId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
            }
            final list = snap.data ?? const <Liker>[];
            return ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Liked by', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (snap.hasError) const ListTile(title: Text('Could not load. Check your connection.')),
              for (final l in list)
                ListTile(
                  leading: CircleAvatar(child: Text(l.name.isEmpty ? '?' : l.name[0].toUpperCase())),
                  title: NameWithBadge(l.name, l.badge),
                  subtitle: l.username == null ? null : Text('@${l.username}'),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Double-tap a picture to like it, with a heart that pops up (Instagram style).
class DoubleTapLike extends StatefulWidget {
  const DoubleTapLike({super.key, required this.onLike, required this.child});
  final Future<void> Function() onLike;
  final Widget child;
  @override
  State<DoubleTapLike> createState() => _DoubleTapLikeState();
}

class _DoubleTapLikeState extends State<DoubleTapLike> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        _c.forward(from: 0);
        widget.onLike();
      },
      child: Stack(alignment: Alignment.center, children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final v = _c.value;
              if (v == 0 || v == 1) return const SizedBox.shrink();
              final scale = v < 0.3 ? Curves.easeOutBack.transform(v / 0.3) : 1.0;
              final opacity = v < 0.7 ? 1.0 : 1 - (v - 0.7) / 0.3;
              return Opacity(
                opacity: opacity.clamp(0, 1),
                child: Transform.scale(
                  scale: scale,
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 96,
                      shadows: [Shadow(blurRadius: 24, color: Colors.black38)]),
                ),
              );
            },
          ),
        ),
      ]),
    );
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
  static final _small = TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 36),
  );

  List<Comment> _list = [];
  Map<String, (int, bool)> _likes = const {};
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
    final api = ref.read(communityProvider);
    try {
      final l = await api.comments(widget.targetType, widget.targetId);
      if (mounted) setState(() => (_list = l, _loading = false));
      // Like counts come second, so comments show without waiting for them.
      final likes = await api.likeCounts('comment', [for (final c in l) c.id]);
      if (mounted) setState(() => _likes = likes);
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
              // Wraps onto a second line on very narrow screens instead of overflowing.
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                TimeStamp(c.createdAt),
                TextButton(
                  style: _small,
                  onPressed: () {
                    // Replies to a reply attach to the top comment (the database does the same).
                    setState(() => _replyTo = c);
                    _focus.requestFocus();
                  },
                  child: const Text('Reply'),
                ),
                if (mine || (me?.isStaff ?? false))
                  TextButton(style: _small, onPressed: () => _delete(c, mine), child: Text(mine ? 'Delete' : 'Remove')),
              ]),
            ]),
          ),
          // Instagram-style: the heart sits on the right of each comment.
          LikeButton(
            key: ValueKey('like-${c.id}-${_likes[c.id]}'),
            targetType: 'comment',
            targetId: c.id,
            likes: _likes[c.id]?.$1 ?? 0,
            liked: _likes[c.id]?.$2 ?? false,
            compact: true,
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
