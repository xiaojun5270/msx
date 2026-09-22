import 'json.dart';

class Subscription {
  final String id;
  final String platform;
  final String sourceId;
  final String kind;
  final String title;
  final String? coverUrl;
  final int trackCount;
  final bool refreshEnabled;
  final String refreshCron;
  final bool ingestEnabled;
  final String ingestCron;
  final String? ingestQuality;
  final String? lastRefreshAt;
  final String? lastRefreshStatus;
  final String? lastRefreshError;
  final int? lastRefreshCount;
  final String? lastIngestAt;
  final String? lastIngestStatus;
  final String? lastIngestError;
  final IngestSummary? lastIngestSummary;
  final String? lastSyncAt;
  final String? syncState;
  final List<SubscriptionTrack>? tracks;

  const Subscription({
    required this.id,
    this.platform = '',
    this.sourceId = '',
    this.kind = 'playlist',
    this.title = '',
    this.coverUrl,
    this.trackCount = 0,
    this.refreshEnabled = false,
    this.refreshCron = '',
    this.ingestEnabled = false,
    this.ingestCron = '',
    this.ingestQuality,
    this.lastRefreshAt,
    this.lastRefreshStatus,
    this.lastRefreshError,
    this.lastRefreshCount,
    this.lastIngestAt,
    this.lastIngestStatus,
    this.lastIngestError,
    this.lastIngestSummary,
    this.lastSyncAt,
    this.syncState,
    this.tracks,
  });

  factory Subscription.fromJson(Map<String, dynamic> c) => Subscription(
        id: c['id'] != null ? flexId(c['id']) : '',
        platform: asStringOr(c['platform'], ''),
        sourceId: c['sourceId'] != null ? flexId(c['sourceId']) : '',
        kind: asStringOr(c['kind'], 'playlist'),
        title: asStringOr(c['title'], ''),
        coverUrl: asString(c['coverUrl']),
        trackCount: asInt(c['trackCount']) ?? 0,
        refreshEnabled: asBool(c['refreshEnabled']) ?? false,
        refreshCron: asStringOr(c['refreshCron'], ''),
        ingestEnabled: asBool(c['ingestEnabled']) ?? false,
        ingestCron: asStringOr(c['ingestCron'], ''),
        ingestQuality: asString(c['ingestQuality']),
        lastRefreshAt: asString(c['lastRefreshAt']),
        lastRefreshStatus: asString(c['lastRefreshStatus']),
        lastRefreshError: asString(c['lastRefreshError']),
        lastRefreshCount: asInt(c['lastRefreshCount']),
        lastIngestAt: asString(c['lastIngestAt']),
        lastIngestStatus: asString(c['lastIngestStatus']),
        lastIngestError: asString(c['lastIngestError']),
        lastIngestSummary: asMap(c['lastIngestSummary']) != null
            ? IngestSummary.fromJson(asMap(c['lastIngestSummary'])!)
            : null,
        lastSyncAt: asString(c['lastSyncAt']),
        syncState: asString(c['syncState']),
        tracks: c['tracks'] is List ? decodeList(c['tracks'], SubscriptionTrack.fromJson) : null,
      );
}

class IngestSummary {
  final int? queued;
  final int? skipped;
  final int? unsupported;
  final int? retried;
  const IngestSummary({this.queued, this.skipped, this.unsupported, this.retried});
  factory IngestSummary.fromJson(Map<String, dynamic> c) => IngestSummary(
        queued: asInt(c['queued']),
        skipped: asInt(c['skipped']),
        unsupported: asInt(c['unsupported']),
        retried: asInt(c['retried']),
      );
}

class SubscriptionTrack {
  final String id;
  final String title;
  final String artistText;
  final String? artworkUrl;
  final String status;
  final bool? isNew;
  final bool? hasLocalFile;
  final String? addedAt;
  final String? removedAt;

  const SubscriptionTrack({
    required this.id,
    this.title = '',
    this.artistText = '',
    this.artworkUrl,
    this.status = 'unknown',
    this.isNew,
    this.hasLocalFile,
    this.addedAt,
    this.removedAt,
  });

  factory SubscriptionTrack.fromJson(Map<String, dynamic> c) => SubscriptionTrack(
        id: c['id'] != null ? flexId(c['id']) : '',
        title: asStringOr(c['title'], ''),
        artistText: asStringOr(c['artistText'], ''),
        artworkUrl: asString(c['artworkUrl']),
        status: asStringOr(c['status'], 'unknown'),
        isNew: asBool(c['isNew']),
        hasLocalFile: asBool(c['hasLocalFile']),
        addedAt: asString(c['addedAt']),
        removedAt: asString(c['removedAt']),
      );
}

class PlaylistChange {
  final String id;
  final String type;
  final String? trackId;
  final String? trackTitle;
  final String? trackArtist;
  final Map<String, String>? metadata;
  final String createdAt;

  const PlaylistChange({
    required this.id,
    this.type = '',
    this.trackId,
    this.trackTitle,
    this.trackArtist,
    this.metadata,
    this.createdAt = '',
  });

  factory PlaylistChange.fromJson(Map<String, dynamic> c) {
    Map<String, String>? meta;
    final raw = asMap(c['metadata']);
    if (raw != null) meta = raw.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return PlaylistChange(
      id: c['id'] != null ? flexId(c['id']) : '',
      type: asStringOr(c['type'], ''),
      trackId: asString(c['trackId']),
      trackTitle: asString(c['trackTitle']),
      trackArtist: asString(c['trackArtist']),
      metadata: meta,
      createdAt: asStringOr(c['createdAt'], ''),
    );
  }
}

class SubscriptionStats {
  final int totalTracks;
  final int addedLastSync;
  final int removedLastSync;
  final int? lastChangesCount;
  final String? lastSyncAt;
  final String? syncState;
  const SubscriptionStats({
    this.totalTracks = 0,
    this.addedLastSync = 0,
    this.removedLastSync = 0,
    this.lastChangesCount,
    this.lastSyncAt,
    this.syncState,
  });
  factory SubscriptionStats.fromJson(Map<String, dynamic> c) => SubscriptionStats(
        totalTracks: asInt(c['totalTracks']) ?? 0,
        addedLastSync: asInt(c['addedLastSync']) ?? 0,
        removedLastSync: asInt(c['removedLastSync']) ?? 0,
        lastChangesCount: asInt(c['lastChangesCount']),
        lastSyncAt: asString(c['lastSyncAt']),
        syncState: asString(c['syncState']),
      );
}

class SubscriptionsBox {
  final List<Subscription>? items;
  const SubscriptionsBox({this.items});
  factory SubscriptionsBox.fromJson(Map<String, dynamic> c) => SubscriptionsBox(
        items: c['items'] is List ? decodeList(c['items'], Subscription.fromJson) : null,
      );
}

class SubscriptionState {
  final bool subscribed;
  final String? id;
  final bool refreshEnabled;
  final bool ingestEnabled;
  const SubscriptionState({
    this.subscribed = false,
    this.id,
    this.refreshEnabled = false,
    this.ingestEnabled = false,
  });
  factory SubscriptionState.fromJson(Map<String, dynamic> c) => SubscriptionState(
        subscribed: asBool(c['subscribed']) ?? false,
        id: asString(c['id']),
        refreshEnabled: asBool(c['refreshEnabled']) ?? false,
        ingestEnabled: asBool(c['ingestEnabled']) ?? false,
      );
}
