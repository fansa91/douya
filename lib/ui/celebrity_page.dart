import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Celebrity page. The id must come from the subject's celebrities
/// endpoint, because the subject detail itself only carries names.
class CelebrityPage extends StatelessWidget {
  const CelebrityPage({super.key, required this.repository, required this.id});

  final DoubanRepository repository;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('影人')),
      body: FutureBuilder(
        future: repository.fetchCelebrity(id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
          final detail = snapshot.data;
          if (detail == null) return const EmptyState(message: '暂无影人信息');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: CircleAvatar(child: Text(detail.celebrity.name.isEmpty ? '?' : detail.celebrity.name[0])),
                title: Text(detail.celebrity.name),
                subtitle: Text(detail.celebrity.character ?? ''),
              ),
              const SizedBox(height: 16),
              const Text('作品', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final work in detail.works)
                SubjectRow(
                  subject: work,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SubjectPage(repository: repository, type: work.type, id: work.id),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
