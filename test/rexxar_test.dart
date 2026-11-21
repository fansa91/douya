import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:douya/api/douban_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rexxar helper tests: the response parsers run against real
/// responses saved in test/fixtures (trimmed to the fields the
/// parsers read), and the cache + in-flight merge are verified with
/// an injected Dio whose adapter counts network calls.
void main() {
  Map<String, dynamic> fixture(String name) {
    final text = File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  group('parseHotGroups', () {
    test('parses the top_groups module from the real response', () {
      final groups = RealDoubanRepository.parseHotGroups(fixture('group_explore.json'));
      expect(groups.length, 3);
      expect(groups[0].name, '哈利波特：魔法觉醒');
      expect(groups[0].memberCount, 25083);
      expect(groups[1].name, '友谊的小船我一个人也能划');
    });

    test('a missing or misshaped feed yields an empty list, never a throw', () {
      expect(RealDoubanRepository.parseHotGroups({}), isEmpty);
      expect(RealDoubanRepository.parseHotGroups({'feed': 'nope'}), isEmpty);
      expect(RealDoubanRepository.parseHotGroups({'feed': []}), isEmpty);
    });
  });

  group('parseHotSearchBoard', () {
    test('parses the bare list from the real response', () {
      final text = File('test/fixtures/hot_search_board.json').readAsStringSync();
      final items = RealDoubanRepository.parseHotSearchBoard(jsonDecode(text));
      expect(items.length, 15);
      expect(items[0].name, '后会友期市场占有率下跌');
      expect(items[0].score, 27232);
      expect(items[0].scoreLabel, '2.7万');
      expect(items[0].uri, startsWith('douban://douban.com/search/result?q='));
    });

    test('a missing or misshaped list yields an empty list, never a throw', () {
      expect(RealDoubanRepository.parseHotSearchBoard({}), isEmpty);
      expect(RealDoubanRepository.parseHotSearchBoard('nope'), isEmpty);
    });
  });

  group('parseGroupExplore', () {
    test('parses all four modules from the real response', () {
      final explore = RealDoubanRepository.parseGroupExplore(fixture('group_explore.json'));
      expect(explore.hotGroups.length, 3);
      expect(explore.hotGroups[0].name, '哈利波特：魔法觉醒');
      expect(explore.categoryTags.length, 7);
      expect(explore.categoryTags[0].name, '分类_兴趣');
      expect(explore.categoryTags[0].count, 1956);
      expect(explore.groupsSets.length, 2);
      expect(explore.groupsSets[0].title, '从今天开始的打卡生活');
      expect(explore.groupsSets[0].groups.length, 2);
      expect(explore.recommendedGroups.length, 3);
      expect(explore.recommendedGroups[0].group.name, '想像Bar');
      expect(explore.recommendedGroups[0].topics.length, 1);
      expect(explore.recommendedGroups[0].topics[0].title, isNotEmpty);
      expect(explore.recommendedGroups[0].source, 'hot');
      expect(explore.recommendedTotal, 60);
    });

    test('a missing or misshaped feed yields an empty explore, never a throw', () {
      final empty = RealDoubanRepository.parseGroupExplore({});
      expect(empty.hotGroups, isEmpty);
      expect(empty.categoryTags, isEmpty);
      expect(empty.groupsSets, isEmpty);
      expect(empty.recommendedGroups, isEmpty);
      expect(empty.recommendedTotal, 0);
    });
  });

  group('parseRecommendedGroups', () {
    test('parses one page plus the total from the real response', () {
      final page = RealDoubanRepository.parseRecommendedGroups(fixture('group_explore.json'));
      expect(page.groups.length, 3);
      expect(page.total, 60);
    });

    test('a missing groups module yields an empty page, never a throw', () {
      expect(RealDoubanRepository.parseRecommendedGroups({}).groups, isEmpty);
    });
  });

  group('parseLanding', () {
    test('parses the movie landing groups from the real response', () {
      final text = File('test/fixtures/movie_landing.json').readAsStringSync();
      final groups = RealDoubanRepository.parseLanding(jsonDecode(text));
      expect(groups.length, 4);
      expect(groups[0].name, '专题');
      expect(groups[0].items[0].name, '豆瓣热门');
      expect(groups[0].items[0].uri, 'douban://douban.com/subject_collection/movie_hot_gaia');
      expect(groups[1].name, '类型');
      expect(groups[1].items[0].name, '喜剧');
    });

    test('parses the tv landing groups from the real response', () {
      final text = File('test/fixtures/tv_landing.json').readAsStringSync();
      final groups = RealDoubanRepository.parseLanding(jsonDecode(text));
      expect(groups.length, 3);
      expect(groups[2].name, '播出平台');
      expect(groups[2].items[0].name, '湖南卫视');
    });

    test('a missing or misshaped response yields an empty list, never a throw', () {
      expect(RealDoubanRepository.parseLanding({}), isEmpty);
      expect(RealDoubanRepository.parseLanding('nope'), isEmpty);
    });
  });

  group('parseRankBoards', () {
    test('parses boards with preview subjects from the real response', () {
      final boards = RealDoubanRepository.parseRankBoards(fixture('rank_boards_tag49.json'));
      expect(boards.length, 3);
      expect(boards[0].id, '1818');
      expect(boards[0].name, '6月豆瓣电影口碑榜Top20');
      expect(boards[0].previewSubjects.length, 3);
      expect(boards[0].previewSubjects[0].title, '驴得水');
    });

    test('a missing or misshaped list yields an empty list, never a throw', () {
      expect(RealDoubanRepository.parseRankBoards({}), isEmpty);
      expect(RealDoubanRepository.parseRankBoards({'subject_collection_boards': 'nope'}), isEmpty);
    });
  });

  group('helper cache and in-flight merge', () {
    late _CountingAdapter adapter;
    late RealDoubanRepository repo;

    setUp(() {
      adapter = _CountingAdapter(File('test/fixtures/group_explore.json').readAsStringSync());
      final dio = Dio()..httpClientAdapter = adapter;
      repo = RealDoubanRepository(DoubanClient(), rexxarDio: dio);
    });

    test('concurrent identical calls share one request, then the cache serves the next', () async {
      final results = await Future.wait([repo.fetchHotGroups(), repo.fetchHotGroups()]);
      expect(adapter.calls, 1);
      expect(results[0].length, 3);
      expect(results[1].length, 3);
      expect(results[0][0].name, '哈利波特：魔法觉醒');
      // Sequential call within the 5-minute TTL: still one request.
      final again = await repo.fetchHotGroups();
      expect(adapter.calls, 1);
      expect(again.length, 3);
    });

    test('a wrong-shaped response returns an empty list', () async {
      adapter.body = '{}';
      expect(await repo.fetchHotGroups(), isEmpty);
    });

    test('a network error throws instead of returning an empty list', () async {
      adapter.throwError = true;
      await expectLater(repo.fetchHotGroups(), throwsA(isA<DioException>()));
    });
  });
}

/// Dio adapter that returns a canned JSON body and counts calls.
/// Set [throwError] to make it fail like a network error.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.body);

  String body;
  int calls = 0;
  bool throwError = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (throwError) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}
