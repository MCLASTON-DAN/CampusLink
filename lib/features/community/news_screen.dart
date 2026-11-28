import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/section.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm_send.dart';
import '../../widgets/media.dart';
import '../../core/image_tools.dart';
import 'policy_gate.dart';
import 'post_questions.dart';
import 'social.dart';
import '../../core/config.dart';

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
      if (mounted) setState(() {
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
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TimeStamp(p.publishedAt,
                        suffix: p.isRetracted ? ' · RETRACTED' : p.isEdited ? ' · edited' : '', style: t.bodySmall),
                  ),
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
                ReactionBar(targetType: 'post', targetId: p.id, likes: p.likes, liked: p.likedByMe, compact: true),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.push('/news/${p.id}?comments=1'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.mode_comment_outlined, size: 18, color: t.bodySmall?.color, semanticLabel: 'Comments'),
                      Text(' ${p.comments}', style: t.bodySmall),
                    ]),
                  ),
                ),
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
  const PostDetailScreen({super.key, required this.postId, this.openComments = false});
  final String postId;

  /// Opened from a card's comment button: scroll to the comments.
  final bool openComments;
  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailState();
}

class _PostDetailState extends ConsumerState<PostDetailScreen> {
  final _commentsKey = GlobalKey();
  Post? _post;
  bool _loading = true;
  int? _views; // only filled for the posting office and admins

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(communityProvider);
    final p = await api.post(widget.postId);
    if (mounted) setState(() {
      _post = p;
      _loading = false;
    });
    if (p == null) return;
    if (widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _commentsKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      });
    }
    await api.recordView(p.id);
    try {
      final v = await api.viewCount(p.id);
      if (mounted) setState(() => _views = v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final me = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('News'), actions: [
        if (p != null && !p.isRetracted)
          IconButton(tooltip: 'Share', icon: const Icon(Icons.share_rounded), onPressed: () => sharePost(context, p)),
        if (p != null && !p.isRetracted) _PostMenu(post: p, onChanged: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Post not found')
              : PageBody(maxWidth: 760, children: [
                  if (MediaBanner.has(coverUrl: p.coverPath, videoUrl: p.videoUrl)) ...[
                    MediaBanner(coverUrl: p.coverPath, videoUrl: p.videoUrl, radius: 16, full: true),
                    const SizedBox(height: 16),
                  ],
                  NameWithBadge(p.byline, badgeForKind(p.publisherKind), style: Theme.of(context).textTheme.titleSmall),
                  TimeStamp(p.publishedAt, prefix: '${p.kindLabel} · '),
                  EditedMark(p.editedAt),
                  if (p.isRetracted) RetractedBanner(word: 'Retracted', by: p.publisherName, reason: p.retractReason),
                  if (_views != null)
                    InkWell(
                      onTap: () => context.push('/insights'),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          const Icon(Icons.visibility_outlined, size: 16),
                          const SizedBox(width: 4),
                          Text('$_views ${_views == 1 ? 'person has' : 'people have'} opened this · view details',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(p.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800, decoration: p.isRetracted ? TextDecoration.lineThrough : null)),
                  const SizedBox(height: 10),
                  // A retracted post stays readable (people should see what was wrong), but faded.
                  Opacity(opacity: p.isRetracted ? 0.55 : 1, child: SelectableText(p.body)),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: const Text('Where this comes from'),
                      subtitle: Text(p.sourceNote.isEmpty ? 'No source given' : p.sourceNote),
                    ),
                  ),
                  PostQuestionsSection(postId: p.id),
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
                  CommentsSection(key: _commentsKey, targetType: 'post', targetId: p.id),
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
    return Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ReactionBar(targetType: widget.targetType, targetId: widget.targetId, likes: widget.likes, liked: widget.liked),
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

/// Kept as a name other screens use; the thread lives in social.dart.
class CommentsSection extends StatelessWidget {
  const CommentsSection({super.key, required this.targetType, required this.targetId});
  final String targetType, targetId;
  @override
  Widget build(BuildContext context) => CommentThread(targetType: targetType, targetId: targetId);
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
  final _questions = <DraftQuestion>[];

  /// Set once the post itself is saved, so a retry only resends the questions.
  String? _createdId;

  @override
  void dispose() {
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

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
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Write with the story guide'),
            subtitle: const Text('Answer a few short questions and we build a clear, well-structured story for you.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final r = await showStoryGuide(context);
              if (r == null) return;
              setState(() {
                _title.text = r.$1;
                _body.text = r.$2;
                if (r.$3.isNotEmpty && _source.text.trim().isEmpty) _source.text = r.$3;
              });
            },
          ),
        ),
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
        const SizedBox(height: 12),
        QuestionsEditor(drafts: _questions, locked: _createdId != null),
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
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_createdId == null ? 'Publish' : 'Save the questions again'),
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
    // Check the questions first, with the database's own rules, so we never
    // publish a post and then find its questions are refused.
    final qs = [for (final d in _questions) d.toQuestion()];
    for (var i = 0; i < qs.length; i++) {
      final bad = qs[i].problem;
      if (bad != null) {
        showSnack(context, 'Question ${i + 1}: $bad');
        return;
      }
    }
    if (_createdId == null &&
        !await confirmBeforeSending(context,
            title: _title.text.trim(),
            preview: _body.text.trim(),
            reach: 'Everyone on CampusLink, as ${_mem!.publisherName}. It is official and can be shared.',
            checks: const [
              'Names, dates, times and places are right',
              'The source is stated and real',
              'Spelling is right, and it is fair and true',
            ],
            sendLabel: 'Publish')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final api = ref.read(communityProvider);
    try {
      _createdId ??= (await api.createPost(
        publisherId: _mem!.publisherId,
        kind: _kind,
        title: _title.text,
        body: _body.text,
        sourceNote: _source.text,
        videoUrl: v,
        meetingUrl: _meeting.text.trim(),
        coverPath: _cover,
      ))
          .id;
      if (qs.isNotEmpty) await api.addPostQuestions(_createdId!, qs);
      if (mounted) context.pop();
    } on CommunityException catch (e) {
      if (mounted) {
        showSnack(
            context,
            _createdId == null
                ? e.message
                : 'Your post is live, but the questions did not save (${e.message}). Tap Publish to try the questions again.');
      }
    } catch (_) {
      if (mounted) {
        showSnack(
            context,
            _createdId == null
                ? 'Could not publish. Check your connection and try again.'
                : 'Your post is live, but the questions did not save. Tap Publish to try them again.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }
}


/// Share a post as a short preview card plus a link back to CampusLink.
/// The full article stays on CampusLink, which discourages copying.
Future<void> sharePost(BuildContext context, Post p) {
  final link = '${AppConfig.webUrl}/news/${p.id}';
  final clean = p.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final excerpt = clean.length > 180 ? '${clean.substring(0, 180).trimRight()}…' : clean;
  final text = '📰 ${p.title}\n${p.byline} · ${friendlyDate(p.publishedAt)}\n\n$excerpt\n\nRead the full story on CampusLink:\n$link';
  return showModalBottomSheet(
    useRootNavigator: true, // above the tab bar, never under it
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Share this post', style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (MediaBanner.has(coverUrl: p.coverPath, videoUrl: p.videoUrl))
                SizedBox(height: 140, child: MediaBanner(coverUrl: p.coverPath, videoUrl: p.videoUrl, radius: 0)),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NameWithBadge(p.byline, badgeForKind(p.publisherKind), style: Theme.of(sheet).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(p.title, style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(excerpt, maxLines: 4, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text('Full story on CampusLink', style: TextStyle(color: Theme.of(sheet).colorScheme.primary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Only this preview and the link are shared. Readers open CampusLink for the full story.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share (WhatsApp, etc.)'),
            onPressed: () async {
              Navigator.pop(sheet);
              try {
                await SharePlus.instance.share(ShareParams(text: text, subject: p.title));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) showSnack(context, 'Copied. Paste it into WhatsApp or anywhere.');
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy link'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (sheet.mounted) Navigator.pop(sheet);
              if (context.mounted) showSnack(context, 'Link copied');
            },
          ),
        ]),
      ),
    ),
  );
}


/// A guided template for writers: who, what, when, where, why, a quote and
/// what readers should do. Returns (title, body, source).
Future<(String, String, String)?> showStoryGuide(BuildContext context) {
  return Navigator.of(context).push<(String, String, String)>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _StoryGuide()),
  );
}

class _StoryGuide extends StatefulWidget {
  const _StoryGuide();
  @override
  State<_StoryGuide> createState() => _StoryGuideState();
}

class _StoryGuideState extends State<_StoryGuide> {
  final _c = {
    for (final k in ['headline', 'who', 'what', 'when', 'where', 'why', 'details', 'quote', 'quoteBy', 'action', 'contact', 'source'])
      k: TextEditingController(),
  };
  String _type = 'news';

  String v(String k) => _c[k]!.text.trim();

  String _sentence(String s) {
    if (s.isEmpty) return s;
    final t = s[0].toUpperCase() + s.substring(1);
    return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
  }

  (String, String, String) _build() {
    final lead = _sentence([
      if (v('who').isNotEmpty) v('who'),
      if (v('what').isNotEmpty) v('what'),
      if (v('when').isNotEmpty) 'on ${v('when')}',
      if (v('where').isNotEmpty) 'at ${v('where')}',
    ].join(' '));
    final parts = <String>[
      if (lead.isNotEmpty) lead,
      if (v('why').isNotEmpty) _sentence(v('why')),
      if (v('details').isNotEmpty) v('details'),
      if (v('quote').isNotEmpty) '“${v('quote')}”${v('quoteBy').isEmpty ? '' : ' — ${v('quoteBy')}'}',
      if (v('action').isNotEmpty) '${_type == 'notice' ? 'What you need to do' : 'What this means for you'}: ${_sentence(v('action'))}',
      if (v('contact').isNotEmpty) 'For more information: ${v('contact')}',
    ];
    var title = v('headline');
    if (title.isEmpty) title = lead.length > 90 ? '${lead.substring(0, 90)}…' : lead.replaceAll(RegExp(r'\.$'), '');
    return (title, parts.join('\n\n'), v('source'));
  }

  Widget _f(String k, String label, {String? hint, int lines = 1, bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k],
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 3,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint, alignLabelWithHint: lines > 1),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final preview = _build();
    final ready = v('what').isNotEmpty && (v('headline').isNotEmpty || v('who').isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text('Story guide')),
      body: PageBody(maxWidth: 760, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'news', label: Text('News story'), icon: Icon(Icons.newspaper_rounded)),
            ButtonSegment(value: 'notice', label: Text('Notice'), icon: Icon(Icons.campaign_rounded)),
          ],
          selected: {_type},
          onSelectionChanged: (x) => setState(() => _type = x.first),
        ),
        const SizedBox(height: 12),
        _f('headline', 'Headline', hint: 'Library opens 24 hours during exams'),
        _f('who', 'Who', hint: 'The University Library', required: true),
        _f('what', 'What happened / will happen', hint: 'will open 24 hours a day', required: true),
        _f('when', 'When', hint: 'Monday 1 December'),
        _f('where', 'Where', hint: 'the Main Library, Block A'),
        _f('why', 'Why it matters', hint: 'Students asked for more quiet study space before exams.', lines: 2),
        _f('details', 'More details', lines: 3),
        _f('quote', 'A quote (optional)', hint: 'We want every student to have a quiet place to revise.'),
        _f('quoteBy', 'Who said it', hint: 'Head Librarian'),
        _f('action', _type == 'notice' ? 'What students must do' : 'What students can do', hint: 'Bring your student ID after 8 pm.', lines: 2),
        _f('contact', 'Contact for questions', hint: 'library@cavendish.ac.ug'),
        _f('source', 'Where this information comes from', hint: 'Memo from the University Librarian, 20 Nov 2026'),
        const SizedBox(height: 8),
        Text('Preview', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(preview.$1.isEmpty ? 'Your headline' : preview.$1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(preview.$2.isEmpty ? 'Your story will appear here as you type.' : preview.$2),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: ready ? () => Navigator.pop(context, _build()) : null,
          child: const Text('Use this story'),
        ),
        const SizedBox(height: 4),
        const Text('You can still edit everything before posting.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}


/// Author: Edit. Author, office lead or super admin: Retract.
class _PostMenu extends ConsumerWidget {
  const _PostMenu({required this.post, required this.onChanged});
  final Post post;
  final Future<void> Function() onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final mems = ref.watch(myMembershipsProvider).valueOrNull ?? const <Membership>[];
    final author = me?.id == post.authorId;
    final lead = mems.any((m) => m.isActive && m.publisherId == post.publisherId && m.can('manage_members'));
    final canRetract = author || lead || (me?.isSuperAdmin ?? false);
    if (!author && !canRetract) return const SizedBox.shrink();
    final api = ref.read(communityProvider);
    return PopupMenuButton<String>(
      onSelected: (v) async {
        try {
          if (v == 'edit') {
            final t = TextEditingController(text: post.title), b = TextEditingController(text: post.body);
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Edit post'),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Everyone will see "Edited". The old version is kept for your office lead.'),
                    TextField(controller: t, decoration: const InputDecoration(labelText: 'Title')),
                    TextField(controller: b, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Text')),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save changes')),
                ],
              ),
            );
            if (ok != true || !context.mounted) return;
            if (!await confirmBeforeSending(context, title: t.text.trim(), preview: b.text.trim(),
                reach: 'Everyone who can see this post. It will show "Edited".', sendLabel: 'Save changes')) {
              return;
            }
            await api.updatePost(post.id, title: t.text, body: b.text);
          } else {
            final why = await askReason(context, title: 'Retract this post?', hint: 'e.g. The date was wrong. The talk is on Friday, not Thursday.');
            if (why == null) return;
            await api.retractPost(post.id, why);
          }
          await onChanged();
          ref.invalidate(postsProvider);
        } on CommunityException catch (e) {
          if (context.mounted) showSnack(context, e.message);
        }
      },
      itemBuilder: (_) => [
        if (author) const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'))),
        if (canRetract)
          const PopupMenuItem(value: 'retract', child: ListTile(leading: Icon(Icons.report_rounded), title: Text('Retract (it was wrong)'))),
      ],
    );
  }
}
