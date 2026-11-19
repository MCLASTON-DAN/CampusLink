import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/section.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart';
import '../../core/image_tools.dart';
import 'policy_gate.dart';

const _filters = <String?, String>{
  null: 'All',
  'news': 'News',
  'clarification': 'Clarifications',
  'notice': 'Notices',
  'meeting_link': 'Meetings',
};

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  String? _kind;
  final _more = <Post>[]; // older pages loaded with "Load more"
  bool _loadingMore = false;
  bool _end = false;

  void _setKind(String? k) => setState(() {
        _kind = k;
        _more.clear();
        _end = false;
      });

  Future<void> _loadMore(List<Post> first) async {
    final all = [...first, ..._more];
    if (all.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(communityProvider).posts(kind: _kind, before: all.last.publishedAt);
      setState(() {
        _more.addAll(page);
        _end = page.length < 20;
      });
    } catch (_) {
      if (mounted) showSnack(context, 'Could not load more. Check your connection.');
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final posts = ref.watch(postsProvider(_kind));
    final mems = ref.watch(myMembershipsProvider).valueOrNull ?? [];
    final canPost = mems.any((m) => m.isActive && (m.can('news') || m.can('notices') || m.can('meeting_links')));
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Campus news')),
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
                      onSelected: (_) => _setKind(e.key),
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
                      onRefresh: () async {
                        setState(() {
                          _more.clear();
                          _end = false;
                        });
                        return ref.refresh(postsProvider(_kind).future);
                      },
                      child: Builder(builder: (context) {
                        final all = [...list, ..._more];
                        final canMore = !_end && list.length >= 20;
                        // Built lazily: only cards on screen are drawn.
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: all.length + (canMore ? 1 : 0),
                          itemBuilder: (_, i) => Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: i < all.length
                                  ? PostCard(all[i])
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: OutlinedButton(
                                        onPressed: _loadingMore ? null : () => _loadMore(list),
                                        child: Text(_loadingMore ? 'Loading…' : 'Load more'),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      }),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard(this.p, {super.key, this.compact = false});
  final Post p;
  final bool compact; // smaller card for the home screen carousel

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final media = MediaBanner.has(coverUrl: p.coverPath, videoUrl: p.videoUrl);
    return Card(
      margin: EdgeInsets.only(bottom: compact ? 0 : 12),
      child: InkWell(
        onTap: () => context.push('/news/${p.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (media) MediaBanner(coverUrl: p.coverPath, videoUrl: p.videoUrl),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: _KindPill(p)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${friendlyDate(p.publishedAt)}${p.isEdited ? ' · edited' : ''}',
                      style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 8),
              Text(p.title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
              if (!compact || !media) ...[
                const SizedBox(height: 6),
                Text(p.body, maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: t.bodySmall?.color)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: NameWithBadge(p.byline, badgeForKind(p.publisherKind), style: t.labelMedium)),
                Icon(p.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 16,
                    color: p.likedByMe ? Colors.redAccent : t.bodySmall?.color),
                Text(' ${p.likes}  ', style: t.bodySmall),
                Icon(Icons.mode_comment_outlined, size: 16, color: t.bodySmall?.color),
                Text(' ${p.comments}', style: t.bodySmall),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill(this.p);
  final Post p;
  @override
  Widget build(BuildContext context) {
    final c = switch (p.kind) {
      'clarification' => const Color(0xFFEA580C),
      'notice' || 'official_record' => const Color(0xFFE53935),
      'meeting_link' => const Color(0xFF0EA5E9),
      _ => Theme.of(context).colorScheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(p.kindLabel.toUpperCase(),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
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
              : PageBody(maxWidth: 760, children: [
                  if (MediaBanner.has(coverUrl: p.coverPath, videoUrl: p.videoUrl)) ...[
                    MediaBanner(coverUrl: p.coverPath, videoUrl: p.videoUrl, radius: 16),
                    const SizedBox(height: 16),
                  ],
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
          final r = await _ask('Why are you reporting this?', 10);
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
  bool _uploading = false;
  String? _cover;

  Future<void> _pickCover() async {
    setState(() => _uploading = true);
    try {
      final demo = ref.read(isDemoModeProvider);
      final bytes = await pickAndShrinkImage(maxBytes: demo ? 190 * 1024 : 900 * 1024);
      if (bytes != null) {
        final url = await ref.read(communityProvider).uploadImage(bytes, extension: 'jpg');
        if (mounted) setState(() => _cover = url);
      }
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
    if (mounted) setState(() => _uploading = false);
  }

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
      body: PageBody(maxWidth: 760, children: [
        CoverPicker(
          url: _cover,
          busy: _uploading,
          onClear: () => setState(() => _cover = null),
          onPick: _pickCover,
        ),
        const SizedBox(height: 14),
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
    if (_source.text.trim().length < 10) {
      showSnack(context, 'Say where this comes from (at least 10 letters).');
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
            coverPath: _cover,
          );
      if (mounted) context.pop();
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }
}
