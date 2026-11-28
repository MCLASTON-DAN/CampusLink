import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm_send.dart';

/// The six chat reactions (WhatsApp's set). Stored by name, shown as emoji.
const chatReactions = <String, String>{
  'like': '👍',
  'love': '❤️',
  'haha': '😂',
  'wow': '😮',
  'sad': '😢',
  'pray': '🙏',
};

final _membersProvider = FutureProvider.autoDispose.family((ref, String id) => ref.watch(repositoryProvider).groupMembers(id));
final _asksProvider = FutureProvider.autoDispose.family((ref, String id) => ref.watch(repositoryProvider).groupJoinRequests(id));

/// A study group's members-only chat.
class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({super.key, required this.groupId});
  final String groupId;
  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _text = TextEditingController();
  final _messages = <String, GroupMessage>{};
  StreamSubscription<GroupMessage>? _live;
  StreamSubscription<Set<String>>? _typingSub;
  Set<String> _typing = {};
  GroupMessage? _replyTo;
  String? _mentionQuery; // text after the last '@' while choosing a member
  bool _loading = true, _sending = false;
  String? _error;

  CampusRepository get _repo => ref.read(repositoryProvider);
  String get _id => widget.groupId;

  @override
  void initState() {
    super.initState();
    _load();
    _live = _repo.groupMessageChanges(_id).listen((m) {
      if (mounted) setState(() => _messages[m.id] = m);
    });
    _typingSub = _repo.typingIn(_id).listen((names) {
      if (mounted) setState(() => _typing = names);
    });
  }

  Future<void> _load() async {
    try {
      final list = await _repo.groupMessages(_id);
      if (!mounted) return;
      setState(() {
        for (final m in list) {
          _messages[m.id] = m;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Only members can read this chat.';
        });
      }
    }
  }

  @override
  void dispose() {
    _live?.cancel();
    _typingSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _repo.sendTyping(_id);
    final m = RegExp(r'@([A-Za-z0-9._]*)$').firstMatch(v);
    setState(() => _mentionQuery = m?.group(1)?.toLowerCase());
  }

  void _insertMention(String handle) {
    final v = _text.text;
    final at = v.lastIndexOf('@');
    final next = '${v.substring(0, at)}@$handle ';
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() => _mentionQuery = null);
  }

  Future<void> _send(List<GroupMember> members) async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    final found = parseMentions(body, members);
    // @all alerts everyone: read it once more. Normal chat stays instant.
    if (found.all &&
        !await confirmBeforeSending(context,
            title: 'Message to everyone',
            preview: body,
            reach: 'All ${members.length} members get a notification.',
            checks: const ['It is worth alerting everyone']) ) {
      return;
    }
    if (!mounted) return;
    final reply = _replyTo;
    setState(() {
      _sending = true;
      _replyTo = null;
      _mentionQuery = null;
    });
    _text.clear();
    try {
      await _repo.sendGroupMessage(_id, body, replyTo: reply?.id, mentions: found.ids, mentionAll: found.all);
    } catch (_) {
      if (mounted) {
        _text.text = body; // give the words back
        setState(() => _replyTo = reply);
        showSnack(context, 'Not sent. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Adds, switches or removes my reaction; shows it at once, then keeps
  /// what the server says.
  Future<void> _react(GroupMessage m, String emoji, String? me) async {
    if (me == null) return;
    final before = m.reactions;
    final guess = Map<String, String>.of(before);
    guess[me] == emoji ? guess.remove(me) : guess[me] = emoji;
    setState(() => _messages[m.id] = m.copyWith(reactions: guess));
    try {
      final now = await _repo.reactToMessage(m.id, emoji);
      if (mounted) setState(() => _messages[m.id] = (_messages[m.id] ?? m).copyWith(reactions: now));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages[m.id] = (_messages[m.id] ?? m).copyWith(reactions: before));
      showSnack(context, '$e'.contains('Visitors') ? 'Visitors can read but not react.' : 'Could not react. Check your connection.');
    }
  }

  /// Who reacted with what, like WhatsApp. Tap your own to remove it.
  void _whoReacted(GroupMessage m, List<GroupMember> members, String? me) {
    final names = {for (final x in members) x.id: x.name};
    final rows = m.reactions.entries.toList()..sort((a, b) => a.key == me ? -1 : b.key == me ? 1 : 0);
    showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final r in rows)
            ListTile(
              leading: Text(chatReactions[r.value] ?? '👍', style: const TextStyle(fontSize: 24)),
              title: Text(r.key == me ? 'You' : (names[r.key] ?? 'A former member')),
              subtitle: r.key == me ? const Text('Tap to remove') : null,
              onTap: r.key != me
                  ? null
                  : () {
                      Navigator.pop(sheet);
                      _react(m, r.value, me);
                    },
            ),
        ]),
      ),
    );
  }

  Future<void> _actions(GroupMessage m, {required bool owner, required String? me}) async {
    final choice = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the tab bar, never under it
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // WhatsApp-style quick reactions; mine is highlighted.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in chatReactions.entries)
                InkResponse(
                  radius: 26,
                  onTap: () => Navigator.pop(sheet, 'react:${e.key}'),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: m.reactions[me] == e.key ? Theme.of(sheet).colorScheme.primaryContainer : null,
                    ),
                    child: Text(e.value, style: const TextStyle(fontSize: 28)),
                  ),
                ),
            ]),
          ),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () => Navigator.pop(sheet, 'reply')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy'), onTap: () => Navigator.pop(sheet, 'copy')),
          if (owner)
            ListTile(
              leading: Icon(m.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
              title: Text(m.pinned ? 'Unpin' : 'Pin for everyone'),
              onTap: () => Navigator.pop(sheet, 'pin'),
            ),
          if (m.authorId == me)
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete'), onTap: () => Navigator.pop(sheet, 'delete')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('react:')) return _react(m, choice.substring(6), me);
    try {
      switch (choice) {
        case 'reply':
          setState(() => _replyTo = m);
        case 'copy':
          await Clipboard.setData(ClipboardData(text: m.body));
        case 'pin':
          await _repo.pinGroupMessage(m.id, pin: !m.pinned);
        case 'delete':
          await _repo.deleteGroupMessage(m.id);
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e'.replaceFirst('Exception: ', '').replaceFirst(RegExp(r'^.*?: '), ''));
    }
  }

  Future<void> _manage(StudyGroup g) async {
    final asks = await _repo.groupJoinRequests(_id);
    if (!mounted) return;
    await showModalBottomSheet(
      useRootNavigator: true, // above the tab bar, never under it
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: StatefulBuilder(
          builder: (sheet, setS) => ListView(shrinkWrap: true, children: [
            SwitchListTile(
              title: const Text('Invite only'),
              subtitle: const Text('People ask to join and you approve them.'),
              value: g.inviteOnly,
              onChanged: (v) async {
                await _repo.setGroupPrivacy(_id, v ? 'invite' : 'open');
                ref.invalidate(studyGroupsProvider);
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
            ListTile(title: Text(asks.isEmpty ? 'No one is waiting to join' : 'Waiting to join (${asks.length})',
                style: const TextStyle(fontWeight: FontWeight.w700))),
            for (final a in asks)
              ListTile(
                title: Text(a.userName.isEmpty ? 'A student' : a.userName),
                subtitle: a.message == null ? null : Text(a.message!),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Decline',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      await _repo.decideGroupRequest(a.id, approve: false);
                      setS(() => asks.remove(a));
                    },
                  ),
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check_rounded, color: Color(0xFF14A44D)),
                    onPressed: () async {
                      await _repo.decideGroupRequest(a.id, approve: true);
                      setS(() => asks.remove(a));
                      ref.invalidate(_membersProvider(_id));
                      ref.invalidate(studyGroupsProvider);
                    },
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
    ref.invalidate(_asksProvider(_id));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull?.id;
    final g = ref.watch(studyGroupsProvider).valueOrNull?.where((x) => x.id == _id).firstOrNull;
    final owner = g != null && g.ownerId == me;
    final members = ref.watch(_membersProvider(_id)).valueOrNull ?? const <GroupMember>[];
    final asks = owner ? (ref.watch(_asksProvider(_id)).valueOrNull?.length ?? 0) : 0;
    final all = _messages.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final pinned = all.where((m) => m.pinned && !m.deleted).toList();
    final s = Theme.of(context).colorScheme;

    final suggestions = _mentionQuery == null
        ? const <(String, String)>[]
        : [
            if ('all'.startsWith(_mentionQuery!)) ('all', 'Everyone in the group'),
            for (final m in members)
              if (m.id != me)
                if (((m.username ?? '').toLowerCase().startsWith(_mentionQuery!)) ||
                    m.name.toLowerCase().startsWith(_mentionQuery!))
                  ((m.username ?? '').isNotEmpty ? m.username! : m.name.split(' ').first, m.name),
          ];

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/groups')),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g?.name ?? 'Group', overflow: TextOverflow.ellipsis),
          Text(
            _typing.isNotEmpty
                ? '${_typing.join(', ')} ${_typing.length == 1 ? 'is' : 'are'} typing…'
                : '${members.length} members${g?.inviteOnly == true ? ' · invite only' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _typing.isNotEmpty ? s.primary : null),
          ),
        ]),
        actions: [
          if (owner)
            IconButton(
              tooltip: 'Group settings and join requests',
              onPressed: () => _manage(g),
              icon: Badge(isLabelVisible: asks > 0, label: Text('$asks'), child: const Icon(Icons.manage_accounts_rounded)),
            ),
        ],
      ),
      body: _error != null
          ? EmptyState(icon: Icons.lock_outline_rounded, title: _error!)
          : Column(children: [
              if (pinned.isNotEmpty)
                Material(
                  color: s.secondaryContainer,
                  child: Column(children: [
                    for (final p in pinned)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.push_pin_rounded, size: 18),
                        title: Text(p.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(p.authorName),
                      ),
                  ]),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : all.isEmpty
                        ? const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', subtitle: 'Say hello. Type @ to mention someone.')
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            itemCount: all.length,
                            itemBuilder: (_, i) {
                              final m = all[all.length - 1 - i];
                              final original = m.replyTo == null ? null : _messages[m.replyTo];
                              // A day heading above the first message of each day.
                              final prev = all.length - 2 - i >= 0 ? all[all.length - 2 - i] : null;
                              final day = DateUtils.dateOnly(m.createdAt.toLocal());
                              final newDay = prev == null || DateUtils.dateOnly(prev.createdAt.toLocal()) != day;
                              final bubble = _Bubble(
                                m: m,
                                mine: m.authorId == me,
                                mentionsMe: m.mentionAll || m.mentions.contains(me),
                                original: original,
                                me: me,
                                onLongPress: () => _actions(m, owner: owner, me: me),
                                onReactionsTap: () => _whoReacted(m, members, me),
                              );
                              if (!newDay) return bubble;
                              return Column(children: [_DayHeader(day), bubble]);
                            },
                          ),
              ),
              if (suggestions.isNotEmpty)
                Material(
                  elevation: 2,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView(shrinkWrap: true, children: [
                      for (final (handle, name) in suggestions)
                        ListTile(dense: true, leading: const Icon(Icons.alternate_email_rounded), title: Text('@$handle'), subtitle: Text(name), onTap: () => _insertMention(handle)),
                    ]),
                  ),
                ),
              if (_replyTo != null)
                Container(
                  color: s.surfaceContainerHighest,
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: Row(children: [
                    const Icon(Icons.reply_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Replying to ${_replyTo!.authorName}: ${_replyTo!.body}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _replyTo = null)),
                  ]),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        onChanged: _onChanged,
                        decoration: const InputDecoration(hintText: 'Message · type @ to mention', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : () => _send(members),
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.m,
    required this.mine,
    required this.mentionsMe,
    required this.original,
    required this.me,
    required this.onLongPress,
    required this.onReactionsTap,
  });
  final GroupMessage m;
  final bool mine, mentionsMe;
  final GroupMessage? original;
  final String? me;
  final VoidCallback onLongPress, onReactionsTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bg = mine ? s.primaryContainer : (mentionsMe ? s.tertiaryContainer : s.surfaceContainerHighest);
    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: m.deleted ? null : onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) Text(m.authorName, style: t.labelMedium?.copyWith(color: s.primary, fontWeight: FontWeight.w700)),
            if (original != null)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: s.primary, width: 3)),
                  color: s.surface.withValues(alpha: 0.5),
                ),
                child: Text('${original!.authorName}: ${original!.deleted ? 'Message deleted' : original!.body}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
              ),
            m.deleted
                ? Text('Message deleted', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: s.onSurfaceVariant))
                : _MentionText(m.body),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (m.pinned) const Icon(Icons.push_pin_rounded, size: 12),
              Text(' ${DateFormat('HH:mm').format(m.createdAt.toLocal())}', style: t.labelSmall?.copyWith(color: s.onSurfaceVariant)),
            ]),
          ]),
        ),
      ),
    );
    if (m.deleted || m.reactions.isEmpty) return bubble;
    // The little reaction badge under the bubble: most-used first, then the count.
    final counts = <String, int>{};
    for (final r in m.reactions.values) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final top = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).map((e) => chatReactions[e.key] ?? '👍').join();
    final mineReacted = me != null && m.reactions.containsKey(me);
    return Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      bubble,
      Transform.translate(
        offset: const Offset(0, -6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Material(
            color: mineReacted ? s.primaryContainer : s.surfaceContainerHigh,
            shape: StadiumBorder(side: BorderSide(color: s.surface, width: 2)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onReactionsTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(m.reactions.length > 1 ? '$top ${m.reactions.length}' : top, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Shows @mentions in bold colour.
class _MentionText extends StatelessWidget {
  const _MentionText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in RegExp(r'@[A-Za-z0-9._]+').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: spans));
  }
}


/// "Today", "Yesterday", "Tuesday 25 Nov", or "25 Nov 2025" between messages.
class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);
  final DateTime day;
  @override
  Widget build(BuildContext context) {
    final now = DateUtils.dateOnly(DateTime.now());
    final label = day == now
        ? 'Today'
        : day == now.subtract(const Duration(days: 1))
            ? 'Yesterday'
            : day.year == now.year
                ? DateFormat('EEEE d MMM').format(day)
                : DateFormat('d MMM yyyy').format(day);
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}
