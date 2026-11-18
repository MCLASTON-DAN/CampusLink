import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import 'policy_gate.dart';

const _filters = <String?, String>{
  null: 'All',
  'news': 'News',
  'clarification': 'Clarifications',
  'notice': 'Notices',
  'meeting_link': 'Meetings',
};

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final posts = ref.watch(postsProvider(_kind));
    final mems = ref.watch(myMembershipsProvider).valueOrNull ?? [];
    final canPost = mems.any((m) => m.isActive && (m.can('news') || m.can('notices') || m.can('meeting_links')));
    return Scaffold(
      appBar: AppBar(title: const Text('Campus news')),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/news/new');
                ref.invalidate(postsProvider(_kind));
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Post'),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _kind == e.key,
                      onSelected: (_) => setState(() => _kind = e.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: posts,
              onRetry: () => ref.invalidate(postsProvider(_kind)),
              builder: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.newspaper_rounded,
                      title: 'Nothing here yet',
                      subtitle: 'Only verified offices can post news.')
                  : RefreshIndicator(
                      onRefresh: () async => ref.refresh(postsProvider(_kind).future),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                        itemCount: list.length,
                        itemBuilder: (_, i) => PostCard(list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard(this.p, {super.key});
  final Post p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/news/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: NameWithBadge(p.byline, badgeForKind(p.publisherKind), style: t.labelLarge)),
                const Spacer(),
                Text(friendlyDate(p.publishedAt), style: t.bodySmall),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                StatusChip(p.kindLabel, color: p.kind == 'clarification' ? Colors.orange : Colors.indigo),
                if (p.isEdited) const StatusChip('Edited', color: Colors.grey),
              ]),
              const SizedBox(height: 6),
              Text(p.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(p.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
              const SizedBox(height: 8),
              Row(children: [
                Icon(p.likedByMe ? Icons.favorite : Icons.favorite_border, size: 16),
                Text(' ${p.likes}   '),
                const Icon(Icons.chat_bubble_outline, size: 16),
                Text(' ${p.comments}'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;
  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailState();
}

class _PostDetailState extends ConsumerState<PostDetailScreen> {
  Post? _post;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ref.read(communityProvider).post(widget.postId);
    if (mounted) setState(() {
      _post = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final me = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Post not found')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  NameWithBadge(p.byline, badgeForKind(p.publisherKind), style: Theme.of(context).textTheme.titleSmall),
                  Text('${p.kindLabel} · ${friendlyDate(p.publishedAt)}${p.isEdited ? ' · edited' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  Text(p.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  SelectableText(p.body),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: const Text('Where this comes from'),
                      subtitle: Text(p.sourceNote.isEmpty ? 'No source given' : p.sourceNote),
                    ),
                  ),
                  if (p.videoUrl != null && p.videoUrl!.isNotEmpty)
                    OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(p.videoUrl!)),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Watch video (YouTube)')),
                  if (p.meetingUrl != null && p.meetingUrl!.isNotEmpty)
                    FilledButton.icon(
                        onPressed: () => launchUrl(Uri.parse(p.meetingUrl!)),
                        icon: const Icon(Icons.video_call_rounded),
                        label: const Text('Join meeting')),
                  const SizedBox(height: 8),
                  Reactions(targetType: 'post', targetId: p.id, likes: p.likes, liked: p.likedByMe, canRemove: me?.isSuperAdmin ?? false, onRemoved: () => context.pop()),
                  const Divider(height: 28),
                  CommentsSection(targetType: 'post', targetId: p.id),
                ]),
    );
  }
}

/// Like button, report and (super admin only) remove.
class Reactions extends ConsumerStatefulWidget {
  const Reactions({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.likes,
    required this.liked,
    this.canRemove = false,
    this.onRemoved,
  });
  final String targetType, targetId;
  final int likes;
  final bool liked;
  final bool canRemove;
  final VoidCallback? onRemoved;
  @override
  ConsumerState<Reactions> createState() => _ReactionsState();
}

class _ReactionsState extends ConsumerState<Reactions> {
  late int _likes = widget.likes;
  late bool _liked = widget.liked;

  Future<String?> _ask(String title, int min) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(helperText: 'At least $min letters')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return null;
    if (c.text.trim().length < min) {
      if (mounted) showSnack(context, 'Please write at least $min letters.');
      return null;
    }
    return c.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(communityProvider);
    return Wrap(spacing: 8, children: [
      TextButton.icon(
        onPressed: () async {
          try {
            final now = await api.toggleLike(widget.targetType, widget.targetId);
            setState(() {
              _liked = now;
              _likes += now ? 1 : -1;
            });
          } on CommunityException catch (e) {
            if (mounted) showSnack(context, e.message);
          }
        },
        icon: Icon(_liked ? Icons.favorite : Icons.favorite_border),
        label: Text('$_likes'),
      ),
      TextButton.icon(
        onPressed: () async {
          final r = await _ask('Why are you reporting this?', 5);
          if (r == null) return;
          try {
            await api.report(widget.targetType, widget.targetId, r);
            if (mounted) showSnack(context, 'Thanks. The administration will look at it.');
          } on CommunityException catch (e) {
            if (mounted) showSnack(context, e.message);
          }
        },
        icon: const Icon(Icons.flag_outlined),
        label: const Text('Report'),
      ),
      if (widget.canRemove)
        TextButton.icon(
          onPressed: () async {
            final r = await _ask('Remove this? The reason becomes public.', 20);
            if (r == null) return;
            try {
              await api.moderate(action: 'remove', targetType: widget.targetType, targetId: widget.targetId, reason: r);
              widget.onRemoved?.call();
            } on CommunityException catch (e) {
              if (mounted) showSnack(context, e.message);
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove'),
        ),
    ]);
  }
}

class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({super.key, required this.targetType, required this.targetId});
  final String targetType, targetId;
  @override
  ConsumerState<CommentsSection> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<CommentsSection> {
  List<Comment> _list = [];
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ref.read(communityProvider).comments(widget.targetType, widget.targetId);
    if (mounted) setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final api = ref.read(communityProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Comments (${_list.length})', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Comments always show your real name.', style: Theme.of(context).textTheme.bodySmall),
      for (final c in _list)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: NameWithBadge(c.authorName, c.badge, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(c.body),
          trailing: (me?.id == c.authorId || (me?.isStaff ?? false))
              ? IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    try {
                      if (me?.id == c.authorId) {
                        await api.deleteComment(c.id);
                      } else {
                        await api.moderate(
                            action: 'remove',
                            targetType: 'comment',
                            targetId: c.id,
                            reason: 'Removed by staff for breaking the posting code');
                      }
                      _load();
                    } on CommunityException catch (e) {
                      if (mounted) showSnack(context, e.message);
                    }
                  },
                )
              : null,
        ),
      Row(children: [
        Expanded(child: TextField(controller: _c, maxLength: 500, decoration: const InputDecoration(hintText: 'Write a comment'))),
        IconButton.filled(
          onPressed: _busy
              ? null
              : () async {
                  if (_c.text.trim().isEmpty) return;
                  setState(() => _busy = true);
                  try {
                    await api.addComment(widget.targetType, widget.targetId, _c.text);
                    _c.clear();
                    await _load();
                  } on CommunityException catch (e) {
                    if (mounted) showSnack(context, e.message);
                  }
                  if (mounted) setState(() => _busy = false);
                },
          icon: const Icon(Icons.send_rounded),
        ),
      ]),
    ]);
  }
}

// ------------------------------------------------------------- compose
class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({super.key});
  @override
  ConsumerState<ComposePostScreen> createState() => _ComposeState();
}

class _ComposeState extends ConsumerState<ComposePostScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _source = TextEditingController();
  final _video = TextEditingController();
  final _meeting = TextEditingController();
  Membership? _mem;
  String _kind = 'news';
  bool _pledge = false;
  bool _busy = false;

  List<String> _kindsFor(Membership m) => [
        if (m.can('news')) ...['news', 'clarification'],
        if (m.can('notices')) ...['notice', 'official_record'],
        if (m.can('meeting_links')) 'meeting_link',
      ];

  @override
  Widget build(BuildContext context) {
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive).toList();
    if (mems.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('New post')),
          body: const EmptyState(icon: Icons.lock_outline, title: 'Only office holders can post'));
    }
    _mem ??= mems.first;
    final kinds = _kindsFor(_mem!);
    if (!kinds.contains(_kind) && kinds.isNotEmpty) _kind = kinds.first;
    return Scaffold(
      appBar: AppBar(title: const Text('New post')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (mems.length > 1)
          DropdownButtonFormField<Membership>(
            isExpanded: true,
            value: _mem,
            decoration: const InputDecoration(labelText: 'Posting as'),
            items: [for (final m in mems) DropdownMenuItem(value: m, child: Text('${m.positionTitle} · ${m.publisherName}'))],
            onChanged: (v) => setState(() => _mem = v),
          )
        else
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_user_outlined),
              title: Text('Posting as ${_mem!.positionTitle}'),
              subtitle: Text('${_mem!.publisherName} · ${_mem!.daysLeft} days left in your term')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
            value: _kind,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(Post.kindLabels[k] ?? k))],
          onChanged: (v) => setState(() => _kind = v ?? 'news'),
        ),
        if (_kind == 'clarification')
          const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('A clarification answers a rumour with facts. Say exactly what is true and show the proof.')),
        const SizedBox(height: 8),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 8),
        TextField(controller: _body, minLines: 5, maxLines: 12, decoration: const InputDecoration(labelText: 'Message')),
        const SizedBox(height: 8),
        TextField(
            controller: _source,
            decoration: const InputDecoration(
                labelText: 'Where does this come from? (required)',
                helperText: 'Example: "Senate minutes, 12 Nov" or "Registrar, in person"')),
        const SizedBox(height: 8),
        if (_kind == 'news' || _kind == 'clarification')
          TextField(controller: _video, decoration: const InputDecoration(labelText: 'YouTube link (optional)')),
        if (_kind == 'meeting_link')
          TextField(controller: _meeting, decoration: const InputDecoration(labelText: 'Meeting link')),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _pledge,
          onChanged: (v) => setState(() => _pledge = v ?? false),
          title: const Text('I checked this is true. I understand my name and office are shown, and that false posts get removed in public.'),
        ),
        TextButton(onPressed: () => showPolicy(context, 'posting_code'), child: const Text('Read the posting code')),
        FilledButton(
          onPressed: _busy || !_pledge ? null : _submit,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Publish'),
        ),
      ]),
    );
  }

  Future<void> _submit() async {
    if (_title.text.trim().length < 5 || _body.text.trim().length < 20) {
      showSnack(context, 'Add a title (5+ letters) and a message (20+ letters).');
      return;
    }
    if (_source.text.trim().length < 5) {
      showSnack(context, 'Say where this comes from.');
      return;
    }
    final v = _video.text.trim();
    if (v.isNotEmpty && !(v.contains('youtube.com') || v.contains('youtu.be'))) {
      showSnack(context, 'Videos must be YouTube links.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(communityProvider).createPost(
            publisherId: _mem!.publisherId,
            kind: _kind,
            title: _title.text,
            body: _body.text,
            sourceNote: _source.text,
            videoUrl: v,
            meetingUrl: _meeting.text.trim(),
          );
      if (mounted) context.pop();
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }
}
