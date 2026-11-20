import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:douya/data/fake_repository.dart';
import 'package:douya/data/local_lists.dart';
import 'package:douya/data/repository.dart';
import 'package:douya/main.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/adaptive_scaffold.dart';
import 'package:douya/ui/breakpoints.dart';
import 'package:douya/ui/browse_page.dart';
import 'package:douya/ui/group_page.dart';
import 'package:douya/ui/group_topics_view.dart';
import 'package:douya/ui/home_page.dart';
import 'package:douya/ui/rankings_page.dart';
import 'package:douya/ui/settings_page.dart';
import 'package:douya/ui/topic_detail_view.dart';
import 'package:douya/ui/subject_page.dart';
import 'package:douya/ui/user_page.dart';
import 'package:douya/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget smoke tests for the adaptive layouts (task 7): each of the
/// five main pages is pumped at four window sizes and must build
/// without throwing. A RenderFlex overflow throws during layout, so
/// a passing test means no overflow at that size. The tests use
/// FakeDoubanRepository (immediate futures, no network, no secrets)
/// and never pump DouyaApp itself: that widget needs
/// SettingsStore.init() plus the DynamicColorBuilder, while the pages
/// only read SettingsStore defaults, which work without init.
///
/// Images are stubbed at the HttpClient level: every request returns
/// a 1x1 transparent PNG, so no test ever touches the douban CDN
/// (which would 418/403 bare requests and be slow even with headers).
/// The stub only implements what package:http's IOClient actually
/// touches (openUrl, headers.set, contentLength, close, listen,
/// statusCode, contentLength, redirects, headers.forEach); everything
/// else falls through to noSuchMethod.

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
  HttpHeaders get headers => _MockHttpHeaders();

  @override
  int contentLength = -1;

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPng.length;

  @override
  HttpHeaders get headers => _MockHttpHeaders();

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _repository = FakeDoubanRepository();

const _sizes = <(String, Size)>[
  ('phone 360x800', Size(360, 800)),
  ('phone-land 800x360', Size(800, 360)),
  ('tablet 768x1024', Size(768, 1024)),
  ('desktop 1440x900', Size(1440, 900)),
];

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

/// A browse repo whose one subject carries a pic URL, so the
/// poster card renders a real CachedNetworkImage (the test
/// HttpClient stub serves a 1x1 PNG for any URL).
class _PicBrowseRepo extends FakeDoubanRepository {
  @override
  Future<BrowseResult> fetchBrowse(String category, String filter,
          {int start = 0, int count = 20}) async =>
      const BrowseResult(items: [
        Subject(
            id: '1292052',
            type: 'movie',
            title: '肖申克的救赎',
            pic: 'https://example.com/p.jpg'),
      ], total: 1);
}

/// A browse repo whose responses only complete when the test says
/// so, keyed by category/filter/start.
class _SlowBrowseRepo extends FakeDoubanRepository {
  _SlowBrowseRepo();
  final calls = <String, Completer<BrowseResult>>{};
  @override
  Future<BrowseResult> fetchBrowse(String category, String filter,
          {int start = 0, int count = 20}) =>
      (calls['$category/$filter/$start'] = Completer<BrowseResult>()).future;
}

/// A repo whose board-items endpoint always fails.
class _NoFullBoards extends FakeDoubanRepository {
  const _NoFullBoards();
  @override
  Future<BrowseResult> fetchBoardItems(String boardId,
          {int start = 0, int count = 20}) async =>
      throw Exception('404');
}

/// A feed repo returning a scripted sequence of pages; each call
/// consumes the next entry, and the last entry repeats. Models the
/// real feed's rotation: the same ids can come back on a later call.
class _ScriptedFeedRepo extends FakeDoubanRepository {
  _ScriptedFeedRepo(this.pages);

  final List<List<FeedItem>> pages;
  var calls = 0;

  @override
  Future<FeedResult> fetchRecommendFeed({int start = 0, int count = 20}) async {
    final page = pages[calls < pages.length ? calls : pages.length - 1];
    calls++;
    return FeedResult(items: page);
  }
}

/// A feed repo whose first page never arrives: the skeleton must
/// show instead of a spinner or an empty page.
class _NeverFeedRepo extends FakeDoubanRepository {
  final _gate = Completer<FeedResult>();

  @override
  Future<FeedResult> fetchRecommendFeed({int start = 0, int count = 20}) => _gate.future;
}

/// A feed repo whose second call fails and whose later calls return
/// one fresh item: the footer retry must recover.
class _FlakyFeedRepo extends FakeDoubanRepository {
  var calls = 0;

  @override
  Future<FeedResult> fetchRecommendFeed({int start = 0, int count = 20}) async {
    calls++;
    if (calls == 2) throw Exception('boom');
    if (calls >= 3) {
      return const FeedResult(items: [
        FeedItem(id: 'new1', type: 'topic', title: '新来的一条', authorName: '新人'),
      ]);
    }
    return const FeedResult(items: [
      FeedItem(id: 'a', type: 'topic', title: '第一条', authorName: '甲'),
      FeedItem(id: 'b', type: 'topic', title: '第二条', authorName: '乙'),
    ]);
  }
}

/// A feed repo that serves one page until the test flips
/// [serveFresh], then serves a fresh page: the refresh banner
/// needs a mostly-new list. (A call-count switch would be
/// consumed by the footer's auto-load retries instead.)
class _RefreshFeedRepo extends FakeDoubanRepository {
  var serveFresh = false;

  @override
  Future<FeedResult> fetchRecommendFeed({int start = 0, int count = 20}) async {
    if (serveFresh) {
      return const FeedResult(items: [
        FeedItem(id: 'c', type: 'topic', title: '第三条', authorName: '丙'),
        FeedItem(id: 'd', type: 'review', title: '第四条', authorName: '丁'),
      ]);
    }
    return const FeedResult(items: [
      FeedItem(id: 'a', type: 'topic', title: '第一条', authorName: '甲'),
      FeedItem(id: 'b', type: 'topic', title: '第二条', authorName: '乙'),
    ]);
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
    // The user page binds ids and records recent users through
    // LocalLists (SharedPreferences); the mock keeps those calls
    // off the real platform channel.
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() => HttpOverrides.global = null);

  for (final (name, size) in _sizes) {
    testWidgets('shell renders at $name', (tester) async {
      await _pumpPage(
        tester,
        const AdaptiveScaffold(repository: _repository),
        size,
      );
    });

    testWidgets('browse (recommend) renders at $name', (tester) async {
      await _pumpPage(
        tester,
        _scaffolded(const BrowsePage(repository: _repository)),
        size,
      );
    });

    testWidgets('subject detail renders at $name', (tester) async {
      await _pumpPage(
        tester,
        const SubjectPage(
          repository: _repository,
          type: 'movie',
          id: '1292052',
        ),
        size,
      );
    });

    testWidgets('group renders at $name', (tester) async {
      await _pumpPage(
        tester,
        _scaffolded(const GroupPage(repository: _repository)),
        size,
      );
    });

    // Step 5: the pushed group detail (mobile slivers / desktop
    // split with placeholder) and the restyled topic detail.
    testWidgets('group detail renders at $name', (tester) async {
      await _pumpPage(
        tester,
        _scaffolded(
          const GroupTopicsPage(repository: _repository, groupId: '146409'),
        ),
        size,
      );
    });

    testWidgets('topic detail renders at $name', (tester) async {
      await _pumpPage(
        tester,
        _scaffolded(
          const TopicDetailPage(repository: _repository, topicId: '504122375'),
        ),
        size,
      );
    });

    // Step 5: the user page, bound (profile + interests) and
    // unbound (bind guide).
    testWidgets('user page (bound) renders at $name', (tester) async {
      await _pumpPage(
        tester,
        _scaffolded(
          const UserPage(repository: _repository, initialUserId: '2870956'),
        ),
        size,
      );
    });

    testWidgets('user page (guide) renders at $name', (tester) async {
      await LocalLists.instance.setMyUserId(null);
      await _pumpPage(
        tester,
        _scaffolded(const UserPage(repository: _repository)),
        size,
      );
    });

    testWidgets('rankings renders at $name', (tester) async {
      await _pumpPage(
        tester,
        _scaffolded(const RankingsPage(repository: _repository)),
        size,
      );
    });

    testWidgets('settings renders at $name', (tester) async {
      await _pumpPage(tester, const SettingsPage(), size);
    });
  }

  // Step 4 (feed redo): dedupe, filter, read state, skeleton,
  // footer retry, new-content banner. The fake feed returns the
  // same two items on every call, which is exactly the rotation
  // the dedupe logic must survive.
  testWidgets('feed dedupes rotated pages and stops when nothing new arrives', (tester) async {
    const a = FeedItem(id: 'a', type: 'topic', title: '第一条', authorName: '甲');
    const b = FeedItem(id: 'b', type: 'topic', title: '第二条', authorName: '乙');
    const c = FeedItem(id: 'c', type: 'topic', title: '第三条', authorName: '丙');
    const d = FeedItem(id: 'd', type: 'review', title: '第四条', authorName: '丁');
    final repo = _ScriptedFeedRepo([
      [a, b],
      [c, d],
      [a, b],
    ]);
    await _pumpPage(
      tester,
      _scaffolded(HomePage(repository: repo)),
      const Size(390, 3000),
    );
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    expect(find.text('第三条'), findsOneWidget);
    expect(find.text('第四条'), findsOneWidget);
    expect(find.text('已全部加载'), findsOneWidget);
  });

  testWidgets('feed filter shows only matching types', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(const HomePage(repository: _repository)),
      const Size(390, 800),
    );
    await tester.tap(find.text('讨论'));
    await tester.pumpAndSettle();
    expect(find.text('假数据示例话题：周末重看了一遍老电影，还是开头那段最耐看。'), findsOneWidget);
    expect(find.text('标题这句话我放这了，过几年回头看看是不是这样。'), findsNothing);
    await tester.tap(find.text('长评'));
    await tester.pumpAndSettle();
    expect(find.text('假数据示例话题：周末重看了一遍老电影，还是开头那段最耐看。'), findsNothing);
    expect(find.text('标题这句话我放这了，过几年回头看看是不是这样。'), findsOneWidget);
  });

  testWidgets('opening a feed card marks it read', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(const HomePage(repository: _repository)),
      const Size(390, 800),
    );
    await tester.tap(find.text('假数据示例话题：周末重看了一遍老电影，还是开头那段最耐看。'));
    await tester.pumpAndSettle();
    expect(find.text('8号线杨思民用水电 押一付一'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(LocalLists.instance.isFeedRead('503570060'), isTrue);
  });

  testWidgets('feed shows a skeleton while the first page loads', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: _scaffolded(HomePage(repository: _NeverFeedRepo()))),
    );
    await tester.pump();
    expect(find.byType(FeedSkeleton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feed load-more failure shows a footer retry', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(HomePage(repository: _FlakyFeedRepo())),
      const Size(390, 3000),
    );
    expect(find.text('加载失败，点击重试'), findsOneWidget);
    await tester.tap(find.text('加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('新来的一条'), findsOneWidget);
    expect(find.text('加载失败，点击重试'), findsNothing);
  });

  testWidgets('feed refresh with mostly new items shows a banner', (tester) async {
    final repo = _RefreshFeedRepo();
    final ticks = ValueNotifier<int>(0);
    await _pumpPage(
      tester,
      _scaffolded(HomePage(repository: repo, refreshListenable: ticks)),
      const Size(390, 800),
    );
    repo.serveFresh = true;
    ticks.value++;
    await tester.pumpAndSettle();
    expect(find.text('有 2 条新内容'), findsOneWidget);
    expect(find.text('第三条'), findsOneWidget);
    expect(find.text('第一条'), findsNothing);
  });

  // Browse's other two layouts: poster grid (desktop) and list (phone).
  testWidgets('browse grid renders at desktop 1440x900', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(
        const BrowsePage(repository: _repository, initialCategory: 'movie'),
      ),
      const Size(1440, 900),
    );
  });

  testWidgets('browse list renders at phone 360x800', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(
        const BrowsePage(repository: _repository, initialCategory: 'movie'),
      ),
      const Size(360, 800),
    );
  });

  // Task 5: the group split appears at expanded widths (list 360),
  // i.e. at a ~1100 window the split is already showing.
  testWidgets('group splits at 1100x800 (expanded, 360 list)', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(const GroupPage(repository: _repository)),
      const Size(1100, 800),
    );
  });

  // 130% text scaling on the shell, at the two sizes that matter most.
  for (final size in [const Size(360, 800), const Size(1440, 900)]) {
    testWidgets('shell renders at $size with 130% text scaling',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final mediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: const AdaptiveScaffold(repository: _repository),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // 130% text scaling on the rankings page, at the two sizes that
  // matter most.
  for (final size in [const Size(360, 800), const Size(1440, 900)]) {
    testWidgets('rankings renders at $size with 130% text scaling',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final mediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: _scaffolded(const RankingsPage(repository: _repository)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // Step 7: the poster grid never loses columns as the window
  // widens, and each cell stays a reasonable width.
  //
  // Two corrections to the first draft of this test: the content
  // width is capped at 1440 by the page's CenteredWidth (without
  // the cap the model keeps growing past the real layout), and the
  // cell range is 150-270, not 150-240 — a 2-column cell peaks at
  // ~262 just before the 3rd column appears. The failure was at
  // window 612 (cell 241.5), not at the 1023/1024 rail switch.
  test('poster grid never loses columns as the window widens', () {
    var last = 0;
    for (var w = 600.0; w <= 2560; w += 4) {
      final rawContent = w < 1024 ? w - 81 : w - 257; // rail width estimate
      final content = rawContent > 1440 ? 1440.0 : rawContent;
      final spec = PosterGridSpec.fit(content - 32, 1.0);
      expect(spec.columns, greaterThanOrEqualTo(last), reason: 'window $w');
      expect(spec.cellWidth, inInclusiveRange(150, 270), reason: 'window $w');
      last = spec.columns;
    }
  });

  // Step 7: the poster's image area is close to 2:3. The fake's
  // subjects have no pic, so this repo returns one with a pic URL
  // (the test HttpClient stub serves a 1x1 PNG for any URL).
  testWidgets('browse poster is close to 2:3', (tester) async {
    await _pumpPage(
      tester,
      _scaffolded(BrowsePage(repository: _PicBrowseRepo(), initialCategory: 'movie')),
      const Size(1440, 900),
    );
    final s = tester.getSize(find.byType(CachedNetworkImage).first);
    expect(s.width / s.height, inInclusiveRange(0.64, 0.70));
  });

  // Step 7: a slow old response must not overwrite a newer list.
  //
  // Not _pumpPage: the slow repo never completes on its own, so the
  // loading spinner would make pumpAndSettle time out. Pump by hand
  // until the results arrive.
  testWidgets('browse ignores a stale response after switching filter', (tester) async {
    final repo = _SlowBrowseRepo();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: _scaffolded(BrowsePage(repository: repo, initialCategory: 'movie'))),
    );
    await tester.pump();
    await tester.tap(find.text('即将上映'));
    await tester.pump();
    repo.calls['movie/soon/0']!.complete(const BrowseResult(
        items: [Subject(id: '2', type: 'movie', title: '新结果')], total: 1));
    await tester.pump();
    repo.calls['movie/showing/0']!.complete(const BrowseResult(
        items: [Subject(id: '1', type: 'movie', title: '旧结果')], total: 1));
    await tester.pump();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Step 7: when the full board list is unavailable, the detail
  // page keeps its previews and shows no spinner.
  testWidgets('board detail falls back to previews quietly', (tester) async {
    const board = RankBoard(
      id: '1818', name: '测试榜', showRank: true,
      previewSubjects: [
        Subject(id: '1', type: 'movie', title: '预览一'),
        Subject(id: '2', type: 'movie', title: '预览二'),
      ],
    );
    await _pumpPage(
      tester,
      const BoardDetailPage(repository: _NoFullBoards(), board: board),
      const Size(390, 800),
    );
    expect(find.text('预览一'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('完整榜单'), findsOneWidget);
  });

  testWidgets('footer pauses after 3 auto-pages on desktop', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _FooterHarness());
    // Each auto-load needs a pump for the post-frame callback and
    // one for the harness rebuild.
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    final state =
        tester.state<_FooterHarnessState>(find.byType(_FooterHarness));
    expect(state.loads, 3);
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(state.loads, greaterThan(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer never pauses on mobile', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _FooterHarness());
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    final state =
        tester.state<_FooterHarnessState>(find.byType(_FooterHarness));
    expect(state.loads, greaterThan(3));
    expect(find.text('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Task 1 (new plan): a resize must not re-fetch. The counting
  // repository lives in the test, not in lib/data (which the plan
  // forbids touching).
  testWidgets('recommend sections do not refetch on resize', (tester) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Pump the shell: its LayoutBuilder rebuilds the whole tab on
    // resize, which is the real-app path that re-creates the
    // sections widget (and its future) on every resize.
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveScaffold(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('书影音'));
    await tester.pumpAndSettle();
    expect(repository.homeSectionsCalls, 1);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    await tester.pump();
    expect(repository.homeSectionsCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic detail refetches only on topic change', (tester) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The LayoutBuilder stands in for the ancestors that rebuild
    // the detail view on resize in the real app (the shell's
    // LayoutBuilder in the group tab, main.dart's MediaQuery
    // builder for a pushed page): without it a resize only
    // re-lays out, it does not rebuild the widget.
    Widget page(String topicId) => MaterialApp(
          home: _scaffolded(
            LayoutBuilder(
              builder: (context, constraints) => TopicDetailView(
                repository: repository,
                topicId: topicId,
              ),
            ),
          ),
        );
    await tester.pumpWidget(page('504122375'));
    await tester.pumpAndSettle();
    expect(repository.topicCalls, 1);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    await tester.pump();
    expect(repository.topicCalls, 1);
    await tester.pumpWidget(page('503570060'));
    await tester.pumpAndSettle();
    expect(repository.topicCalls, 2);
    expect(tester.takeException(), isNull);
  });

  // Task 2 (new plan): switching tabs keeps the page's state —
  // no re-fetch, and the same State object survives the round trip.
  testWidgets('switching tabs keeps browse state', (tester) async {
    final repository = _CountingRepository();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveScaffold(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('书影音'));
    await tester.pumpAndSettle();
    expect(repository.homeSectionsCalls, 1);
    final stateBefore =
        tester.state<State>(find.byType(BrowsePage, skipOffstage: false));
    await tester.tap(find.text('小组'));
    await tester.pumpAndSettle();
    expect(repository.hotGroupsCalls, 1);
    await tester.tap(find.text('书影音'));
    await tester.pumpAndSettle();
    expect(repository.homeSectionsCalls, 1);
    final stateAfter =
        tester.state<State>(find.byType(BrowsePage, skipOffstage: false));
    expect(identical(stateBefore, stateAfter), isTrue);
    expect(tester.takeException(), isNull);
  });

  // Task 3 (new plan): the global scroll behavior adds mouse drag.
  test('AppScrollBehavior includes mouse drag', () {
    const behavior = AppScrollBehavior();
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
  });

  testWidgets('global scroll behavior lets the mouse drag a plain row',
      (tester) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 10; i++)
                  SizedBox(width: 120, height: 100, child: Text('box$i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('box0'));
    await tester.timedDrag(
      find.text('box0'),
      const Offset(-300, 0),
      const Duration(milliseconds: 300),
      buttons: kPrimaryMouseButton,
    );
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('box0'));
    expect(after.dx, lessThan(before.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('HScrollRow arrows scroll the row', (tester) async {
    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 120,
            child: HScrollRow(
              children: [
                for (var i = 0; i < 10; i++)
                  SizedBox(width: 120, height: 100, child: Text('card$i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The arrows are hover-only now: move a mouse over the row
    // before the arrow becomes hittable.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(HScrollRow)));
    await mouse.moveTo(tester.getCenter(find.byType(HScrollRow)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('向右滚动'), findsOneWidget);
    final before = tester.getTopLeft(find.text('card0'));
    await tester.tap(find.byTooltip('向右滚动'));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('card0'));
    expect(after.dx, lessThan(before.dx - 200));
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  // Task 5 (new plan): desktop detail at 900/1024/1440/1920. The
  // right column is 28% of the page width clamped to 340–440,
  // measured through the TabBar that sits inside it; the mobile
  // layout's TabBar spans the full width instead.
  testWidgets('subject desktop right column follows the 28% rule',
      (tester) async {
    Future<double> tabBarWidth(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        const MaterialApp(
          home: SubjectPage(
            repository: _repository,
            type: 'movie',
            id: '1292052',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byType(TabBar).first).width;
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(await tabBarWidth(const Size(900, 800)), closeTo(340, 1));
    expect(await tabBarWidth(const Size(1024, 800)), closeTo(340, 1));
    expect(await tabBarWidth(const Size(1440, 900)), closeTo(403, 1));
    expect(await tabBarWidth(const Size(1920, 1080)), closeTo(440, 1));
  });

  testWidgets('no hard-coded grey placeholder in dark mode',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const SubjectPage(
          repository: _repository,
          type: 'movie',
          id: '1292052',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grey = tester.widgetList<Container>(find.byType(Container)).where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == Colors.grey.shade300,
        );
    expect(grey, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // Task 6 (new plan): group split at pane 900, list 340 below a
  // 1280 pane and 420 at/above it. The shell's rail takes 240 at
  // these widths, so window 1100 -> pane 860 (no split), window
  // 1440 -> pane 1200 (split, list 340), window 1600 -> pane 1360
  // (split, list 420). Pumped once and resized between checks: a
  // second pumpWidget would reuse the shell's state instead of
  // starting fresh.
  testWidgets('group split and list width follow the new plan',
      (tester) async {
    (bool, double) measure() {
      final hasDetail = find.byType(TopicDetailView).evaluate().isNotEmpty;
      final listWidth = hasDetail
          ? tester.getSize(find.byType(ListView).first).width
          : 0.0;
      return (hasDetail, listWidth);
    }

    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveScaffold(repository: _repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('小组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('后会友期').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The pushed page splits at 1100, but nothing is selected yet:
    // the right pane is the placeholder, not a detail view.
    expect(measure(), const (false, 0.0));
    // The pushed page has no rail, so its content width IS the
    // window width: 1200 is below the 1280 list-wide threshold
    // (list 340), 1440 is above it (list 420).
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('8号线杨思民用水电 押一付一'));
    await tester.pumpAndSettle();
    expect(measure(), const (true, 340.0));
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    await tester.pump();
    expect(measure(), const (true, 420.0));
    expect(tester.takeException(), isNull);
  });

  // Task 8 (new plan): at short heights the rail's leading loses
  // its vertical padding (labelType none was already done).
  testWidgets('short rail drops the leading padding', (tester) async {
    Future<Widget?> leadingAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveScaffold(repository: _repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.widget<NavigationRail>(find.byType(NavigationRail)).leading;
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(await leadingAt(const Size(800, 360)), isA<Text>());
    expect(await leadingAt(const Size(1440, 900)), isA<Padding>());
  });

  // Task 9 (new plan): posters decode at display size, not full
  // original size. At dpr 2 a 120-wide poster card decodes at 240
  // and a 56-wide row cover at 112.
  testWidgets('poster card decodes at display width', (tester) async {
    const subject = Subject(
      id: '1292052',
      type: 'movie',
      title: '肖申克的救赎',
      pic: 'https://img3.doubanio.com/view/photo/m_ratio_poster/public/p2930565623.jpg',
    );
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 220,
            child: SubjectPosterCard(subject: subject),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subject row cover decodes at 56 wide', (tester) async {
    const subject = Subject(
      id: '1292052',
      type: 'movie',
      title: '肖申克的救赎',
      pic: 'https://img3.doubanio.com/view/photo/m_ratio_poster/public/p2930565623.jpg',
    );
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SubjectRow(subject: subject),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 112);
    expect(tester.takeException(), isNull);
  });

  // Step 4: entering a group pushes a real route (system back
  // works); backing out returns to the hot list. This replaces the
  // step-1 in-tab back handling, which died with _selectedGroupId.
  testWidgets('group detail is a pushed route with system back',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveScaffold(repository: _repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('小组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('后会友期').first);
    await tester.pumpAndSettle();
    expect(find.byType(GroupDetailPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GroupDetailPage), findsNothing);
    expect(find.text('后会友期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 4: on a wide window the detail page shows a placeholder
  // instead of auto-opening the first topic; tapping a topic fills
  // the right pane.
  testWidgets('group detail shows a placeholder until a topic is picked',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          const GroupTopicsPage(repository: _repository, groupId: '146409'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择左侧话题'), findsOneWidget);
    expect(find.byType(TopicDetailView), findsNothing);
    await tester.tap(find.text('8号线杨思民用水电 押一付一'));
    await tester.pumpAndSettle();
    expect(find.text('选择左侧话题'), findsNothing);
    expect(find.byType(TopicDetailView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 4: the topic detail shows loaded-vs-total replies, and
  // the reply row carries the author and the like count. A tall
  // viewport is used because the body image block pushes the
  // replies below the fold at phone height.
  testWidgets('topic detail shows loaded reply count', (tester) async {
    await _pumpPage(
      tester,
      const TopicDetailPage(repository: _repository, topicId: '504122375'),
      const Size(390, 3000),
    );
    // The fake topic now has 25 replies (20 on the first page);
    // the header shows the total, and the footer the loaded count.
    expect(find.text('回应 25'), findsOneWidget);
    // 路人5 is not a hot reply (the fake's hot replies are 路人3
    // and 路人4), so its nickname appears once; the meta line is
    // a separate "时间 · IP属地" text.
    expect(find.text('路人5'), findsOneWidget);
    expect(find.text('19'), findsOneWidget);
    final title = tester.widget<Text>(find.text('8号线杨思民用水电 押一付一'));
    expect(title.style?.fontSize, 20);
    expect(tester.takeException(), isNull);
  });

  // Step 3: 楼主 badge, IP 属地， quoted reply, hot replies, and
  // the floor number. A tall viewport shows the whole page.
  testWidgets('topic detail shows author badge, ip location, quote, hot replies', (tester) async {
    await _pumpPage(
      tester,
      const TopicDetailPage(repository: _repository, topicId: '504122375'),
      const Size(390, 3000),
    );
    expect(find.text('楼主'), findsOneWidget);
    expect(find.text('热门回应'), findsOneWidget);
    expect(find.text('路人1：请问还可以看房吗？'), findsOneWidget);
    expect(find.text('1楼'), findsOneWidget);
    expect(find.text('只看楼主'), findsOneWidget);
  });

  // Step 3: 只看楼主 keeps only the topic author's replies.
  testWidgets('topic detail only-author filter', (tester) async {
    await _pumpPage(
      tester,
      const TopicDetailPage(repository: _repository, topicId: '504122375'),
      const Size(390, 3000),
    );
    await tester.tap(find.text('只看楼主'));
    await tester.pumpAndSettle();
    expect(find.text('房东'), findsOneWidget);
    expect(find.text('路人3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Step 3: the AppBar star bookmarks the topic, and the menu
  // offers copy-link / open-in-browser. (The copy tap itself is
  // not exercised: Clipboard goes through the platform channel,
  // which has no stub in widget tests.)
  testWidgets('topic detail star and menu', (tester) async {
    await _pumpPage(
      tester,
      const TopicDetailPage(repository: _repository, topicId: '504122375'),
      const Size(390, 800),
    );
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();
    expect(LocalLists.instance.isFavoriteTopic('504122375'), isTrue);
    expect(find.byIcon(Icons.star), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('浏览器打开'), findsOneWidget);
    // Dismiss the menu before tapping the star again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();
    expect(LocalLists.instance.isFavoriteTopic('504122375'), isFalse);
    expect(tester.takeException(), isNull);
  });

  // Step 3: while the detail loads, a skeleton replaces the spinner.
  testWidgets('topic detail shows a skeleton while loading', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: _scaffolded(TopicDetailPage(repository: _NeverTopicRepo(), topicId: '504122375'))),
    );
    await tester.pump();
    expect(find.byType(TopicDetailSkeleton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 3: a failed load offers a retry, which reloads the topic.
  testWidgets('topic detail retry after failure', (tester) async {
    await _pumpPage(
      tester,
      TopicDetailPage(repository: _FlakyTopicRepo(), topicId: '504122375'),
      const Size(390, 800),
    );
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('回应 25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 3: on desktop the replies header stays pinned while the
  // body column scrolls.
  testWidgets('topic detail desktop replies header stays pinned', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: _scaffolded(const TopicDetailPage(repository: _repository, topicId: '504122375'))),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('回应 25').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 2: the reply footer auto-loads the next page when it
  // appears (the fake topic has 25 replies: 20 + 5). A tall
  // viewport makes the footer visible without scrolling; it has
  // to be very tall because the body image and hot section push
  // the last replies down.
  testWidgets('topic detail loads more comments', (tester) async {
    await _pumpPage(
      tester,
      const TopicDetailPage(repository: _repository, topicId: '504122375'),
      const Size(390, 4200),
    );
    expect(find.text('回复内容24'), findsOneWidget);
    expect(find.text('已加载 25 / 25'), findsOneWidget);
  });

  // Step 2: the fake comments endpoint pages by start/count and
  // reports the total.
  test('fake fetchTopicComments pages and totals', () async {
    final first = await _repository.fetchTopicComments('504122375', start: 0, count: 20);
    expect(first.comments.length, 20);
    expect(first.total, 25);
    final second = await _repository.fetchTopicComments('504122375', start: 20, count: 20);
    expect(second.comments.length, 5);
    expect(second.total, 25);
    final pastEnd = await _repository.fetchTopicComments('504122375', start: 25, count: 20);
    expect(pastEnd.comments, isEmpty);
  });

  // Step 4: the group tab has 热门 | 已收藏 segments; the favorites
  // tab is empty until a group is starred.
  testWidgets('group tab segments and empty favorites', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(const GroupPage(repository: _repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('热门'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);
    expect(find.text('后会友期'), findsOneWidget);
    await tester.tap(find.text('已收藏'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有收藏的小组'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 1: user page labels are Chinese, followers/following are
  // the right way round (fake profile: followers 120, following 80).
  testWidgets('user page shows Chinese labels and correct counts',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          const UserPage(repository: _repository, initialUserId: '2870956'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图书'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('音乐'), findsOneWidget);
    expect(find.text('想读'), findsOneWidget);
    expect(find.text('在读'), findsOneWidget);
    expect(find.text('读过'), findsOneWidget);
    expect(find.text('book'), findsNothing);
    // Step 3: the header shows 粉丝 first; the interest row shows
    // the user's own comment and date.
    expect(find.text('粉丝 120 · 关注 80'), findsOneWidget);
    expect(find.text('读过，很好。'), findsOneWidget);
    expect(find.text('2026-03-21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 1: the desktop poster grid opens the subject detail now.
  testWidgets('user page desktop grid poster opens the subject',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          const UserPage(repository: _repository, initialUserId: '2870956'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SubjectPosterCard), findsWidgets);
    await tester.tap(find.byType(SubjectPosterCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(SubjectPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 1: a profile avatar is used instead of the initial letter.
  testWidgets('user page shows the profile avatar', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          UserPage(repository: _AvatarRepository(), initialUserId: '2870956'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNotNull);
    expect(tester.takeException(), isNull);
  });

  // Step 3: with no bound id and no initialUserId, the user page
  // shows the bind guide instead of someone else's interests.
  testWidgets('user page shows the bind guide when unbound',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(const UserPage(repository: _repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的公开收藏'), findsOneWidget);
    expect(find.text('绑定并查看'), findsOneWidget);
    // No interests are loaded (earlier tests may have left a
    // 'River' row in 最近查看 — that is the guide's own section).
    expect(find.text('红楼梦'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Step 3: binding an id from the guide loads that user's profile
  // and interests, and stores the binding in LocalLists.
  testWidgets('user page binds an id from the guide', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => LocalLists.instance.setMyUserId(null));
    addTearDown(() => LocalLists.instance.clearRecentUsers());
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(const UserPage(repository: _repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2870956');
    await tester.tap(find.text('绑定并查看'));
    await tester.pumpAndSettle();
    expect(find.text('River'), findsOneWidget);
    expect(find.text('红楼梦'), findsOneWidget);
    expect(LocalLists.instance.myUserId, '2870956');
    expect(tester.takeException(), isNull);
  });

  // Step 3: switching back to a visited (type, status) tab reuses
  // the cache instead of fetching again.
  testWidgets('user page caches interests per type and status',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CountingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          UserPage(repository: repository, initialUserId: '2870956'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.interestsCalls, 1);
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(repository.interestsCalls, 2);
    await tester.tap(find.text('图书'));
    await tester.pumpAndSettle();
    expect(repository.interestsCalls, 2);
    expect(tester.takeException(), isNull);
  });
}

/// Counts how often the two refetch-prone calls run, so the task-1
/// tests can tell a rebuild from a re-fetch. Extends the fake
/// repository instead of touching lib/data (forbidden by the plan).
class _CountingRepository extends FakeDoubanRepository {
  int homeSectionsCalls = 0;
  int topicCalls = 0;
  int hotGroupsCalls = 0;
  int interestsCalls = 0;

  @override
  Future<List<HomeSection>> fetchHomeSections() {
    homeSectionsCalls++;
    return super.fetchHomeSections();
  }

  @override
  Future<TopicDetail> fetchTopic(String topicId) {
    topicCalls++;
    return super.fetchTopic(topicId);
  }

  @override
  Future<List<SearchGroup>> fetchHotGroups() {
    hotGroupsCalls++;
    return super.fetchHotGroups();
  }

  @override
  Future<InterestListResult> fetchInterests(
    String userId,
    String type,
    String status, {
    int start = 0,
    int count = 50,
  }) {
    interestsCalls++;
    return super.fetchInterests(userId, type, status, start: start, count: count);
  }
}

/// Step 3: a repository whose topic never resolves, so the
/// skeleton stays on screen.
class _NeverTopicRepo extends FakeDoubanRepository {
  @override
  Future<TopicDetail> fetchTopic(String topicId) => Completer<TopicDetail>().future;
}

/// Step 3: a repository whose first topic fetch fails, then
/// succeeds, so the retry button can be exercised.
class _FlakyTopicRepo extends FakeDoubanRepository {
  var _failed = false;

  @override
  Future<TopicDetail> fetchTopic(String topicId) async {
    if (!_failed) {
      _failed = true;
      throw StateError('boom');
    }
    return super.fetchTopic(topicId);
  }
}

/// Step 1: the fake profile has no avatar, so the avatar branch is
/// covered with a repository that returns one.
class _AvatarRepository extends FakeDoubanRepository {
  @override
  Future<UserProfile> fetchUser(String id) async => const UserProfile(
        id: '2870956',
        name: 'River',
        avatar:
            'https://img3.doubanio.com/view/photo/m_ratio_poster/public/p2930565623.jpg',
        followersCount: 120,
        followingCount: 80,
      );
}

/// Task 5: on desktop the footer auto-loads 3 pages, then pauses
/// with a 加载更多 button; tapping it resets the counter and
/// auto-loading resumes. On mobile it never pauses.
class _FooterHarness extends StatefulWidget {
  const _FooterHarness();

  @override
  State<_FooterHarness> createState() => _FooterHarnessState();
}

class _FooterHarnessState extends State<_FooterHarness> {
  int loads = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LoadMoreFooter(
          countText: '已加载 $loads',
          canLoadMore: () => true,
          onLoadMore: () => setState(() => loads++),
        ),
      ),
    );
  }
}
