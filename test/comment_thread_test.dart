import 'package:flutter_test/flutter_test.dart';

import 'package:douya/data/comment_threads.dart';
import 'package:douya/models/models.dart';

TopicComment _c(String name, {String? id, String? refId, int votes = 0}) =>
    TopicComment(
      authorName: name,
      text: '正文 $name',
      voteCount: votes,
      id: id,
      refCommentId: refId,
    );

void main() {
  group('TopicComment id parsing', () {
    test('parses id and ref_comment id', () {
      final c = TopicComment.fromJson({
        'id': '5854641171',
        'text': '回复',
        'author': {'name': '路人', 'id': 'u-1'},
        'ref_comment': {'id': '5854196938', 'text': '原评论'},
      });
      expect(c.id, '5854641171');
      expect(c.refCommentId, '5854196938');
      // The quoted comment is still parsed one level deep.
      expect(c.refComment, isNotNull);
      expect(c.refComment!.text, '原评论');
    });

    test('missing ids stay null', () {
      final c = TopicComment.fromJson({
        'text': '回复',
        'author': {'name': '路人'},
      });
      expect(c.id, isNull);
      expect(c.refCommentId, isNull);
      expect(c.refComment, isNull);
    });

    test('a ref without an id gives no refCommentId', () {
      final c = TopicComment.fromJson({
        'id': '1',
        'text': '回复',
        'author': {'name': '路人'},
        'ref_comment': {'text': '原评论'},
      });
      expect(c.id, '1');
      expect(c.refCommentId, isNull);
    });
  });

  group('buildCommentThreads', () {
    test('a root with direct replies, in time order', () {
      final threads = buildCommentThreads([
        _c('A', id: '1'),
        _c('B', id: '2', refId: '1'),
        _c('C', id: '3'),
        _c('D', id: '4', refId: '1'),
      ]);
      expect(threads.length, 2);
      expect(threads[0].root.authorName, 'A');
      expect(
        threads[0].children.map((t) => t.comment.authorName),
        ['B', 'D'],
      );
      // Direct replies to the root carry no replyTo.
      expect(threads[0].children[0].replyTo, isNull);
      expect(threads[1].root.authorName, 'C');
      expect(threads[1].children, isEmpty);
    });

    test('a comment without an id is a root; with a ref it nests', () {
      final threads = buildCommentThreads([
        _c('A', id: '1'),
        _c('B'), // no id, no ref
        _c('C', refId: '1'), // no id, but answers A
      ]);
      expect(threads.length, 2);
      expect(threads[0].root.authorName, 'A');
      expect(
        threads[0].children.map((t) => t.comment.authorName),
        ['C'],
      );
      expect(threads[1].root.authorName, 'B');
    });

    test('a ref to a parent that is not loaded becomes a root', () {
      final threads = buildCommentThreads([
        _c('A', id: '1'),
        _c('B', id: '2', refId: '999'), // parent not in the list
      ]);
      expect(threads.length, 2);
      expect(threads[1].root.authorName, 'B');
      expect(threads[1].children, isEmpty);
    });

    test('a ref to a deleted parent becomes a root', () {
      // A deleted comment is omitted from the list, so its ref
      // resolves to nothing: the reply is shown as its own root,
      // with the quote block as the fallback (step 5 UI).
      final threads = buildCommentThreads([
        _c('A', id: '1'),
        _c('B', id: '2', refId: 'deleted-id'),
      ]);
      expect(threads.length, 2);
      expect(threads[1].root.authorName, 'B');
    });

    test('a self-reference becomes a root', () {
      final threads = buildCommentThreads([
        _c('A', id: '1', refId: '1'),
      ]);
      expect(threads.length, 1);
      expect(threads[0].root.authorName, 'A');
      expect(threads[0].children, isEmpty);
    });

    test('a two-comment cycle becomes two roots', () {
      final threads = buildCommentThreads([
        _c('A', id: '1', refId: '2'),
        _c('B', id: '2', refId: '1'),
      ]);
      expect(threads.length, 2);
      expect(threads[0].root.authorName, 'A');
      expect(threads[1].root.authorName, 'B');
      expect(threads[0].children, isEmpty);
      expect(threads[1].children, isEmpty);
    });

    test('a deep chain flattens to two levels', () {
      // A <- B <- C <- D: B answers A, C answers B, D answers C.
      // All three nest under A; replyTo names the direct parent.
      final a = _c('A', id: '1');
      final b = _c('B', id: '2', refId: '1');
      final c = _c('C', id: '3', refId: '2');
      final d = _c('D', id: '4', refId: '3');
      final threads = buildCommentThreads([a, b, c, d]);
      expect(threads.length, 1);
      expect(threads[0].root.authorName, 'A');
      expect(
        threads[0].children.map((t) => t.comment.authorName),
        ['B', 'C', 'D'],
      );
      expect(threads[0].children[0].replyTo, isNull);
      expect(threads[0].children[1].replyTo, same(b));
      expect(threads[0].children[2].replyTo, same(c));
    });

    test('appending a page only changes the affected root', () {
      final page1 = [
        _c('A', id: '1'),
        _c('B', id: '2'),
        _c('C', id: '3', refId: '1'),
      ];
      final before = buildCommentThreads(page1);
      expect(before.length, 2);
      expect(before[0].children.length, 1);
      expect(before[1].children, isEmpty);

      // Page 2 adds a reply to B and a new root.
      final page2 = [
        ...page1,
        _c('D', id: '4', refId: '2'),
        _c('E', id: '5'),
      ];
      final after = buildCommentThreads(page2);
      expect(after.length, 3);
      // A is untouched, B gained one child, E is a new root.
      expect(after[0].root.authorName, 'A');
      expect(after[0].children.length, 1);
      expect(after[1].root.authorName, 'B');
      expect(
        after[1].children.map((t) => t.comment.authorName),
        ['D'],
      );
      expect(after[2].root.authorName, 'E');
    });

    test('an empty list builds no threads', () {
      expect(buildCommentThreads(const []), isEmpty);
    });
  });
}
