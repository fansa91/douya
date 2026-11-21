import 'dart:convert';
import 'dart:io';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/ui/celebrity_page.dart';
import 'package:douya/ui/celebrity_photos_page.dart';
import 'package:douya/ui/topic_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round-3 step 7: the topic detail and celebrity pages at four
/// sizes (360, 800x360 landscape phone, 900, 1440) and at 130%
/// text scaling, with no overflow. A RenderFlex overflow throws
/// during layout, so a passing test means no overflow at that size.
///
/// The pages are lazy (comments, works and photos build as they
/// scroll into view), so each test scrolls the whole page through
/// and checks for exceptions after every drag — a pump of the
/// first screen alone would miss below-the-fold overflows.
///
/// The "no refetch on resize" counting test (step 2) and the
/// thread-function edge cases (step 4) already live in
/// step2_refetch_test.dart and comment_thread_test.dart; they are
/// re-verified by the full suite, not duplicated here.

const _sizes = [
  Size(360, 800),
  Size(800, 360),
  Size(900, 800),
  Size(1440, 900),
];

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  Size size, {
  double textScale = 1.0,
}) async {
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
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(textScale)),
            child: page,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Scroll a scrollable through its whole extent in steps, checking
/// for layout exceptions after each drag. [scrollable] picks the
/// scroll view (the first CustomScrollView by default).
Future<void> _scrollThrough(
  WidgetTester tester, {
  Finder? scrollable,
  int steps = 12,
}) async {
  final target = scrollable ?? find.byType(CustomScrollView).first;
  for (var i = 0; i < steps; i++) {
    await tester.drag(target, const Offset(0, -800));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });

  group('topic detail at four sizes', () {
    for (final size in _sizes) {
      testWidgets('topic detail renders at $size with no overflow', (tester) async {
        await _pump(
          tester,
          const TopicDetailPage(repository: FakeDoubanRepository(), topicId: '504122375'),
          size,
        );
        // At 800x360 the tab row sits below the fold: scroll it
        // into view (a no-op where it is already visible).
        await tester.scrollUntilVisible(
          find.text('回应 25'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('回应 25'), findsOneWidget);
        await _scrollThrough(tester);
      });
    }
  });

  group('celebrity page at four sizes', () {
    for (final size in _sizes) {
      testWidgets('celebrity page renders at $size with no overflow', (tester) async {
        await _pump(
          tester,
          const CelebrityPage(repository: FakeDoubanRepository(), id: '1054521'),
          size,
        );
        expect(find.text('蒂姆·罗宾斯'), findsOneWidget);
        await _scrollThrough(tester);
        // Desktop has a second, independently scrolling column
        // (the left bio column): scroll it too.
        if (size.width >= 900) {
          final listViews = find.byType(ListView);
          if (listViews.evaluate().isNotEmpty) {
            await _scrollThrough(tester, scrollable: listViews.first, steps: 4);
          }
        }
      });
    }
  });

  group('photo wall page at two sizes', () {
    for (final size in [const Size(360, 800), const Size(1440, 900)]) {
      testWidgets('photo wall renders at $size with no overflow', (tester) async {
        await _pump(
          tester,
          const CelebrityPhotosPage(repository: FakeDoubanRepository(), id: '1054521', name: '蒂姆·罗宾斯'),
          size,
        );
        await _scrollThrough(tester, steps: 4);
      });
    }
  });

  group('130% text scaling', () {
    for (final size in [const Size(360, 800), const Size(1440, 900)]) {
      testWidgets('topic detail renders at $size with 130% text', (tester) async {
        await _pump(
          tester,
          const TopicDetailPage(repository: FakeDoubanRepository(), topicId: '504122375'),
          size,
          textScale: 1.3,
        );
        await _scrollThrough(tester);
      });

      testWidgets('celebrity page renders at $size with 130% text', (tester) async {
        await _pump(
          tester,
          const CelebrityPage(repository: FakeDoubanRepository(), id: '1054521'),
          size,
          textScale: 1.3,
        );
        await _scrollThrough(tester);
      });
    }
  });

  testWidgets('threaded topic detail renders at 360 with no overflow', (tester) async {
    await _pump(
      tester,
      const TopicDetailPage(repository: FakeDoubanRepository(), topicId: '504122375'),
      const Size(360, 800),
    );
    // Open the 筛选 menu and switch on 楼中楼 (flat is the
    // default), then scroll the threaded list through.
    await tester.scrollUntilVisible(
      find.byIcon(Icons.filter_list),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('楼中楼'));
    await tester.pumpAndSettle();
    expect(find.text('楼中楼'), findsNothing);
    await _scrollThrough(tester);
  });
}

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
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
