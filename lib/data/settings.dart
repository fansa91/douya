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
  static const _historyEnabledKey = 'search_history_enabled';
  static const _historyKey = 'search_history';
  static const maxHistory = 20;

  ThemeMode _themeMode = ThemeMode.system;
  bool _searchHistoryEnabled = true;
  List<String> _searchHistory = const [];
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
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
