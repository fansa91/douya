import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/local_lists.dart';

void main() {
  final lists = LocalLists.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await lists.init();
  });

  setUp(() async {
    // Reset to a known-empty state through the public API.
    for (final g in List.of(lists.favoriteGroups)) {
      await lists.toggleFavoriteGroup(id: g.id, name: g.name);
    }
    await lists.setMyUserId(null);
    await lists.clearRecentUsers();
  });

  test('starts empty when nothing is stored', () {
    expect(lists.favoriteGroups, isEmpty);
    expect(lists.myUserId, isNull);
    expect(lists.isBound, isFalse);
    expect(lists.recentUsers, isEmpty);
  });

  test('toggle favorite adds, then removes', () async {
    await lists.toggleFavoriteGroup(id: '146409', name: '上海租房');
    expect(lists.isFavoriteGroup('146409'), isTrue);
    expect(lists.favoriteGroups.first.name, '上海租房');
    await lists.toggleFavoriteGroup(id: '146409', name: '上海租房');
    expect(lists.isFavoriteGroup('146409'), isFalse);
    expect(lists.favoriteGroups, isEmpty);
  });

  test('favorites are newest-first and capped at 30', () async {
    for (var i = 0; i < 31; i++) {
      await lists.toggleFavoriteGroup(id: '$i', name: '小组 $i');
    }
    expect(lists.favoriteGroups.length, LocalLists.maxFavoriteGroups);
    expect(lists.favoriteGroups.first.id, '30');
    expect(lists.isFavoriteGroup('0'), isFalse);
  });

  test('binding a user id persists, blank clears', () async {
    await lists.setMyUserId('2870956');
    expect(lists.myUserId, '2870956');
    expect(lists.isBound, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('my_user_id'), '2870956');
    await lists.setMyUserId('  ');
    expect(lists.myUserId, isNull);
    expect(lists.isBound, isFalse);
    expect(prefs.getString('my_user_id'), isNull);
  });

  test('recent users dedup, newest-first, capped at 10', () async {
    await lists.addRecentUser(id: '1', name: 'A');
    await lists.addRecentUser(id: '2', name: 'B');
    await lists.addRecentUser(id: '1', name: 'A');
    expect(lists.recentUsers.map((u) => u.id).toList(), ['1', '2']);
    for (var i = 3; i <= 12; i++) {
      await lists.addRecentUser(id: '$i', name: 'U$i');
    }
    expect(lists.recentUsers.length, LocalLists.maxRecentUsers);
    expect(lists.recentUsers.first.id, '12');
    expect(lists.recentUsers.map((u) => u.id), isNot(contains('1')));
  });

  test('init reloads persisted JSON, and bad JSON becomes empty',
      () async {
    await lists.toggleFavoriteGroup(id: '146409', name: '上海租房');
    await lists.setMyUserId('2870956');
    await lists.addRecentUser(id: '2', name: 'B');
    await lists.init();
    expect(lists.isFavoriteGroup('146409'), isTrue);
    expect(lists.myUserId, '2870956');
    expect(lists.recentUsers.map((u) => u.id).toList(), ['2']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('favorite_groups', 'not-json');
    await lists.init();
    expect(lists.favoriteGroups, isEmpty);
  });
}
