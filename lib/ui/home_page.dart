import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'browse_page.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Discover page: guest-usable recommendation sections, like the mobile
/// homepage's recommendation area. "正在热映" lives in BrowsePage now,
/// not here. Each section's "更多" opens BrowsePage at that filter.
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

  void _openMore(BuildContext context, HomeSection section) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowsePage(
          repository: repository,
          initialCategory: section.category,
          initialFilter: section.filter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HomeSection>>(
      future: repository.fetchHomeSections(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingList();
        }
        if (snapshot.hasError) {
          return EmptyState(message: '加载失败：${snapshot.error}');
        }
        final sections = snapshot.data ?? const [];
        if (sections.isEmpty) return const EmptyState(message: '暂无推荐内容');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final section in sections) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openMore(context, section),
                    child: const Text('更多 >'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: section.items.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: 120,
                    child: SubjectPosterCard(
                      subject: section.items[i],
                      onTap: () => _openSubject(context, section.items[i]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }
}
