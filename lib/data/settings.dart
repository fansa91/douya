import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App settings, modeled on c001apk's categorized settings page but
/// kept to what douya actually has: theme, search history, and about.
/// Persisted with SharedPreferences; if storage fails, settings still
/// work in-memory for this session instead of crashing the app.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const _themeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';
  static const _historyEnabledKey = 'search_history_enabled';
  static const _historyKey = 'search_history';
  static const maxHistory = 20;

  /// M3 seed color presets. Default is Douban green; the rest are
  /// standard M3-style seeds, not per-screen custom themes.
  static const List<(Color, String)> seedPresets = [
    (Color(0xFF00B51D), '豆瓣绿'),
    (Color(0xFF6750A4), 'M3 紫'),
    (Color(0xFF0061A4), '蓝'),
    (Color(0xFF006A6A), '青绿'),
    (Color(0xFFBF6900), '橙'),
    (Color(0xFFBA1A1A), '红'),
  ];

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = seedPresets.first.$1;
  bool _searchHistoryEnabled = true;
  List<String> _searchHistory = const [];
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get searchHistoryEnabled => _searchHistoryEnabled;
  List<String> get searchHistory => _searchHistory;
  bool get loaded => _loaded;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final theme = prefs.getString(_themeKey);
      _themeMode = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      final seedValue = prefs.getInt(_seedColorKey);
      if (seedValue != null) {
        _seedColor = Color(seedValue);
      }
      _searchHistoryEnabled = prefs.getBool(_historyEnabledKey) ?? true;
      _searchHistory = prefs.getStringList(_historyKey) ?? const [];
    } catch (_) {
      // Keep defaults; settings stay in-memory for this session.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _themeKey,
        switch (_themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
      await prefs.setInt(_seedColorKey, _seedColor.toARGB32());
      await prefs.setBool(_historyEnabledKey, _searchHistoryEnabled);
      await prefs.setStringList(_historyKey, _searchHistory);
    } catch (_) {
      // In-memory settings still apply; persistence is best-effort.
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    _save();
  }

  void setSeedColor(Color color) {
    if (color == _seedColor) return;
    _seedColor = color;
    notifyListeners();
    _save();
  }

  void setSearchHistoryEnabled(bool enabled) {
    if (enabled == _searchHistoryEnabled) return;
    _searchHistoryEnabled = enabled;
    if (!enabled) _searchHistory = const [];
    notifyListeners();
    _save();
  }

  void addSearchHistory(String query) {
    final text = query.trim();
    if (!_searchHistoryEnabled || text.isEmpty) return;
    final next = [text, ..._searchHistory.where((item) => item != text)]
        .take(maxHistory)
        .toList();
    _searchHistory = next;
    notifyListeners();
    _save();
  }

  void clearSearchHistory() {
    if (_searchHistory.isEmpty) return;
    _searchHistory = const [];
    notifyListeners();
    _save();
  }
}
