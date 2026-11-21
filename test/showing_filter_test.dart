import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/cities.dart';
import 'package:douya/data/fake_repository.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/browse_page.dart';

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

/// A repo whose showing list carries real regions, so the
/// client-side area filter can actually hide items.
class _RegionRepo extends FakeDoubanRepository {
  const _RegionRepo();

  static const _us = Subject(
    id: '1',
    type: 'movie',
    title: '美国片',
    cardSubtitle: '2026 / 美国 / 动作 / 导演',
  );
  static const _cn = Subject(
    id: '2',
    type: 'movie',
    title: '中国片',
    cardSubtitle: '2026 / 中国大陆 / 剧情 / 导演',
  );
  static const _jp = Subject(
    id: '3',
    type: 'movie',
    title: '日本片',
    cardSubtitle: '2026 / 日本 / 动画 / 导演',
  );

  @override
  Future<BrowseResult> fetchMovieShowing({
    String? sort,
    bool playable = false,
    String? scoreRange,
    required int locId,
    int start = 0,
    int count = 20,
  }) async {
    const items = [_us, _cn, _jp];
    return BrowseResult(
      items: items.skip(start).take(count).toList(),
      total: items.length,
    );
  }
}

Future<void> _pumpShowing(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: BrowsePage(repository: _RegionRepo(), initialCategory: 'movie'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Subject _subject(String subtitle) =>
    Subject(id: '1', type: 'movie', title: '片名', cardSubtitle: subtitle);

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() => HttpOverrides.global = null);

  group('subjectRegion', () {
    test('parses the region from a showing cardSubtitle', () {
      expect(subjectRegion(_subject('2026 / 美国 / 动作 科幻 / 导演')), '美国');
      expect(subjectRegion(_subject('2026 / 中国大陆 / 剧情 / 导演')), '中国大陆');
    });

    test('returns null when the subtitle has no year/region shape', () {
      expect(subjectRegion(_subject('剧情 / 犯罪')), isNull);
      expect(
        subjectRegion(const Subject(id: '1', type: 'movie', title: '片名')),
        isNull,
      );
    });
  });

  group('subjectMatchesArea', () {
    test('全部 matches everything', () {
      expect(subjectMatchesArea(_subject('2026 / 美国 / 动作'), '全部'), isTrue);
      expect(subjectMatchesArea(_subject('剧情 / 犯罪'), '全部'), isTrue);
    });

    test('华语 matches Chinese regions only', () {
      expect(subjectMatchesArea(_subject('2026 / 中国大陆 / 剧情'), '华语'), isTrue);
      expect(subjectMatchesArea(_subject('2026 / 中国香港 / 剧情'), '华语'), isTrue);
      expect(subjectMatchesArea(_subject('2026 / 美国 / 剧情'), '华语'), isFalse);
      expect(subjectMatchesArea(_subject('2026 / 日本 / 动画'), '华语'), isFalse);
    });

    test('韩国 and 日本 match their own region', () {
      expect(subjectMatchesArea(_subject('2026 / 韩国 / 剧情'), '韩国'), isTrue);
      expect(subjectMatchesArea(_subject('2026 / 日本 / 动画'), '日本'), isTrue);
      expect(subjectMatchesArea(_subject('2026 / 韩国 / 剧情'), '日本'), isFalse);
    });

    test('欧美 is everything non-Chinese/Korean/Japanese', () {
      expect(subjectMatchesArea(_subject('2026 / 美国 / 动作'), '欧美'), isTrue);
      expect(subjectMatchesArea(_subject('2026 / 英国 / 剧情'), '欧美'), isTrue);
      expect(subjectMatchesArea(_subject('2026 / 中国大陆 / 剧情'), '欧美'), isFalse);
      expect(subjectMatchesArea(_subject('2026 / 日本 / 动画'), '欧美'), isFalse);
    });

    test('unparseable region matches every area (never hides a film)', () {
      expect(subjectMatchesArea(_subject('剧情 / 犯罪'), '日本'), isTrue);
      expect(subjectMatchesArea(_subject('剧情 / 犯罪'), '华语'), isTrue);
    });
  });

  group('showingCities', () {
    test('12 verified cities with unique ids', () {
      expect(showingCities.length, 12);
      expect(showingCities.map((c) => c.locId).toSet().length, 12);
      expect(showingCityById(108288)?.name, '北京');
      expect(showingCityById(108296)?.name, '上海');
      expect(showingCityById(118163)?.name, '苏州');
      expect(showingCityById(999999), isNull);
    });
  });

  testWidgets('showing filter: pick a city, then filter by area', (tester) async {
    await _pumpShowing(tester, const Size(360, 800));

    // No city saved: the prompt shows and the national list loads.
    expect(find.text('选择城市查看本地热映并筛选'), findsOneWidget);
    expect(find.text('肖申克的救赎'), findsOneWidget);

    // Open the filter sheet and pick 北京.
    await tester.tap(find.textContaining('筛选 · 选择城市'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北京'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    // The city list loads with the filtered count.
    expect(find.text('选择城市查看本地热映并筛选'), findsNothing);
    expect(find.text('共 3 部'), findsOneWidget);
    expect(find.text('美国片'), findsOneWidget);
    expect(find.text('中国片'), findsOneWidget);
    expect(find.text('日本片'), findsOneWidget);

    // Filter by area 日本: only the Japanese film remains.
    await tester.tap(find.textContaining('筛选 · 北京'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('共 1 部'), findsOneWidget);
    expect(find.text('日本片'), findsOneWidget);
    expect(find.text('美国片'), findsNothing);
    expect(find.text('中国片'), findsNothing);
  });
}
