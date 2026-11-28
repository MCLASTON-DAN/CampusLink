/// A message in a study group's chat.
class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.authorId,
    this.authorName = '',
    required this.body,
    this.replyTo,
    this.mentions = const [],
    this.mentionAll = false,
    this.pinned = false,
    this.deleted = false,
    this.reactions = const {},
    required this.createdAt,
  });
  final String id, groupId, authorId, authorName, body;
  final String? replyTo;
  final List<String> mentions;
  final bool mentionAll, pinned, deleted;
  final DateTime createdAt;

  /// Who reacted with what: user id -> 'like' | 'love' | 'haha' | 'wow' | 'sad' | 'pray'.
  final Map<String, String> reactions;

  GroupMessage copyWith({String? authorName, bool? pinned, bool? deleted, Map<String, String>? reactions}) => GroupMessage(
      id: id, groupId: groupId, authorId: authorId, authorName: authorName ?? this.authorName, body: body, replyTo: replyTo,
      mentions: mentions, mentionAll: mentionAll, pinned: pinned ?? this.pinned, deleted: deleted ?? this.deleted,
      reactions: reactions ?? this.reactions, createdAt: createdAt);

  GroupMessage withName(String name) => copyWith(authorName: name);

  factory GroupMessage.fromMap(Map<String, dynamic> m, {String name = ''}) => GroupMessage(
        id: m['id'] as String,
        groupId: m['group_id'] as String,
        authorId: m['author_id'] as String,
        authorName: name,
        body: (m['body'] ?? '') as String,
        replyTo: m['reply_to'] as String?,
        mentions: [for (final x in (m['mentions'] as List? ?? const [])) x.toString()],
        mentionAll: m['mention_all'] == true,
        pinned: m['pinned'] == true,
        deleted: m['deleted'] == true,
        reactions: {
          for (final e in ((m['reactions'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
        },
        createdAt: DateTime.parse(m['created_at'].toString()).toLocal(),
      );
}

/// Someone asking to join an invite-only group.
class GroupJoinRequest {
  const GroupJoinRequest({required this.id, required this.groupId, required this.userId, this.userName = '', this.message});
  final String id, groupId, userId, userName;
  final String? message;
}

/// A group member (for @mentions).
typedef GroupMember = ({String id, String name, String? username});

/// Finds @mentions in a message. "@all" alerts everyone; "@username" or
/// "@firstname" alerts that member. Unknown names are ignored.
({List<String> ids, bool all}) parseMentions(String text, List<GroupMember> members) {
  final words = RegExp(r'@([A-Za-z0-9._]+)').allMatches(text).map((m) => m.group(1)!.toLowerCase()).toSet();
  final all = words.contains('all') || words.contains('everyone');
  final ids = <String>[];
  for (final m in members) {
    final handles = {
      if ((m.username ?? '').isNotEmpty) m.username!.toLowerCase(),
      m.name.split(' ').first.toLowerCase(),
    };
    if (handles.any(words.contains)) ids.add(m.id);
  }
  return (ids: ids, all: all);
}
