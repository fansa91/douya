import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// App settings, modeled on c001apk's categorized settings page but
/// kept to what douya actually has: theme, search history, and about.
/// Persisted with SharedPreferences; if storage fails, settings still
/// work in-memory for this session instead of crashing the app.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const _themeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';
  static const _dynamicColorKey = 'dynamic_color';
  static const _fontScaleKey = 'font_scale';
  static const _imageQualityKey = 'image_quality';
  static const _historyEnabledKey = 'search_history_enabled';
  static const _historyKey = 'search_history';
  static const maxHistory = 20;

  /// Font scale range for the 字号 slider (c001apk-style).
  static const minFontScale = 0.8;
  static const maxFontScale = 1.3;

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
  bool _dynamicColor = false;
  double _fontScale = 1.0;
  ImageQuality _imageQuality = ImageQuality.auto;
  bool _searchHistoryEnabled = true;
  List<String> _searchHistory = const [];
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;

  /// c001apk's 动态取色: follow the system palette when on (only
  /// Android 12+ actually provides one; elsewhere the seed color is
  /// used). Off by default so douya keeps its Douban-green look
  /// unless the user opts in; while on, the seed presets below do
  /// not apply.
  bool get dynamicColor => _dynamicColor;
  double get fontScale => _fontScale;
  ImageQuality get imageQuality => _imageQuality;
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
      _dynamicColor = prefs.getBool(_dynamicColorKey) ?? false;
      final fontScale = prefs.getDouble(_fontScaleKey);
      if (fontScale != null) {
        _fontScale = fontScale.clamp(minFontScale, maxFontScale);
      }
      final quality = prefs.getString(_imageQualityKey);
      _imageQuality = switch (quality) {
        'origin' => ImageQuality.origin,
        'thumbnail' => ImageQuality.thumbnail,
        _ => ImageQuality.auto,
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
      await prefs.setInt(_seedColorKey, _seedColor.toARGB32());
      await prefs.setBool(_dynamicColorKey, _dynamicColor);
      await prefs.setDouble(_fontScaleKey, _fontScale);
      await prefs.setString(_imageQualityKey, _imageQuality.name);
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

  void setDynamicColor(bool enabled) {
    if (enabled == _dynamicColor) return;
    _dynamicColor = enabled;
    notifyListeners();
    _save();
  }

  void setFontScale(double scale) {
    final clamped = scale.clamp(minFontScale, maxFontScale);
    if (clamped == _fontScale) return;
    _fontScale = clamped;
    notifyListeners();
    _save();
  }

  void setImageQuality(ImageQuality quality) {
    if (quality == _imageQuality) return;
    _imageQuality = quality;
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
