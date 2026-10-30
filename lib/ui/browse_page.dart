import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Browse by type. The repository interface is type-agnostic here;
/// a real implementation would pass the selected type to the
/// collection endpoint. The skeleton keeps one list per chip.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.repository});

  final DoubanRepository repository;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _types = const ['电影', '剧集', '图书', '音乐'];
  int _selected = 0;

  void _openSubject(Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(repository: widget.repository, type: subject.type, id: subject.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < _types.length; i++)
                ChoiceChip(
                  label: Text(_types[i]),
                  selected: _selected == i,
                  onSelected: (_) => setState(() => _selected = i),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Subject>>(
            future: widget.repository.fetchRecentHot(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingList();
              }
              if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
              final subjects = snapshot.data ?? const [];
              if (subjects.isEmpty) return const EmptyState(message: '该分类暂无内容');
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 600) {
                    return ListView.builder(
                      itemCount: subjects.length,
                      itemBuilder: (_, i) => SubjectRow(
                        subject: subjects[i],
                        onTap: () => _openSubject(subjects[i]),
                      ),
                    );
                  }
                  final columns = constraints.maxWidth >= 1440 ? 5 : 4;
                  return GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: subjects.length,
                    itemBuilder: (_, i) => SubjectPosterCard(
                      subject: subjects[i],
                      onTap: () => _openSubject(subjects[i]),
                    ),
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
