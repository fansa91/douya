import '../models/models.dart';
import 'repository.dart';

/// Offline sample data, using the ids already verified by probing
/// (see../douban-guest-api/DOUBAN_GUEST_API.md section 6).
/// This lets the UI run without a key or network.
class FakeDoubanRepository implements DoubanRepository {
const FakeDoubanRepository();

static const _shawshank = Subject(
id: '1292052',
type: 'movie',
title: '肖申克的救赎',
rating: Rating(value: 9.7, max: 10, count: 3354509),
year: '1994',
cardSubtitle: '剧情 / 犯罪',
);

static const _honglou = Subject(
id: '1007305',
type: 'book',
title: '红楼梦',
rating: Rating(value: 9.7, max: 10, count: 470778),
cardSubtitle: '小说',
);

@override
Future<List<Subject>> fetchHot() async => const [_shawshank, _honglou];

@override
Future<List<Subject>> fetchRecentHot() async => const [_shawshank];

@override
Future<List<Subject>> fetchTrending() async => const [_shawshank, _honglou];

@override
Future<BrowseResult> fetchBrowse(String category, String filter, {int start = 0, int count = 20}) async {
  final items = category == 'book' ? const [_honglou] : const [_shawshank];
  return BrowseResult(items: items, total: items.length);
}

@override
Future<List<HomeSection>> fetchHomeSections() async => const [
      HomeSection(title: '电影推荐', items: [_shawshank], category: 'movie', filter: 'recommend'),
      HomeSection(title: '热门图书', items: [_honglou], category: 'book', filter: 'hot'),
    ];

@override
Future<BrowseResult> fetchMovieShowing({
  String? sort,
  bool playable = false,
  String? scoreRange,
  required int locId,
  int start = 0,
  int count = 20,
}) async =>
    const BrowseResult(items: [_shawshank, _honglou], total: 2);

@override
Future<SubjectDetail> fetchSubject(String type, String id) async {
return const SubjectDetail(
subject: _shawshank,
summary: '希望放在心里，永远不会褪色。这是一部关于自由与希望的电影。',
directors: ['弗兰克·德拉邦特'],
actors: ['蒂姆·罗宾斯', '摩根·弗里曼'],
genres: ['剧情', '犯罪'],
comments: [
ShortComment(
userName: '用户A',
text: '有些鸟是关不住的，因为它们的羽毛太光亮了。',
rating: Rating(value: 5, max: 5),
voteCount: 128,
),
ShortComment(
userName: '用户B',
text: '希望是一件好事，也许是人间至善，而美好的事永不消逝。',
rating: Rating(value: 4, max: 5),
voteCount: 96,
),
],
reviews: [
Review(
id: '1000369',
title: '十年·肖申克的救赎',
abstract: '这篇长评的摘要放在这里，详情页只显示前三行。',
usefulCount: 1024,
commentsCount: 128,
),
],
celebrities: [
Celebrity(id: '1054521', name: '蒂姆·罗宾斯', character: '饰 安迪·杜佛兰'),
],
doulists: [
Subject(id: '1', type: 'doulist', title: '画家-艺术 传记相关', isDoulist: true, doulistCount: 24),
],
);
}

@override
Future<List<Subject>> fetchSuggest(String query) async {
if (query.isEmpty) return const [];
return const [_shawshank];
}

@override
Future<List<Subject>> fetchSearch(String query) async {
if (query.isEmpty) return const [];
return const [_shawshank, _honglou];
}

@override
Future<SearchSubjectsResult> fetchSearchSubjects(String query, {String? type, int start = 0, int count = 20}) async {
if (query.isEmpty) return const SearchSubjectsResult();
final items = type == null
    ? const [_shawshank, _honglou]
    : type == 'book'
        ? const [_honglou]
        : const [_shawshank];
return SearchSubjectsResult(
types: const [
SearchTypeCount(type: 'movie', typeName: '影视', total: 1),
SearchTypeCount(type: 'book', typeName: '图书', total: 1),
],
items: items,
total: items.length,
);
}

@override
Future<SuggestionResult> fetchSearchSuggestion(String query) async {
if (query.isEmpty) return const SuggestionResult();
return SuggestionResult(words: [query], subjects: const [_shawshank]);
}

@override
Future<List<Subject>> fetchSearchHots() async => const [_shawshank, _honglou];

@override
Future<List<HotSearchBoardItem>> fetchHotSearchBoard() async => const [
  HotSearchBoardItem(name: '示例热搜一', score: 27232, uri: 'douban://douban.com/search/result?q=%23%E7%A4%BA%E4%BE%8B%E7%83%AD%E6%90%9C%E4%B8%80%23'),
  HotSearchBoardItem(name: '示例热搜二', score: 18500, uri: 'douban://douban.com/search/result?q=%23%E7%A4%BA%E4%BE%8B%E7%83%AD%E6%90%9C%E4%BA%8C%23'),
  HotSearchBoardItem(name: '示例热搜三', score: 9200, uri: 'douban://douban.com/search/result?q=%23%E7%A4%BA%E4%BE%8B%E7%83%AD%E6%90%9C%E4%B8%89%23'),
];

@override
Future<List<LandingGroup>> fetchLanding(String type) async {
  if (type == 'tv') {
    return const [
      LandingGroup(name: '地区', items: [
        LandingItem(name: '大陆剧', uri: 'douban://douban.com/tv/tag?q=中国大陆,电视剧'),
        LandingItem(name: '美剧', uri: 'douban://douban.com/tv/tag?q=美国,电视剧'),
      ]),
      LandingGroup(name: '播出平台', items: [
        LandingItem(name: 'HBO', uri: 'douban://douban.com/tv/tag?q=HBO,电视剧'),
      ]),
    ];
  }
  return const [
    LandingGroup(name: '专题', items: [
      LandingItem(name: '豆瓣热门', uri: 'douban://douban.com/subject_collection/movie_hot_gaia'),
      LandingItem(name: '最新电影', uri: 'douban://douban.com/subject_collection/movie_newest'),
    ]),
    LandingGroup(name: '类型', items: [
      LandingItem(name: '喜剧', uri: 'douban://douban.com/subject/recommendation/movie?tag=喜剧,电影'),
      LandingItem(name: '动作', uri: 'douban://douban.com/subject/recommendation/movie?tag=动作,电影'),
    ]),
  ];
}

@override
Future<List<SearchContentItem>> fetchSearchContent(String query, {int start = 0, int count = 20}) async {
if (query.isEmpty) return const [];
return const [SearchContentItem(id: '1', title: '示例话题', subtitle: '离线示例，真实数据走 Frodo /search/content_tab')];
}

@override
Future<SearchGroupResult> fetchSearchGroups(String query, {int start = 0, int count = 20}) async {
if (query.isEmpty) return const SearchGroupResult();
return const SearchGroupResult(
groups: [SearchGroup(id: '48007', name: '肖申克的救赎', memberCount: 1494, description: '希望是美好的')],
topics: [SearchContentItem(id: '504122375', title: '示例话题', subtitle: '离线示例')],
);
}

@override
Future<List<SearchUser>> fetchSearchUsers(String query, {int start = 0, int count = 20}) async {
if (query.isEmpty) return const [];
return const [SearchUser(id: '2870956', name: 'River', abstractText: '离线示例用户')];
}

@override
Future<UserProfile> fetchUser(String id) async {
return const UserProfile(
id: '2870956',
name: 'River',
followersCount: 120,
followingCount: 80,
bookCollectedCount: 1,
);
}

@override
Future<InterestListResult> fetchInterests(
  String userId,
  String type,
  String status, {
  int start = 0,
  int count = 50,
}) async {
  const all = [
    Interest(
      subject: _honglou,
      status: 'done',
      rating: Rating(value: 5, max: 5),
      comment: '读过，很好。',
      createTime: '2026-03-21',
    ),
  ];
  return InterestListResult(
    items: all.skip(start).take(count).toList(),
    total: all.length,
  );
}

@override
Future<List<SearchGroup>> fetchHotGroups() async => const [
      SearchGroup(id: '762280', name: '后会友期', memberCount: 8705, description: '离线示例，真实数据走 Rexxar /group/explore top_groups'),
      SearchGroup(id: '48007', name: '肖申克的救赎', memberCount: 1494, description: '离线示例，真实数据走 Rexxar /group/explore top_groups'),
    ];

@override
Future<GroupExplore> fetchGroupExplore() async => const GroupExplore(
  hotGroups: [
    SearchGroup(id: '762280', name: '后会友期', memberCount: 8705),
    SearchGroup(id: '48007', name: '肖申克的救赎', memberCount: 1494),
  ],
  categoryTags: [
    GroupCategoryTag(name: '分类_闲趣', count: 1833),
    GroupCategoryTag(name: '追剧', count: 5590),
  ],
  groupsSets: [
    GroupsSet(
      title: '用镜头表达',
      isFeatured: true,
      groups: [SearchGroup(id: '762280', name: '后会友期', memberCount: 8705)],
    ),
  ],
  recommendedGroups: [
    RecommendedGroup(
      group: SearchGroup(id: '111', name: '更多小组一', memberCount: 1000),
      topics: [GroupTopic(id: '1', title: '示例话题一', commentsCount: 12)],
      source: 'hot',
    ),
    RecommendedGroup(
      group: SearchGroup(id: '222', name: '更多小组二', memberCount: 2000),
      topics: [GroupTopic(id: '2', title: '示例话题二', commentsCount: 34)],
      source: 'hot',
    ),
  ],
  // Page 1 holds 2 of 3; the third arrives through
  // fetchRecommendedGroups, so the UI's load-more is exercised.
  recommendedTotal: 3,
);

@override
Future<RecommendedGroupsResult> fetchRecommendedGroups({int start = 0, int count = 20}) async {
  const all = [
    RecommendedGroup(group: SearchGroup(id: '111', name: '更多小组一', memberCount: 1000), source: 'hot'),
    RecommendedGroup(group: SearchGroup(id: '222', name: '更多小组二', memberCount: 2000), source: 'hot'),
    RecommendedGroup(group: SearchGroup(id: '333', name: '更多小组三', memberCount: 3000), source: 'hot'),
  ];
  if (start >= all.length) return const RecommendedGroupsResult(groups: [], total: 3);
  final end = (start + count).clamp(0, all.length);
  return RecommendedGroupsResult(groups: all.sublist(start, end), total: 3);
}

@override
Future<List<RankBoard>> fetchRankBoards(String tagId) async {
  // Only the one board whose id + subject count were verified by
  // probing (6月豆瓣电影口碑榜Top20, id 1818, 159 subjects, tag 49).
  if (tagId != '49') return const [];
  return const [
    RankBoard(id: '1818', name: '6月豆瓣电影口碑榜Top20', subjectCount: 159, showRank: true),
  ];
}

@override
Future<BrowseResult> fetchBoardItems(String boardId, {int start = 0, int count = 20}) async {
  const ranked = Subject(
    id: '1292052',
    type: 'movie',
    title: '肖申克的救赎',
    rating: Rating(value: 9.7, max: 10, count: 3354509),
    year: '1994',
    cardSubtitle: '剧情 / 犯罪',
    rank: 1,
  );
  return const BrowseResult(items: [ranked], total: 1);
}

@override
Future<TagSearchResult> fetchTagSearch(
  String endpoint, {
  String q = '',
  String sort = 'U',
  bool playable = false,
  int start = 0,
  int count = 20,
}) async {
  return const TagSearchResult(
    items: [_shawshank],
    total: 1,
    groups: [
      TagGroup(type: '地区', values: ['全部地区', '中国大陆', '美国', '日本']),
      TagGroup(type: '类型', values: ['全部类型', '剧情', '喜剧']),
      TagGroup(type: '年代', values: ['全部年代', '2024', '2010年代']),
      TagGroup(type: '特色', values: ['全部特色', '经典', '青春']),
    ],
    sorts: [
      TagSort(name: 'U', text: '默认'),
      TagSort(name: 'T', text: '热度'),
      TagSort(name: 'S', text: '评分'),
      TagSort(name: 'R', text: '时间'),
    ],
  );
}

@override
Future<List<GroupTopic>> fetchGroupTopics(String groupId) async {
return const [
GroupTopic(id: '504122375', title: '8号线杨思民用水电 押一付一', authorName: '房东', commentsCount: 3),
GroupTopic(id: '504121040', title: '个人转租，9号线漕河泾地铁口600米', authorName: '转租人', commentsCount: 0),
];
}

@override
Future<TopicListResult> fetchGroupTopicsPaged(String groupId, String sort, {int start = 0, int count = 20}) async {
  final topics = await fetchGroupTopics(groupId);
  return TopicListResult(items: topics, total: topics.length);
}

@override
Future<SearchGroup> fetchGroupDetail(String groupId) async {
  return SearchGroup(id: groupId, name: '示例小组', memberCount: 1494, description: '离线示例，真实数据走 Frodo /group/{id}');
}

/// 25 fake replies: enough for two pages (20 + 5). The first is
/// by the topic author (for the 楼主 badge); one quotes another
/// comment; every third one carries an ip_location.
static List<TopicComment> get _fakeTopicComments {
  final comments = <TopicComment>[];
  for (var i = 0; i < 25; i++) {
    final isAuthor = i == 0;
    comments.add(TopicComment(
      authorName: isAuthor ? '房东' : '路人$i',
      authorId: isAuthor ? 'u-landlord' : 'u-$i',
      text: isAuthor
          ? '我是房东，房子还在'
          : i == 1
              ? '请问还可以看房吗？'
              : i == 2
                  ? '已私信'
                  : '回复内容$i',
      voteCount: isAuthor ? 30 : i == 1 ? 12 : i == 2 ? 8 : 24 - i,
      createTime: '2026-11-20 10:00',
      ipLocation: i % 3 == 0 ? '上海' : null,
      refComment: i == 2
          ? const TopicComment(authorName: '路人1', authorId: 'u-1', text: '请问还可以看房吗？', voteCount: 12)
          : null,
    ));
  }
  return comments;
}

@override
Future<TopicCommentsResult> fetchTopicComments(String topicId, {int start = 0, int count = 20}) async {
  final total = _fakeTopicComments.length;
  final page = start < total
      ? _fakeTopicComments.sublist(start, (start + count).clamp(0, total))
      : const <TopicComment>[];
  // Hot replies ride on the first page only: the two most-liked
  // replies that are not the topic author's.
  final popular = start == 0
      ? (_fakeTopicComments.where((c) => c.authorId != 'u-landlord').toList()
            ..sort((a, b) => b.voteCount.compareTo(a.voteCount)))
          .take(2)
          .toList()
      : const <TopicComment>[];
  return TopicCommentsResult(comments: page, total: total, popularComments: popular);
}

@override
Future<TopicDetail> fetchTopic(String topicId) async {
  final page = await fetchTopicComments(topicId, start: 0, count: 20);
  return TopicDetail(
    topic: const GroupTopic(
      id: '504122375',
      title: '8号线杨思民用水电 押一付一',
      authorName: '房东',
      authorId: 'u-landlord',
      commentsCount: 25,
      createTime: '2026-11-20 10:00',
    ),
    groupId: '146409',
    groupName: '上海租房',
    content: '话题正文放在这里。相关链接第二段正文。',
    contentHtml: '<p>话题正文放在这里。<a href="https://example.com">相关链接</a></p><img src="https://img.example/body.jpg"><p>第二段正文。</p>',
    sharingUrl: 'https://www.douban.com/group/topic/504122375/',
    ipLocation: '上海',
    comments: page.comments,
    commentsTotal: page.total,
    popularComments: page.popularComments,
  );
}

@override
Future<CommentListResult> fetchSubjectComments(String type, String id, {int start = 0, int count = 20}) async {
  final detail = await fetchSubject(type, id);
  return CommentListResult(items: detail.comments, total: detail.comments.length);
}

@override
Future<ReviewListResult> fetchSubjectReviews(String type, String id, {int start = 0, int count = 20}) async {
  final detail = await fetchSubject(type, id);
  return ReviewListResult(items: detail.reviews, total: detail.reviews.length);
}

@override
@override
Future<PhotoListResult> fetchSubjectPhotos(String type, String id, {int start = 0, int count = 20}) async {
  // The fake detail carries no photos, so the paged photo grid has
  // nothing to page through offline.
  return const PhotoListResult();
}

@override
Future<FeedResult> fetchRecommendFeed({int start = 0, int count = 20}) async {
  // Offline samples mirroring the real feed shape: a topic post
  // and a review post. Paging ends after this one page.
  if (start > 0) return const FeedResult();
  return const FeedResult(
    items: [
      FeedItem(
        id: '503570060',
        type: 'topic',
        typeCn: '动态',
        abstract: '假数据示例话题：周末重看了一遍老电影，还是开头那段最耐看。',
        authorName: '样例用户',
        commentsCount: 61,
        reactionsCount: 323,
        resharesCount: 2,
      ),
      FeedItem(
        id: '17839104',
        type: 'review',
        typeCn: '影评',
        abstract: '标题这句话我放这了，过几年回头看看是不是这样。',
        authorName: '样例用户',
        commentsCount: 2,
      ),
    ],
  );
}

@override
Future<ReviewDetail> fetchReview(String reviewId) async {
  return const ReviewDetail(
    id: '1000369',
    title: '十年·肖申克的救赎',
    userName: '离线示例',
    content: '长评全文示例。真实数据走 Frodo /api/v2/review/{id}，返回的 HTML 会在模型层转成纯文本。',
    usefulCount: 1024,
    commentsCount: 128,
  );
}

/// Sample works for the fake celebrity (both on the first page).
static const _fakeCelebrityWorks = <CelebrityWork>[
  CelebrityWork(subject: _shawshank, roles: ['演员 (饰 安迪·杜佛兰 Andy Dufresne)']),
  CelebrityWork(
    subject: Subject(id: '1292971', type: 'movie', title: '绿里奇迹', rating: Rating(value: 8.9, max: 10, count: 1200000), year: '1999', cardSubtitle: '剧情 / 奇幻'),
    roles: ['演员 (饰 保罗·艾吉康)'],
  ),
];

@override
Future<CelebrityDetail> fetchCelebrity(String id) async {
  final page = await fetchCelebrityWorks(id, start: 0, count: 20);
  return CelebrityDetail(
    celebrity: const Celebrity(
      id: '1054521',
      name: '蒂姆·罗宾斯',
      avatar: 'https://img3.doubanio.com/view/celebrity/s_ratio_celebrity/public/p12345.jpg',
      latinTitle: 'Tim Robbins',
      shortInfo: '演员 导演 制片人 / 肖申克的救赎',
      info: [('性别', '男'), ('出生日期', '1958年10月16日'), ('出生地', '美国,加利福尼亚州,西科维纳')],
      character: '饰 安迪·杜佛兰',
    ),
    works: page.works,
    worksTotal: page.total,
  );
}

@override
Future<CelebrityWorksResult> fetchCelebrityWorks(String id, {int start = 0, int count = 20}) async {
  final total = _fakeCelebrityWorks.length;
  final page = start < total ? _fakeCelebrityWorks.sublist(start, (start + count).clamp(0, total)) : const <CelebrityWork>[];
  return CelebrityWorksResult(works: page, total: total);
}

@override
Future<RatingStats> fetchRatingStats(String type, String id) async =>
    const RatingStats(
      stats: [0.01, 0.02, 0.12, 0.30, 0.55],
      doneCount: 1000,
      doingCount: 10,
      wishCount: 500,
      typeRanks: [TypeRank(type: '剧情片', rank: 0.95)],
    );

@override
Future<AwardsResult> fetchAwards(String type, String id, {int start = 0, int count = 20}) async =>
    const AwardsResult(
      awards: [
        Award(
          ceremonyId: '1',
          ceremonyTitle: '示例电影节',
          ceremonyNumber: 1,
          ceremonyYear: 2026,
          categories: [AwardCategory(title: '最佳影片', isWon: true, celebrityNames: ['示例影人'])],
        ),
      ],
      total: 1,
    );

@override
Future<CelebrityPhotosResult> fetchCelebrityPhotos(String id, {int start = 0, int count = 20}) async =>
    const CelebrityPhotosResult(
      photos: [
        CelebrityPhoto(id: '1', imageUrl: 'https://example.com/photo1.jpg', description: '示例剧照', authorName: '示例用户'),
      ],
      total: 1,
    );
}
