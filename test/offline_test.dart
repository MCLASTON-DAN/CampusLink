import 'package:campuslink/data/community_models.dart';
import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/offline_cache.dart';
import 'package:campuslink/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A community whose network can be switched off.
class FlakyCommunity implements CommunityApi {
  bool down = false;
  final List<Post> data;
  FlakyCommunity(this.data);
  @override
  Future<List<Post>> posts({String? kind, int limit = 20, DateTime? before}) async {
    if (down) throw CommunityException('No connection');
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test('a saved copy never shows for a different account', () async {
    SharedPreferences.setMockInitialValues({});
    final c = OfflineCache(await SharedPreferences.getInstance());
    await c.save('amina', 'posts', [{'id': '1'}]);
    expect(c.load('amina', 'posts')!.$1.single['id'], '1');
    expect(c.load('brian', 'posts'), isNull);
    await c.save('brian', 'posts', [{'id': '2'}]);
    expect(c.load('amina', 'posts'), isNull, reason: 'a new account wipes the old one\'s copies');
    c.clear();
    expect(c.load('brian', 'posts'), isNull);
  });

  test('offline: feed shows the saved copy with the right badge, then fresh again', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalRepository(prefs);
    await repo.signIn(email: 'student@x.ug', password: 'password1');
    final post = Post(
      id: 'p1', publisherId: 'pub-press', publisherName: 'Newsroom', publisherKind: 'press',
      authorId: 'a', authorName: 'Reporter', authorPosition: '', kind: 'news',
      title: 'Hello', body: 'Body text', sourceNote: '', publishedAt: DateTime(2026, 11, 1), likes: 4,
    );
    final com = FlakyCommunity([post]);
    final c = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      communityProvider.overrideWithValue(com),
      offlineCacheProvider.overrideWithValue(OfflineCache(prefs)),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(postsProvider(null), (_, __) {});
    await c.read(currentUserProvider.future);

    expect((await c.read(postsProvider(null).future)).single.title, 'Hello');
    expect(c.read(offlineSinceProvider), isEmpty);

    com.down = true;
    c.invalidate(postsProvider);
    final saved = (await c.read(postsProvider(null).future)).single;
    expect(saved.publisherKind, 'press', reason: 'purple stays purple offline');
    expect(saved.likes, 4);
    expect(c.read(offlineSinceProvider).keys, contains('posts:all'));

    com.down = false;
    c.invalidate(postsProvider);
    await c.read(postsProvider(null).future);
    expect(c.read(offlineSinceProvider), isEmpty, reason: 'banner goes away once back online');
    sub.close();
  });
}
