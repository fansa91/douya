/// Shared models for douya. All parsers are tolerant: Frodo and Rexxar
/// use different field names for the same idea (pic vs cover vs images),
/// and some fields are absent on some types.
library;

class Rating {
  const Rating({required this.value, required this.max, this.count = 0});

  /// Community rating: value is 0-10, max is 10.
  /// Personal rating: value is 1-5, max is 5. Never mix the two.
  final double value;
  final int max;
  final int count;

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      value: (json['value'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toInt() ?? 10,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  static Rating? tryParse(dynamic value) {
    if (value is Map<String, dynamic>) return Rating.fromJson(value);
    return null;
  }
}

class Subject {
  const Subject({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.pic,
    this.rating,
    this.year,
    this.cardSubtitle,
    this.isDoulist = false,
    this.doulistCount,
  });

  final String id;
  final String type; // movie | tv | book | music | game
  final String title;
  final String? originalTitle;
  final String? pic;
  final Rating? rating;
  final String? year;
  final String? cardSubtitle;
  final bool isDoulist;
  final int? doulistCount;

  factory Subject.fromJson(Map<String, dynamic> json, {String fallbackType = 'movie'}) {
    String? pic;
    final rawPic = json['pic'];
    if (rawPic is Map) {
      pic = rawPic['large'] as String? ?? rawPic['normal'] as String?;
    } else if (rawPic is String) {
      pic = rawPic;
    }
    final rawCover = json['cover'];
    if (pic == null && rawCover is Map) {
      pic = rawCover['large'] as String? ?? rawCover['normal'] as String?;
    }
    pic ??= json['cover_url'] as String? ?? (rawCover is String ? rawCover : null);
    final images = json['images'];
    if (pic == null && images is Map) {
      pic = images['large'] as String?;
    }
    final itemType = json['item_type'] as String? ?? json['type'] as String?;
    return Subject(
      id: '${json['id'] ?? ''}',
      type: itemType ?? fallbackType,
      title: (json['title'] as String?) ?? '',
      originalTitle: json['original_title'] as String?,
      pic: pic,
      rating: Rating.tryParse(json['rating']),
      year: json['year'] as String?,
      cardSubtitle: json['card_subtitle'] as String?,
      isDoulist: (json['doulist_type'] as String?) != null || itemType == 'doulist',
      doulistCount: (json['items_count'] as num?)?.toInt(),
    );
  }
}

class Trailer {
  const Trailer({
    required this.id,
    this.title = '',
    this.coverUrl,
    this.videoUrl,
    this.runtime = '',
    this.desc = '',
  });

  final String id;
  final String title;
  final String? coverUrl;
  final String? videoUrl;
  final String runtime;
  final String desc;

  factory Trailer.fromJson(Map<String, dynamic> json) {
    return Trailer(
      id: '${json['id'] ?? ''}',
      title: (json['title'] as String?) ?? '',
      coverUrl: json['cover_url'] as String?,
      videoUrl: json['video_url'] as String?,
      runtime: (json['runtime'] as String?) ?? '',
      desc: (json['desc'] as String?) ?? '',
    );
  }
}

class SubjectDetail {
  const SubjectDetail({
    required this.subject,
    this.summary = '',
    this.directors = const [],
    this.actors = const [],
    this.authors = const [],
    this.episodesCount = 0,
    this.episodesInfo = '',
    this.genres = const [],
    this.comments = const [],
    this.reviews = const [],
    this.photos = const [],
    this.recommendations = const [],
    this.doulists = const [],
    this.celebrities = const [],
    this.trailers = const [],
  });

  final Subject subject;
  final String summary;
  final List<String> directors;
  final List<String> actors;

  /// Book author (detail['author'], a list of strings) and music
  /// singer (detail['singer'], a list of {name}) share this field;
  /// movie/tv leave it empty and use directors/actors instead.
  final List<String> authors;

  /// TV only. episodes_count is the total (e.g. 29); episodes_info
  /// is a status string (e.g. 更新至22集), NOT an episode list, so
  /// there is no per-episode data to show behind this line.
  final int episodesCount;
  final String episodesInfo;
  final List<String> genres;
  final List<ShortComment> comments;
  final List<Review> reviews;
  final List<Photo> photos;
  final List<Subject> recommendations;
  final List<Subject> doulists;
  final List<Celebrity> celebrities;
  final List<Trailer> trailers;
}

/// Search result models. Frodo search responses are card-shaped:
/// items carry layout + target_id + target_type + target, not a flat
/// subject. Parsers below stay tolerant because different tabs use
/// different target shapes (subject / group / user / content).

class SearchTypeCount {
  const SearchTypeCount({required this.type, required this.typeName, required this.total});

  final String type;
  final String typeName;
  final int total;

  factory SearchTypeCount.fromJson(Map<String, dynamic> json) {
    return SearchTypeCount(
      type: (json['type'] as String?) ?? '',
      typeName: (json['type_name'] as String?) ?? '',
      total: int.tryParse('${json['total'] ?? 0}') ?? 0,
    );
  }
}

class SearchSubjectsResult {
  const SearchSubjectsResult({this.types = const [], this.items = const [], this.total = 0});

  final List<SearchTypeCount> types;
  final List<Subject> items;
  final int total;
}

class SuggestionResult {
  const SuggestionResult({this.words = const [], this.subjects = const []});

  final List<String> words;
  final List<Subject> subjects;
}

class SearchContentItem {
  const SearchContentItem({required this.id, required this.title, this.subtitle = ''});

  final String id;
  final String title;
  final String subtitle;
}

class SearchGroup {
  const SearchGroup({
    required this.id,
    required this.name,
    this.avatar,
    this.memberCount = 0,
    this.description = '',
  });

  final String id;
  final String name;
  final String? avatar;
  final int memberCount;
  final String description;

  /// Tolerant group summary parser. Used by Frodo /search/group_tab
  /// (avatar is a String, description is desc_abstract) and by Rexxar
  /// /group/explore top_groups (avatar may be a String or a Map,
  /// description is desc). Hot-group objects are full group objects,
  /// so only the summary fields are kept here.
  factory SearchGroup.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar'];
    String? avatar;
    if (rawAvatar is String) {
      avatar = rawAvatar;
    } else if (rawAvatar is Map) {
      avatar = rawAvatar['large'] as String? ?? rawAvatar['normal'] as String?;
    }
    return SearchGroup(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?) ?? '',
      avatar: avatar,
      memberCount: int.tryParse('${json['member_count'] ?? 0}') ?? 0,
      description: (json['desc_abstract'] as String?) ?? (json['desc'] as String?) ?? (json['description'] as String?) ?? '',
    );
  }
}

class SearchGroupResult {
  const SearchGroupResult({this.groups = const [], this.topics = const []});

  final List<SearchGroup> groups;
  final List<SearchContentItem> topics;
}

class SearchUser {
  const SearchUser({required this.id, required this.name, this.avatar, this.abstractText = ''});

  final String id;
  final String name;
  final String? avatar;
  final String abstractText;
}

class ShortComment {
  const ShortComment({
    required this.userName,
    required this.text,
    this.rating,
    this.voteCount = 0,
    this.createTime = '',
  });

  final String userName;
  final String text;
  final Rating? rating;
  final int voteCount;
  final String createTime;

  factory ShortComment.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String name = '';
    if (user is Map) name = (user['name'] as String?) ?? '';
    return ShortComment(
      userName: name,
      text: (json['comment'] as String?) ?? (json['text'] as String?) ?? '',
      rating: Rating.tryParse(json['rating']),
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      createTime: (json['create_time'] as String?) ?? '',
    );
  }
}

class Review {
  const Review({
    required this.id,
    required this.title,
    required this.abstract,
    this.userName = '',
    this.rating,
    this.usefulCount = 0,
    this.commentsCount = 0,
  });

  final String id;
  final String title;
  final String abstract;
  final String userName;
  final Rating? rating;
  final int usefulCount;
  final int commentsCount;

  factory Review.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String name = '';
    if (user is Map) name = (user['name'] as String?) ?? '';
    return Review(
      id: '${json['id'] ?? ''}',
      title: (json['title'] as String?) ?? '',
      abstract: (json['abstract'] as String?) ?? '',
      userName: name,
      rating: Rating.tryParse(json['rating']),
      usefulCount: (json['useful_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class Photo {
  const Photo({required this.id, this.url, this.description = ''});

  final String id;
  final String? url;
  final String description;

  factory Photo.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    String? url;
    if (image is Map) {
      url = image['large'] as String? ?? image['normal'] as String?;
    } else if (image is String) {
      url = image;
    }
    url ??= json['url'] as String?;
    return Photo(
      id: '${json['id'] ?? ''}',
      url: url,
      description: (json['description'] as String?) ?? '',
    );
  }
}

class Celebrity {
  const Celebrity({
    required this.id,
    required this.name,
    this.avatar,
    this.character,
    this.roles = const [],
  });

  final String id;
  final String name;
  final String? avatar;
  final String? character;
  final List<String> roles;

  factory Celebrity.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'];
    String? avatarUrl;
    if (avatar is Map) {
      avatarUrl = avatar['large'] as String? ?? avatar['normal'] as String?;
    }
    return Celebrity(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?) ?? '',
      avatar: avatarUrl,
      character: json['character'] as String?,
      roles: ((json['roles'] as List?) ?? []).map((e) => '$e').toList(),
    );
  }
}

class CelebrityDetail {
  const CelebrityDetail({
    required this.celebrity,
    this.works = const [],
  });

  final Celebrity celebrity;
  final List<Subject> works;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.avatar,
    this.followersCount = 0,
    this.followingCount = 0,
    this.bookCollectedCount = 0,
  });

  final String id;
  final String name;
  final String? avatar;
  final int followersCount;
  final int followingCount;
  final int bookCollectedCount;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'];
    String? avatarUrl;
    if (avatar is Map) {
      avatarUrl = avatar['large'] as String? ?? avatar['normal'] as String?;
    } else if (avatar is String) {
      avatarUrl = avatar;
    }
    return UserProfile(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?) ?? '',
      avatar: avatarUrl,
      followersCount: (json['followers_count'] as num?)?.toInt() ??
          (json['display_followers_count'] as num?)?.toInt() ??
          0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      bookCollectedCount: (json['book_collected_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class Interest {
  const Interest({
    required this.subject,
    this.status = '',
    this.rating,
    this.comment = '',
    this.createTime = '',
  });

  final Subject subject;
  final String status; // done | doing | mark
  final Rating? rating;
  final String comment;
  final String createTime;

  factory Interest.fromJson(Map<String, dynamic> json) {
    final subjectJson = json['subject'];
    return Interest(
      subject: subjectJson is Map<String, dynamic>
          ? Subject.fromJson(subjectJson)
          : const Subject(id: '', type: 'movie', title: ''),
      status: (json['status'] as String?) ?? '',
      rating: Rating.tryParse(json['rating']),
      comment: (json['comment'] as String?) ?? '',
      createTime: (json['create_time'] as String?) ?? '',
    );
  }
}

class GroupTopic {
  const GroupTopic({
    required this.id,
    required this.title,
    this.authorName = '',
    this.commentsCount = 0,
    this.createTime = '',
    this.coverUrl,
  });

  final String id;
  final String title;
  final String authorName;
  final int commentsCount;
  final String createTime;
  final String? coverUrl;

  factory GroupTopic.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    String name = '';
    if (author is Map) name = (author['name'] as String?) ?? '';
    return GroupTopic(
      id: '${json['id'] ?? ''}',
      title: (json['title'] as String?) ?? '',
      authorName: name,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      createTime: (json['create_time'] as String?) ?? '',
      coverUrl: json['cover_url'] as String?,
    );
  }
}

class TopicComment {
  const TopicComment({
    required this.authorName,
    required this.text,
    this.voteCount = 0,
    this.createTime = '',
  });

  final String authorName;
  final String text;
  final int voteCount;
  final String createTime;

  factory TopicComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    String name = '';
    if (author is Map) name = (author['name'] as String?) ?? '';
    return TopicComment(
      authorName: name,
      text: (json['text'] as String?) ?? '',
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      createTime: (json['create_time'] as String?) ?? '',
    );
  }
}

/// Browse (书影音) filter definitions. Every (category, filter) pair below
/// was probed 2026-10-31 and is guest-usable; see DOUBAN_GUEST_API.md §10.
/// Categories: movie 电影, tv 剧集, book 图书, music 音乐.
class BrowseFilter {
  const BrowseFilter(this.id, this.label);

  final String id;
  final String label;
}

const browseCategoryLabels = <String, String>{
  'movie': '电影',
  'tv': '剧集',
  'book': '图书',
  'music': '音乐',
};

const browseFilters = <String, List<BrowseFilter>>{
  'movie': [
    BrowseFilter('showing', '正在热映'),
    BrowseFilter('soon', '即将上映'),
    BrowseFilter('recent', '近期热门'),
    BrowseFilter('top250', 'Top250'),
    BrowseFilter('recommend', '推荐'),
  ],
  'tv': [
    BrowseFilter('recent', '近期热门'),
    BrowseFilter('hot', '热门剧集'),
    BrowseFilter('recommend', '推荐'),
  ],
  'book': [
    BrowseFilter('hot', '热门图书'),
    BrowseFilter('bestseller', '畅销榜'),
    BrowseFilter('top250', 'Top250'),
  ],
  'music': [
    BrowseFilter('hot', '热门音乐'),
  ],
};

class BrowseResult {
  const BrowseResult({this.items = const [], this.total = 0});

  final List<Subject> items;
  final int total;
}

/// One home (发现) recommendation section. `category` + `filter` are the
/// BrowsePage selection that its "更多" button opens.
class HomeSection {
  const HomeSection({
    required this.title,
    required this.items,
    required this.category,
    required this.filter,
  });

  final String title;
  final List<Subject> items;
  final String category;
  final String filter;
}

class TopicListResult {
  const TopicListResult({this.items = const [], this.total = 0});

  final List<GroupTopic> items;
  final int total;
}

/// Group topic sorts verified 2026-10-31 for group 146409:
/// new = 最新 (total 2,443,291), hot = 热门 (total capped at 10,000).
/// popular/default return 0 items and are NOT used.
const groupTopicSorts = <String, String>{'new': '最新', 'hot': '热门'};

class TopicDetail {
  const TopicDetail({
    required this.topic,
    this.content = '',
    this.comments = const [],
  });

  final GroupTopic topic;
  final String content;
  final List<TopicComment> comments;
}
