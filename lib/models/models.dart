/// Shared models for douya. All parsers are tolerant: Frodo and Rexxar
/// use different field names for the same idea (pic vs cover vs images),
/// and some fields are absent on some types.
library;

/// Extract a URL from a value that may be a plain string or a size
/// object {url, width, height, size}. The photos endpoint (and later
/// feed pages) return image.large / image.normal as size objects,
/// not strings (verified live 2026-10-31); a blind `as String?` cast
/// on them throws and kills the whole feed/detail page.
String? imageUrlOf(dynamic value) {
  if (value is String) return value;
  if (value is Map) {
    final url = value['url'];
    if (url is String) return url;
  }
  return null;
}

/// Strip an HTML body to plain text. Topic detail content arrives
/// as HTML (`<div id='content'><p ...>...</p></div>`, sometimes with
/// image wrappers); shown raw it leaks literal tags into the page
/// (reported 2026-10-31). Long-review content uses the same shape.
/// Image URLs embedded in an HTML body (`<img src="...">`). Topic
/// detail content carries its pictures this way as well as in the
/// structured `photos` array (verified live 2026-10-31: the two
/// carry the same images, so the page prefers `photos` and only
/// falls back to these when the array is empty).
List<String> htmlImageUrls(String raw) {
  final matches = RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false).allMatches(raw);
  return matches.map((m) => m.group(1)!).where((url) => url.isNotEmpty).toList();
}

String htmlToPlainText(String raw) {
  return raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// One run inside a paragraph block: plain text, or a link
/// (<a href>) whose text stays tappable.
class TextRun {
  const TextRun(this.text, {this.link});

  final String text;
  final String? link;
}

/// One piece of a topic/review body, in original order: a
/// paragraph (with link runs) or an image. No new dependency: a
/// small hand-written parser over the <p> / <img> / <a> tags the
/// API actually emits.
class ContentBlock {
  const ContentBlock.paragraph(this.runs) : imageUrl = null;
  const ContentBlock.image(this.imageUrl) : runs = const [];

  final List<TextRun> runs;
  final String? imageUrl;

  bool get isImage => imageUrl != null;
}

/// Split an HTML body into paragraph/image blocks, keeping the
/// original order. Images nested inside a <p> are lifted out as
/// their own blocks; bare text between blocks becomes a paragraph.
/// Empty blocks are dropped.
List<ContentBlock> parseContentBlocks(String html) {
  final blocks = <ContentBlock>[];
  final tokenRe = RegExp(
    r'''<p[^>]*>(.*?)</p>|<img[^>]+src=["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
    dotAll: true,
  );
  var pos = 0;
  for (final m in tokenRe.allMatches(html)) {
    if (m.start > pos) _addTextBlock(blocks, html.substring(pos, m.start));
    final paragraph = m.group(1);
    if (paragraph != null) {
      _addParagraph(blocks, paragraph);
    } else {
      final src = m.group(2);
      if (src != null && src.isNotEmpty) blocks.add(ContentBlock.image(src));
    }
    pos = m.end;
  }
  if (pos < html.length) _addTextBlock(blocks, html.substring(pos));
  return blocks;
}

void _addTextBlock(List<ContentBlock> blocks, String html) {
  final text = htmlToPlainText(html);
  if (text.isNotEmpty) blocks.add(ContentBlock.paragraph([TextRun(text)]));
}

/// A <p> body: split on nested <img> tags (each becomes an image
/// block), the rest becomes link-run paragraphs.
void _addParagraph(List<ContentBlock> blocks, String html) {
  final imgRe = RegExp(r'''<img[^>]+src=["']([^"']+)["'][^>]*>''', caseSensitive: false);
  var pos = 0;
  for (final m in imgRe.allMatches(html)) {
    if (m.start > pos) {
      final runs = _parseRuns(html.substring(pos, m.start));
      if (runs.isNotEmpty) blocks.add(ContentBlock.paragraph(runs));
    }
    final src = m.group(1);
    if (src != null && src.isNotEmpty) blocks.add(ContentBlock.image(src));
    pos = m.end;
  }
  if (pos < html.length) {
    final runs = _parseRuns(html.substring(pos));
    if (runs.isNotEmpty) blocks.add(ContentBlock.paragraph(runs));
  }
}

/// Split a paragraph's inner HTML into text/link runs.
List<TextRun> _parseRuns(String html) {
  final runs = <TextRun>[];
  final linkRe = RegExp(r'''<a[^>]+href=["']([^"']+)["']>(.*?)</a>''', caseSensitive: false, dotAll: true);
  var pos = 0;
  for (final m in linkRe.allMatches(html)) {
    if (m.start > pos) {
      final text = htmlToPlainText(html.substring(pos, m.start));
      if (text.isNotEmpty) runs.add(TextRun(text));
    }
    final text = htmlToPlainText(m.group(2) ?? '');
    final href = m.group(1);
    if (text.isNotEmpty) runs.add(TextRun(text, link: href));
    pos = m.end;
  }
  if (pos < html.length) {
    final text = htmlToPlainText(html.substring(pos));
    if (text.isNotEmpty) runs.add(TextRun(text));
  }
  return runs;
}

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

/// Image quality (c001apk's 自动 / 原图 / 缩略图). Applied to
/// posters and photo grids; the image preview page always shows the
/// large URL it was opened with, regardless of this setting.
enum ImageQuality {
  auto('自动'),
  origin('原图'),
  thumbnail('缩略图');

  const ImageQuality(this.label);

  final String label;
}

/// Resolve which URL a subject poster uses under [quality]:
/// auto = the parsed best URL (large first, as before),
/// origin = the large URL, thumbnail = the normal URL, each
/// falling back to the parsed URL when that size is absent.
String? subjectImageUrl(Subject subject, ImageQuality quality) {
  return switch (quality) {
    ImageQuality.origin => subject.picLarge ?? subject.pic,
    ImageQuality.thumbnail => subject.picSmall ?? subject.pic,
    ImageQuality.auto => subject.pic,
  };
}

/// Same resolution for a photo grid item.
String? photoImageUrl(Photo photo, ImageQuality quality) {
  return switch (quality) {
    ImageQuality.origin => photo.urlLarge ?? photo.url,
    ImageQuality.thumbnail => photo.urlSmall ?? photo.url,
    ImageQuality.auto => photo.url,
  };
}

class Subject {
  const Subject({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.pic,
    this.picLarge,
    this.picSmall,
    this.rating,
    this.year,
    this.cardSubtitle,
    this.isDoulist = false,
    this.doulistCount,
    this.rank,
  });

  final String id;
  final String type; // movie | tv | book | music | game
  final String title;
  final String? originalTitle;
  final String? pic;
  final String? picLarge;
  final String? picSmall;
  final Rating? rating;
  final String? year;
  final String? cardSubtitle;
  final bool isDoulist;
  final int? doulistCount;

  /// Position inside a ranking board, from the collection item's
  /// `rank` (fallback `rank_value`); null for non-ranking lists.
  final int? rank;

  factory Subject.fromJson(Map<String, dynamic> json, {String fallbackType = 'movie'}) {
    String? pic;
    final rawPic = json['pic'];
    if (rawPic is Map) {
      pic = imageUrlOf(rawPic['large']) ?? imageUrlOf(rawPic['normal']);
    } else if (rawPic is String) {
      pic = rawPic;
    }
    final rawCover = json['cover'];
    if (pic == null && rawCover is Map) {
      pic = imageUrlOf(rawCover['large']) ?? imageUrlOf(rawCover['normal']);
    }
    pic ??= json['cover_url'] as String? ?? (rawCover is String ? rawCover : null);
    final images = json['images'];
    if (pic == null && images is Map) {
      pic = images['large'] as String?;
    }
    String? picLarge;
    String? picSmall;
    if (rawPic is Map) {
      picLarge = rawPic['large'] as String?;
      picSmall = rawPic['normal'] as String?;
    }
    if (rawCover is Map) {
      picLarge ??= rawCover['large'] as String?;
      picSmall ??= rawCover['normal'] as String?;
    }
    if (images is Map) {
      picLarge ??= images['large'] as String?;
    }
    picLarge ??= json['cover_url'] as String? ?? (rawCover is String ? rawCover : null);
    final itemType = json['item_type'] as String? ?? json['type'] as String?;
    return Subject(
      id: '${json['id'] ?? ''}',
      type: itemType ?? fallbackType,
      title: (json['title'] as String?) ?? '',
      originalTitle: json['original_title'] as String?,
      pic: pic,
      picLarge: picLarge,
      picSmall: picSmall,
      rating: Rating.tryParse(json['rating']),
      year: json['year'] as String?,
      cardSubtitle: json['card_subtitle'] as String?,
      isDoulist: (json['doulist_type'] as String?) != null || itemType == 'doulist',
      doulistCount: (json['items_count'] as num?)?.toInt(),
      rank: (json['rank'] as num?)?.toInt() ?? (json['rank_value'] as num?)?.toInt(),
    );
  }
}

/// One ranking board from Rexxar
/// /tag/{tagId}/subject_collection_boards: the `subject_collection`
/// object inside each board entry. Tag ids verified 2026-10-31:
/// 49 = 影视 (30 boards), 2 = 音乐 (27), 3 = 图书 (18), 42 = 游戏 (2).
class RankBoard {
  const RankBoard({
    required this.id,
    required this.name,
    this.description = '',
    this.subjectCount = 0,
    this.showRank = false,
    this.previewSubjects = const [],
  });

  final String id;
  final String name;
  final String description;
  final int subjectCount;
  final bool showRank;

  /// Preview subjects embedded in the boards index response (3 per
  /// board). The numeric boards' full items endpoint 404s on both
  /// Rexxar and Frodo (verified 2026-10-31), so the board detail
  /// page falls back to these when its items call fails.
  final List<Subject> previewSubjects;

  factory RankBoard.fromJson(Map<String, dynamic> json) {
    return RankBoard(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      subjectCount: (json['subject_count'] as num?)?.toInt() ?? 0,
      showRank: json['show_rank'] as bool? ?? false,
    );
  }
}

/// Ranking board categories shown on the rankings page.
const rankBoardCategories = <String, String>{
  '49': '影视',
  '2': '音乐',
  '3': '图书',
  '42': '游戏',
};

/// The unit for a board's subject count, by the same tag id.
const rankBoardUnits = <String, String>{'49': '部', '2': '张', '3': '本', '42': '款'};

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
    this.commentsTotal = 0,
    this.reviewsTotal = 0,
    this.photosTotal = 0,
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

  /// Totals for the paged comment/review tabs. fetchSubject still
  /// loads only the first 10 of each; the tabs page from there.
  final int commentsTotal;
  final int reviewsTotal;

  /// Total for the paged photo grid (e.g. 942 for movie 1292052).
  /// Unlike comments/reviews, photos page with start/count.
  final int photosTotal;

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
    this.largeAvatar,
    this.memberCount = 0,
    this.description = '',
  });

  final String id;
  final String name;
  final String? avatar;

  /// Medium avatar from the group detail response (`large_avatar`);
  /// the detail-page header prefers this over the small `avatar`.
  final String? largeAvatar;
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
      avatar = imageUrlOf(rawAvatar['large']) ?? imageUrlOf(rawAvatar['normal']);
    }
    return SearchGroup(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?) ?? '',
      avatar: avatar,
      largeAvatar: json['large_avatar'] as String?,
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
    this.userAvatar,
  });

  final String userName;
  final String text;
  final Rating? rating;
  final int voteCount;
  final String createTime;

  /// Commenter's avatar (plain URL string in the interests payload).
  final String? userAvatar;

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
      userAvatar: authorAvatarOf(user),
    );
  }
}

/// Paged short comments (interests) and long reviews. Totals come
/// from the API; stop paging when items.length reaches total.
class CommentListResult {
  const CommentListResult({this.items = const [], this.total = 0});

  final List<ShortComment> items;
  final int total;
}

class ReviewListResult {
  const ReviewListResult({this.items = const [], this.total = 0});

  final List<Review> items;
  final int total;
}

/// Long review full text. The API returns HTML
/// (<div><p>…</p><strong>…</strong></p>), so fromJson converts it to
/// plain text (paragraph breaks kept) before the UI ever sees it.
class ReviewDetail {
  const ReviewDetail({
    required this.id,
    required this.title,
    this.userName = '',
    this.content = '',
    this.usefulCount = 0,
    this.commentsCount = 0,
    this.createTime = '',
  });

  final String id;
  final String title;
  final String userName;
  final String content;
  final int usefulCount;
  final int commentsCount;
  final String createTime;

  factory ReviewDetail.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String name = '';
    if (user is Map) name = (user['name'] as String?) ?? '';
    final plain = htmlToPlainText((json['content'] as String?) ?? '');
    return ReviewDetail(
      id: '${json['id'] ?? ''}',
      title: (json['title'] as String?) ?? '',
      userName: name,
      content: plain,
      usefulCount: (json['useful_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
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
  const Photo({required this.id, this.url, this.urlLarge, this.urlSmall, this.description = '', this.width, this.height});

  final String id;
  final String? url;
  final String? urlLarge;
  final String? urlSmall;
  final String description;

  /// Pixel size from the image size object ({url, width, height}),
  /// when the payload carries one. The feed card uses it for the
  /// natural aspect ratio; null means the size is unknown and the
  /// card falls back to 4:3.
  final int? width;
  final int? height;

  factory Photo.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    String? url;
    String? urlLarge;
    String? urlSmall;
    int? width;
    int? height;
    if (image is Map) {
      urlLarge = imageUrlOf(image['large']);
      urlSmall = imageUrlOf(image['normal']);
      url = urlLarge ?? urlSmall;
      final size = image['large'] is Map ? image['large'] : image['normal'];
      if (size is Map) {
        width = (size['width'] as num?)?.toInt();
        height = (size['height'] as num?)?.toInt();
      }
    } else if (image is String) {
      url = image;
    }
    url ??= imageUrlOf(json['url']);
    return Photo(
      id: '${json['id'] ?? ''}',
      url: url,
      urlLarge: urlLarge,
      urlSmall: urlSmall,
      description: (json['description'] as String?) ?? '',
      width: width,
      height: height,
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
    this.latinTitle,
    this.shortInfo,
    this.info = const [],
    this.followedCount = 0,
  });

  final String id;
  final String name;
  final String? avatar;
  final String? character;
  final List<String> roles;

  /// English name (latin_title), e.g. "Tim Robbins".
  final String? latinTitle;

  /// Short line from extra.short_info: professions + notable works.
  final String? shortInfo;

  /// Bio key/value pairs from extra.info: [[label, value], ...]
  /// (gender, birthday, birthplace, ...).
  final List<(String, String)> info;

  /// followed_count.
  final int followedCount;

  factory Celebrity.fromJson(Map<String, dynamic> json) {
    // The celebrities endpoint returns {large, normal} maps; other
    // celebrity payloads carry a plain URL string. Both are valid.
    final avatar = json['avatar'];
    String? avatarUrl;
    if (avatar is String) {
      avatarUrl = avatar;
    } else if (avatar is Map) {
      avatarUrl = imageUrlOf(avatar['large']) ?? imageUrlOf(avatar['normal']);
    }
    return Celebrity(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?) ?? '',
      avatar: avatarUrl,
      character: json['character'] as String?,
      roles: ((json['roles'] as List?) ?? []).map((e) => '$e').toList(),
    );
  }

  /// Parse a /celebrity/{id} detail response (probed 2026-11-21).
  /// The detail carries no flat gender/birthday fields: the bio
  /// lives in extra.info as [label, value] pairs, the photo in
  /// cover ({large, normal}) or cover_img ({url}).
  factory Celebrity.fromDetailJson(Map<String, dynamic> json) {
    String? avatarUrl;
    final cover = json['cover'];
    if (cover is Map) {
      avatarUrl = imageUrlOf(cover['large']) ?? imageUrlOf(cover['normal']);
    }
    final coverImg = json['cover_img'];
    if (avatarUrl == null && coverImg is Map) {
      avatarUrl = imageUrlOf(coverImg['url']);
    }
    String? shortInfo;
    final info = <(String, String)>[];
    final extra = json['extra'];
    if (extra is Map) {
      shortInfo = extra['short_info'] as String?;
      final rawInfo = extra['info'];
      if (rawInfo is List) {
        for (final pair in rawInfo) {
          if (pair is List && pair.length >= 2) {
            info.add(('${pair[0]}', '${pair[1]}'));
          }
        }
      }
    }
    return Celebrity(
      id: '${json['id'] ?? ''}',
      name: (json['title'] as String?) ?? '',
      avatar: avatarUrl,
      latinTitle: json['latin_title'] as String?,
      shortInfo: shortInfo,
      info: info,
      followedCount: (json['followed_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One entry of /celebrity/{id}/works: the entry is NOT a flat
/// subject — it is {roles, work}, where work is the subject and
/// roles names the celebrity's part in it (probed 2026-11-21).
/// The old parser read the wrapper as a Subject, so id/title were
/// empty and the works list was blank on real data.
class CelebrityWork {
  const CelebrityWork({required this.subject, this.roles = const []});

  final Subject subject;
  final List<String> roles;

  factory CelebrityWork.fromJson(Map<String, dynamic> json) {
    final work = json['work'];
    return CelebrityWork(
      subject: work is Map ? Subject.fromJson(work.cast<String, dynamic>()) : const Subject(id: '', type: '', title: ''),
      roles: ((json['roles'] as List?) ?? []).map((e) => '$e').toList(),
    );
  }
}

class CelebrityWorksResult {
  const CelebrityWorksResult({this.works = const [], this.total = 0});

  final List<CelebrityWork> works;
  final int total;
}

class CelebrityDetail {
  const CelebrityDetail({
    required this.celebrity,
    this.works = const [],
    this.worksTotal = 0,
  });

  final Celebrity celebrity;
  final List<CelebrityWork> works;

  /// Total for the paged works list (113 for Tim Robbins).
  final int worksTotal;
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
      avatarUrl = imageUrlOf(avatar['large']) ?? imageUrlOf(avatar['normal']);
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

/// Author avatar from a detail/comment payload's `author` object:
/// a plain URL string, or a {large, normal} map (the feed uses the
/// map form). Null when the payload carries none — the UI then
/// shows the fallback person icon instead of an empty circle.
String? authorAvatarOf(dynamic author) {
  if (author is! Map) return null;
  final avatar = author['avatar'];
  if (avatar is String) return avatar;
  if (avatar is Map) return imageUrlOf(avatar['large']) ?? imageUrlOf(avatar['normal']);
  return null;
}

class GroupTopic {
  const GroupTopic({
    required this.id,
    required this.title,
    this.authorName = '',
    this.authorAvatar,
    this.commentsCount = 0,
    this.createTime = '',
    this.coverUrl,
    this.authorId = '',
  });

  final String id;
  final String title;
  final String authorName;
  final String? authorAvatar;
  final int commentsCount;
  final String createTime;
  final String? coverUrl;

  /// Author id (author.id), for "只看楼主" and opening the author's
  /// page from a detail. The old model only kept the name.
  final String authorId;

  factory GroupTopic.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    String name = '';
    String authorId = '';
    if (author is Map) {
      name = (author['name'] as String?) ?? '';
      authorId = '${author['id'] ?? ''}';
    }
    return GroupTopic(
      id: '${json['id'] ?? ''}',
      title: (json['title'] as String?) ?? '',
      authorName: name,
      authorAvatar: authorAvatarOf(author),
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      createTime: (json['create_time'] as String?) ?? '',
      coverUrl: json['cover_url'] as String?,
      authorId: authorId,
    );
  }
}

class TopicComment {
  const TopicComment({
    required this.authorName,
    required this.text,
    this.voteCount = 0,
    this.createTime = '',
    this.authorAvatar,
    this.authorId = '',
    this.ipLocation,
    this.refComment,
  });

  final String authorName;
  final String text;
  final int voteCount;
  final String createTime;
  final String? authorAvatar;

  /// Author id (author.id), for "只看楼主" and opening the author's
  /// page. The old model only kept the name.
  final String authorId;

  /// IP 属地 (ip_location, a plain string, verified guest-visible
  /// 2026-11-21). Null when the API omits it; never inferred from
  /// author.loc, which is the user's home location, not the IP.
  final String? ipLocation;

  /// The quoted reply (ref_comment), one level only: a reply quotes
  /// the comment it answers. Null for top-level comments.
  final TopicComment? refComment;

  factory TopicComment.fromJson(Map<String, dynamic> json, {bool includeRef = true}) {
    final author = json['author'];
    String name = '';
    String authorId = '';
    if (author is Map) {
      name = (author['name'] as String?) ?? '';
      authorId = '${author['id'] ?? ''}';
    }
    final ip = json['ip_location'];
    final ref = json['ref_comment'];
    return TopicComment(
      authorName: name,
      text: (json['text'] as String?) ?? '',
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      createTime: (json['create_time'] as String?) ?? '',
      authorAvatar: authorAvatarOf(author),
      authorId: authorId,
      ipLocation: ip is String && ip.isNotEmpty ? ip : null,
      refComment: includeRef && ref is Map<String, dynamic>
          ? TopicComment.fromJson(ref, includeRef: false)
          : null,
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
  'recommend': '推荐',
  'movie': '电影',
  'tv': '剧集',
  'book': '图书',
  'music': '音乐',
  'show': '综艺',
};

const browseFilters = <String, List<BrowseFilter>>{
  // The 推荐 category has no filters: it renders the recommendation
  // sections view (BrowsePage special-cases it, never calls
  // fetchBrowse for it), so this list is deliberately empty.
  'recommend': [],
  'movie': [
    BrowseFilter('showing', '正在热映'),
    BrowseFilter('soon', '即将上映'),
    BrowseFilter('recent', '近期热门'),
    BrowseFilter('top250', 'Top250'),
    BrowseFilter('recommend', '精选'),
    BrowseFilter('hot_gaia', '豆瓣热门'),
    BrowseFilter('filter', '多维筛选'),
  ],
  'tv': [
    BrowseFilter('recent', '近期热门'),
    BrowseFilter('hot', '热门剧集'),
    BrowseFilter('recommend', '精选'),
    BrowseFilter('filter', '多维筛选'),
  ],
  'book': [
    BrowseFilter('hot', '热门图书'),
    BrowseFilter('bestseller', '畅销榜'),
    BrowseFilter('top250', 'Top250'),
  ],
  'music': [
    BrowseFilter('hot', '热门音乐'),
  ],
  'show': [
    BrowseFilter('hot', '热门综艺'),
    BrowseFilter('domestic', '国内综艺'),
    BrowseFilter('foreign', '国外综艺'),
  ],
};

class BrowseResult {
  const BrowseResult({this.items = const [], this.total = 0});

  final List<Subject> items;
  final int total;
}

/// One filter dimension from a tag-search response: `type` is the
/// group name (形式 / 地区 / 类型 / 年代 / 特色) and `values` are its
/// selectable values, the first usually being 全部… (meaning "no
/// selection", not a value to send). Only 地区 / 类型 / 年代 / 特色
/// values are tags that may go into q; 形式 values are NOT tags
/// (sending one, e.g. 电视剧, returns 0 items) and are never offered
/// as choices in the faceted UI.
class TagGroup {
  const TagGroup({required this.type, required this.values});

  final String type;
  final List<String> values;

  factory TagGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    return TagGroup(
      type: (json['type'] as String?) ?? '',
      values: raw is List ? raw.whereType<String>().toList() : const [],
    );
  }
}

class TagSort {
  const TagSort({required this.name, required this.text});

  /// U = 默认, T = 热度, S = 评分, R = 时间 (verified 2026-10-31:
  /// sort changes the first items and, for R, the total).
  final String name;
  final String text;

  factory TagSort.fromJson(Map<String, dynamic> json) {
    return TagSort(
      name: (json['name'] as String?) ?? 'U',
      text: (json['text'] as String?) ?? '',
    );
  }
}

/// Result of a faceted tag search: paged subjects plus the filter
/// dimensions and sort options that came with the response.
class TagSearchResult {
  const TagSearchResult({
    this.items = const [],
    this.total = 0,
    this.groups = const [],
    this.sorts = const [],
  });

  final List<Subject> items;
  final int total;
  final List<TagGroup> groups;
  final List<TagSort> sorts;
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

class PhotoListResult {
  const PhotoListResult({this.items = const [], this.total = 0});

  final List<Photo> items;
  final int total;
}

/// One home recommend-feed card. Feed items are posts (mostly
/// topic, sometimes review), not subjects: the readable payload
/// lives in content (abstract/title/author/photos), the author
/// also appears as the top-level owner, and the item id is the
/// post id (topic items: content.id == item.id == group topic id,
/// verified 2026-10-31 from the content uri).
class FeedItem {
  const FeedItem({
    required this.id,
    required this.type,
    this.typeCn = '',
    this.title = '',
    this.abstract = '',
    this.authorName = '',
    this.authorAvatar,
    this.photos = const [],
    this.commentsCount = 0,
    this.reactionsCount = 0,
    this.resharesCount = 0,
    this.createdTime = '',
    this.sharingUrl = '',
  });

  final String id;
  final String type;
  final String typeCn;
  final String title;
  final String abstract;
  final String authorName;
  final String? authorAvatar;

  /// Attached pictures as Photo objects (with pixel size when the
  /// payload carries it, for the card's natural aspect ratio).
  final List<Photo> photos;

  /// Plain URLs, for callers that only need the images (preview
  /// page, tests). Derived from `photos`.
  List<String> get photoUrls => photos.map((p) => p.url).whereType<String>().toList();

  final int commentsCount;
  final int reactionsCount;
  final int resharesCount;
  final String createdTime;
  final String sharingUrl;

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    final content = json['content'] is Map<String, dynamic>
        ? json['content'] as Map<String, dynamic>
        : <String, dynamic>{};
    final author = content['author'] is Map<String, dynamic>
        ? content['author'] as Map<String, dynamic>
        : (json['owner'] is Map<String, dynamic> ? json['owner'] as Map<String, dynamic> : null);
    String? authorAvatar;
    final avatar = author?['avatar'];
    if (avatar is String) {
      authorAvatar = avatar;
    } else if (avatar is Map<String, dynamic>) {
      authorAvatar = imageUrlOf(avatar['large']) ?? imageUrlOf(avatar['normal']);
    }
    final photos = <Photo>[];
    if (content['photos'] is List) {
      for (final p in content['photos'] as List) {
        if (p is Map<String, dynamic>) {
          final photo = Photo.fromJson(p);
          if (photo.url != null) photos.add(photo);
        }
      }
    }
    return FeedItem(
      id: '${json['id'] ?? content['id'] ?? ''}',
      type: '${json['type'] ?? content['type'] ?? ''}',
      typeCn: '${json['type_cn'] ?? ''}',
      title: '${content['title'] ?? ''}',
      abstract: '${content['abstract'] ?? ''}',
      authorName: '${author?['name'] ?? ''}',
      authorAvatar: authorAvatar,
      photos: photos,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      reactionsCount: (json['reactions_count'] as num?)?.toInt() ?? 0,
      resharesCount: (json['reshares_count'] as num?)?.toInt() ?? 0,
      createdTime: json['created_time'] is String ? json['created_time'] as String : '',
      sharingUrl: json['sharing_url'] is String ? json['sharing_url'] as String : '',
    );
  }
}

/// Paged recommend-feed result. The feed response carries no
/// total (its count field is just the page size), so hasMore is
/// "this page came back full" and paging stops on a short page.
class FeedResult {
  const FeedResult({this.items = const [], this.hasMore = false});

  final List<FeedItem> items;
  final bool hasMore;
}

/// Group topic sorts verified 2026-10-31 for group 146409:
/// new = 最新 (total 2,443,291), hot = 热门 (total capped at 10,000).
/// popular/default return 0 items and are NOT used.
const groupTopicSorts = <String, String>{'new': '最新', 'hot': '热门'};

class TopicDetail {
  const TopicDetail({
    required this.topic,
    this.content = '',
    this.contentHtml = '',
    this.comments = const [],
    this.commentsTotal = 0,
    this.popularComments = const [],
    this.groupId = '',
    this.groupName = '',
    this.sharingUrl = '',
    this.ipLocation,
    this.photos = const [],
    this.videoUrl,
    this.videoCoverUrl,
    this.videoDuration,
  });

  final GroupTopic topic;
  final String content;

  /// The raw HTML body, for the block parser (paragraphs and
  /// images in original order). `content` is the plain-text
  /// fallback when the HTML is empty.
  final String contentHtml;

  final List<TopicComment> comments;

  /// The comments endpoint's `popular_comments` (hot replies),
  /// from the first page. Empty in every topic probed 2026-11-21,
  /// so the page falls back to the most-liked loaded replies.
  final List<TopicComment> popularComments;

  /// The topic's share link, for copy / open-in-browser.
  final String sharingUrl;

  /// The topic's own IP 属地 (top-level `ip_location`, a plain
  /// string, verified guest-visible 2026-11-21). Null when the
  /// API omits it; shown in the author row when present.
  final String? ipLocation;

  /// The comments endpoint's `total` (== topic.commentsCount when
  /// the topic is fresh). The footer uses it to decide whether
  /// more pages exist; the header falls back to commentsCount.
  final int commentsTotal;

  /// Attached pictures, from the detail response's `photos` array
  /// (Photo-shaped, image.large/normal as size objects). When the
  /// array is empty, fetchTopic falls back to the `<img>` URLs
  /// embedded in the HTML content.
  final List<Photo> photos;

  /// Video attached to the topic, from `video_info` (key names
  /// video_url / video_duration follow the app's own video widget).
  /// Null in every topic probed 2026-10-31, so the video entry only
  /// appears when a topic actually carries one.
  final String? videoUrl;
  final String? videoCoverUrl;
  final String? videoDuration;

  /// The group this topic belongs to, from the detail response's
  /// `group` object (every topic payload carries one: verified in
  /// the APK's topic flow model and in a live detail sample,
  /// 2026-10-31). Empty when the response carries none, and the
  /// detail page then hides the group row instead of showing a
  /// blank one.
  final String groupId;
  final String groupName;
}
