import 'json.dart';
import 'catalog.dart';
import 'track.dart';

// LX custom sources ----------------------------------------------------------

class LxSourcesBox {
  final bool? enabled;
  final List<LxSourceSummary>? sources;
  const LxSourcesBox({this.enabled, this.sources});
  factory LxSourcesBox.fromJson(Map<String, dynamic> c) => LxSourcesBox(
        enabled: asBool(c['enabled']),
        sources: c['sources'] is List ? decodeList(c['sources'], LxSourceSummary.fromJson) : null,
      );
}

class LxSourceSummary {
  final String id;
  final String? filename;
  final String? name;
  final String? description;
  final String? version;
  final String? author;
  final String? homepage;
  final bool? enabled;
  final List<String>? supportedSources;
  final String? createdAt;
  final String? updatedAt;
  final String? status;
  final String? error;
  const LxSourceSummary({
    this.id = '',
    this.filename,
    this.name,
    this.description,
    this.version,
    this.author,
    this.homepage,
    this.enabled,
    this.supportedSources,
    this.createdAt,
    this.updatedAt,
    this.status,
    this.error,
  });
  factory LxSourceSummary.fromJson(Map<String, dynamic> c) => LxSourceSummary(
        id: c['id'] != null ? flexId(c['id']) : '',
        filename: asString(c['filename']),
        name: asString(c['name']),
        description: asString(c['description']),
        version: asString(c['version']),
        author: asString(c['author']),
        homepage: asString(c['homepage']),
        enabled: asBool(c['enabled']),
        supportedSources: c['supportedSources'] != null ? flexStringList(c['supportedSources']) : null,
        createdAt: asString(c['createdAt']),
        updatedAt: asString(c['updatedAt']),
        status: asString(c['status']),
        error: asString(c['error']),
      );
}

class LxSourceValidation {
  final bool? valid;
  final LxSourceMetadata? metadata;
  final List<String>? supportedSources;
  const LxSourceValidation({this.valid, this.metadata, this.supportedSources});
  factory LxSourceValidation.fromJson(Map<String, dynamic> c) => LxSourceValidation(
        valid: asBool(c['valid']),
        metadata: asMap(c['metadata']) != null ? LxSourceMetadata.fromJson(asMap(c['metadata'])!) : null,
        supportedSources: c['supportedSources'] != null ? flexStringList(c['supportedSources']) : null,
      );
}

class LxSourceMetadata {
  final String? name;
  final String? description;
  final String? version;
  final String? author;
  final String? homepage;
  const LxSourceMetadata({this.name, this.description, this.version, this.author, this.homepage});
  factory LxSourceMetadata.fromJson(Map<String, dynamic> c) => LxSourceMetadata(
        name: asString(c['name']),
        description: asString(c['description']),
        version: asString(c['version']),
        author: asString(c['author']),
        homepage: asString(c['homepage']),
      );
}

// Search history --------------------------------------------------------------

class SearchHistoryBox {
  final List<SearchHistoryItem>? items;
  const SearchHistoryBox({this.items});
  factory SearchHistoryBox.fromJson(Map<String, dynamic> c) => SearchHistoryBox(
        items: c['items'] is List ? decodeList(c['items'], SearchHistoryItem.fromJson) : null,
      );
}

class SearchHistoryItem {
  final String id;
  final String query;
  final String? platform;
  final String? intent;
  final String? updatedAt;
  final SearchHistorySummary? resultSummary;
  const SearchHistoryItem({
    required this.id,
    this.query = '',
    this.platform,
    this.intent,
    this.updatedAt,
    this.resultSummary,
  });
  factory SearchHistoryItem.fromJson(Map<String, dynamic> c) => SearchHistoryItem(
        id: c['id'] != null ? flexId(c['id']) : '',
        query: asStringOr(c['query'], ''),
        platform: asString(c['platform']),
        intent: asString(c['intent']),
        updatedAt: asString(c['updatedAt']),
        resultSummary: asMap(c['resultSummary']) != null
            ? SearchHistorySummary.fromJson(asMap(c['resultSummary'])!)
            : null,
      );
}

class SearchHistorySummary {
  final int? tracks;
  final int? playlists;
  final int? albums;
  final int? artists;
  const SearchHistorySummary({this.tracks, this.playlists, this.albums, this.artists});
  factory SearchHistorySummary.fromJson(Map<String, dynamic> c) => SearchHistorySummary(
        tracks: asInt(c['tracks']),
        playlists: asInt(c['playlists']),
        albums: asInt(c['albums']),
        artists: asInt(c['artists']),
      );
}

// Playlist health -------------------------------------------------------------

class PlaylistHealthSummary {
  final double? checked;
  final double? unavailable;
  final double? vip;
  final double? lowQuality;
  final double? elapsedMs;
  const PlaylistHealthSummary({this.checked, this.unavailable, this.vip, this.lowQuality, this.elapsedMs});
  factory PlaylistHealthSummary.fromJson(Map<String, dynamic> c) => PlaylistHealthSummary(
        checked: asDouble(c['checked']),
        unavailable: asDouble(c['unavailable']),
        vip: asDouble(c['vip']),
        lowQuality: asDouble(c['low_quality']),
        elapsedMs: asDouble(c['elapsedMs']),
      );
}

class PlaylistHealthConfig {
  final bool? enabled;
  final String? cron;
  final double? minBitrate;
  final bool? preferLossless;
  final List<String>? replacementPlatforms;
  final String? lastRunAt;
  final String? lastStatus;
  final String? lastError;
  final PlaylistHealthSummary? lastSummary;
  const PlaylistHealthConfig({
    this.enabled,
    this.cron,
    this.minBitrate,
    this.preferLossless,
    this.replacementPlatforms,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.lastSummary,
  });
  factory PlaylistHealthConfig.fromJson(Map<String, dynamic> c) => PlaylistHealthConfig(
        enabled: asBool(c['enabled']),
        cron: asString(c['cron']),
        minBitrate: asDouble(c['minBitrate']),
        preferLossless: asBool(c['preferLossless']),
        replacementPlatforms: c['replacementPlatforms'] != null ? flexStringList(c['replacementPlatforms']) : null,
        lastRunAt: asString(c['lastRunAt']),
        lastStatus: asString(c['lastStatus']),
        lastError: asString(c['lastError']),
        lastSummary: asMap(c['lastSummary']) != null ? PlaylistHealthSummary.fromJson(asMap(c['lastSummary'])!) : null,
      );
}

// QR login --------------------------------------------------------------------

enum QRLoginType { qq, wechat }

QRLoginType? _qrType(dynamic v) {
  switch (asString(v)) {
    case 'qq':
      return QRLoginType.qq;
    case 'wechat':
      return QRLoginType.wechat;
    default:
      return null;
  }
}

class QRStart {
  final QRLoginType? loginType;
  final String? unikey;
  final String? qrimg;
  final double? expiresAt;
  final String? message;
  final double? retryAfterMs;
  const QRStart({this.loginType, this.unikey, this.qrimg, this.expiresAt, this.message, this.retryAfterMs});
  factory QRStart.fromJson(Map<String, dynamic> c) => QRStart(
        loginType: _qrType(c['loginType']),
        unikey: asString(c['unikey']),
        qrimg: asString(c['qrimg']),
        expiresAt: asDouble(c['expiresAt']),
        message: asString(c['message']),
        retryAfterMs: asDouble(c['retryAfterMs']),
      );
}

class QRPoll {
  final QRLoginType? loginType;
  final bool? done;
  final bool? expired;
  final bool? cancelled;
  final String? status;
  final String? message;
  final double? retryAfterMs;
  const QRPoll({this.loginType, this.done, this.expired, this.cancelled, this.status, this.message, this.retryAfterMs});
  factory QRPoll.fromJson(Map<String, dynamic> c) => QRPoll(
        loginType: _qrType(c['loginType']),
        done: asBool(c['done']),
        expired: asBool(c['expired']),
        cancelled: asBool(c['cancelled']),
        status: asString(c['status']),
        message: asString(c['message']),
        retryAfterMs: asDouble(c['retryAfterMs']),
      );
}

// Services / version / cookiecloud / schedules --------------------------------

class ServiceInfo {
  final String? name;
  final String? hint;
  final String? envUrl;
  final String? customUrl;
  final String? effectiveUrl;
  final String? source;
  final bool? testable;
  const ServiceInfo({this.name, this.hint, this.envUrl, this.customUrl, this.effectiveUrl, this.source, this.testable});
  factory ServiceInfo.fromJson(Map<String, dynamic> c) => ServiceInfo(
        name: asString(c['name']),
        hint: asString(c['hint']),
        envUrl: asString(c['envUrl']),
        customUrl: asString(c['customUrl']),
        effectiveUrl: asString(c['effectiveUrl']),
        source: asString(c['source']),
        testable: asBool(c['testable']),
      );
}

class ServicesBox {
  final Map<String, ServiceInfo>? services;
  const ServicesBox({this.services});
  factory ServicesBox.fromJson(Map<String, dynamic> c) {
    final raw = asMap(c['services']);
    return ServicesBox(
      services: raw?.map((k, v) => MapEntry(k, ServiceInfo.fromJson(asMap(v) ?? {}))),
    );
  }
}

class VersionInfo {
  final String? name;
  final String? version;
  const VersionInfo({this.name, this.version});
  factory VersionInfo.fromJson(Map<String, dynamic> c) =>
      VersionInfo(name: asString(c['name']), version: asString(c['version']));
}

class CookieCloudConfig {
  final bool? enabled;
  final String? url;
  final String? uuid;
  final bool? passwordConfigured;
  final String? cryptoType;
  final double? refreshSeconds;
  final String? lastSyncAt;
  final int? lastCookieCount;
  final String? lastError;
  const CookieCloudConfig({
    this.enabled,
    this.url,
    this.uuid,
    this.passwordConfigured,
    this.cryptoType,
    this.refreshSeconds,
    this.lastSyncAt,
    this.lastCookieCount,
    this.lastError,
  });
  factory CookieCloudConfig.fromJson(Map<String, dynamic> c) => CookieCloudConfig(
        enabled: asBool(c['enabled']),
        url: asString(c['url']),
        uuid: asString(c['uuid']),
        passwordConfigured: asBool(c['passwordConfigured']),
        cryptoType: asString(c['cryptoType']),
        refreshSeconds: asDouble(c['refreshSeconds']),
        lastSyncAt: asString(c['lastSyncAt']),
        lastCookieCount: asInt(c['lastCookieCount']),
        lastError: asString(c['lastError']),
      );
}

class ScheduleRow {
  final String platform;
  final bool? enabled;
  final String? cron;
  final List<String>? tasks;
  final double? ttlSeconds;
  final double? chartLimit;
  final String? lastRunAt;
  final String? lastStatus;
  final String? lastError;
  const ScheduleRow({
    this.platform = '',
    this.enabled,
    this.cron,
    this.tasks,
    this.ttlSeconds,
    this.chartLimit,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
  });
  String get id => platform;
  factory ScheduleRow.fromJson(Map<String, dynamic> c) => ScheduleRow(
        platform: asStringOr(c['platform'], ''),
        enabled: asBool(c['enabled']),
        cron: asString(c['cron']),
        tasks: c['tasks'] != null ? flexStringList(c['tasks']) : null,
        ttlSeconds: asDouble(c['ttlSeconds']),
        chartLimit: asDouble(c['chartLimit']),
        lastRunAt: asString(c['lastRunAt']),
        lastStatus: asString(c['lastStatus']),
        lastError: asString(c['lastError']),
      );
}

class SchedulesBox {
  final List<ScheduleRow>? schedules;
  const SchedulesBox({this.schedules});
  factory SchedulesBox.fromJson(Map<String, dynamic> c) => SchedulesBox(
        schedules: c['schedules'] is List ? decodeList(c['schedules'], ScheduleRow.fromJson) : null,
      );
}

class ScheduleBox {
  final ScheduleRow? schedule;
  const ScheduleBox({this.schedule});
  factory ScheduleBox.fromJson(Map<String, dynamic> c) => ScheduleBox(
        schedule: asMap(c['schedule']) != null ? ScheduleRow.fromJson(asMap(c['schedule'])!) : null,
      );
}

// Server logs -----------------------------------------------------------------

class ServerLog {
  final String id;
  final String level;
  final String scope;
  final String message;
  final dynamic meta;
  final String createdAt;
  const ServerLog({
    required this.id,
    this.level = '',
    this.scope = '',
    this.message = '',
    this.meta,
    this.createdAt = '',
  });
  factory ServerLog.fromJson(Map<String, dynamic> c) => ServerLog(
        id: c['id'] != null ? flexId(c['id']) : '',
        level: asStringOr(c['level'], ''),
        scope: asStringOr(c['scope'], ''),
        message: asStringOr(c['message'], ''),
        meta: c['meta'],
        createdAt: asStringOr(c['createdAt'], ''),
      );

  String get metaPretty => _pretty(meta);
  static String _pretty(dynamic v) {
    if (v == null) return '';
    if (v is bool || v is num || v is String) return v.toString();
    if (v is List) return v.map(_pretty).join(', ');
    if (v is Map) return v.entries.map((e) => '${e.key}: ${_pretty(e.value)}').join('\n');
    return v.toString();
  }
}

class ServerLogsBox {
  final List<ServerLog>? items;
  final int? total;
  const ServerLogsBox({this.items, this.total});
  factory ServerLogsBox.fromJson(Map<String, dynamic> c) => ServerLogsBox(
        items: c['items'] is List ? decodeList(c['items'], ServerLog.fromJson) : null,
        total: asInt(c['total']),
      );
}

// Discover / recommend / boxes ------------------------------------------------

class RecommendBox {
  final List<FeedItem>? feed;
  final List<FeedItem>? items;
  const RecommendBox({this.feed, this.items});
  factory RecommendBox.fromJson(Map<String, dynamic> c) => RecommendBox(
        feed: c['feed'] is List ? decodeList(c['feed'], FeedItem.fromJson) : null,
        items: c['items'] is List ? decodeList(c['items'], FeedItem.fromJson) : null,
      );
}

class DiscoverPlaylists {
  final List<Playlist>? public;
  final List<Playlist>? shared;
  const DiscoverPlaylists({this.public, this.shared});
  factory DiscoverPlaylists.fromJson(Map<String, dynamic> c) => DiscoverPlaylists(
        public: c['public'] is List ? decodeList(c['public'], Playlist.fromJson) : null,
        shared: c['shared'] is List ? decodeList(c['shared'], Playlist.fromJson) : null,
      );
}

class DiscoverAlbums {
  final List<FeedItem>? albums;
  const DiscoverAlbums({this.albums});
  factory DiscoverAlbums.fromJson(Map<String, dynamic> c) => DiscoverAlbums(
        albums: c['albums'] is List ? decodeList(c['albums'], FeedItem.fromJson) : null,
      );
}

class PlaylistsPayload {
  final List<Playlist>? playlists;
  const PlaylistsPayload({this.playlists});
  factory PlaylistsPayload.fromJson(Map<String, dynamic> c) => PlaylistsPayload(
        playlists: c['playlists'] is List ? decodeList(c['playlists'], Playlist.fromJson) : null,
      );
}

class LibraryPayload {
  final Map<String, List<Playlist>>? groups;
  const LibraryPayload({this.groups});
  factory LibraryPayload.fromJson(Map<String, dynamic> c) {
    final raw = asMap(c['groups']);
    return LibraryPayload(
      groups: raw?.map((k, v) => MapEntry(k, decodeList(v, Playlist.fromJson))),
    );
  }
}

class PlaylistBox {
  final Playlist? playlist;
  const PlaylistBox({this.playlist});
  factory PlaylistBox.fromJson(Map<String, dynamic> c) => PlaylistBox(
        playlist: asMap(c['playlist']) != null ? Playlist.fromJson(asMap(c['playlist'])!) : null,
      );
}

class ResolveResult {
  final Track? preferred;
  final List<Track>? candidates;
  const ResolveResult({this.preferred, this.candidates});
  factory ResolveResult.fromJson(Map<String, dynamic> c) => ResolveResult(
        preferred: asMap(c['preferred']) != null ? Track.fromJson(asMap(c['preferred'])!) : null,
        candidates: c['candidates'] is List ? decodeList(c['candidates'], Track.fromJson) : null,
      );
}

class ArtistResolve {
  final Artist? preferred;
  const ArtistResolve({this.preferred});
  factory ArtistResolve.fromJson(Map<String, dynamic> c) => ArtistResolve(
        preferred: asMap(c['preferred']) != null ? Artist.fromJson(asMap(c['preferred'])!) : null,
      );
}

class HistoryPayload {
  final List<Track>? items;
  final List<Track>? tracks;
  const HistoryPayload({this.items, this.tracks});
  factory HistoryPayload.fromJson(Map<String, dynamic> c) => HistoryPayload(
        items: c['items'] is List ? decodeList(c['items'], Track.fromJson) : null,
        tracks: c['tracks'] is List ? decodeList(c['tracks'], Track.fromJson) : null,
      );
}

class ItemsBox<T> {
  final List<T>? items;
  final bool? has;
  final bool? favorited;
  const ItemsBox({this.items, this.has, this.favorited});
  factory ItemsBox.fromJson(Map<String, dynamic> c, T Function(Map<String, dynamic>) factory) =>
      ItemsBox<T>(
        items: c['items'] is List ? decodeList(c['items'], factory) : null,
        has: asBool(c['has']),
        favorited: asBool(c['favorited']),
      );
}

/// Mirrors Swift `PlaySource`.
class PlaySource {
  final String kind;
  final String platform;
  final String id;
  final String? title;
  final String? name;
  final List<String>? artists;
  final String? coverUrl;
  final String? artworkUrl;
  final String? avatarUrl;
  final String? motionUrl;
  final List<String>? mosaicUrls;
  final String? listKind;
  final int? trackCount;

  const PlaySource({
    required this.kind,
    required this.platform,
    required this.id,
    this.title,
    this.name,
    this.artists,
    this.coverUrl,
    this.artworkUrl,
    this.avatarUrl,
    this.motionUrl,
    this.mosaicUrls,
    this.listKind,
    this.trackCount,
  });

  Map<String, dynamic> payload() {
    final o = <String, dynamic>{'kind': kind, 'platform': platform, 'id': id};
    if (title != null) o['title'] = title;
    if (name != null) o['name'] = name;
    if (artists != null) o['artists'] = artists;
    if (coverUrl != null) o['coverUrl'] = coverUrl;
    if (artworkUrl != null) o['artworkUrl'] = artworkUrl;
    if (avatarUrl != null) o['avatarUrl'] = avatarUrl;
    if (motionUrl != null) o['motionUrl'] = motionUrl;
    if (mosaicUrls != null) o['mosaicUrls'] = mosaicUrls;
    if (listKind != null) o['listKind'] = listKind;
    if (trackCount != null) o['trackCount'] = trackCount;
    return o;
  }
}
