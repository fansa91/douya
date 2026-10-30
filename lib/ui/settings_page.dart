import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Settings page, modeled on c001apk's categorized settings:
/// mobile pushes a detail page per category; desktop (wide) shows
/// categories on the left and the selected category on the right.
/// Only settings douya actually implements are listed here — no
/// placeholder switches for features that do not exist yet.
enum SettingsSection {
  appearance('外观', '主题模式', Icons.palette_outlined),
  search('搜索', '搜索历史', Icons.search_outlined),
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
                child: _SettingsDetail(key: ValueKey(_section), section: _section),
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
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: switch (section) {
            SettingsSection.appearance => [
              const Text('主题模式', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final entry in [
                (ThemeMode.system, '跟随系统'),
                (ThemeMode.light, '浅色'),
                (ThemeMode.dark, '深色'),
              ])
                RadioListTile<ThemeMode>(
                  title: Text(entry.$2),
                  value: entry.$1,
                  groupValue: settings.themeMode,
                  onChanged: (mode) {
                    if (mode != null) settings.setThemeMode(mode);
                  },
                ),
              const SizedBox(height: 8),
              const Text('主色仍固定为豆瓣绿 #00B51D，纸张底色 #F7F5F0，见 README 的 M3 说明。'),
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
            SettingsSection.about => [
              ListTile(
                leading: Image.asset('assets/logo.png', width: 48, height: 48),
                title: const Text('douya'),
                subtitle: const Text('豆瓣访客只读客户端 · 首个发布 v0.1'),
              ),
              const ListTile(
                title: Text('访客模式'),
                subtitle: Text('不登录、不标记、不关注、不评论、不发帖、不收通知。只能看公开内容。'),
              ),
              const ListTile(
                title: Text('图片预览'),
                subtitle: Text('剧照点开是全屏画廊，可缩放、滑动、桌面左右键切换，长按复制链接。保存/分享尚未接入。'),
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
