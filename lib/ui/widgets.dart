import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../models/models.dart';

/// Headers every remote image load must carry. Douban's image CDN
/// (img*.doubanio.com) returns 418 with no Referer and 403 for Dart's
/// default user-agent, so a bare Image.network / NetworkImage fails
/// for every poster, still and avatar (verified live 2026-10-31:
/// bare -> 418, browser UA + Referer -> 200).
const doubanImageHeaders = <String, String>{
  'Referer': 'https://m.douban.com/',
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
};

/// Image provider with the headers above, for CircleAvatar and
/// other ImageProvider slots.
ImageProvider<Object> doubanImageProvider(String url) =>
    CachedNetworkImageProvider(url, headers: doubanImageHeaders);

/// Poster card for grids. [isDoulist] subjects render a list badge
/// instead of a rating, because Rexxar recommend items are mixed cards.
class SubjectPosterCard extends StatelessWidget {
  const SubjectPosterCard({super.key, required this.subject, this.onTap});

  final Subject subject;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pic = subjectImageUrl(subject, SettingsStore.instance.imageQuality);
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
              child: pic == null
                  ? Center(child: Text(subject.title.isEmpty ? '?' : subject.title[0]))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: pic,
                        httpHeaders: doubanImageHeaders,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (context, url, error) => Center(
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
    final pic = subjectImageUrl(subject, SettingsStore.instance.imageQuality);
    return ListTile(
      leading: Container(
        width: 56,
        height: 76,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: pic == null
            ? const Icon(Icons.book_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: pic,
                  httpHeaders: doubanImageHeaders,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const Icon(Icons.book_outlined),
                ),
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

/// Centers a page's content at a readable width on desktop
/// (c001apk's reading pane centers detail at ~680-760; this uses
/// 720 for text lists). On narrow screens the cap is wider than
/// the viewport, so mobile layouts are unaffected.
class CenteredWidth extends StatelessWidget {
  const CenteredWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
