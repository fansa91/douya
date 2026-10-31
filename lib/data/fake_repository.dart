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
Future<List<Interest>> fetchInterests(String userId, String type, String status) async {
return const [
Interest(
subject: _honglou,
status: 'done',
rating: Rating(value: 5, max: 5),
comment: '读过，很好。',
createTime: '2026-03-21',
),
];
}

@override
Future<List<SearchGroup>> fetchHotGroups() async => const [
      SearchGroup(id: '762280', name: '后会友期', memberCount: 8705, description: '离线示例，真实数据走 Rexxar /group/explore top_groups'),
      SearchGroup(id: '48007', name: '肖申克的救赎', memberCount: 1494, description: '离线示例，真实数据走 Rexxar /group/explore top_groups'),
    ];

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
Future<TopicDetail> fetchTopic(String topicId) async {
return const TopicDetail(
topic: GroupTopic(id: '504122375', title: '8号线杨思民用水电 押一付一', authorName: '房东'),
content: '话题正文放在这里。访客版只读，不提供回复入口。',
comments: [
TopicComment(authorName: '路人', text: '请问还可以看房吗？', voteCount: 2),
],
);
}

@override
Future<CelebrityDetail> fetchCelebrity(String id) async {
return const CelebrityDetail(
celebrity: Celebrity(id: '1054521', name: '蒂姆·罗宾斯', character: '饰 安迪·杜佛兰'),
works: [_shawshank],
);
}
}
