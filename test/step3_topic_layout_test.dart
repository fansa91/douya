import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/data/repository.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/topic_detail_view.dart';

// 1x1 transparent PNG.
final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> get(String host, int port, String path) async =>
      _MockHttpClientRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse implements HttpClientResponse {
  @override
  int get contentLength => _transparentPng.length;

  @override
  int get statusCode => 200;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _scaffolded(Widget child) => Scaffold(body: child);

Future<void> _pumpPage(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// A long topic (100 replies) so the page scrolls and the jump
/// button appears.
class _LongTopicRepo extends FakeDoubanRepository {
  @override
  Future<TopicCommentsResult> fetchTopicComments(String topicId,
      {int start = 0, int count = 20}) async {
    final all = List.generate(
      100,
      (i) => TopicComment(
        authorName: i == 0 ? '房东' : '路人$i',
        authorId: i == 0 ? 'u-landlord' : 'u-$i',
        text: '回复内容$i',
        voteCount: 100 - i,
        createTime: '2026-11-20 10:00',
      ),
    );
    final page = start < all.length
        ? all.sublist(start, (start + count).clamp(0, all.length))
        : const <TopicComment>[];
    return TopicCommentsResult(comments: page, total: all.length);
  }
}

/// A topic whose body image matches a tall structured photo
/// (300x800), so the tall-image cap and hint render.
class _TallPhotoRepo extends FakeDoubanRepository {
  @override
  Future<TopicDetail> fetchTopic(String topicId) async {
    final base = await super.fetchTopic(topicId);
    return TopicDetail(
      topic: base.topic,
      content: base.content,
      contentHtml:
          '<p>正文。</p><img src="https://img.example/tall.jpg"><p>更多正文。</p>',
      comments: base.comments,
      commentsTotal: base.commentsTotal,
      popularComments: base.popularComments,
      groupId: base.groupId,
      groupName: base.groupName,
      sharingUrl: base.sharingUrl,
      ipLocation: base.ipLocation,
      photos: const [
        Photo(
          id: '1',
          url: 'https://img.example/tall.jpg',
          urlLarge: 'https://img.example/tall.jpg',
          width: 300,
          height: 800,
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('topic header is flat, author split in two lines, group capsule',
      (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(
        const TopicDetailPage(
          repository: FakeDoubanRepository(),
          topicId: '504122375',
        ),
      ),
      const Size(390, 3000),
    );
    // No Card left in the header (the fake topic has no video, so
    // no other Card exists on the page).
    expect(find.byType(Card), findsNothing);
    // The header column holds the title, the author name on its own
    // line, and time + IP on the next line. (The same meta string
    // also appears in comment rows, so scope the check to the
    // header.)
    final header = find.ancestor(
      of: find.text('8号线杨思民用水电 押一付一'),
      matching: find.byType(Column),
    ).first;
    expect(
      find.descendant(of: header, matching: find.text('房东')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.text('2026-11-20 10:00 · IP属地：上海'),
      ),
      findsOneWidget,
    );
    // The old single-line "name · IP · time" string is gone.
    expect(
      find.text('房东 · IP属地：上海 · 2026-11-20 10:00'),
      findsNothing,
    );
    // Group capsule, at least 40dp tall.
    expect(find.text('上海租房'), findsOneWidget);
    final capsule = find.ancestor(
      of: find.text('上海租房'),
      matching: find.byType(Material),
    );
    expect(capsule, findsWidgets);
    expect(tester.getSize(capsule.first).height, greaterThanOrEqualTo(40));
  });

  testWidgets('reply count is merged into the sticky tab row', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(
        const TopicDetailPage(
          repository: FakeDoubanRepository(),
          topicId: '504122375',
        ),
      ),
      const Size(390, 3000),
    );
    expect(find.text('回应 25'), findsOneWidget);
    // The count sits in the same row as the tabs, not on its own line.
    final row = find.ancestor(
      of: find.text('回应 25'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row.first, matching: find.byType(TabBar)),
      findsOneWidget,
    );
  });

  testWidgets('app bar shows the topic title after scrolling past the header',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          const TopicDetailPage(
            repository: FakeDoubanRepository(),
            topicId: '504122375',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('话题详情'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('话题详情'), findsNothing);
    expect(find.text('8号线杨思民用水电 押一付一'), findsWidgets);
  });

  testWidgets('body image reserves its aspect ratio, tall image is capped',
      (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(
        const TopicDetailPage(
          repository: FakeDoubanRepository(),
          topicId: '504122375',
        ),
      ),
      const Size(390, 3000),
    );
    // The fake body image has no matching photo, so it falls back
    // to the 4:3 placeholder aspect.
    final img = find.byWidgetPredicate(
      (w) =>
          w is CachedNetworkImage &&
          w.imageUrl == 'https://img.example/body.jpg',
    );
    expect(img, findsOneWidget);
    final aspect =
        find.ancestor(of: img, matching: find.byType(AspectRatio));
    expect(aspect, findsOneWidget);
    expect(
      tester.widget<AspectRatio>(aspect).aspectRatio,
      closeTo(4 / 3, 0.01),
    );
  });

  testWidgets('tall body image is capped with a view-full hint',
      (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(
        TopicDetailPage(
          repository: _TallPhotoRepo(),
          topicId: '504122375',
        ),
      ),
      const Size(390, 3000),
    );
    expect(find.text('点击查看全图'), findsOneWidget);
  });

  testWidgets('jump button scrolls to replies and back to top',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          TopicDetailPage(
            repository: _LongTopicRepo(),
            topicId: '504122375',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Long post, at the top: the button offers to jump to replies.
    expect(find.text('跳到回应'), findsOneWidget);
    await tester.tap(find.text('跳到回应'));
    await tester.pumpAndSettle();
    expect(find.text('回到顶部'), findsOneWidget);
    expect(find.text('热门').hitTestable(), findsOneWidget);
    await tester.tap(find.text('回到顶部'));
    await tester.pumpAndSettle();
    expect(find.text('跳到回应'), findsOneWidget);
  });

  testWidgets('desktop right column is 360 at 1000 wide, 460 at 1440 wide',
      (tester) async {
    for (final (width, expected) in [(1000.0, 360.0), (1440.0, 460.0)]) {
      await _pumpPage(
        tester,
        _scaffolded(
          const TopicDetailPage(
            repository: FakeDoubanRepository(),
            topicId: '504122375',
          ),
        ),
        Size(width, 900),
      );
      // The right column's own scroll view fills its width.
      final column = find.byType(CustomScrollView);
      expect(column, findsOneWidget);
      expect(tester.getSize(column).width, closeTo(expected, 0.5));
    }
  });
}
