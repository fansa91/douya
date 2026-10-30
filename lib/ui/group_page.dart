import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'widgets.dart';

/// Group browsing. Desktop uses master-detail: topic list on the left,
/// topic detail on the right. Mobile pushes a detail page.
/// Note: there is deliberately no "my groups" list here, because
/// group/user/{id}/joined_groups returns 403 for guest signatures.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.repository, this.initialGroupId});

  final DoubanRepository repository;
  final String? initialGroupId;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  late final _groupController = TextEditingController(text: widget.initialGroupId ?? '146409');
  String? _selectedTopicId;

  @override
  void dispose() {
    _groupController.dispose();
    super.dispose();
  }

  Widget _topicList(List<GroupTopic> topics, {required bool isDesktop}) {
    return ListView.builder(
      itemCount: topics.length,
      itemBuilder: (_, i) {
        final topic = topics[i];
        return ListTile(
          selected: isDesktop && _selectedTopicId == topic.id,
          title: Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${topic.authorName} · 回应 ${topic.commentsCount}'),
          onTap: () {
            if (isDesktop) {
              setState(() => _selectedTopicId = topic.id);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TopicDetailPage(repository: widget.repository, topicId: topic.id)),
              );
            }
          },
        );
      },
    );
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
                  controller: _groupController,
                  decoration: const InputDecoration(
                    hintText: '输入小组 id，例如 146409',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
                  ),
                  onSubmitted: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => setState(() {}), child: const Text('查看')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<GroupTopic>>(
            future: widget.repository.fetchGroupTopics(_groupController.text.trim()),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingList();
              }
              if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
              final topics = snapshot.data ?? const [];
              if (topics.isEmpty) return const EmptyState(message: '该小组暂无话题');
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 1024) {
                    return _topicList(topics, isDesktop: false);
                  }
                  final selected = _selectedTopicId ?? topics.first.id;
                  return Row(
                    children: [
                      SizedBox(width: 420, child: _topicList(topics, isDesktop: true)),
                      const VerticalDivider(width: 1),
                      Expanded(child: TopicDetailView(repository: widget.repository, topicId: selected)),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class TopicDetailPage extends StatelessWidget {
  const TopicDetailPage({super.key, required this.repository, required this.topicId});

  final DoubanRepository repository;
  final String topicId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('话题详情')),
      body: TopicDetailView(repository: repository, topicId: topicId),
    );
  }
}

class TopicDetailView extends StatelessWidget {
  const TopicDetailView({super.key, required this.repository, required this.topicId});

  final DoubanRepository repository;
  final String topicId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TopicDetail>(
      future: repository.fetchTopic(topicId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingList();
        }
        if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
        final detail = snapshot.data;
        if (detail == null) return const EmptyState(message: '暂无话题');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(detail.topic.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${detail.topic.authorName} · ${detail.topic.createTime}'),
            const SizedBox(height: 16),
            Text(detail.content),
            const Divider(height: 32),
            const Text('回复', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (detail.comments.isEmpty) const EmptyState(message: '暂无回复'),
            for (final c in detail.comments)
              ListTile(
                title: Text(c.authorName),
                subtitle: Text(c.text),
                trailing: Text('赞 ${c.voteCount}'),
              ),
          ],
        );
      },
    );
  }
}
