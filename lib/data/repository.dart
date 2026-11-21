import '../models/models.dart';

/// One page of a user's public interests: the items plus the API's
/// `total`. It lives here rather than in models.dart because the
/// other result classes predate the rule that models.dart is
/// off-limits for this round of work; the shape is identical.
class InterestListResult {
  const InterestListResult({required this.items, required this.total});

  final List<Interest> items;
  final int total;
}

/// One page of the "更多小组" list: the entries plus the API's
/// `total`. Pages overlap, so callers dedupe by group id and stop
/// when the loaded ids reach the total or a page adds nothing new.
class RecommendedGroupsResult {
  const RecommendedGroupsResult({required this.groups, required this.total});

  final List<RecommendedGroup> groups;
  final int total;
}

/// One page of a topic's replies: the items plus the API's `total`.
/// Same shape as InterestListResult, for the comments endpoint
/// (verified 2026-11-21: start/count paging works, total present).
class TopicCommentsResult {
  const TopicCommentsResult({required this.comments, required this.total, this.popularComments = const []});

  final List<TopicComment> comments;
  final int total;

  /// The response's `popular_comments` (hot replies), only
  /// meaningful on the first page.
  final List<TopicComment> popularComments;
}

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

  /// Paged subject photos: /{type}/{id}/photos with start/count +
  /// total (verified 2026-10-31 for movie 1292052: total 942,
  /// start=10 returns a different page). Failures surface to the
  /// UI as a SnackBar, like the paged comments.
  Future<PhotoListResult> fetchSubjectPhotos(String type, String id, {int start = 0, int count = 20});

  /// Home recommend feed: Frodo /elendil/recommend_feed with
  /// for_mobile=1 (guest-usable, verified 2026-10-31). No total:
  /// hasMore is true only when a full page came back.
  Future<FeedResult> fetchRecommendFeed({int start = 0, int count = 20});
  Future<List<Subject>> fetchSuggest(String query);
  Future<List<Subject>> fetchSearch(String query);
  Future<SearchSubjectsResult> fetchSearchSubjects(String query, {String? type, int start = 0, int count = 20});
  Future<SuggestionResult> fetchSearchSuggestion(String query);
  Future<List<Subject>> fetchSearchHots();

  /// Hot search board: Rexxar /chart/hot_search_board (unsigned,
  /// guest 200, verified 2026-11-21). A bare list of 15 {name, score,
  /// trend_flag, uri}. This is the search page's primary hot list;
  /// fetchSearchHots (Frodo /search/hots, 10 subjects, no score or
  /// trend) is only the fallback when this board fails or comes back
  /// empty. A wrong-shaped response returns an empty list; a network
  /// error throws.
  Future<List<HotSearchBoardItem>> fetchHotSearchBoard();

  /// Find-movie / find-tv landing: Rexxar /{movie|tv}/landing
  /// (unsigned, guest 200, verified 2026-11-21). Returns the tag
  /// groups {name, items[{name, uri, header_bg_image,
  /// header_bg_color}]}: 专题 (board deep links) + 类型/地区/特色/
  /// 播出平台 (tag deep links). A wrong-shaped response returns an
  /// empty list; a network error throws.
  Future<List<LandingGroup>> fetchLanding(String type);

  /// Faceted now-playing list: Rexxar /movie/movie_showing
  /// (unsigned, guest 200, verified 2026-11-21). `locId` is required
  /// by the server (missing -> 400 code 113); the other filters are
  /// optional. Verified: sort (recommend/time/rank) reorders,
  /// playable=true filters to playable titles, score_range is
  /// "min,max" (e.g. "8,10"). The area parameter the H5 page shows
  /// is ignored by this endpoint (every area value returns the
  /// unfiltered total), so it is deliberately not a parameter here.
  Future<BrowseResult> fetchMovieShowing({
    String? sort,
    bool playable = false,
    String? scoreRange,
    required int locId,
    int start = 0,
    int count = 20,
  });
  Future<List<SearchContentItem>> fetchSearchContent(String query, {int start = 0, int count = 20});
  Future<SearchGroupResult> fetchSearchGroups(String query, {int start = 0, int count = 20});
  Future<List<SearchUser>> fetchSearchUsers(String query, {int start = 0, int count = 20});
  Future<UserProfile> fetchUser(String id);

  /// One page of a user's public interests. The interests endpoint
  /// returns a `total` alongside the items; the old List return type
  /// dropped it, so pages over 50 were silently truncated.
  Future<InterestListResult> fetchInterests(
    String userId,
    String type,
    String status, {
    int start = 0,
    int count = 50,
  });
  /// Hot groups: Rexxar /group/explore, top_groups module
  /// (本周热门趋势榜Top20), guest-usable without a signature
  /// (verified 2026-10-31; cross-checked against web
  /// /group/explore/hot_groups). NOT Frodo/Rexxar
  /// /group/recommend_feed_groups, which returns {"items":[]} for guests.
  /// Discussion featured (讨论精选) is deliberately NOT here: it has
  /// no JSON API, only server-rendered web HTML, and is shelved.
  /// The 5-minute cache shares the response with fetchGroupExplore.
  Future<List<SearchGroup>> fetchHotGroups();

  /// Group discovery: Rexxar /group/explore, all four modules at
  /// once (top_groups, category_tags, groups_sets, groups/更多小组）,
  /// guest-usable without a signature (verified 2026-11-21). One
  /// response is one snapshot; the 5-minute cache keeps this and
  /// fetchHotGroups on the same request. Categories and sets have no
  /// second hop in the response (no uri), so the UI renders only the
  /// "更多小组" list until their list API is found.
  Future<GroupExplore> fetchGroupExplore();

  /// One page of the "更多小组" list (the groups module of
  /// /group/explore, start/count + total, verified 2026-11-21).
  /// Pages overlap, so callers dedupe by group id and stop when the
  /// loaded ids reach the total or a page adds nothing new.
  Future<RecommendedGroupsResult> fetchRecommendedGroups({int start = 0, int count = 20});

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

  /// Full group object for the detail-page header (name, member
  /// count, description, avatars): Frodo /group/{id}, signed, guest
  /// 200 (verified 2026-10-31, e.g. 146409 上海租房）.
  Future<SearchGroup> fetchGroupDetail(String groupId);
  Future<TopicDetail> fetchTopic(String topicId);

  /// One page of a topic's replies, by start/count. The comments
  /// endpoint returns a `total`; stop when loaded reaches it.
  Future<TopicCommentsResult> fetchTopicComments(String topicId, {int start = 0, int count = 20});
  Future<CelebrityDetail> fetchCelebrity(String id);

  /// Paged works for a celebrity (the /works endpoint pages with
  /// start/count; total 113 for the probed case). The detail's
  /// first page comes from fetchCelebrity.
  Future<CelebrityWorksResult> fetchCelebrityWorks(String id, {int start = 0, int count = 20});

  /// Five-tier rating distribution for a subject (Frodo
  /// /{type}/{id}/rating, guest 200, verified 2026-11-21).
  Future<RatingStats> fetchRatingStats(String type, String id);

  /// Awards for a subject (Frodo /{type}/{id}/awards, guest 200,
  /// verified 2026-11-21; total 15 for movie 1291546, total 0 for
  /// 1292052 — an empty result is normal, hide the section).
  Future<AwardsResult> fetchAwards(String type, String id, {int start = 0, int count = 20});

  /// Photos for a celebrity (Frodo /celebrity/{id}/photos, guest
  /// 200, verified 2026-11-21; total 120 for 1054521).
  Future<CelebrityPhotosResult> fetchCelebrityPhotos(String id, {int start = 0, int count = 20});
}
