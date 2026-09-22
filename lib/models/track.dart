import 'json.dart';

/// Mirrors Swift `Track`.
class Track {
  String id;
  String platform;
  String title;
  List<String> artists;
  String? album;
  String? albumId;
  double? durationMs;
  String? isrc;
  String? recordingVersion;
  String? artworkUrl;
  String? coverUrl;
  String? streamUrl;
  String? previewUrl;
  bool? playable;
  bool? vip;
  bool? trial;
  String? quality;
  String? format;
  double? bitrate;
  String? webUrl;
  double? confidence;
  List<String> artistIds;
  String? mixSongId;
  String? fileHash;
  String? hqHash;
  String? sqHash;
  List<TrackAlternative> alternatives;
  String? groupId;
  bool historyReplay;

  Track({
    required this.id,
    required this.platform,
    required this.title,
    required this.artists,
    this.album,
    this.albumId,
    this.durationMs,
    this.isrc,
    this.recordingVersion,
    this.artworkUrl,
    this.coverUrl,
    this.streamUrl,
    this.previewUrl,
    this.playable,
    this.vip,
    this.trial,
    this.quality,
    this.format,
    this.bitrate,
    this.webUrl,
    this.confidence,
    List<String>? artistIds,
    this.mixSongId,
    this.fileHash,
    this.hqHash,
    this.sqHash,
    List<TrackAlternative>? alternatives,
    this.groupId,
    this.historyReplay = false,
  })  : artistIds = artistIds ?? [],
        alternatives = alternatives ?? [];

  String? get cover => artworkUrl ?? coverUrl;
  String get artistText => artists.join(' / ');
  String get key => '$platform::$id';
  double get duration => (durationMs ?? 0) / 1000;

  List<({String name, String id})> get artistEntries {
    final out = <({String name, String id})>[];
    for (var i = 0; i < artists.length; i++) {
      final n = artists[i].trim();
      if (n.isEmpty) continue;
      out.add((name: n, id: i < artistIds.length ? artistIds[i] : ''));
    }
    return out;
  }

  factory Track.fromJson(Map<String, dynamic> c) {
    return Track(
      isrc: asString(c['isrc']),
      recordingVersion: asString(c['version']),
      id: c['id'] != null ? flexId(c['id']) : _uuid(),
      platform: asStringOr(c['platform'], ''),
      title: asStringOr(c['title'], ''),
      artists: flexStringList(c['artists']),
      artistIds: flexStringList(c['artistIds']),
      album: asString(c['album']),
      albumId: flexIdOrNull(c['albumId']),
      durationMs: asDouble(c['durationMs']),
      artworkUrl: asString(c['artworkUrl']),
      coverUrl: asString(c['coverUrl']),
      streamUrl: asString(c['streamUrl']),
      previewUrl: asString(c['previewUrl']),
      playable: asBool(c['playable']),
      vip: asBool(c['vip']),
      trial: asBool(c['trial']),
      quality: asString(c['quality']),
      format: asString(c['format']),
      bitrate: asDouble(c['bitrate']),
      webUrl: asString(c['webUrl']),
      confidence: asDouble(c['confidence']),
      mixSongId: flexIdOrNull(c['mixSongId']),
      fileHash: asString(c['fileHash']),
      hqHash: asString(c['hqHash']),
      sqHash: asString(c['sqHash']),
      alternatives: decodeList(c['alternatives'], TrackAlternative.fromJson),
      groupId: asString(c['groupId']),
    );
  }

  /// Portable song identity only — mirrors `identityPayload()`.
  Map<String, dynamic> identityPayload() {
    final v = <String, dynamic>{
      'id': id,
      'platform': platform,
      'title': title,
      'artists': artists,
    };
    if (album != null) v['album'] = album;
    if (isrc != null) v['isrc'] = isrc;
    if (recordingVersion != null) v['version'] = recordingVersion;
    if (durationMs != null) v['durationMs'] = durationMs;
    if (artworkUrl != null) v['artworkUrl'] = artworkUrl;
    if (coverUrl != null) v['coverUrl'] = coverUrl;
    return v;
  }

  /// Mirrors `ingestPayload()`.
  Map<String, dynamic> ingestPayload() {
    final v = identityPayload();
    if (artistIds.isNotEmpty) v['artistIds'] = artistIds;
    return v;
  }

  /// Mirrors `payload()`.
  Map<String, dynamic> payload() {
    final o = <String, dynamic>{
      'id': id,
      'platform': platform,
      'title': title,
      'artists': artists,
    };
    if (artistIds.isNotEmpty) o['artistIds'] = artistIds;
    if (album != null) o['album'] = album;
    if (albumId != null) o['albumId'] = albumId;
    if (durationMs != null) o['durationMs'] = durationMs;
    if (artworkUrl != null) o['artworkUrl'] = artworkUrl;
    if (coverUrl != null) o['coverUrl'] = coverUrl;
    if (streamUrl != null) o['streamUrl'] = streamUrl;
    if (playable != null) o['playable'] = playable;
    if (vip != null) o['vip'] = vip;
    return o;
  }

  static int _counter = 0;
  static String _uuid() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}

/// Mirrors Swift `TrackAlternative`.
class TrackAlternative {
  final String id;
  final String platform;
  final String title;
  final List<String> artists;
  final String? album;
  final double? durationMs;
  final String? artworkUrl;
  final String? coverUrl;
  final String? streamUrl;
  final bool? playable;
  final String? quality;
  final String? format;
  final double? bitrate;
  final List<String> artistIds;
  final bool? vip;
  final bool? trial;

  const TrackAlternative({
    required this.id,
    required this.platform,
    required this.title,
    required this.artists,
    this.album,
    this.durationMs,
    this.artworkUrl,
    this.coverUrl,
    this.streamUrl,
    this.playable,
    this.quality,
    this.format,
    this.bitrate,
    this.artistIds = const [],
    this.vip,
    this.trial,
  });

  String? get cover => artworkUrl ?? coverUrl;
  String get artistText => artists.join(' / ');

  factory TrackAlternative.fromJson(Map<String, dynamic> c) => TrackAlternative(
        id: c['id'] != null ? flexId(c['id']) : Track._uuid(),
        platform: asStringOr(c['platform'], ''),
        title: asStringOr(c['title'], ''),
        artists: flexStringList(c['artists']),
        artistIds: flexStringList(c['artistIds']),
        album: asString(c['album']),
        durationMs: asDouble(c['durationMs']),
        artworkUrl: asString(c['artworkUrl']),
        coverUrl: asString(c['coverUrl']),
        streamUrl: asString(c['streamUrl']),
        playable: asBool(c['playable']),
        quality: asString(c['quality']),
        format: asString(c['format']),
        bitrate: asDouble(c['bitrate']),
        vip: asBool(c['vip']),
        trial: asBool(c['trial']),
      );

  Track asTrack() => Track(
        id: id,
        platform: platform,
        title: title,
        artists: artists,
        album: album,
        durationMs: durationMs,
        artworkUrl: artworkUrl,
        coverUrl: coverUrl,
        streamUrl: streamUrl,
        playable: playable,
        artistIds: artistIds,
        quality: quality,
        format: format,
        bitrate: bitrate,
        vip: vip,
        trial: trial,
      );
}

/// Mirrors Swift `LibraryIngest` enum helpers.
class LibraryIngest {
  static bool isLocalLibraryTrack(Track track) {
    final platform = track.platform.trim().toLowerCase();
    return ['local', 'localfile', 'files'].contains(platform) ||
        (track.streamUrl?.startsWith('/api/library/') ?? false);
  }

  static bool canIngest(Track track) =>
      track.platform.trim().isNotEmpty &&
      track.id.trim().isNotEmpty &&
      !isLocalLibraryTrack(track);

  static List<Map<String, dynamic>> items(List<Track> tracks) => tracks
      .where(canIngest)
      .map((t) => t.ingestPayload())
      .toList();
}
