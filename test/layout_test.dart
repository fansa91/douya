import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/ui/adaptive_scaffold.dart';
import 'package:douya/ui/browse_page.dart';
import 'package:douya/ui/group_page.dart';
import 'package:douya/ui/settings_page.dart';
import 'package:douya/ui/subject_page.dart';
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
}
