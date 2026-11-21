import '../models/models.dart';

/// One root comment and the replies nested under it, in time order
/// (the order the API returns them). At most two levels: a reply to
/// another reply stays under the same root, with [ThreadedComment.
/// replyTo] naming the comment it directly answers so the UI can
/// render "回复 @某某".
class CommentThread {
  const CommentThread({required this.root, this.children = const []});

  final TopicComment root;

  /// Replies to this root, in time order. Never contains the root
  /// itself.
  final List<ThreadedComment> children;
}

/// A reply inside a thread.
class ThreadedComment {
  const ThreadedComment({required this.comment, this.replyTo});

  final TopicComment comment;

  /// The comment this one directly answers, or null when it answers
  /// the root itself. Null for a direct reply to the root; set when
  /// the reply answers another reply (a second-level reply).
  final TopicComment? replyTo;
}

/// Rebuild the threads for a flat, time-ordered comment list.
///
/// The API returns comments flat by time with only a one-level
/// `ref_comment`; threading is rebuilt client-side by id. A comment
/// becomes a root when it has no ref, its ref is not in the loaded
/// set (parent not loaded yet, or parent deleted and so omitted
/// from the list), it carries no id, or its ref forms a self-reference
/// or a cycle. Every other comment nests under the topmost ancestor
/// it resolves to, so a deep chain flattens to two levels.
///
/// Pure and deterministic: rebuilding from the extended list after
/// a load-more only changes the roots that gained new replies, so
/// the UI can keep the rest untouched. Runs in O(n) over the loaded
/// list; the walk up a chain is bounded by the number of loaded
/// comments (the visited set breaks cycles).
List<CommentThread> buildCommentThreads(List<TopicComment> comments) {
  final byId = <String, TopicComment>{};
  for (final c in comments) {
    final id = c.id;
    if (id != null && !byId.containsKey(id)) byId[id] = c;
  }
  final childrenByRoot = <TopicComment, List<ThreadedComment>>{};
  final rootOrder = <TopicComment>[];
  for (final c in comments) {
    final root = _findRoot(c, byId);
    final children = childrenByRoot.putIfAbsent(root, () {
      rootOrder.add(root);
      return <ThreadedComment>[];
    });
    if (!identical(c, root)) {
      final parent = c.refCommentId == null ? null : byId[c.refCommentId!];
      children.add(
        ThreadedComment(
          comment: c,
          replyTo: parent == null || identical(parent, root) ? null : parent,
        ),
      );
    }
  }
  return rootOrder
      .map((r) => CommentThread(root: r, children: childrenByRoot[r] ?? const []))
      .toList();
}

/// The topmost ancestor [comment] resolves to, or [comment] itself
/// when it is a root. Walks up through refCommentId; a ref that is
/// not loaded, a self-reference, or a cycle stops the walk and makes
/// the comment a root.
TopicComment _findRoot(TopicComment comment, Map<String, TopicComment> byId) {
  var current = comment;
  final seen = <String>{};
  if (current.id != null) seen.add(current.id!);
  while (current.refCommentId != null) {
    final parentId = current.refCommentId!;
    if (seen.contains(parentId)) return comment;
    final parent = byId[parentId];
    if (parent == null) return comment;
    seen.add(parentId);
    current = parent;
  }
  return current;
}
