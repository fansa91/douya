import 'package:flutter/material.dart';

import '../models/models.dart';

/// Poster card for grids. [isDoulist] subjects render a list badge
/// instead of a rating, because Rexxar recommend items are mixed cards.
class SubjectPosterCard extends StatelessWidget {
  const SubjectPosterCard({super.key, required this.subject, this.onTap});

  final Subject subject;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: subject.pic == null
                  ? Center(child: Text(subject.title.isEmpty ? '?' : subject.title[0]))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        subject.pic!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(subject.title.isEmpty ? '?' : subject.title[0]),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(subject.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          if (subject.isDoulist)
            Text('豆列 · ${subject.doulistCount ?? ''} 条', style: Theme.of(context).textTheme.bodySmall)
          else if (subject.rating != null && subject.rating!.value > 0)
            RatingText(rating: subject.rating!)
          else
            Text('暂无评分', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Compact list row for collections and search results.
class SubjectRow extends StatelessWidget {
  const SubjectRow({super.key, required this.subject, this.trailing, this.onTap});

  final Subject subject;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 56,
        height: 76,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: subject.pic == null
            ? const Icon(Icons.book_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(subject.pic!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.book_outlined)),
              ),
      ),
      title: Text(subject.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subject.cardSubtitle ?? subject.year ?? subject.type),
      trailing: trailing ??
          (subject.rating != null && subject.rating!.value > 0 ? RatingText(rating: subject.rating!) : null),
      onTap: onTap,
    );
  }
}

/// Rating display. [community] means 0-10 (divide by 2 for stars);
/// personal means 1-5 stars already. Do not convert personal twice.
class RatingText extends StatelessWidget {
  const RatingText({super.key, required this.rating, this.community = true});

  final Rating rating;
  final bool community;

  @override
  Widget build(BuildContext context) {
    final stars = community ? (rating.value / 2).round() : rating.value.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rating.value.toStringAsFixed(1),
          style: const TextStyle(color: Color(0xFFE8A33D), fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            5,
            (i) => Icon(
              i < stars ? Icons.star : Icons.star_border,
              size: 14,
              color: const Color(0xFFE8A33D),
            ),
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
