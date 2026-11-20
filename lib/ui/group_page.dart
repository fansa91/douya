import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'group_hot_view.dart';
import 'group_topics_view.dart';

/// The group tab: hot groups and favorites. Entering a group pushes
/// GroupDetailPage (a real route), so this page owns no detail state
/// and needs no back handling of its own.
class GroupPage extends StatelessWidget {
  const GroupPage({super.key, required this.repository});

  final DoubanRepository repository;

  @override
  Widget build(BuildContext context) {
    return GroupHotView(
      repository: repository,
      onOpenGroup: (groupId, groupName) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupTopicsPage(repository: repository, groupId: groupId, groupName: groupName),
          ),
        );
      },
    );
  }
}
