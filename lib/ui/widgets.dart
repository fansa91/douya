import 'breakpoints.dart';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Web URL for a subject. The model carries no URL field (the APIs
/// never return one), so this derives the canonical web address from
/// the subject type: movie/tv live under movie.douban.com, books
/// under book.douban.com, music under music.douban.com.
String subjectWebUrl(Subject subject) {
  return switch (subject.type) {
    'book' => 'https://book.douban.com/subject/${subject.id}/',
    'music' => 'https://music.douban.com/subject/${subject.id}/',
    'movie' || 'tv' => 'https://movie.douban.com/subject/${subject.id}/',
    _ => 'https://www.douban.com/subject/${subject.id}/',
  };
}

/// Web URL for a group topic.
String topicWebUrl(String topicId) =>
    'https://www.douban.com/group/topic/$topicId/';

/// Web URL for a feed card: the payload's sharing URL when present,
/// otherwise the derived topic URL for topic items. Null when no URL
/// can be determined (e.g. a review without a sharing URL).
String? feedItemWebUrl(FeedItem item) {
  if (item.sharingUrl.isNotEmpty) return item.sharingUrl;
  if (item.type == 'topic') return topicWebUrl(item.id);
  return null;
}

/// Right-click (desktop) link menu for cards and rows: copy the link
/// or open it in the browser. [position] is the tap's global position.
Future<void> showLinkMenu(
  BuildContext context,
  Offset position,
  String url,
) async {
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    items: const [
      PopupMenuItem(value: 'copy', child: Text('复制链接')),
      PopupMenuItem(value: 'open', child: Text('在浏览器中打开')),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'copy':
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('链接已复制')),
        );
      }
    case 'open':
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// Footer for paged lists that loads more automatically: it calls
/// [onLoadMore] as soon as it is built while [canLoadMore] is true.
/// Used as the last item of lazy lists (ListView.builder / slivers),
/// the footer is only built when the user scrolls near the bottom,
/// so building it IS the scroll signal — no button, no controller.
/// When the list is too short to scroll, the footer builds
/// immediately and pages keep loading until the viewport fills or
/// the list ends. Callers must make [canLoadMore] false while a
/// load is in flight and make their load stop on an empty page,
/// or the footer would re-trigger forever.
///
/// On desktop, auto-loading pauses after 3 consecutive pages and
/// shows a 加载更多 button instead (tapping it resets the counter),
/// so a long list does not keep fetching while the user is only
/// scrolling past it. Mobile keeps auto-loading without a pause.
/// The counter resets when this footer is remounted, which coincides
/// with a list reset: the pages show a full loading state then,
/// unmounting the footer.
class LoadMoreFooter extends StatefulWidget {
  const LoadMoreFooter({super.key, required this.canLoadMore, required this.onLoadMore, this.countText, this.failed = false});

  final bool Function() canLoadMore;
  final VoidCallback onLoadMore;
  final String? countText;

  /// The last load-more attempt failed: show a retry button and
  /// stop auto-loading until the user taps it.
  final bool failed;

  @override
  State<LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<LoadMoreFooter> {
  int _autoPages = 0;

  bool get _paused {
    if (Breakpoints.ofContext(context) == WindowSize.compact) return false;
    return _autoPages >= 3;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  @override
  void didUpdateWidget(LoadMoreFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  void _maybeLoad() {
    if (!mounted || widget.failed || _paused) return;
    if (widget.canLoadMore()) {
      _autoPages++;
      widget.onLoadMore();
    }
  }

  void _loadMoreManually() {
    setState(() => _autoPages = 0);
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.countText != null) ...[
              Text(widget.countText!),
              const SizedBox(height: 8),
            ],
            if (widget.failed)
              TextButton.icon(
                onPressed: _loadMoreManually,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('加载失败，点击重试'),
              )
            else if (widget.canLoadMore())
              if (_paused)
                OutlinedButton(
                  onPressed: _loadMoreManually,
                  child: const Text('加载更多'),
                )
              else
                const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Text('已全部加载'),
          ],
        ),
      ),
    );
  }
}

/// Full-page failure state: a short message and a retry button.
/// The raw exception is never shown to the user; callers log it
/// with debugPrint instead.
class RetryState extends StatelessWidget {
  const RetryState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ]),
      );
}

/// Poster card for grids. [isDoulist] subjects render a list badge
/// instead of a rating, because Rexxar recommend items are mixed cards.
///
/// Desktop: hover slightly enlarges the card (1.02, non-compact
/// only) with a pointer cursor, and right-click opens the link menu
/// (copy link / open in browser). Mobile is unchanged.
class SubjectPosterCard extends StatefulWidget {
  const SubjectPosterCard({super.key, required this.subject, this.onTap, this.subtitle});

  final Subject subject;
  final VoidCallback? onTap;

  /// A second line shown instead of the rating (e.g. the
  /// celebrity page's "年份 · 角色"). Null keeps the rating row.
  final String? subtitle;

  @override
  State<SubjectPosterCard> createState() => _SubjectPosterCardState();
}

class _SubjectPosterCardState extends State<SubjectPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final pic = subjectImageUrl(subject, SettingsStore.instance.imageQuality);
    final isDesktop =
        Breakpoints.ofContext(context) != WindowSize.compact;
    return GestureDetector(
      onSecondaryTapUp: (details) => showLinkMenu(
        context,
        details.globalPosition,
        subjectWebUrl(subject),
      ),
      child: AnimatedScale(
        scale: _hovered && isDesktop ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) {
            if (hovered != _hovered) setState(() => _hovered = hovered);
          },
          hoverColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          mouseCursor: SystemMouseCursors.click,
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
                          // Decode at display size: without
                          // memCacheWidth the grid decoded every
                          // poster at its full original size.
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final dpr =
                                  MediaQuery.devicePixelRatioOf(context);
                              return CachedNetworkImage(
                                imageUrl: pic,
                                httpHeaders: doubanImageHeaders,
                                memCacheWidth: constraints.maxWidth.isFinite
                                    ? (constraints.maxWidth * dpr).round()
                                    : null,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorWidget: (context, url, error) => Center(
                                  child: Text(subject.title.isEmpty ? '?' : subject.title[0]),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(subject.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              if (widget.subtitle != null)
                Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)
              else if (subject.isDoulist)
                Text('豆列 · ${subject.doulistCount ?? ''} 条', style: Theme.of(context).textTheme.bodySmall)
              else if (subject.rating != null && subject.rating!.value > 0)
                RatingText(rating: subject.rating!)
              else
                Text('暂无评分', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact list row for collections and search results.
class SubjectRow extends StatelessWidget {
  const SubjectRow({super.key, required this.subject, this.trailing, this.onTap, this.subtitle});

  final Subject subject;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Override for the subtitle line (default: cardSubtitle ?? year
  /// ?? type). The celebrity works list uses it for the role text.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final pic = subjectImageUrl(subject, SettingsStore.instance.imageQuality);
    return GestureDetector(
      onSecondaryTapUp: (details) => showLinkMenu(
        context,
        details.globalPosition,
        subjectWebUrl(subject),
      ),
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        hoverColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
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
                // The cover is a fixed 56 wide; decode at that size.
                child: CachedNetworkImage(
                  imageUrl: pic,
                  httpHeaders: doubanImageHeaders,
                  memCacheWidth:
                      (56 * MediaQuery.devicePixelRatioOf(context)).round(),
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const Icon(Icons.book_outlined),
                ),
              ),
      ),
        title: Text(subject.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle ?? subject.cardSubtitle ?? subject.year ?? subject.type),
        trailing: trailing ??
            (subject.rating != null && subject.rating!.value > 0 ? RatingText(rating: subject.rating!) : null),
        onTap: onTap,
      ),
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

/// Pinned tab header for a CustomScrollView: exactly one tab-bar
/// height, so the bar sticks to the top without a gap or a clip
/// once the sections above it have scrolled away. The child is
/// usually a TabBar, or a Row of a TabBar plus a filter chip; it
/// must be 48 tall (kTextTabBarHeight). The background is opaque
/// so list content does not show through while pinned.
class PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  const PinnedTabBarDelegate(this.child);

  final Widget child;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(PinnedTabBarDelegate oldDelegate) => child != oldDelegate.child;
}

/// One grey placeholder bar for skeleton screens. Uses the
/// surface container color, so it adapts to light and dark mode.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.width, this.height = 14});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Skeleton for the recommend feed: three card-shaped placeholders
/// (author row, title, image), in place of the first-load spinner.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            const Row(
              children: [
                SkeletonBar(width: 32, height: 32),
                SizedBox(width: 8),
                SkeletonBar(width: 120),
              ],
            ),
            const SizedBox(height: 12),
            const SkeletonBar(width: 220, height: 18),
            const SizedBox(height: 8),
            const SkeletonBar(),
            const SizedBox(height: 8),
            const SkeletonBar(width: 180),
            const SizedBox(height: 12),
            const SkeletonBar(height: 160),
            if (i < 2) const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for the topic detail page: title, author row, and a
/// few body lines, in place of the first-load spinner.
class TopicDetailSkeleton extends StatelessWidget {
  const TopicDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBar(width: 260, height: 24),
        SizedBox(height: 12),
        Row(
          children: [
            SkeletonBar(width: 32, height: 32),
            SizedBox(width: 8),
            SkeletonBar(width: 180),
          ],
        ),
        SizedBox(height: 20),
        SkeletonBar(),
        SizedBox(height: 8),
        SkeletonBar(),
        SizedBox(height: 8),
        SkeletonBar(width: 220),
        SizedBox(height: 20),
        SkeletonBar(height: 180),
      ],
    );
  }
}

/// Centers a page's content at a readable width on desktop
/// (c001apk's reading pane centers detail at ~680-760; this uses
/// 720 for text lists). On narrow screens the cap is wider than
/// the viewport, so mobile layouts are unaffected.
class CenteredWidth extends StatelessWidget {
  const CenteredWidth({super.key, required this.child, this.maxWidth = Breakpoints.textMaxWidth});

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

/// Drag devices for horizontal rows: the framework default (touch,
/// stylus, trackpad, unknown) plus mouse. The default
/// ScrollBehavior.dragDevices has no mouse (verified in the Flutter
/// 3.47 SDK source), so a plain SingleChildScrollView cannot be
/// dragged with a mouse on desktop at all.
const kHorizontalDragDevices = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// Single-line horizontal row with desktop affordances: mouse drag,
/// a scrollbar, and left/right arrow buttons that appear only when
/// the row can scroll that way. Mobile (<600 content width) keeps
/// touch scrolling only — no arrows, no scrollbar.
///
/// The mouse wheel is deliberately NOT converted to horizontal
/// scrolling here: a plain wheel scrolls the page vertically, and
/// Shift+wheel already scrolls horizontal rows (the framework flips
/// axes while Shift is held), so converting it would scroll both the
/// row and the page at once. The desktop threshold is
/// Breakpoints.medium (600), the shell's mobile/desktop split.
class HScrollRow extends StatefulWidget {
  const HScrollRow({super.key, required this.children, this.spacing = 8});

  final List<Widget> children;
  final double spacing;

  @override
  State<HScrollRow> createState() => _HScrollRowState();
}

class _HScrollRowState extends State<HScrollRow> {
  final _controller = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void didUpdateWidget(HScrollRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final canLeft = position.pixels > 0;
    final canRight = position.pixels < position.maxScrollExtent;
    if (canLeft != _canLeft || canRight != _canRight) {
      setState(() {
        _canLeft = canLeft;
        _canRight = canRight;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Overlay arrow: it floats over the row's edge instead of
  /// taking layout space, so appearing/disappearing never makes
  /// the content jump. Only shown while the mouse hovers the row.
  Widget _edgeArrow(bool left) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        child: Center(
          child: AnimatedOpacity(
            opacity: _hover ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: IgnorePointer(
              ignoring: !_hover,
              child: Material(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                elevation: 2,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
                  tooltip: left ? '向左滚动' : '向右滚动',
                  onPressed: () => _scrollBy(left ? -300 : 300),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = Breakpoints.of(constraints.maxWidth) != WindowSize.compact;
        final row = NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: kHorizontalDragDevices,
              scrollbars: false,
            ),
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: isDesktop && _hover, // scrollbar only on hover too
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.children.length; i++) ...[
                      if (i > 0) SizedBox(width: widget.spacing),
                      widget.children[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        if (!isDesktop) return row;
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Stack(children: [
            row,
            if (_canLeft) _edgeArrow(true),
            if (_canRight) _edgeArrow(false),
          ]),
        );
      },
    );
  }
}
