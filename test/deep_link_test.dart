import 'dart:convert';
import 'dart:io';

import 'package:douya/api/deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deep-link parser tests. The fixture cases use the real URIs from
/// test/fixtures (hot search board, movie/tv landing, 2026-11-21);
/// the hand-written cases cover the subject shape and the unknowns.
void main() {
  test('parses every real URI in the fixtures', () {
    final board = jsonDecode(File('test/fixtures/hot_search_board.json').readAsStringSync()) as List;
    for (final item in board) {
      final link = parseDeepLink(item['uri'] as String);
      expect(link, isA<SearchLink>());
      expect((link as SearchLink).keyword, isNotEmpty);
    }
    for (final name in ['movie_landing.json', 'tv_landing.json']) {
      final landing = jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;
      for (final group in landing['tags'] as List) {
        final groupName = group['name'] as String;
        for (final item in group['items'] as List) {
          final link = parseDeepLink(item['uri'] as String, groupType: groupName);
          if (groupName == '专题') {
            expect(link, isA<BoardLink>());
            expect((link as BoardLink).boardId, isNotEmpty);
          } else {
            expect(link, isA<TagSearchLink>());
            final tag = link as TagSearchLink;
            expect(tag.query, isNotEmpty);
            // The form suffix is stripped: it is not a tag.
            expect(tag.query, isNot(contains('电影')));
            expect(tag.query, isNot(contains('电视剧')));
            expect(tag.groupType, groupName);
          }
        }
      }
    }
  });

  test('strips the form suffix, or keeps a bare value', () {
    expect(parseDeepLink('douban://douban.com/subject/recommendation/movie?tag=喜剧,电影'),
        isA<TagSearchLink>());
    final withForm = parseDeepLink('douban://douban.com/subject/recommendation/movie?tag=喜剧,电影') as TagSearchLink;
    expect(withForm.endpoint, 'movie');
    expect(withForm.query, '喜剧');
    final bare = parseDeepLink('douban://douban.com/tv/tag?q=动漫') as TagSearchLink;
    expect(bare.endpoint, 'tv');
    expect(bare.query, '动漫');
    final region = parseDeepLink('douban://douban.com/tv/tag?q=中国大陆,电视剧') as TagSearchLink;
    expect(region.query, '中国大陆');
  });

  test('parses a subject deep link', () {
    final link = parseDeepLink('douban://douban.com/movie/1292052') as SubjectLink;
    expect(link.type, 'movie');
    expect(link.id, '1292052');
  });

  test('unknown shapes return UnknownLink', () {
    expect(parseDeepLink('douban://douban.com/subject/1292052'), isA<UnknownLink>());
    expect(parseDeepLink('https://movie.douban.com/subject/1292052'), isA<UnknownLink>());
    expect(parseDeepLink('douban://douban.com/search/result?q='), isA<UnknownLink>());
    expect(parseDeepLink('douban://douban.com/tv/tag?q=电视剧'), isA<UnknownLink>());
    expect(parseDeepLink('not a uri'), isA<UnknownLink>());
    expect(parseDeepLink(''), isA<UnknownLink>());
  });
}
