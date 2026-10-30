import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Discover page. Mobile: horizontal poster rows + vertical feed.
/// Desktop: poster grid + right trending column on very wide windows.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.repository});

  final DoubanRepository repository;

  void _openSubject(BuildContext context, Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(repository: repository, type: subject.type, id: subject.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Subject>>(
      future: repository.fetchHot(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingList();
        }
        if (snapshot.hasError) {
          return EmptyState(message: '加载失败：${snapshot.error}');
        }
        final subjects = snapshot.data ?? const [];
        if (subjects.isEmpty) return const EmptyState(message: '暂无内容');
        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 1024;
            if (!isDesktop) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('正在热映', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: subjects.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => SizedBox(
                        width: 120,
                        child: SubjectPosterCard(
                          subject: subjects[i],
                          onTap: () => _openSubject(context, subjects[i]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('推荐', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final s in subjects)
                    SubjectRow(subject: s, onTap: () => _openSubject(context, s)),
                ],
              );
            }
            final columns = constraints.maxWidth >= 1440 ? 5 : 4;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: subjects.length,
                      itemBuilder: (_, i) => SubjectPosterCard(
                        subject: subjects[i],
                        onTap: () => _openSubject(context, subjects[i]),
                      ),
                    ),
                  ),
                ),
                if (constraints.maxWidth >= 1440)
                  SizedBox(
                    width: 320,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('口碑榜', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          for (var i = 0; i < subjects.length; i++)
                            ListTile(
                              leading: Text('${i + 1}', style: const TextStyle(color: Color(0xFF00B51D), fontWeight: FontWeight.bold)),
                              title: Text(subjects[i].title),
                              onTap: () => _openSubject(context, subjects[i]),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
