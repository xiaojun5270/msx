import 'json.dart';

/// A server capability, not a client-side provider alias. Pass `id` verbatim.
/// Mirrors Swift `SearchTarget`.
class SearchTarget {
  final String id;
  final String name;
  final String platform;
  final String kind;

  const SearchTarget({
    this.id = '',
    this.name = '',
    this.platform = '',
    this.kind = '',
  });

  bool get isAvailable =>
      id.trim().isNotEmpty && name.isNotEmpty && (kind == 'platform' || kind == 'source');

  factory SearchTarget.fromJson(Map<String, dynamic> c) => SearchTarget(
        id: asStringOr(c['id'], ''),
        name: asStringOr(c['name'], ''),
        platform: asStringOr(c['platform'], ''),
        kind: asStringOr(c['kind'], ''),
      );
}

class SearchTargetSnapshot {
  final List<SearchTarget> targets;
  const SearchTargetSnapshot({this.targets = const []});
  factory SearchTargetSnapshot.fromJson(Map<String, dynamic> c) => SearchTargetSnapshot(
        targets: decodeList(c['targets'], SearchTarget.fromJson),
      );
}

/// Persisted search history + recently-used targets. Mirrors Swift `SearchActivity`.
class SearchActivity {
  List<String> queries;
  List<String> recentTargetIds;

  SearchActivity({List<String>? queries, List<String>? recentTargetIds})
      : queries = queries ?? [],
        recentTargetIds = recentTargetIds ?? [];

  void record(String query, {String? targetId}) {
    final text = query.trim();
    if (text.isEmpty) return;
    queries.removeWhere((q) => q.toLowerCase() == text.toLowerCase());
    queries.insert(0, text);
    if (queries.length > 20) queries = queries.sublist(0, 20);
    if (targetId != null && targetId.isNotEmpty) {
      recentTargetIds.remove(targetId);
      recentTargetIds.insert(0, targetId);
      if (recentTargetIds.length > 20) recentTargetIds = recentTargetIds.sublist(0, 20);
    }
  }

  void remove(String query) => queries.removeWhere((q) => q == query);

  Map<String, dynamic> toJson() => {'queries': queries, 'recentTargetIDs': recentTargetIds};

  factory SearchActivity.fromJson(Map<String, dynamic> c) => SearchActivity(
        queries: flexStringList(c['queries']),
        recentTargetIds: flexStringList(c['recentTargetIDs']),
      );
}
