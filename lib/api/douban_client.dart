import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../data/repository.dart';
import '../models/models.dart';

/// Live Frodo client. Credentials are NOT hard-coded here on purpose.
/// Pass them with --dart-define=DOUBAN_API_KEY=... --dart-define=DOUBAN_API_SECRET=...
const _apiKey = String.fromEnvironment('DOUBAN_API_KEY');
const _apiSecret = String.fromEnvironment('DOUBAN_API_SECRET');

class DoubanClient {
  DoubanClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://frodo.douban.com',
                headers: const {
                  'User-Agent': 'api-client/1 com.douban.frodo/7.0.0(1) Android/34 product/generic vendor/Google model/sdk_gphone64_arm64 rom/android network/wifi platform/mobile nd/1',
                },
              ),
            );

  final Dio _dio;

  /// Signed GET. Only the path is signed, never the query string.
  /// Raw string: GET & url-encoded(path) & timestamp-seconds.
  /// A wrong signature returns code 996; a missing key returns code 131.
  Future<Map<String, dynamic>> signedGet(String path, [Map<String, dynamic>? extra]) async {
    if (_apiKey.isEmpty || _apiSecret.isEmpty) {
      throw StateError(
        'DOUBAN_API_KEY / DOUBAN_API_SECRET is empty. '
        'Run with --dart-define=DOUBAN_API_KEY=... --dart-define=DOUBAN_API_SECRET=...',
      );
    }
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final raw = 'GET&${Uri.encodeComponent(path)}&$ts';
    final sig = base64Encode(
      Hmac(sha1, utf8.encode(_apiSecret)).convert(utf8.encode(raw)).bytes,
    );
    final params = <String, dynamic>{
      'apiKey': _apiKey,
      '_ts': ts,
      '_sig': sig,
      'os_rom': 'android',
      ...?extra,
    };
    final response = await _dio.get(path, queryParameters: params);
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    // recommendations returns a bare List, handled by the caller.
    throw StateError('Unexpected Frodo response for $path');
  }

  Future<List<dynamic>> signedGetList(String path) async {
    if (_apiKey.isEmpty || _apiSecret.isEmpty) {
      throw StateError('DOUBAN_API_KEY / DOUBAN_API_SECRET is empty.');
    }
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final raw = 'GET&${Uri.encodeComponent(path)}&$ts';
    final sig = base64Encode(
      Hmac(sha1, utf8.encode(_apiSecret)).convert(utf8.encode(raw)).bytes,
    );
    final response = await _dio.get(
      path,
      queryParameters: {'apiKey': _apiKey, '_ts': ts, '_sig': sig, 'os_rom': 'android'},
    );
    final data = response.data;
    if (data is List) return data;
    throw StateError('Expected a List response for $path');
  }
}

/// Live implementation of the UI repository. Search is wired to the
/// verified Frodo /search/subjects endpoint; suggest still uses the
/// Web endpoint until it is moved to Frodo /search/suggestion.
class RealDoubanRepository implements DoubanRepository {
  RealDoubanRepository(this._client);

  final DoubanClient _client;

  List<T> _parseList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(fromJson).toList().cast<T>();
  }

  @override
  Future<List<Subject>> fetchHot() async {
    final data = await _client.signedGet(
      '/api/v2/subject_collection/movie_showing/items',
      {'start': 0, 'count': 20},
    );
    return _parseList(data['subject_collection_items'], (j) => Subject.fromJson(j));
  }

  @override
  Future<List<Subject>> fetchRecentHot() async {
    // Rexxar needs no signature; kept as a Dio call without Frodo signing.
    final dio = Dio();
    final response = await dio.get(
      'https://m.douban.com/rexxar/api/v2/subject/recent_hot/movie',
      queryParameters: {'start': 0, 'limit': 20},
      options: Options(headers: {'Referer': 'https://movie.douban.com/'}),
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return _parseList(data['items'], (j) => Subject.fromJson(j, fallbackType: 'movie'));
    }
    return const [];
  }

  @override
  Future<List<Subject>> fetchTrending() => fetchHot();

  // --- Browse / home (v0.2) -------------------------------------------------
  // Frodo collections are signed; Rexxar collections / recent / recommend
  // are unsigned. Both collection shapes carry subject_collection_items
  // + total; recent/recommend carry items + total.
  Future<BrowseResult> _frodoCollection(String name, int start, int count) async {
    final data = await _client.signedGet(
      '/api/v2/subject_collection/$name/items',
      {'start': start, 'count': count},
    );
    return BrowseResult(
      items: _parseList(data['subject_collection_items'], (j) => Subject.fromJson(j)),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>?> _rexxar(String path, Map<String, dynamic> params) async {
    final dio = Dio();
    final response = await dio.get(
      'https://m.douban.com/rexxar/api/v2/$path',
      queryParameters: params,
      options: Options(headers: {'Referer': 'https://movie.douban.com/'}),
    );
    final data = response.data;
    return data is Map<String, dynamic> ? data : null;
  }

  Future<BrowseResult> _rexxarCollection(String name, int start, int count) async {
    final data = await _rexxar(
      'subject_collection/$name/items',
      {'start': start, 'count': count, 'items_only': 1, 'for_mobile': 1},
    );
    if (data == null) return const BrowseResult();
    return BrowseResult(
      items: _parseList(data['subject_collection_items'], (j) => Subject.fromJson(j)),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<BrowseResult> _rexxarRecent(String type, int start, int count) async {
    final data = await _rexxar(
      'subject/recent_hot/$type',
      {'start': start, 'limit': count},
    );
    if (data == null) return const BrowseResult();
    return BrowseResult(
      items: _parseList(data['items'], (j) => Subject.fromJson(j, fallbackType: type)),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  // Recommend endpoints mix subject items with chart/readlist cards;
  // only flat subject items (movie/tv/book/music with an id) are kept.
  Future<BrowseResult> _rexxarRecommend(String type, int start, int count) async {
    final data = await _rexxar('$type/recommend', {'start': start, 'count': count});
    if (data == null) return const BrowseResult();
    final raw = data['items'];
    if (raw is! List) return const BrowseResult();
    final items = raw
        .whereType<Map<String, dynamic>>()
        .where((j) {
          final t = j['type'] as String?;
          final layout = j['layout'] as String?;
          return (t == 'movie' || t == 'tv' || t == 'book' || t == 'music') &&
              layout != 'chart' &&
              layout != 'readlist' &&
              '${j['id'] ?? ''}'.isNotEmpty;
        })
        .map((j) => Subject.fromJson(j, fallbackType: type))
        .toList();
    return BrowseResult(items: items, total: (data['total'] as num?)?.toInt() ?? items.length);
  }

  @override
  Future<BrowseResult> fetchBrowse(String category, String filter, {int start = 0, int count = 20}) async {
    switch ('$category/$filter') {
      case 'movie/showing':
        return _frodoCollection('movie_showing', start, count);
      case 'movie/soon':
        return _frodoCollection('movie_soon', start, count);
      case 'movie/recent':
        return _rexxarRecent('movie', start, count);
      case 'movie/top250':
        return _rexxarCollection('movie_top250', start, count);
      case 'movie/recommend':
        return _rexxarRecommend('movie', start, count);
      case 'tv/recent':
        return _rexxarRecent('tv', start, count);
      case 'tv/hot':
        return _rexxarCollection('tv_hot', start, count);
      case 'tv/recommend':
        return _rexxarRecommend('tv', start, count);
      case 'book/hot':
        return _frodoCollection('book_hot', start, count);
      case 'book/bestseller':
        return _rexxarCollection('book_bestseller', start, count);
      case 'book/top250':
        return _rexxarCollection('book_top250', start, count);
      case 'music/hot':
        return _frodoCollection('music_hot', start, count);
      default:
        return const BrowseResult();
    }
  }

  @override
  Future<List<HomeSection>> fetchHomeSections() async {
    // The app's own home feed is NOT guest-usable: Frodo
    // /elendil/recommend_feed returns 200 with 0 items and toast 暂无更新
    // for a guest signature, and /elendil/home_timeline needs login
    // (403 code 103). So the guest home is assembled from the verified
    // guest-usable recommendation sources below; one failing source
    // only drops its own section, never the whole home page.
    Future<HomeSection?> section(String title, String category, String filter, int count) async {
      try {
        final result = await fetchBrowse(category, filter, start: 0, count: count);
        if (result.items.isEmpty) return null;
        return HomeSection(title: title, items: result.items, category: category, filter: filter);
      } catch (_) {
        return null;
      }
    }

    final sections = await Future.wait([
      section('电影推荐', 'movie', 'recommend', 10),
      section('近期热门电影', 'movie', 'recent', 10),
      section('热门剧集', 'tv', 'recent', 10),
      section('热门图书', 'book', 'hot', 10),
      section('热门音乐', 'music', 'hot', 10),
    ]);
    return sections.whereType<HomeSection>().toList();
  }

  @override
  Future<SubjectDetail> fetchSubject(String type, String id) async {
    final results = await Future.wait([
      _client.signedGet('/api/v2/$type/$id'),
      _client.signedGet('/api/v2/$type/$id/interests', {'status': 'done', 'start': 0, 'count': 10}),
      _client.signedGet('/api/v2/$type/$id/reviews', {'start': 0, 'count': 10}),
      _client.signedGet('/api/v2/$type/$id/photos', {'start': 0, 'count': 10}),
      _client.signedGetList('/api/v2/$type/$id/recommendations'),
      _client.signedGet('/api/v2/$type/$id/related_doulists', {'start': 0, 'count': 10}),
      _client.signedGet('/api/v2/$type/$id/celebrities', {'start': 0, 'count': 10}),
    ]);
    final detail = results[0] as Map<String, dynamic>;
    final interests = results[1] as Map<String, dynamic>;
    final reviews = results[2] as Map<String, dynamic>;
    final photos = results[3] as Map<String, dynamic>;
    final recommendations = results[4] as List<dynamic>;
    final doulists = results[5] as Map<String, dynamic>;
    final celebrities = results[6] as Map<String, dynamic>;
    String nameOf(dynamic person) {
      if (person is Map) return (person['name'] as String?) ?? '';
      return '$person';
    }

    return SubjectDetail(
      subject: Subject.fromJson(detail, fallbackType: type),
      // Frodo movie detail carries 'intro', not 'summary' (probe 2026-10-31).
      summary: (detail['summary'] as String?) ?? (detail['intro'] as String?) ?? '',
      trailers: _parseList(detail['trailers'], Trailer.fromJson),
      directors: ((detail['directors'] as List?) ?? []).map(nameOf).toList(),
      actors: ((detail['actors'] as List?) ?? []).map(nameOf).toList(),
      genres: ((detail['genres'] as List?) ?? []).map((e) => '$e').toList(),
      comments: _parseList(interests['interests'], ShortComment.fromJson),
      reviews: _parseList(reviews['reviews'], Review.fromJson),
      photos: _parseList(photos['photos'], Photo.fromJson),
      recommendations: recommendations.whereType<Map<String, dynamic>>().map((j) => Subject.fromJson(j)).toList(),
      doulists: _parseList(doulists['doulists'], (j) => Subject.fromJson(j)),
      celebrities: _parseList(
        [...(celebrities['directors'] as List? ?? []), ...(celebrities['actors'] as List? ?? [])],
        Celebrity.fromJson,
      ),
    );
  }

  /// Card-shaped search item -> Subject. Shared by /search/subjects,
  /// /search/suggestion cards and /search/hots subjects (the latter
  /// are already flat, so the target branch is skipped for them).
  Subject _subjectFromSearchItem(Map<String, dynamic> item) {
    final target = item['target'];
    final base = target is Map<String, dynamic>
        ? Map<String, dynamic>.from(target)
        : Map<String, dynamic>.from(item);
    base['id'] = item['target_id'] ?? base['id'] ?? '';
    final targetType = item['target_type'] as String?;
    if (targetType != null) base['item_type'] = targetType;
    return Subject.fromJson(base, fallbackType: targetType ?? 'movie');
  }

  List<Subject> _subjectsFromItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(_subjectFromSearchItem)
        .where((subject) => subject.id.isNotEmpty)
        .toList();
  }

  static int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  @override
  Future<List<Subject>> fetchSuggest(String query) async {
    final result = await fetchSearchSuggestion(query);
    return result.subjects;
  }

  @override
  Future<List<Subject>> fetchSearch(String query) async {
    final result = await fetchSearchSubjects(query);
    return result.items;
  }

  @override
  Future<SearchSubjectsResult> fetchSearchSubjects(
    String query, {
    String? type,
    int start = 0,
    int count = 20,
  }) async {
    // Verified 2026-10-31 from official com.douban.frodo 7.136.0 APK +
    // signed guest probe (see DOUBAN_GUEST_API.md §2.6/2.7):
    // /search/subjects is the guest-usable subject search (200 for 肖申克,
    // first item 1292052). Do NOT use /search here: it returns 403
    // code 103 need_login for guests. Response shape:
    // subjects: {items: [{target_id, target_type, target: {id, title,
    // cover_url, card_subtitle, year, rating}}], total: "21"},
    // types: [{type, type_name, total: "21"}] (totals are strings).
    final data = await _client.signedGet(
      '/api/v2/search/subjects',
      {
        'q': query,
        if (type != null) 'type': type,
        'start': start,
        'count': count,
      },
    );
    final subjects = data['subjects'];
    if (subjects is! Map<String, dynamic>) return const SearchSubjectsResult();
    return SearchSubjectsResult(
      types: _parseList(data['types'], SearchTypeCount.fromJson),
      items: _subjectsFromItems(subjects['items']),
      total: _asInt(subjects['total']),
    );
  }

  @override
  Future<SuggestionResult> fetchSearchSuggestion(String query) async {
    // Frodo /search/suggestion (guest 200, 2026-10-31): cards[0] is the
    // top subject, words are plain suggestion strings. This replaces
    // the old Web j/subject_suggest, which had become unstable (empty
    // results / 403 code 008) in the 2026-10-31 recheck.
    final data = await _client.signedGet('/api/v2/search/suggestion', {'q': query});
    final words = (data['words'] as List?) ?? const [];
    return SuggestionResult(
      words: words.map((w) => '$w').toList(),
      subjects: _subjectsFromItems(data['cards']),
    );
  }

  @override
  Future<List<Subject>> fetchSearchHots() async {
    // Frodo /search/hots (guest 200, 2026-10-31): subjects[10] are
    // flat subject objects, not card-wrapped.
    final data = await _client.signedGet('/api/v2/search/hots');
    final raw = data['subjects'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((j) => Subject.fromJson(j))
        .where((subject) => subject.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<SearchContentItem>> fetchSearchContent(
    String query, {
    int start = 0,
    int count = 20,
  }) async {
    // Frodo /search/content_tab (guest 200, 2026-10-31):
    // contents: {items: [{layout, target: {title|name, card_subtitle, id}}]}.
    // Content items have no douya detail page yet, so the UI shows
    // them read-only instead of navigating.
    final data = await _client.signedGet(
      '/api/v2/search/content_tab',
      {'q': query, 'start': start, 'count': count},
    );
    final contents = data['contents'];
    if (contents is! Map<String, dynamic>) return const [];
    final items = contents['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().map((item) {
      final target = item['target'];
      final t = target is Map<String, dynamic> ? target : item;
      return SearchContentItem(
        id: '${t['id'] ?? ''}',
        title: (t['title'] as String?) ?? (t['name'] as String?) ?? '',
        subtitle: (t['card_subtitle'] as String?) ?? '',
      );
    }).where((item) => item.title.isNotEmpty).toList();
  }

  @override
  Future<SearchGroupResult> fetchSearchGroups(
    String query, {
    int start = 0,
    int count = 20,
  }) async {
    // Frodo /search/group_tab (guest 200, 2026-10-31):
    // groups: {items: [{target: {id, name, avatar, member_count, desc_abstract}}]},
    // topics: {items: [{target: {abstract, card_subtitle}}]}.
    final data = await _client.signedGet(
      '/api/v2/search/group_tab',
      {'q': query, 'start': start, 'count': count},
    );
    final groupsRaw = data['groups'];
    final topicsRaw = data['topics'];
    final groups = <SearchGroup>[];
    if (groupsRaw is Map<String, dynamic> && groupsRaw['items'] is List) {
      for (final item in (groupsRaw['items'] as List).whereType<Map<String, dynamic>>()) {
        final target = item['target'];
        final t = target is Map<String, dynamic> ? target : item;
        final id = '${t['id'] ?? ''}';
        if (id.isEmpty) continue;
        groups.add(SearchGroup(
          id: id,
          name: (t['name'] as String?) ?? '',
          avatar: t['avatar'] as String?,
          memberCount: _asInt(t['member_count']),
          description: (t['desc_abstract'] as String?) ?? '',
        ));
      }
    }
    final topics = <SearchContentItem>[];
    if (topicsRaw is Map<String, dynamic> && topicsRaw['items'] is List) {
      for (final item in (topicsRaw['items'] as List).whereType<Map<String, dynamic>>()) {
        final target = item['target'];
        final t = target is Map<String, dynamic> ? target : item;
        final title = (t['abstract'] as String?) ?? '';
        if (title.isEmpty) continue;
        topics.add(SearchContentItem(
          id: '${t['id'] ?? ''}',
          title: title,
          subtitle: (t['card_subtitle'] as String?) ?? '',
        ));
      }
    }
    return SearchGroupResult(groups: groups, topics: topics);
  }

  @override
  Future<List<SearchUser>> fetchSearchUsers(
    String query, {
    int start = 0,
    int count = 20,
  }) async {
    // Frodo /search/user (guest 200, total 648 for 肖申克, 2026-10-31):
    // items: [{layout: user, target_id, target: {avatar, abstract, name|display_name|uid}}].
    final data = await _client.signedGet(
      '/api/v2/search/user',
      {'q': query, 'start': start, 'count': count},
    );
    final items = data['items'];
    if (items is! List) return const [];
    final users = <SearchUser>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final target = item['target'];
      final t = target is Map<String, dynamic> ? target : item;
      final id = '${item['target_id'] ?? t['id'] ?? ''}';
      if (id.isEmpty) continue;
      users.add(SearchUser(
        id: id,
        name: (t['name'] as String?) ?? (t['display_name'] as String?) ?? (t['uid'] as String?) ?? '',
        avatar: t['avatar'] as String?,
        abstractText: (t['abstract'] as String?) ?? '',
      ));
    }
    return users;
  }

  @override
  Future<UserProfile> fetchUser(String id) async {
    final data = await _client.signedGet('/api/v2/user/$id');
    return UserProfile.fromJson(data);
  }

  @override
  Future<List<Interest>> fetchInterests(String userId, String type, String status) async {
    final data = await _client.signedGet(
      '/api/v2/user/$userId/interests',
      {'type': type, 'status': status, 'start': 0, 'count': 50},
    );
    return _parseList(data['interests'], Interest.fromJson);
  }

  @override
  Future<List<SearchGroup>> fetchHotGroups() async {
    // Rexxar /group/explore (unsigned, guest 200, 2026-10-31):
    // {"feed": [...]} with a top_groups module (本周热门趋势榜Top20,
    // 20 full group objects). The other modules (category_tags,
    // groups_sets, groups/你可能感兴趣) are ignored here. This is the
    // web-API equivalent of web /group/explore/hot_groups, verified
    // by matching first entry + member count across both sources.
    // Referer matches the probe (m.douban.com), not the movie referer
    // used by the subject Rexxar calls.
    final dio = Dio();
    final response = await dio.get(
      'https://m.douban.com/rexxar/api/v2/group/explore',
      queryParameters: {'start': 0, 'count': 20},
      options: Options(headers: {'Referer': 'https://m.douban.com/'}),
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) return const [];
    final feed = data['feed'];
    if (feed is! List) return const [];
    for (final module in feed.whereType<Map<String, dynamic>>()) {
      if (module['type'] != 'top_groups') continue;
      return _parseList(module['groups'], SearchGroup.fromJson)
          .where((group) => group.id.isNotEmpty && group.name.isNotEmpty)
          .toList();
    }
    return const [];
  }

  @override
  Future<List<GroupTopic>> fetchGroupTopics(String groupId) async {
    final result = await fetchGroupTopicsPaged(groupId, 'new', start: 0, count: 20);
    return result.items;
  }

  @override
  Future<TopicListResult> fetchGroupTopicsPaged(String groupId, String sort, {int start = 0, int count = 20}) async {
    final data = await _client.signedGet(
      '/api/v2/group/$groupId/topics',
      {'sortby': sort, 'start': start, 'count': count},
    );
    return TopicListResult(
      items: _parseList(data['topics'], GroupTopic.fromJson),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<TopicDetail> fetchTopic(String topicId) async {
    final results = await Future.wait([
      _client.signedGet('/api/v2/group/topic/$topicId'),
      _client.signedGet('/api/v2/group/topic/$topicId/comments', {'start': 0, 'count': 20}),
    ]);
    final detail = results[0];
    final comments = results[1];
    return TopicDetail(
      topic: GroupTopic.fromJson(detail),
      content: (detail['content'] as String?) ?? '',
      comments: _parseList(comments['comments'], TopicComment.fromJson),
    );
  }

  @override
  Future<CelebrityDetail> fetchCelebrity(String id) async {
    final results = await Future.wait([
      _client.signedGet('/api/v2/celebrity/$id'),
      _client.signedGet('/api/v2/celebrity/$id/works', {'start': 0, 'count': 20}),
    ]);
    final detail = results[0];
    final works = results[1];
    return CelebrityDetail(
      celebrity: Celebrity(
        id: id,
        name: (detail['title'] as String?) ?? '',
      ),
      works: _parseList(works['works'], (j) => Subject.fromJson(j)),
    );
  }
}
