import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Guest user page: the user types a public user id (from
/// douban.com/people/<ID>/). There is no login account here.

/// Type/status labels in Chinese. The API keys are book/movie/music
/// and done/doing/mark; the status verb follows the type (读/看/听).
String userTypeLabel(String type) => switch (type) {
      'book' => '图书',
      'movie' => '电影',
      'music' => '音乐',
      _ => type,
    };

String userStatusLabel(String type, String status) {
  final verb = switch (type) { 'book' => '读', 'music' => '听', _ => '看' };
  return switch (status) { 'mark' => '想$verb', 'doing' => '在$verb', _ => '$verb过' };
}

class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.repository, this.initialUserId});

  final DoubanRepository repository;
  final String? initialUserId;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  late final _controller = TextEditingController(text: widget.initialUserId ?? '2870956');
  String _type = 'book';
  String _status = 'done';
  UserProfile? _profile;
  List<Interest> _interests = const [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await widget.repository.fetchUser(_controller.text.trim());
      final interests = await widget.repository.fetchInterests(_controller.text.trim(), _type, _status);
      if (mounted) {
        setState(() {
          _profile = profile;
          _interests = interests;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openSubject(Interest interest) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(
          repository: widget.repository,
          type: interest.subject.type,
          id: interest.subject.id,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: '输入公开用户 id，例如 2870956',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _load, child: const Text('查看')),
            ],
          ),
        ),
        if (_profile != null)
          ListTile(
            leading: CircleAvatar(
              backgroundImage: _profile!.avatar != null ? doubanImageProvider(_profile!.avatar!) : null,
              child: _profile!.avatar == null ? Text(_profile!.name.isEmpty ? '?' : _profile!.name[0]) : null,
            ),
            title: Text(_profile!.name),
            subtitle: Text('关注 ${_profile!.followingCount} · 粉丝 ${_profile!.followersCount}'),
          ),
        Wrap(
          spacing: 8,
          children: [
            for (final t in ['book', 'movie', 'music'])
              ChoiceChip(
                label: Text(userTypeLabel(t)),
                selected: _type == t,
                onSelected: (_) {
                  setState(() => _type = t);
                  _load();
                },
              ),
            for (final s in ['done', 'doing', 'mark'])
              ChoiceChip(
                label: Text(userStatusLabel(_type, s)),
                selected: _status == s,
                onSelected: (_) {
                  setState(() => _status = s);
                  _load();
                },
              ),
            TextButton(onPressed: _load, child: const Text('刷新')),
          ],
        ),
        const Divider(),
        Expanded(
          child: _loading
              ? const LoadingList()
              : _interests.isEmpty
                  ? const EmptyState(message: '该用户没有公开收藏（total 为 0 是合法结果，不是接口坏了）。')
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (Breakpoints.of(constraints.maxWidth) == WindowSize.compact) {
                          return ListView.builder(
                            itemCount: _interests.length,
                            itemBuilder: (_, i) {
                              final interest = _interests[i];
                              return SubjectRow(
                                subject: interest.subject,
                                trailing: interest.rating != null
                                    ? RatingText(rating: interest.rating!, community: false)
                                    : null,
                                onTap: () => _openSubject(interest),
                              );
                            },
                          );
                        }
                        // Same poster-grid rule as Browse: row capped
                        // at 1440, columns from a ~240 poster width.
                        final contentWidth = constraints.maxWidth > Breakpoints.gridMaxWidth ? Breakpoints.gridMaxWidth : constraints.maxWidth;
                        final columns = Breakpoints.posterColumns(contentWidth);
                        return CenteredWidth(
                          maxWidth: Breakpoints.gridMaxWidth,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(24),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.68,
                            ),
                            itemCount: _interests.length,
                            itemBuilder: (_, i) => SubjectPosterCard(
                              subject: _interests[i].subject,
                              onTap: () => _openSubject(_interests[i]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
