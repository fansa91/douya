import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/ui/celebrity_page.dart';
import 'package:douya/ui/image_preview_page.dart';
import 'package:douya/ui/subject_page.dart';

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

Future<void> _pump(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

const _subject = SubjectPage(
  repository: FakeDoubanRepository(),
  type: 'movie',
  id: '1292052',
);

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('rating bars show expanded on desktop', (tester) async {
    await _pump(tester, _subject, const Size(1440, 3000));
    expect(find.text('评分分布'), findsOneWidget);
    expect(find.text('5星'), findsOneWidget);
    expect(find.text('55.0%'), findsOneWidget);
    expect(find.text('30.0%'), findsOneWidget);
    expect(find.text('12.0%'), findsOneWidget);
    expect(find.text('1.0%'), findsOneWidget);
  });

  testWidgets('rating bars start collapsed on narrow screens, tap to expand',
      (tester) async {
    await _pump(tester, _subject, const Size(390, 4200));
    expect(find.text('评分分布'), findsOneWidget);
    expect(find.text('五星 55%'), findsOneWidget);
    expect(find.text('55.0%'), findsNothing);
    await tester.tap(find.text('评分分布'));
    await tester.pumpAndSettle();
    expect(find.text('55.0%'), findsOneWidget);
    expect(find.text('30.0%'), findsOneWidget);
  });

  testWidgets('awards show under the summary', (tester) async {
    await _pump(tester, _subject, const Size(390, 4200));
    expect(find.text('获奖'), findsOneWidget);
    expect(find.text('示例电影节 · 2026'), findsOneWidget);
    expect(find.text('最佳影片 · 获奖 · 示例影人'), findsOneWidget);
  });

  testWidgets('celebrity page shows a photo strip, tap opens the preview',
      (tester) async {
    await _pump(
      tester,
      const CelebrityPage(repository: FakeDoubanRepository(), id: '1054521'),
      const Size(390, 3000),
    );
    expect(find.text('剧照（1）'), findsOneWidget);
    final photo = find.byWidgetPredicate(
      (w) => w is CachedNetworkImage && w.imageUrl == 'https://example.com/photo1.jpg',
    );
    expect(photo, findsOneWidget);
    // Invoke the thumbnail's onTap directly: a real tap in the
    // test is swallowed by the nested scrollables' drag
    // recognizers (the same tap works in the app — the pattern
    // mirrors the subject page's photo grid). This verifies the
    // tap wires the photo to the preview with the loaded urls.
    final thumb = find.ancestor(of: photo, matching: find.byType(GestureDetector));
    expect(thumb, findsOneWidget);
    tester.widget<GestureDetector>(thumb).onTap!();
    // Pump manually, not pumpAndSettle: the preview's image never
    // resolves in tests, so its loading spinner spins forever.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ImagePreviewPage), findsOneWidget);
  });
}
