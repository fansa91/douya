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
import 'package:douya/ui/browse_page.dart';
import 'package:douya/ui/group_page.dart';
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

    testWidgets('settings renders at $name', (tester) async {
      await _pumpPage(tester, const SettingsPage(), size);
    });
  }

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
    expect(find.byTooltip('向右滚动'), findsOneWidget);
    final before = tester.getTopLeft(find.text('card0'));
    await tester.tap(find.byTooltip('向右滚动'));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('card0'));
    expect(after.dx, lessThan(before.dx - 200));
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
    expect(measure(), const (false, 0.0));
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    await tester.pump();
    expect(measure(), const (true, 340.0));
    tester.view.physicalSize = const Size(1600, 900);
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

  // Step 1 (group/user redesign): returning from an embedded group
  // page to the hot list no longer spins forever.
  testWidgets('embedded group page returns to a loaded hot list',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: _scaffolded(
          const GroupPage(repository: _repository, initialGroupId: '146409'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('热门小组'));
    await tester.pumpAndSettle();
    expect(find.text('后会友期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Step 1: system back in the group tab first returns to the hot
  // list instead of leaving the app.
  testWidgets('system back in the group tab returns to hot list',
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
    // Desktop splits: the first topic opens inline in the detail pane.
    expect(find.byType(TopicDetailView), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TopicDetailView), findsNothing);
    expect(find.text('后会友期'), findsOneWidget);
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
