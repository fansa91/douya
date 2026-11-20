import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A locally saved group (id / name / avatar) for the "已收藏" tab.
/// Guest mode has no login and the joined-groups endpoint returns
/// 403 for guests, so favorites are stored on the device instead.
class FavoriteGroup {
  const FavoriteGroup({required this.id, required this.name, this.avatar});

  final String id;
  final String name;
  final String? avatar;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (avatar != null) 'avatar': avatar,
      };

  factory FavoriteGroup.fromJson(Map<String, dynamic> json) => FavoriteGroup(
        id: '${json['id'] ?? ''}',
        name: (json['name'] as String?) ?? '',
        avatar: json['avatar'] as String?,
      );
}

/// A locally saved topic (id / title) for the detail page's star.
/// Same store as favorite groups; there is no "saved topics" list
/// page yet — the star is a bookmark the feed's local signals can
/// use later.
class FavoriteTopic {
  const FavoriteTopic({required this.id, required this.title});

  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory FavoriteTopic.fromJson(Map<String, dynamic> json) => FavoriteTopic(
        id: '${json['id'] ?? ''}',
        title: (json['title'] as String?) ?? '',
      );
}

/// A recently viewed user (id / name / avatar) for the bind guide.
class RecentUser {
  const RecentUser({required this.id, required this.name, this.avatar});

  final String id;
  final String name;
  final String? avatar;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (avatar != null) 'avatar': avatar,
      };

  factory RecentUser.fromJson(Map<String, dynamic> json) => RecentUser(
        id: '${json['id'] ?? ''}',
        name: (json['name'] as String?) ?? '',
        avatar: json['avatar'] as String?,
      );
}

/// Local-only lists, kept in SharedPreferences — the same store
/// SettingsStore uses (and the same pattern as `search_history`).
/// A ChangeNotifier, so the group and user pages can listen to it
/// directly without a provider package.
class LocalLists extends ChangeNotifier {
  LocalLists._();

  static final LocalLists instance = LocalLists._();

  static const _favoriteGroupsKey = 'favorite_groups';
  static const _favoriteTopicsKey = 'favorite_topics';
  static const _myUserIdKey = 'my_user_id';
  static const _recentUsersKey = 'recent_users';
  static const _readFeedIdsKey = 'read_feed_ids';

  static const maxFavoriteGroups = 30;
  static const maxFavoriteTopics = 30;
  static const maxRecentUsers = 10;
  static const maxReadFeedIds = 500;

  List<FavoriteGroup> favoriteGroups = [];
  List<FavoriteTopic> favoriteTopics = [];
  String? myUserId;
  List<RecentUser> recentUsers = [];

  /// Feed items the user has opened, newest first. The card shows
  /// a read title in a muted colour. Only ids are stored.
  List<String> readFeedIds = [];

  bool isFeedRead(String id) => readFeedIds.contains(id);

  bool get isBound => myUserId != null && myUserId!.isNotEmpty;

  bool isFavoriteGroup(String id) => favoriteGroups.any((g) => g.id == id);

  bool isFavoriteTopic(String id) => favoriteTopics.any((t) => t.id == id);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    favoriteGroups = _decodeList(
      prefs.getString(_favoriteGroupsKey),
      FavoriteGroup.fromJson,
    );
    favoriteTopics = _decodeList(
      prefs.getString(_favoriteTopicsKey),
      FavoriteTopic.fromJson,
    );
    final readRaw = prefs.getString(_readFeedIdsKey);
    readFeedIds = readRaw == null || readRaw.isEmpty
        ? []
        : (jsonDecode(readRaw) as List?)?.whereType<String>().toList() ?? [];
    myUserId = prefs.getString(_myUserIdKey);
    recentUsers = _decodeList(
      prefs.getString(_recentUsersKey),
      RecentUser.fromJson,
    );
    notifyListeners();
  }

  Future<void> toggleFavoriteGroup({
    required String id,
    required String name,
    String? avatar,
  }) async {
    if (isFavoriteGroup(id)) {
      favoriteGroups = favoriteGroups.where((g) => g.id != id).toList();
    } else {
      favoriteGroups = [
        FavoriteGroup(id: id, name: name, avatar: avatar),
        ...favoriteGroups,
      ];
      if (favoriteGroups.length > maxFavoriteGroups) {
        favoriteGroups = favoriteGroups.sublist(0, maxFavoriteGroups);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _favoriteGroupsKey,
      jsonEncode(favoriteGroups.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> toggleFavoriteTopic({required String id, required String title}) async {
    if (isFavoriteTopic(id)) {
      favoriteTopics = favoriteTopics.where((t) => t.id != id).toList();
    } else {
      favoriteTopics = [
        FavoriteTopic(id: id, title: title),
        ...favoriteTopics,
      ];
      if (favoriteTopics.length > maxFavoriteTopics) {
        favoriteTopics = favoriteTopics.sublist(0, maxFavoriteTopics);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _favoriteTopicsKey,
      jsonEncode(favoriteTopics.map((t) => t.toJson()).toList()),
    );
  }

  /// Mark a feed item as read. No-op when it already is (so the
  /// card does not rebuild on a repeat open).
  Future<void> markFeedRead(String id) async {
    if (id.isEmpty || isFeedRead(id)) return;
    readFeedIds = [id, ...readFeedIds];
    if (readFeedIds.length > maxReadFeedIds) {
      readFeedIds = readFeedIds.sublist(0, maxReadFeedIds);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readFeedIdsKey, jsonEncode(readFeedIds));
  }

  /// Bind (or clear, with null) the "my" user id. A blank string
  /// clears the binding.
  Future<void> setMyUserId(String? id) async {
    final trimmed = id?.trim();
    myUserId = trimmed == null || trimmed.isEmpty ? null : trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (myUserId == null) {
      await prefs.remove(_myUserIdKey);
    } else {
      await prefs.setString(_myUserIdKey, myUserId!);
    }
  }

  Future<void> addRecentUser({
    required String id,
    required String name,
    String? avatar,
  }) async {
    recentUsers = [
      RecentUser(id: id, name: name, avatar: avatar),
      ...recentUsers.where((u) => u.id != id),
    ];
    if (recentUsers.length > maxRecentUsers) {
      recentUsers = recentUsers.sublist(0, maxRecentUsers);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentUsersKey,
      jsonEncode(recentUsers.map((u) => u.toJson()).toList()),
    );
  }

  Future<void> clearRecentUsers() async {
    recentUsers = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentUsersKey);
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
    } catch (_) {
      return [];
    }
  }
}
