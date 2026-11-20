import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/main.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/adaptive_scaffold.dart';
import 'package:douya/ui/browse_page.dart';
import 'package:douya/ui/group_page.dart';
import 'package:douya/ui/settings_page.dart';
import 'package:douya/ui/subject_page.dart';
import 'package:douya/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  setUpAll(() => HttpOverrides.global = _MockHttpOverrides());
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
}

/// Counts how often the two refetch-prone calls run, so the task-1
/// tests can tell a rebuild from a re-fetch. Extends the fake
/// repository instead of touching lib/data (forbidden by the plan).
class _CountingRepository extends FakeDoubanRepository {
  int homeSectionsCalls = 0;
  int topicCalls = 0;
  int hotGroupsCalls = 0;

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
