import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Guest user page: the user types a public user id (from
/// douban.com/people/<ID>/). There is no login account here.
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
            leading: CircleAvatar(child: Text(_profile!.name.isEmpty ? '?' : _profile!.name[0])),
            title: Text(_profile!.name),
            subtitle: Text('关注 ${_profile!.followersCount} · 粉丝 ${_profile!.followingCount}'),
          ),
        Wrap(
          spacing: 8,
          children: [
            for (final t in ['book', 'movie', 'music'])
              ChoiceChip(
                label: Text(t),
                selected: _type == t,
                onSelected: (_) {
                  setState(() => _type = t);
                  _load();
                },
              ),
            for (final s in ['done', 'doing', 'mark'])
              ChoiceChip(
                label: Text(s),
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
                        if (constraints.maxWidth < 600) {
                          return ListView.builder(
                            itemCount: _interests.length,
                            itemBuilder: (_, i) {
                              final interest = _interests[i];
                              return SubjectRow(
                                subject: interest.subject,
                                trailing: interest.rating != null
                                    ? RatingText(rating: interest.rating!, community: false)
                                    : null,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SubjectPage(
                                        repository: widget.repository,
                                        type: interest.subject.type,
                                        id: interest.subject.id,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }
                        return GridView.builder(
                          padding: const EdgeInsets.all(24),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.68,
                          ),
                          itemCount: _interests.length,
                          itemBuilder: (_, i) => SubjectPosterCard(subject: _interests[i].subject),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
