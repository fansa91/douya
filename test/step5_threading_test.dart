import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/data/local_lists.dart';
import 'package:douya/data/repository.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/topic_detail_view.dart';

/// A repo whose replies form two threads: A (id 1) with four
/// replies (B answers A, C answers B, D and E answer A), and F
/// (id 6) with none. Page 1 returns the first [pageSize] comments
/// so load-more can be driven by scrolling.
class _ThreadRepo extends FakeDoubanRepository {
  _ThreadRepo({this.pageSize = 20});

  final int pageSize;

  static const _a = TopicComment(
    authorName: '房东',
    authorId: 'u-landlord',
    text: '我是房东',
    id: '1',
    createTime: '2026-11-20 10:00',
  );
  static const _b = TopicComment(
    authorName: '路人1',
    text: '回复A',
    id: '2',
    refCommentId: '1',
    refComment: _a,
    createTime: '2026-11-20 10:01',
  );
  static const _c = TopicComment(
    authorName: '路人2',
    text: '回复B',
    id: '3',
    refCommentId: '2',
    refComment: _b,
    createTime: '2026-11-20 10:02',
  );
  static const _d = TopicComment(
    authorName: '路人3',
    text: '回复A2',
    id: '4',
    refCommentId: '1',
    refComment: _a,
    createTime: '2026-11-20 10:03',
  );
  static const _e = TopicComment(
    authorName: '路人4',
    text: '回复A3',
    id: '5',
    refCommentId: '1',
    refComment: _a,
    createTime: '2026-11-20 10:04',
  );
  static const _f = TopicComment(
    authorName: '路人5',
    text: '另一个根',
    id: '6',
    createTime: '2026-11-20 10:05',
  );

  static final _all = [_a, _b, _c, _d, _e, _f];

  @override
  Future<TopicCommentsResult> fetchTopicComments(
    String topicId, {
    int start = 0,
    int count = 20,
  }) async {
    final take = count < pageSize ? count : pageSize;
    final end = (start + take).clamp(0, _all.length);
    final page = start < _all.length ? _all.sublist(start, end) : const <TopicComment>[];
    return TopicCommentsResult(comments: page, total: _all.length);
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  DoubanRepository repo, {
  Size size = const Size(390, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TopicDetailPage(topicId: '504122375', repository: repo),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _enableThreaded(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.filter_list));
  await tester.pumpAndSettle();
  await tester.tap(find.text('楼中楼'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _ImageHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    await LocalLists.instance.setThreadedComments(false);
  });

  testWidgets('threaded mode nests replies, first two then expand', (tester) async {
    await _pumpPage(tester, _ThreadRepo());
    expect(find.text('回复A'), findsOneWidget);
    expect(find.text('展开其余 2 条回复'), findsNothing);
    await _enableThreaded(tester);
    // A's four replies (B, C, D, E) nest under it: first two
    // shown, the rest behind the expand button.
    expect(find.text('回复A'), findsOneWidget);
    // C answers B, so its body is the rich "回复 @路人1 回复B"
    // (the prefix and the body are one SelectableText).
    expect(find.text('回复 @路人1 回复B', findRichText: true), findsOneWidget);
    expect(find.text('回复A2'), findsNothing);
    expect(find.text('回复A3'), findsNothing);
    expect(find.text('展开其余 2 条回复'), findsOneWidget);
    // Expand: the hidden two appear, and the button goes away.
    await tester.tap(find.text('展开其余 2 条回复'));
    await tester.pump();
    expect(find.text('回复A2'), findsOneWidget);
    expect(find.text('回复A3'), findsOneWidget);
    expect(find.text('展开其余 2 条回复'), findsNothing);
  });

  testWidgets('threaded choice persists across pages', (tester) async {
    await _pumpPage(tester, _ThreadRepo());
    await _enableThreaded(tester);
    expect(LocalLists.instance.threadedComments, isTrue);
    // A fresh page reads the persisted choice and starts threaded.
    await _pumpPage(tester, _ThreadRepo());
    expect(find.text('展开其余 2 条回复'), findsOneWidget);
    expect(find.text('回复A2'), findsNothing);
  });

  testWidgets('只看楼主 forces flat, 热门 is always flat', (tester) async {
    await _pumpPage(tester, _ThreadRepo());
    await _enableThreaded(tester);
    expect(find.text('展开其余 2 条回复'), findsOneWidget);
    // 只看楼主 on: back to flat, only the author's reply shows.
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看楼主'));
    await tester.pumpAndSettle();
    expect(find.text('展开其余 2 条回复'), findsNothing);
    expect(find.text('我是房东'), findsOneWidget);
    expect(find.text('回复A'), findsNothing);
    // 只看楼主 off again: threading returns.
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看楼主'));
    await tester.pumpAndSettle();
    expect(find.text('展开其余 2 条回复'), findsOneWidget);
    // The 热门 tab is always flat, even in threaded mode.
    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();
    expect(find.text('展开其余 2 条回复'), findsNothing);
  });

  testWidgets('flat quote tap opens the conversation sheet', (tester) async {
    await _pumpPage(tester, _ThreadRepo());
    // B's quote block (first 查看对话 hint) opens the sheet.
    await tester.tap(find.text('查看对话').first);
    await tester.pumpAndSettle();
    expect(find.text('被回复的评论'), findsOneWidget);
    expect(find.text('当前评论'), findsOneWidget);
    expect(find.text('对当前评论的回复（1）'), findsOneWidget);
    // The parent (A), the current reply (B) and its reply (C).
    expect(find.text('我是房东'), findsWidgets);
    expect(find.text('回复A'), findsWidgets);
    expect(find.text('回复B'), findsWidgets);
  });

  testWidgets('threaded 查看对话 opens the sheet', (tester) async {
    await _pumpPage(tester, _ThreadRepo());
    await _enableThreaded(tester);
    // C is a thread child (last 查看对话 is C's button): its
    // conversation is parent B, current C, no replies.
    await tester.tap(find.text('查看对话').last);
    await tester.pumpAndSettle();
    expect(find.text('被回复的评论'), findsOneWidget);
    expect(find.text('当前评论'), findsOneWidget);
    expect(find.text('暂无回复'), findsOneWidget);
  });

  testWidgets('desktop quote tap shows the conversation in the right column', (tester) async {
    await _pumpPage(tester, _ThreadRepo(), size: const Size(1440, 900));
    await tester.tap(find.text('查看对话').first);
    await tester.pumpAndSettle();
    expect(find.text('被回复的评论'), findsOneWidget);
    expect(find.text('对当前评论的回复（1）'), findsOneWidget);
    // Back to the reply list.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('被回复的评论'), findsNothing);
    expect(find.text('回应 6'), findsOneWidget);
  });

  testWidgets('load-more grows a root count without auto-expanding', (tester) async {
    // Page 1: A and B only. Page 2 adds C, D, E, F.
    await _pumpPage(
      tester,
      _ThreadRepo(pageSize: 2),
      size: const Size(390, 800),
    );
    await _enableThreaded(tester);
    expect(find.text('展开其余'), findsNothing);
    // Scroll to the footer to load page 2.
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // A's thread now has four replies: first two shown, two hidden,
    // and the thread was NOT auto-expanded by the load.
    expect(find.text('展开其余 2 条回复'), findsOneWidget);
    expect(find.text('回复A2'), findsNothing);
  });
}

class _ImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
}

class _FakeHttpClientResponse implements HttpClientResponse {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
}

const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
