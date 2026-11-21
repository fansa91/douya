/// Parses a Douban deep link (douban://...) into one of five results.
/// Unknown shapes return [UnknownLink]; the UI hides those instead of
/// showing a button that does nothing. The raw `uri` is kept on the
/// models (HotSearchBoardItem, LandingItem) so new shapes can be
/// supported later without re-fetching.
///
/// Verified shapes (real URIs from test/fixtures, 2026-11-21):
/// - search: douban://douban.com/search/result?q=%23...%23
///   (hot search board)
/// - board: douban://douban.com/subject_collection/movie_hot_gaia
///   (landing 专题）
/// - tag: douban://douban.com/subject/recommendation/movie?tag=喜剧,电影
///   and douban://douban.com/tv/tag?q=中国大陆,电视剧 (landing
///   类型/地区/特色/播出平台）
/// - subject: douban://douban.com/movie/1292052 (the standard
///   deep-link shape; no such URI has appeared in a fixture yet)
sealed class DeepLink {
  const DeepLink();
}

/// A ranking board (subject_collection id, slug or numeric).
class BoardLink extends DeepLink {
  const BoardLink(this.boardId);

  final String boardId;
}

/// A multi-dim tag search: `endpoint` is 'movie' or 'tv', `query` is
/// the tag-search q with the form suffix stripped (the form is not a
/// tag: sending it returns 0 items). `groupType` is the landing
/// section the chip came from (类型/地区/特色/播出平台）; it is the
/// FacetedView initial-selection key, and stays as-is for groups the
/// tag search has no dimension for (播出平台）.
class TagSearchLink extends DeepLink {
  const TagSearchLink(this.endpoint, this.query, {this.groupType = ''});

  final String endpoint;
  final String query;
  final String groupType;
}

/// A subject detail page.
class SubjectLink extends DeepLink {
  const SubjectLink(this.type, this.id);

  final String type;
  final String id;
}

/// A keyword search. The #...# markers are the topic's own
/// delimiters, stripped before searching.
class SearchLink extends DeepLink {
  const SearchLink(this.keyword);

  final String keyword;
}

/// An unrecognised shape. Callers hide it.
class UnknownLink extends DeepLink {
  const UnknownLink();
}

/// Form values (the 形式 dimension). They are not tags: a q
/// containing one returns 0 items, so they are stripped from tag
/// values before the query is built.
const _formValues = {'电影', '电视剧', '综艺', '动画', '纪录片', '短片'};

/// Form values that are never a genre tag either (电影/电视剧). The
/// other form values (综艺/动画/纪录片/短片) are also type values, so
/// a lone one is a real tag, not a form suffix.
const _formOnlyValues = {'电影', '电视剧'};

/// Strips a trailing form segment from a comma-joined tag value
/// ("喜剧,电影" -> "喜剧", "动漫" -> "动漫"). A form is only a suffix:
/// a lone value is kept when it is also a genre (纪录片/动画), and
/// dropped only when it is a form-only value (电影/电视剧), which the
/// backend returns 0 items for.
String _stripForm(String value) {
  final parts = value.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.length > 1 && _formValues.contains(parts.last)) parts.removeLast();
  if (parts.length == 1 && _formOnlyValues.contains(parts.first)) return '';
  return parts.join(',');
}

DeepLink parseDeepLink(String uri, {String groupType = ''}) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'douban') return const UnknownLink();
  if (parsed.host != 'douban.com') return const UnknownLink();
  final segments = parsed.pathSegments;
  if (segments.isEmpty) return const UnknownLink();

  // Search: /search/result?q=%23...%23
  if (segments.length == 2 && segments[0] == 'search' && segments[1] == 'result') {
    final keyword = (parsed.queryParameters['q'] ?? '').replaceAll('#', '').trim();
    if (keyword.isEmpty) return const UnknownLink();
    return SearchLink(keyword);
  }

  // Board: /subject_collection/{id}
  if (segments.length == 2 && segments[0] == 'subject_collection') {
    final id = segments[1];
    if (id.isEmpty) return const UnknownLink();
    return BoardLink(id);
  }

  // Tag search, recommendation form:
  // /subject/recommendation/{movie|tv}?tag={value},{form}
  if (segments.length == 3 && segments[0] == 'subject' && segments[1] == 'recommendation') {
    final endpoint = segments[2];
    if (endpoint != 'movie' && endpoint != 'tv') return const UnknownLink();
    final query = _stripForm(parsed.queryParameters['tag'] ?? '');
    if (query.isEmpty) return const UnknownLink();
    return TagSearchLink(endpoint, query, groupType: groupType);
  }

  // Tag search, direct form: /{movie|tv}/tag?q={value},{form}
  if (segments.length == 2 && segments[1] == 'tag' && (segments[0] == 'movie' || segments[0] == 'tv')) {
    final query = _stripForm(parsed.queryParameters['q'] ?? '');
    if (query.isEmpty) return const UnknownLink();
    return TagSearchLink(segments[0], query, groupType: groupType);
  }

  // Subject: /{movie|tv|book|music}/{id}
  if (segments.length == 2 &&
      (segments[0] == 'movie' || segments[0] == 'tv' || segments[0] == 'book' || segments[0] == 'music')) {
    final id = segments[1];
    if (id.isEmpty) return const UnknownLink();
    return SubjectLink(segments[0], id);
  }

  return const UnknownLink();
}
