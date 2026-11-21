import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/celebrity_page.dart';
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

/// Counting repository: 113 works, 20 per page. fetchCelebrity
/// returns the first page directly (it does NOT call
/// fetchCelebrityWorks), so the works counter only counts the
/// paged list's load-more calls.
class _CountingRepo extends FakeDoubanRepository {
  static const totalWorks = 113;

  int fetchCelebrityCalls = 0;
  int fetchCelebrityWorksCalls = 0;
  int fetchSubjectCalls = 0;

  CelebrityWork _work(int i) => CelebrityWork(
        subject: Subject(
          id: 'w$i',
          type: 'movie',
          title: '作品 $i',
          year: '2000',
        ),
        roles: const ['演员'],
      );

  @override
  Future<CelebrityDetail> fetchCelebrity(String id) async {
    fetchCelebrityCalls++;
    return CelebrityDetail(
      celebrity: const Celebrity(
        id: '1054521',
        name: '测试影人',
        latinTitle: 'Test Person',
        shortInfo: '演员',
        info: [('性别', '男')],
      ),
      works: List.generate(20, _work),
      worksTotal: totalWorks,
    );
  }

  @override
  Future<CelebrityWorksResult> fetchCelebrityWorks(
    String id, {
    int start = 0,
    int count = 20,
  }) async {
    fetchCelebrityWorksCalls++;
    final end = (start + count).clamp(0, totalWorks);
    final items = start < totalWorks
        ? List.generate(end - start, (i) => _work(start + i))
        : const <CelebrityWork>[];
    return CelebrityWorksResult(works: items, total: totalWorks);
  }

  @override
  Future<SubjectDetail> fetchSubject(String type, String id) async {
    fetchSubjectCalls++;
    return super.fetchSubject(type, id);
  }
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

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('celebrity page does not re-fetch on rebuild or window resize',
      (tester) async {
    final repo = _CountingRepo();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // A fresh (non-const) instance forces build() to run again.
    // The old StatelessWidget created the future in build(), so
    // this re-fetched; the same rebuild happens in the app when
    // the window is resized and the route rebuilds.
    await tester.pumpWidget(
      MaterialApp(home: CelebrityPage(repository: repo, id: '1054521')),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试影人'), findsOneWidget);
    expect(repo.fetchCelebrityCalls, 1);

    await tester.pumpWidget(
      MaterialApp(home: CelebrityPage(repository: repo, id: '1054521')),
    );
    await tester.pumpAndSettle();
    expect(repo.fetchCelebrityCalls, 1);

    // Window resize: the same rebuild path as dragging the window.
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(repo.fetchCelebrityCalls, 1);
  });

  testWidgets('subject page does not re-fetch on rebuild or window resize',
      (tester) async {
    final repo = _CountingRepo();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SubjectPage(repository: repo, type: 'movie', id: '1292052'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('肖申克的救赎'), findsOneWidget);
    expect(repo.fetchSubjectCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: SubjectPage(repository: repo, type: 'movie', id: '1292052'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.fetchSubjectCalls, 1);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(repo.fetchSubjectCalls, 1);
  });

  testWidgets('celebrity works load page by page, not all at once',
      (tester) async {
    final repo = _CountingRepo();
    await _pump(
      tester,
      CelebrityPage(repository: repo, id: '1054521'),
      const Size(390, 844),
    );
    expect(find.text('作品（113）'), findsOneWidget);
    expect(find.text('作品 0'), findsOneWidget);
    // The footer is below the fold and not mounted yet, so no
    // load-more request has fired. The old shrink-wrapped list
    // built every child at once and auto-loaded all 113 works
    // (~6 requests) on page load.
    expect(find.text('已加载 20 / 113'), findsNothing);
    expect(repo.fetchCelebrityWorksCalls, 0);

    // Scroll the last first-page work into view: the footer sits
    // right after it, so it mounts and loads the next page. (The
    // footer's count text is a moving target — it changes as pages
    // load — so scroll to the stable last item instead.)
    await tester.scrollUntilVisible(
      find.text('作品 19'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(repo.fetchCelebrityWorksCalls, greaterThanOrEqualTo(1));
    expect(find.text('作品 20'), findsOneWidget);
  });
}
