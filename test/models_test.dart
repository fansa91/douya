import 'package:douya/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure model-parsing tests: no network, no device, safe to run in
/// CI on every release build. Shapes mirror the probed API payloads
/// (see DOUBAN_GUEST_API.md); values are neutral samples, not real
/// user content.
void main() {
  group('Subject.fromJson', () {
    test('pic map wins, large/normal split into picLarge/picSmall', () {
      final subject = Subject.fromJson(<String, dynamic>{
        'id': '1292052',
        'type': 'movie',
        'title': '肖申克的救赎',
        'pic': <String, dynamic>{'large': 'https://img.example/l.jpg', 'normal': 'https://img.example/n.jpg'},
        'rating': <String, dynamic>{'value': 9.7, 'count': 3354509, 'max': 10},
      });
      expect(subject.id, '1292052');
      expect(subject.pic, 'https://img.example/l.jpg');
      expect(subject.picLarge, 'https://img.example/l.jpg');
      expect(subject.picSmall, 'https://img.example/n.jpg');
      expect(subject.rating?.value, 9.7);
      expect(subject.rating?.max, 10);
      expect(subject.rating?.count, 3354509);
    });

    test('string pic, cover fallback, and missing rating', () {
      final fromString = Subject.fromJson(<String, dynamic>{
        'id': '1',
        'type': 'movie',
        'title': 'A',
        'pic': 'https://img.example/p.jpg',
      });
      expect(fromString.pic, 'https://img.example/p.jpg');
      // A string pic has no separate large variant (origin quality
      // falls back to pic at the subjectImageUrl layer, not here).
      expect(fromString.picLarge, isNull);
      expect(fromString.rating, isNull);

      final fromCover = Subject.fromJson(<String, dynamic>{
        'id': '2',
        'title': 'B',
        'cover_url': 'https://img.example/c.jpg',
      });
      expect(fromCover.pic, 'https://img.example/c.jpg');
      // No explicit type: falls back to the caller's default.
      expect(fromCover.type, 'movie');
    });

    test('rank prefers rank over rank_value; doulist detection', () {
      final ranked = Subject.fromJson(<String, dynamic>{
        'id': '3',
        'title': 'C',
        'rank': 1,
        'rank_value': 2,
      });
      expect(ranked.rank, 1);

      final rankedValue = Subject.fromJson(<String, dynamic>{
        'id': '4',
        'title': 'D',
        'rank_value': 7,
      });
      expect(rankedValue.rank, 7);

      final doulist = Subject.fromJson(<String, dynamic>{
        'id': '5',
        'title': 'E',
        'doulist_type': 'chart',
        'items_count': 20,
      });
      expect(doulist.isDoulist, isTrue);
      expect(doulist.doulistCount, 20);
    });
  });

  group('FeedItem.fromJson', () {
    test('topic card: content author/photos, top-level counts', () {
      final item = FeedItem.fromJson(<String, dynamic>{
        'id': 503570060,
        'type': 'topic',
        'type_cn': '话题',
        'comments_count': 61,
        'reactions_count': 323,
        'reshares_count': 2,
        'created_time': null,
        'sharing_url': 'https://www.douban.com/group/topic/503570060',
        'content': <String, dynamic>{
          'id': 503570060,
          'title': '',
          'abstract': '帖子正文摘要',
          'author': <String, dynamic>{
            'name': '示例用户',
            'avatar': <String, dynamic>{
              'large': 'https://img.example/a-l.jpg',
              'normal': 'https://img.example/a-n.jpg',
            },
          },
          'photos': [
            <String, dynamic>{
              'id': '11',
              'image': <String, dynamic>{'large': 'https://img.example/p-l.jpg', 'normal': 'https://img.example/p-n.jpg'},
            },
          ],
        },
      });
      expect(item.id, '503570060');
      expect(item.title, isEmpty);
      expect(item.abstract, '帖子正文摘要');
      expect(item.authorName, '示例用户');
      expect(item.authorAvatar, 'https://img.example/a-l.jpg');
      expect(item.photoUrls, ['https://img.example/p-l.jpg']);
      expect(item.commentsCount, 61);
      expect(item.reactionsCount, 323);
      expect(item.resharesCount, 2);
      // Null created_time degrades to an empty string (card hides it).
      expect(item.createdTime, isEmpty);
    });

    test('author falls back to top-level owner', () {
      final item = FeedItem.fromJson(<String, dynamic>{
        'id': '9',
        'type': 'review',
        'owner': <String, dynamic>{'name': '所有者', 'avatar': 'https://img.example/o.jpg'},
        'content': <String, dynamic>{'abstract': '短评'},
      });
      expect(item.authorName, '所有者');
      expect(item.authorAvatar, 'https://img.example/o.jpg');
    });
  });

  group('topic avatars', () {
    test('GroupTopic parses string and map avatars, missing stays null', () {
      final fromString = GroupTopic.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'T',
        'author': <String, dynamic>{'name': '楼主', 'avatar': 'https://img.example/a.jpg'},
      });
      expect(fromString.authorAvatar, 'https://img.example/a.jpg');

      final fromMap = GroupTopic.fromJson(<String, dynamic>{
        'id': '2',
        'title': 'T',
        'author': <String, dynamic>{
          'name': '楼主',
          'avatar': <String, dynamic>{'large': 'https://img.example/a-l.jpg', 'normal': 'https://img.example/a-n.jpg'},
        },
      });
      expect(fromMap.authorAvatar, 'https://img.example/a-l.jpg');

      final missing = GroupTopic.fromJson(<String, dynamic>{
        'id': '3',
        'title': 'T',
        'author': <String, dynamic>{'name': '楼主'},
      });
      expect(missing.authorAvatar, isNull);
    });

    test('TopicComment parses the comment author avatar the same way', () {
      final comment = TopicComment.fromJson(<String, dynamic>{
        'text': '你好',
        'author': <String, dynamic>{'name': '路人', 'avatar': 'https://img.example/c.jpg'},
      });
      expect(comment.authorAvatar, 'https://img.example/c.jpg');
    });
  });

  group('other models', () {
    test('RankBoard reads the subject_collection object', () {
      final board = RankBoard.fromJson(<String, dynamic>{
        'id': 1818,
        'name': '6月豆瓣电影口碑榜Top20',
        'description': '月榜',
        'subject_count': 159,
        'show_rank': true,
      });
      expect(board.id, '1818');
      expect(board.subjectCount, 159);
      expect(board.showRank, isTrue);
    });

    test('Photo prefers large, falls back to normal then url', () {
      final fromImage = Photo.fromJson(<String, dynamic>{
        'id': '1',
        'image': <String, dynamic>{'large': 'https://img.example/l.jpg', 'normal': 'https://img.example/n.jpg'},
      });
      expect(fromImage.url, 'https://img.example/l.jpg');
      expect(fromImage.urlLarge, 'https://img.example/l.jpg');
      expect(fromImage.urlSmall, 'https://img.example/n.jpg');

      final fromUrl = Photo.fromJson(<String, dynamic>{'id': '2', 'url': 'https://img.example/u.jpg'});
      expect(fromUrl.url, 'https://img.example/u.jpg');
      expect(fromUrl.urlLarge, isNull);
    });

    test('ReviewDetail strips HTML to plain text', () {
      final review = ReviewDetail.fromJson(<String, dynamic>{
        'id': 1000369,
        'title': '长评标题',
        'user': <String, dynamic>{'name': '示例用户'},
        'content': "<div id='content'><p>第一段&nbsp;文字</p><p>第二段<strong>加粗</strong> &amp; 实体</p></div>",
        'useful_count': 18958,
        'comments_count': 1082,
      });
      expect(review.content, '第一段 文字\n\n第二段加粗 & 实体');
      expect(review.usefulCount, 18958);
      expect(review.commentsCount, 1082);
    });
  });
}
