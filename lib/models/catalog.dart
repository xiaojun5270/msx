import 'json.dart';
import 'track.dart';

/// Mirrors Swift `FeedItem`.
class FeedItem {
  String id;
  String? platform;
  String? type;
  String? title;
  String? coverUrl;
  String? artworkUrl;
  String? avatarUrl;
  String? source;
  List<Track>? tracks;
  String? chartId;
  String? motionUrl;

  FeedItem({
    required this.id,
    this.platform,
    this.type,
    this.title,
    this.coverUrl,
    this.artworkUrl,
    this.avatarUrl,
    this.source,
    this.tracks,
    this.chartId,
    this.motionUrl,
  });

  String? get cover => coverUrl ?? artworkUrl ?? avatarUrl;

  factory FeedItem.fromJson(Map<String, dynamic> c) => FeedItem(
        id: c['id'] != null ? flexId(c['id']) : Track_uuid(),
        platform: asString(c['platform']),
        type: asString(c['type']),
        title: asString(c['title']),
        coverUrl: asString(c['coverUrl']),
        artworkUrl: asString(c['artworkUrl']),
        avatarUrl: asString(c['avatarUrl']),
        source: asString(c['source']),
        tracks: c['tracks'] is List
            ? decodeList(c['tracks'], Track.fromJson)
            : null,
        chartId: asMap(c['meta']) != null
            ? asString(asMap(c['meta'])!['chartId'])
            : null,
        motionUrl: asString(c['motionUrl']),
      );
}

// Helper so FeedItem can generate ids without exposing Track's private ctor.
String Track_uuid() =>
    'feed-${DateTime.now().microsecondsSinceEpoch}';

/// Mirrors Swift `HomeShelf`.
class HomeShelf {
  final String? title;
  final String? more;
  final List<FeedItem>? items;
  final List<Track>? tracks;
  final List<HomeShelfSection>? sections;
  final bool? refreshing;
  final double? retryAfterMs;

  const HomeShelf({
    this.title,
    this.more,
    this.items,
    this.tracks,
    this.sections,
    this.refreshing,
    this.retryAfterMs,
  });

  factory HomeShelf.fromJson(Map<String, dynamic> c) => HomeShelf(
        title: asString(c['title']),
        more: asString(c['more']),
        items: c['items'] is List ? decodeList(c['items'], FeedItem.fromJson) : null,
        tracks: c['tracks'] is List ? decodeList(c['tracks'], Track.fromJson) : null,
        sections: c['sections'] is List
            ? decodeList(c['sections'], HomeShelfSection.fromJson)
            : null,
        refreshing: asBool(c['refreshing']),
        retryAfterMs: asDouble(c['retryAfterMs']),
      );
}

class HomeShelfSection {
  final String id;
  final String? title;
  final String? artist;
  final List<FeedItem> items;

  const HomeShelfSection({
    required this.id,
    this.title,
    this.artist,
    this.items = const [],
  });

  factory HomeShelfSection.fromJson(Map<String, dynamic> c) => HomeShelfSection(
        id: c['id'] != null ? flexId(c['id']) : Track_uuid(),
        title: asString(c['title']),
        artist: asString(c['artist']),
        items: decodeList(c['items'], FeedItem.fromJson),
      );
}

/// Mirrors Swift `Playlist`.
class Playlist {
  String id;
  String? name;
  String? title;
  String? platform;
  String? coverUrl;
  String? artworkUrl;
  List<String>? mosaicUrls;
  String? listKind;
  String? kind;
  int? trackCount;
  List<Track>? tracks;
  String? source;
  String? motionUrl;
  bool? ingestEnabled;
  String? ingestCron;
  String? ingestQuality;
  String? createdAt;
  String? updatedAt;
  String? addedAt;

  Playlist({
    required this.id,
    this.name,
    this.title,
    this.platform,
    this.coverUrl,
    this.artworkUrl,
    this.mosaicUrls,
    this.listKind,
    this.kind,
    this.trackCount,
    this.tracks,
    this.source,
    this.motionUrl,
    this.ingestEnabled,
    this.ingestCron,
    this.ingestQuality,
    this.createdAt,
    this.updatedAt,
    this.addedAt,
  });

  String get displayTitle => title ?? name ?? '歌单';
  String? get cover => coverUrl ?? artworkUrl ?? (artTiles.isNotEmpty ? artTiles.first : null);

  List<String> get artTiles {
    final urls = (mosaicUrls ?? []).where((s) => s.isNotEmpty).toList();
    if (urls.isNotEmpty) return urls;
    final seen = <String>{};
    final out = <String>[];
    for (final t in tracks ?? const <Track>[]) {
      final c = t.cover;
      if (c == null || c.isEmpty || !seen.add(c)) continue;
      out.add(c);
      if (out.length >= 9) break;
    }
    return out;
  }

  factory Playlist.fromJson(Map<String, dynamic> c) => Playlist(
        id: c['id'] != null ? flexId(c['id']) : Track_uuid(),
        name: asString(c['name']),
        title: asString(c['title']),
        platform: asString(c['platform']),
        coverUrl: asString(c['coverUrl']),
        artworkUrl: asString(c['artworkUrl']),
        mosaicUrls: c['mosaicUrls'] is List ? flexStringList(c['mosaicUrls']) : null,
        listKind: asString(c['listKind']),
        kind: asString(c['kind']),
        trackCount: asInt(c['trackCount']),
        tracks: c['tracks'] is List ? decodeList(c['tracks'], Track.fromJson) : null,
        source: asString(c['source']),
        motionUrl: asString(c['motionUrl']),
        ingestEnabled: asBool(c['ingestEnabled']),
        ingestCron: asString(c['ingestCron']),
        ingestQuality: asString(c['ingestQuality']),
        createdAt: asString(c['createdAt']),
        updatedAt: asString(c['updatedAt']),
        addedAt: asString(c['addedAt']),
      );
}

/// Mirrors Swift `Album`.
class Album {
  final String id;
  final String platform;
  final String? title;
  final List<String> artists;
  final String? artworkUrl;
  final String? coverUrl;
  final List<Track>? tracks;
  final String? motionUrl;
  final String? addedAt;

  const Album({
    required this.id,
    required this.platform,
    this.title,
    this.artists = const [],
    this.artworkUrl,
    this.coverUrl,
    this.tracks,
    this.motionUrl,
    this.addedAt,
  });

  String? get cover => artworkUrl ?? coverUrl;
  String get displayTitle => title ?? '专辑';
  String get artistText => artists.join(' / ');

  factory Album.fromJson(Map<String, dynamic> c) => Album(
        id: c['id'] != null ? flexId(c['id']) : Track_uuid(),
        platform: asStringOr(c['platform'], ''),
        title: asString(c['title']),
        artists: flexStringList(c['artists']),
        artworkUrl: asString(c['artworkUrl']),
        coverUrl: asString(c['coverUrl']),
        tracks: c['tracks'] is List ? decodeList(c['tracks'], Track.fromJson) : null,
        motionUrl: asString(c['motionUrl']),
        addedAt: asString(c['addedAt']),
      );
}

/// Mirrors Swift `Artist`.
class Artist {
  final String id;
  final String platform;
  final String? name;
  final String? title;
  final String? avatarUrl;
  final String? artworkUrl;
  final String? coverUrl;
  final List<Track>? tracks;
  final List<Album>? albums;

  const Artist({
    required this.id,
    required this.platform,
    this.name,
    this.title,
    this.avatarUrl,
    this.artworkUrl,
    this.coverUrl,
    this.tracks,
    this.albums,
  });

  String get displayName => name ?? title ?? '艺人';
  String? get cover => avatarUrl ?? artworkUrl ?? coverUrl;

  factory Artist.fromJson(Map<String, dynamic> c) => Artist(
        id: c['id'] != null ? flexId(c['id']) : Track_uuid(),
        platform: asStringOr(c['platform'], ''),
        name: asString(c['name']),
        title: asString(c['title']),
        avatarUrl: asString(c['avatarUrl']),
        artworkUrl: asString(c['artworkUrl']),
        coverUrl: asString(c['coverUrl']),
        tracks: c['tracks'] is List ? decodeList(c['tracks'], Track.fromJson) : null,
        albums: c['albums'] is List ? decodeList(c['albums'], Album.fromJson) : null,
      );
}

/// Mirrors Swift `Genre`.
class Genre {
  final String id;
  final String name;
  final String platform;
  final String? parentId;
  final int? count;

  const Genre({
    required this.id,
    required this.name,
    this.platform = 'catalog',
    this.parentId,
    this.count,
  });

  factory Genre.fromJson(Map<String, dynamic> c) => Genre(
        id: c['id'] != null ? flexId(c['id']) : '',
        name: asStringOr(c['name'], ''),
        platform: asStringOr(c['platform'], ''),
        parentId: flexIdOrNull(c['parentId']),
        count: asInt(c['count']),
      );

  /// Stable fallback catalog — mirrors Swift `commonCatalog`.
  static final List<Genre> commonCatalog = <(String, String)>[
    ('pop', '流行'), ('rock', '摇滚'), ('hip-hop', '嘻哈'), ('rap', '说唱'),
    ('rnb', 'R&B'), ('electronic', '电子'), ('folk', '民谣'), ('gu-feng', '古风'),
    ('classical', '古典'), ('jazz', '爵士'), ('blues', '蓝调'), ('country', '乡村'),
    ('metal', '金属'), ('punk', '朋克'), ('soul', '灵魂乐'), ('reggae', '雷鬼'),
    ('world', '世界音乐'), ('easy-listening', '轻音乐'), ('instrumental', '纯音乐'),
    ('soundtrack', '影视原声'), ('acg', 'ACG'), ('chinese-pop', '华语流行'),
    ('japanese-pop', '日语流行'), ('korean-pop', '韩语流行'),
  ].map((e) => Genre(id: 'common:${e.$1}', name: e.$2)).toList();
}

class GenreListResult {
  final List<Genre> items;
  final List<String> platforms;
  const GenreListResult({this.items = const [], this.platforms = const []});
  factory GenreListResult.fromJson(Map<String, dynamic> c) => GenreListResult(
        items: decodeList(c['items'], Genre.fromJson),
        platforms: flexStringList(c['platforms']),
      );
}

class GenreResult {
  final Genre? genre;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> tracks;
  final List<Track> eraTracks;
  final List<Track> annualTracks;
  final List<Album> classicAlbums;
  final bool? hasMore;
  final int? nextOffset;

  const GenreResult({
    this.genre,
    this.artists = const [],
    this.albums = const [],
    this.tracks = const [],
    this.eraTracks = const [],
    this.annualTracks = const [],
    this.classicAlbums = const [],
    this.hasMore,
    this.nextOffset,
  });

  factory GenreResult.fromJson(Map<String, dynamic> c) => GenreResult(
        genre: asMap(c['genre']) != null ? Genre.fromJson(asMap(c['genre'])!) : null,
        artists: decodeList(c['artists'], Artist.fromJson),
        albums: decodeList(c['albums'], Album.fromJson),
        tracks: decodeList(c['tracks'], Track.fromJson),
        eraTracks: decodeList(c['eraTracks'], Track.fromJson),
        annualTracks: decodeList(c['annualTracks'], Track.fromJson),
        classicAlbums: decodeList(c['classicAlbums'], Album.fromJson),
        hasMore: asBool(c['hasMore']),
        nextOffset: asInt(c['nextOffset']),
      );
}

/// Mirrors Swift `SearchResult`.
class SearchResult {
  final String? rawQuery;
  final String? intent;
  final ShareHit? parsed;
  final List<SearchSection>? sections;
  final List<Track>? tracks;
  final List<Album>? albums;
  final List<Artist>? artists;
  final List<Playlist>? playlists;
  final int? offset;
  final int? limit;
  final bool? hasMore;
  final int? nextOffset;
  final List<SearchFailure>? errors;

  const SearchResult({
    this.rawQuery,
    this.intent,
    this.parsed,
    this.sections,
    this.tracks,
    this.albums,
    this.artists,
    this.playlists,
    this.offset,
    this.limit,
    this.hasMore,
    this.nextOffset,
    this.errors,
  });

  String? get errorMessage {
    if (errors == null || errors!.isEmpty) return null;
    return errors!
        .map((e) => e.error.isEmpty ? '搜索失败' : e.error)
        .join('\n');
  }

  bool get isEmpty =>
      (tracks ?? const []).isEmpty &&
      (playlists ?? const []).isEmpty &&
      (albums ?? const []).isEmpty &&
      (artists ?? const []).isEmpty;

  factory SearchResult.fromJson(Map<String, dynamic> c) => SearchResult(
        rawQuery: asString(c['rawQuery']),
        intent: asString(c['intent']),
        parsed: asMap(c['parsed']) != null ? ShareHit.fromJson(asMap(c['parsed'])!) : null,
        sections: c['sections'] is List ? decodeList(c['sections'], SearchSection.fromJson) : null,
        tracks: c['tracks'] is List ? decodeList(c['tracks'], Track.fromJson) : null,
        albums: c['albums'] is List ? decodeList(c['albums'], Album.fromJson) : null,
        artists: c['artists'] is List ? decodeList(c['artists'], Artist.fromJson) : null,
        playlists: c['playlists'] is List ? decodeList(c['playlists'], Playlist.fromJson) : null,
        offset: asInt(c['offset']),
        limit: asInt(c['limit']),
        hasMore: asBool(c['hasMore']),
        nextOffset: asInt(c['nextOffset']),
        errors: c['errors'] is List ? decodeList(c['errors'], SearchFailure.fromJson) : null,
      );
}

class SearchFailure {
  final String? platform;
  final String error;
  const SearchFailure({this.platform, this.error = ''});
  factory SearchFailure.fromJson(Map<String, dynamic> c) =>
      SearchFailure(platform: asString(c['platform']), error: asStringOr(c['error'], ''));
}

class SearchSection {
  final String id;
  final String? title;
  final String? kind;
  final int? count;
  const SearchSection({required this.id, this.title, this.kind, this.count});
  factory SearchSection.fromJson(Map<String, dynamic> c) => SearchSection(
        id: c['id'] != null ? flexId(c['id']) : '',
        title: asString(c['title']),
        kind: asString(c['kind']),
        count: asInt(c['count']),
      );
}

class ShareHit {
  final String? kind;
  final String? platform;
  final String? id;
  const ShareHit({this.kind, this.platform, this.id});
  factory ShareHit.fromJson(Map<String, dynamic> c) => ShareHit(
        kind: asString(c['kind']),
        platform: asString(c['platform']),
        id: asString(c['id']),
      );
}
