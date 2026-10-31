import '../models/models.dart';

/// The only data surface the UI depends on. Swap the implementation
/// in main.dart to switch between fake UI data and the live Frodo client.
abstract class DoubanRepository {
  Future<List<Subject>> fetchHot();
  Future<List<Subject>> fetchRecentHot();
  Future<List<Subject>> fetchTrending();

  /// Browse list for one (category, filter) pair, paged. `total` is the
  /// API's total; stop paging when items.length reaches it.
  Future<BrowseResult> fetchBrowse(String category, String filter, {int start = 0, int count = 20});

  /// Home (发现) recommendation sections, assembled from guest-usable
  /// sources (see RealDoubanRepository.fetchHomeSections for why the
  /// app's own personal feed is not used here).
  Future<List<HomeSection>> fetchHomeSections();
  Future<SubjectDetail> fetchSubject(String type, String id);

  /// Paged short comments (interests, status=done) and long reviews
  /// for a subject. Totals come from the API; stop at total.
  Future<CommentListResult> fetchSubjectComments(String type, String id, {int start = 0, int count = 20});
  Future<ReviewListResult> fetchSubjectReviews(String type, String id, {int start = 0, int count = 20});

  /// Long review full text. /api/v2/review/{id} (200, HTML content
  /// converted to plain text by ReviewDetail.fromJson). The
  /// /{type}/{id}/review/{id} form is 404 and must not be used.
  Future<ReviewDetail> fetchReview(String reviewId);
  Future<List<Subject>> fetchSuggest(String query);
  Future<List<Subject>> fetchSearch(String query);
  Future<SearchSubjectsResult> fetchSearchSubjects(String query, {String? type, int start = 0, int count = 20});
  Future<SuggestionResult> fetchSearchSuggestion(String query);
  Future<List<Subject>> fetchSearchHots();
  Future<List<SearchContentItem>> fetchSearchContent(String query, {int start = 0, int count = 20});
  Future<SearchGroupResult> fetchSearchGroups(String query, {int start = 0, int count = 20});
  Future<List<SearchUser>> fetchSearchUsers(String query, {int start = 0, int count = 20});
  Future<UserProfile> fetchUser(String id);
  Future<List<Interest>> fetchInterests(String userId, String type, String status);
  /// Hot groups: Rexxar /group/explore, top_groups module
  /// (本周热门趋势榜Top20), guest-usable without a signature
  /// (verified 2026-10-31; cross-checked against web
  /// /group/explore/hot_groups). NOT Frodo/Rexxar
  /// /group/recommend_feed_groups, which returns {"items":[]} for guests.
  /// Discussion featured (讨论精选) is deliberately NOT here: it has
  /// no JSON API, only server-rendered web HTML, and is shelved.
  Future<List<SearchGroup>> fetchHotGroups();

  /// Ranking boards for one tag category (numeric tag id, see
  /// RankBoard): Rexxar /tag/{tagId}/subject_collection_boards,
  /// unsigned, guest-usable (verified 2026-10-31). Each board's
  /// items come from fetchBoardItems.
  Future<List<RankBoard>> fetchRankBoards(String tagId);

  /// Paged items of one ranking board: Rexxar
  /// /subject_collection/{boardId}/items, unsigned, guest-usable
  /// (verified 2026-10-31, e.g. movie_top250 total 250, items carry
  /// rank/rank_value). `total` is the API's total.
  Future<BrowseResult> fetchBoardItems(String boardId, {int start = 0, int count = 20});

  /// Faceted tag search: Rexxar /{endpoint}/tag (endpoint is
  /// 'movie' or 'tv'; both hit the same backend, verified
  /// 2026-10-31), unsigned, guest-usable. `q` is the comma-joined
  /// selected dimension values (地区 / 类型 / 年代 / 特色); an empty
  /// q returns everything (total 786,514 at probe time). `sort` is
  /// U (默认) / T (热度) / S (评分) / R (时间); `playable` must be
  /// sent as the string 'true' (playable=1 is ignored, verified).
  /// The response also carries the dimension groups and sorts, so
  /// the first call supplies the filter UI itself.
  Future<TagSearchResult> fetchTagSearch(
    String endpoint, {
    String q = '',
    String sort = 'U',
    bool playable = false,
    int start = 0,
    int count = 20,
  });

  Future<List<GroupTopic>> fetchGroupTopics(String groupId);

  /// Paged group topics with a verified sort (new = 最新, hot = 热门).
  Future<TopicListResult> fetchGroupTopicsPaged(String groupId, String sort, {int start = 0, int count = 20});
  Future<TopicDetail> fetchTopic(String topicId);
  Future<CelebrityDetail> fetchCelebrity(String id);
}
