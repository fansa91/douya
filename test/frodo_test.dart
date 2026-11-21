import 'dart:convert';
import 'dart:io';

import 'package:douya/api/douban_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frodo parse tests: the response parsers run against real
/// responses saved in test/fixtures (trimmed to the fields the
/// parsers read).
void main() {
  Map<String, dynamic> fixture(String name) {
    final text = File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  group('parseRatingStats', () {
    test('parses the five-tier distribution from the real response (movie 1292052)', () {
      final stats = RealDoubanRepository.parseRatingStats(
        fixture('rating_stats_1292052.json'),
      );
      expect(stats.stats.length, 5);
      // 1-to-5-star order; the 5-star share dominates for a 9.7 film.
      expect(stats.stats[4], closeTo(0.8538, 0.001));
      expect(stats.stats.reduce((a, b) => a + b), closeTo(1.0, 0.0001));
      expect(stats.doneCount, 5792775);
      expect(stats.wishCount, 522653);
      expect(stats.typeRanks.length, 2);
      expect(stats.typeRanks[0].type, '犯罪片');
      expect(stats.typeRanks[0].rank, closeTo(0.99, 0.001));
    });

    test('a missing or misshaped response yields empty stats, never a throw', () {
      expect(RealDoubanRepository.parseRatingStats({}).stats, isEmpty);
      expect(RealDoubanRepository.parseRatingStats('nope').doneCount, 0);
    });
  });

  group('parseAwards', () {
    test('parses ceremonies with categories from the real response (movie 1291546)', () {
      final result = RealDoubanRepository.parseAwards(
        fixture('awards_1291546.json'),
      );
      expect(result.total, 15);
      expect(result.awards.length, 2);
      expect(result.awards[0].ceremonyTitle, '第66届奥斯卡金像奖');
      expect(result.awards[0].ceremonyNumber, 66);
      expect(result.awards[0].categories[0].title, '最佳外语片');
      expect(result.awards[0].categories[0].isWon, isFalse);
      expect(result.awards[0].categories[0].celebrityNames, ['陈凯歌']);
      expect(result.awards[1].categories[0].title, '主竞赛单元 金棕榈奖');
      expect(result.awards[1].categories[0].isWon, isTrue);
    });

    test('a missing or misshaped response yields an empty result, never a throw', () {
      expect(RealDoubanRepository.parseAwards({}).awards, isEmpty);
      expect(RealDoubanRepository.parseAwards('nope').total, 0);
    });
  });

  group('parseCelebrityPhotos', () {
    test('parses photos with image urls from the real response (celebrity 1054521)', () {
      final result = RealDoubanRepository.parseCelebrityPhotos(
        fixture('celebrity_photos_1054521.json'),
      );
      expect(result.total, 120);
      expect(result.photos.length, 2);
      expect(result.photos[0].imageUrl, contains('doubanio.com'));
      expect(result.photos[0].authorName, isNotEmpty);
    });

    test('a missing or misshaped response yields an empty result, never a throw', () {
      expect(RealDoubanRepository.parseCelebrityPhotos({}).photos, isEmpty);
      expect(RealDoubanRepository.parseCelebrityPhotos('nope').total, 0);
    });
  });
}
