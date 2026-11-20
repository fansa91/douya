import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import 'widgets.dart';

/// Detail-page header: group avatar, name, member count and
/// description. Flat (no Card) so it scrolls away with the list on
/// mobile and sits as one full-width row above the split on desktop.
/// Long descriptions collapse to two lines with an expand toggle.
/// Loading shows a thin progress bar; a failed detail fetch falls
/// back to the group id (topics still load).
class GroupHeader extends StatefulWidget {
  const GroupHeader({
    super.key,
    required this.detail,
    required this.loading,
    required this.groupId,
  });

  final SearchGroup? detail;
  final bool loading;
  final String groupId;

  @override
  State<GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<GroupHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: LinearProgressIndicator(),
      );
    }
    final group = widget.detail;
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('小组 ${widget.groupId}', style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }
    final avatarUrl = group.largeAvatar ?? group.avatar;
    final description = group.description;
    final collapsible = description.length > 80;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: avatarUrl == null || avatarUrl.isEmpty
                ? const SizedBox(width: 52, height: 52, child: Icon(Icons.group_outlined))
                : CachedNetworkImage(imageUrl: avatarUrl, httpHeaders: doubanImageHeaders, width: 52, height: 52, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.group_outlined)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${group.memberCount} 个成员', style: Theme.of(context).textTheme.bodySmall),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (collapsible)
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(_expanded ? '收起' : '展开', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
