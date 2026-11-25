import 'package:campuslink/data/community_models.dart';
import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('question rules match the database', () {
    PostQuestion q(String kind, String p, List<String> o, [int? c]) =>
        PostQuestion(kind: kind, prompt: p, options: o, correctIndex: c);
    expect(q('poll', 'Best day?', ['Mon', 'Tue']).problem, isNull);
    expect(q('poll', 'Hi', ['a', 'b']).problem, isNotNull, reason: 'too short');
    expect(q('poll', 'Best day?', ['Mon']).problem, isNotNull, reason: 'one choice');
    expect(q('poll', 'Best day?', ['Mon', ' ']).problem, isNotNull, reason: 'empty choice');
    expect(q('poll', 'Best day?', ['Mon', 'Mon']).problem, isNotNull, reason: 'duplicate');
    expect(q('quiz', 'Capital of Uganda?', ['Kampala', 'Gulu']).problem, isNotNull, reason: 'no right answer');
    expect(q('quiz', 'Capital of Uganda?', ['Kampala', 'Gulu'], 0).problem, isNull);
  });

  test('quiz: answer hidden until you answer, one try only, author sees results', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());

    await r.signIn(email: 'guild@x.ug', password: 'password1');
    final m = (await r.community.myMemberships()).firstWhere((m) => m.can('news'));
    final post = await r.community.createPost(
        publisherId: m.publisherId, kind: 'news', title: 'Quiz time', body: 'x' * 30, sourceNote: 'Guild office');
    final quiz = PostQuestion(kind: 'quiz', prompt: 'Capital of Uganda?', options: ['Gulu', 'Kampala'], correctIndex: 1);
    await expectLater(
        r.community.addPostQuestions(post.id, [PostQuestion(kind: 'quiz', prompt: 'No answer set', options: ['a', 'b'])]),
        throwsA(isA<CommunityException>()));
    await r.community.addPostQuestions(post.id, [quiz]);
    await r.signOut();

    await r.signIn(email: 'student@x.ug', password: 'password1');
    await expectLater(r.community.addPostQuestions(post.id, [quiz]), throwsA(isA<CommunityException>()),
        reason: 'only the author adds questions');
    var q = (await r.community.postQuestions(post.id)).single;
    expect(q.correctIndex, isNull, reason: 'no peeking');
    expect(q.counts, isNull);
    await r.community.answerQuestion(q.id, 0);
    await expectLater(r.community.answerQuestion(q.id, 1), throwsA(isA<CommunityException>()), reason: 'one try');
    q = (await r.community.postQuestions(post.id)).single;
    expect((q.myAnswer, q.correctIndex, q.total), (0, 1, 1));
    expect(q.counts, [1, 0]);
    await r.signOut();

    await r.signIn(email: 'guild@x.ug', password: 'password1');
    q = (await r.community.postQuestions(post.id)).single;
    expect(q.counts, [1, 0], reason: 'the author sees results without answering');
  });
}
