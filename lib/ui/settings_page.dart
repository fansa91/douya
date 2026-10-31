import 'package:flutter/material.dart';

import '../data/image_cache.dart';
import '../data/settings.dart';
import '../models/models.dart';
import 'widgets.dart';

/// Settings page, modeled on c001apk's categorized settings:
/// mobile pushes a detail page per category; desktop (wide) shows
/// categories on the left and the selected category on the right.
/// Only settings douya actually implements are listed here — no
/// placeholder switches for features that do not exist yet.
enum SettingsSection {
  appearance('外观', '主题模式、M3 主题色、动态取色、字号、图片质量', Icons.palette_outlined),
  search('搜索', '搜索历史', Icons.search_outlined),
  storage('存储', '图片缓存与清理', Icons.storage_outlined),
  about('关于', '版本与访客模式说明', Icons.info_outlined);

  const SettingsSection(this.title, this.description, this.icon);

  final String title;
  final String description;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSection _section = SettingsSection.appearance;

  Widget _categories(bool wide) {
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      children: [
        for (final section in SettingsSection.values)
          ListTile(
            leading: Icon(section.icon),
            title: Text(section.title),
            subtitle: Text(section.description),
            selected: wide && _section == section,
            onTap: () {
              if (wide) {
                setState(() => _section = section);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(section.title)),
                      body: _SettingsDetail(section: section),
                    ),
                  ),
                );
              }
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          if (!wide) return _categories(false);
          return Row(
            children: [
              SizedBox(width: 280, child: _categories(true)),
              const VerticalDivider(width: 1),
              Expanded(
                child: CenteredWidth(
                  child: _SettingsDetail(key: ValueKey(_section), section: _section),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsDetail extends StatelessWidget {
  const _SettingsDetail({super.key, required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsStore.instance;
    // Version comes from the release tag via --dart-define=APP_VERSION
    // (release.yml sets it from the tag on tag builds, 'dev' on any
    // other build); it is never hard-coded here, so About always
    // shows this build's own release version.
    const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: switch (section) {
            SettingsSection.appearance => [
              const Text('主题模式', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (mode) {
                  if (mode != null) settings.setThemeMode(mode);
                },
                child: Column(
                  children: [
                    for (final entry in [
                      (ThemeMode.system, '跟随系统'),
                      (ThemeMode.light, '浅色'),
                      (ThemeMode.dark, '深色'),
                    ])
                      RadioListTile<ThemeMode>(
                        title: Text(entry.$2),
                        value: entry.$1,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('M3 主题色', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('改的是 Material 3 的种子色，整个应用的配色都会跟着变，默认是豆瓣绿。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  for (final preset in SettingsStore.seedPresets)
                    GestureDetector(
                      onTap: () => settings.setSeedColor(preset.$1),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: preset.$1,
                            child: settings.seedColor == preset.$1
                                ? const Icon(Icons.check, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(preset.$2, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              if (settings.dynamicColor)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('动态取色已开启，上面这些种子色暂不生效。'),
                ),
              const SizedBox(height: 8),
              const Text('纸张底色仍固定为 #F7F5F0，评分仍为琥珀色，见 README 的 M3 说明。'),
              const SizedBox(height: 24),
              const Text('动态取色', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('跟随系统配色'),
                subtitle: const Text('开启后按系统配色换主题（仅 Android 12+ 有效，其他平台自动回落到种子色）；关闭后用上面的种子色'),
                value: settings.dynamicColor,
                onChanged: settings.setDynamicColor,
              ),
              const SizedBox(height: 16),
              const Text('字号', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('小'),
                  Expanded(
                    child: Slider(
                      value: settings.fontScale,
                      min: SettingsStore.minFontScale,
                      max: SettingsStore.maxFontScale,
                      divisions: 10,
                      label: '${(settings.fontScale * 100).round()}%',
                      onChanged: settings.setFontScale,
                    ),
                  ),
                  const Text('大'),
                ],
              ),
              Text('当前 ${(settings.fontScale * 100).round()}%，改动立即对全应用文字生效。'),
              const SizedBox(height: 24),
              const Text('图片质量', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('控制海报、剧照网格用大图还是小图。自动是大图优先（和以前一样）；预览页点开后始终显示大图，不受这项影响。'),
              const SizedBox(height: 8),
              RadioGroup<ImageQuality>(
                groupValue: settings.imageQuality,
                onChanged: (quality) {
                  if (quality != null) settings.setImageQuality(quality);
                },
                child: Column(
                  children: [
                    for (final quality in ImageQuality.values)
                      RadioListTile<ImageQuality>(
                        title: Text(quality.label),
                        value: quality,
                      ),
                  ],
                ),
              ),
            ],
            SettingsSection.search => [
              SwitchListTile(
                title: const Text('保存搜索历史'),
                subtitle: const Text('关闭后不再保存新历史，并清空已有历史'),
                value: settings.searchHistoryEnabled,
                onChanged: settings.setSearchHistoryEnabled,
              ),
              ListTile(
                title: const Text('清除搜索历史'),
                subtitle: Text(
                  settings.searchHistory.isEmpty
                      ? '暂无历史'
                      : '${settings.searchHistory.length} 条',
                ),
                onTap: settings.searchHistory.isEmpty
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确定清除全部搜索历史？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) settings.clearSearchHistory();
                      },
              ),
            ],
            SettingsSection.storage => [
              const Text('图片缓存', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('这里是预览画廊下载过的图片（海报、剧照的磁盘缓存）。清理后再次打开会重新下载，不影响搜索历史和设置。'),
              const SizedBox(height: 8),
              const _CacheSection(),
            ],
            SettingsSection.about => [
              ListTile(
                leading: Image.asset('assets/logo.png', width: 48, height: 48),
                title: const Text('douya'),
                subtitle: const Text('豆瓣访客只读客户端 · 首个发布 v0.1'),
              ),
              const ListTile(
                title: Text('版本'),
                subtitle: Text(appVersion == 'dev' ? '开发版（本地构建，未走 tag 发布）' : appVersion),
              ),
              const ListTile(
                title: Text('访客模式'),
                subtitle: Text('不登录、不标记、不关注、不评论、不发帖、不收通知。只能看公开内容。'),
              ),
              const ListTile(
                title: Text('图片预览'),
                subtitle: Text('剧照点开是全屏画廊，可缩放、滑动、桌面左右键切换，长按菜单可保存 / 分享 / 复制链接 / 在浏览器中打开（桌面端保存走浏览器打开）。'),
              ),
              const ListTile(
                title: Text('视频预览'),
                subtitle: Text('条目详情的预告片点开可播放，点画面显示/隐藏控制条，3 秒无操作自动隐藏。'),
              ),
              const ListTile(
                title: Text('数据来源'),
                subtitle: Text('Frodo 签名接口 + Rexxar 公开接口，见仓库外的 DOUBAN_GUEST_API.md。'),
              ),
            ],
          },
        );
      },
    );
  }
}

/// Cache size display + clear action for the storage section.
/// Size is re-measured on open and after every clear.
class _CacheSection extends StatefulWidget {
  const _CacheSection();

  @override
  State<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<_CacheSection> {
  Future<int>? _sizeFuture;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _sizeFuture = ImageCacheService.sizeBytes();
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    final freed = await ImageCacheService.clear();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _sizeFuture = ImageCacheService.sizeBytes();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清理图片缓存 ${ImageCacheService.formatBytes(freed)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _sizeFuture,
      builder: (context, snapshot) {
        final size = snapshot.data ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: const Text('图片磁盘缓存'),
              subtitle: Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? '正在统计…'
                    : ImageCacheService.formatBytes(size),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _clearing ? null : _clear,
              child: Text(_clearing ? '清理中…' : '清理缓存'),
            ),
          ],
        );
      },
    );
  }
}
