import 'json.dart';
import 'track.dart';

/// Mirrors Swift `LocalPlaylist` + stats.
class LocalPlaylist {
  final String id;
  final String name;
  final String? kind;
  final String? path;
  final bool recursive;
  final bool pathOk;
  final String? lastScanAt;
  final LocalPlaylistStats stats;

  const LocalPlaylist({
    required this.id,
    required this.name,
    this.kind,
    this.path,
    this.recursive = true,
    this.pathOk = false,
    this.lastScanAt,
    this.stats = LocalPlaylistStats.empty,
  });

  factory LocalPlaylist.fromJson(Map<String, dynamic> c) => LocalPlaylist(
        id: c['id'] != null ? flexId(c['id']) : '',
        name: asStringOr(c['name'], '本地音乐目录'),
        kind: asString(c['kind']),
        path: asString(c['path']),
        recursive: asBool(c['recursive']) ?? true,
        pathOk: asBool(c['pathOk']) ?? false,
        lastScanAt: asString(c['lastScanAt']),
        stats: asMap(c['stats']) != null
            ? LocalPlaylistStats.fromJson(asMap(c['stats'])!)
            : LocalPlaylistStats.empty,
      );
}

class LocalPlaylistListBox {
  final List<LocalPlaylist> playlists;
  const LocalPlaylistListBox({this.playlists = const []});
  factory LocalPlaylistListBox.fromJson(Map<String, dynamic> c) =>
      LocalPlaylistListBox(playlists: decodeList(c['playlists'], LocalPlaylist.fromJson));
}

class LocalPlaylistWriteResponse {
  final String id;
  const LocalPlaylistWriteResponse({this.id = ''});
  factory LocalPlaylistWriteResponse.fromJson(Map<String, dynamic> c) =>
      LocalPlaylistWriteResponse(id: c['id'] != null ? flexId(c['id']) : '');
}

class LocalPlaylistUpdateResponse {
  final bool rescanned;
  const LocalPlaylistUpdateResponse({this.rescanned = false});
  factory LocalPlaylistUpdateResponse.fromJson(Map<String, dynamic> c) =>
      LocalPlaylistUpdateResponse(rescanned: asBool(c['rescanned']) ?? false);
}

class LocalPlaylistStats {
  final int total;
  final int pending;
  final int parsing;
  final int enriched;
  final int success;
  final int unrecognized;
  final int deleted;
  final int failed;

  const LocalPlaylistStats({
    this.total = 0,
    this.pending = 0,
    this.parsing = 0,
    this.enriched = 0,
    this.success = 0,
    this.unrecognized = 0,
    this.deleted = 0,
    this.failed = 0,
  });

  static const empty = LocalPlaylistStats();
  int get active => pending + parsing + enriched;

  factory LocalPlaylistStats.fromJson(Map<String, dynamic> c) => LocalPlaylistStats(
        total: asInt(c['total']) ?? 0,
        pending: asInt(c['pending']) ?? 0,
        parsing: asInt(c['parsing']) ?? 0,
        enriched: asInt(c['enriched']) ?? 0,
        success: asInt(c['success']) ?? 0,
        unrecognized: asInt(c['unrecognized']) ?? 0,
        deleted: asInt(c['deleted']) ?? 0,
        failed: asInt(c['failed']) ?? 0,
      );
}

class LocalDirectoryBrowser {
  final String path;
  final String? parent;
  final List<LocalDirectory> roots;
  final List<LocalDirectory> entries;
  final List<LocalDirectoryFile> files;
  final LocalDirectorySummary summary;

  const LocalDirectoryBrowser({
    this.path = '',
    this.parent,
    this.roots = const [],
    this.entries = const [],
    this.files = const [],
    this.summary = const LocalDirectorySummary(),
  });

  factory LocalDirectoryBrowser.fromJson(Map<String, dynamic> c) => LocalDirectoryBrowser(
        path: asStringOr(c['path'], ''),
        parent: asString(c['parent']),
        roots: decodeList(c['roots'], LocalDirectory.fromJson),
        entries: decodeList(c['entries'], LocalDirectory.fromJson),
        files: decodeList(c['files'], LocalDirectoryFile.fromJson),
        summary: asMap(c['summary']) != null
            ? LocalDirectorySummary.fromJson(asMap(c['summary'])!)
            : const LocalDirectorySummary(),
      );
}

class LocalDirectory {
  final String name;
  final String path;
  final String type;
  const LocalDirectory({this.name = '', this.path = '', this.type = 'dir'});
  factory LocalDirectory.fromJson(Map<String, dynamic> c) {
    final name = asStringOr(c['name'], '');
    return LocalDirectory(
      name: name,
      path: asStringOr(c['path'], name),
      type: asStringOr(c['type'], 'dir'),
    );
  }
}

class LocalDirectoryFile {
  final String name;
  final String path;
  final String type;
  final double? size;
  final String? ext;
  final bool audio;
  final String? updatedAt;
  const LocalDirectoryFile({
    this.name = '',
    this.path = '',
    this.type = 'file',
    this.size,
    this.ext,
    this.audio = false,
    this.updatedAt,
  });
  factory LocalDirectoryFile.fromJson(Map<String, dynamic> c) {
    final name = asStringOr(c['name'], '');
    return LocalDirectoryFile(
      name: name,
      path: asStringOr(c['path'], name),
      type: asStringOr(c['type'], 'file'),
      size: asDouble(c['size']),
      ext: asString(c['ext']),
      audio: asBool(c['audio']) ?? false,
      updatedAt: asString(c['updatedAt']),
    );
  }
}

class LocalDirectorySummary {
  final int dirs;
  final int files;
  final int audioFiles;
  final double totalSize;
  const LocalDirectorySummary({
    this.dirs = 0,
    this.files = 0,
    this.audioFiles = 0,
    this.totalSize = 0,
  });
  factory LocalDirectorySummary.fromJson(Map<String, dynamic> c) => LocalDirectorySummary(
        dirs: asInt(c['dirs']) ?? 0,
        files: asInt(c['files']) ?? 0,
        audioFiles: asInt(c['audioFiles']) ?? 0,
        totalSize: asDouble(c['totalSize']) ?? 0,
      );
}

class LibraryBrowse {
  final String? path;
  final String? parent;
  final String? title;
  final String? artworkUrl;
  final List<LibraryEntry>? entries;
  const LibraryBrowse({this.path, this.parent, this.title, this.artworkUrl, this.entries});
  factory LibraryBrowse.fromJson(Map<String, dynamic> c) => LibraryBrowse(
        path: asString(c['path']),
        parent: asString(c['parent']),
        title: asString(c['title']),
        artworkUrl: asString(c['artworkUrl']),
        entries: c['entries'] is List ? decodeList(c['entries'], LibraryEntry.fromJson) : null,
      );
}

class LibraryEntry {
  final String name;
  final String path;
  final String type;
  final double? size;
  final String? ext;
  final bool? audio;
  final String? title;
  final List<String>? artists;
  final String? album;
  final String? artworkUrl;
  final String? createdAt;
  final Track? track;

  const LibraryEntry({
    this.name = '',
    this.path = '',
    this.type = 'file',
    this.size,
    this.ext,
    this.audio,
    this.title,
    this.artists,
    this.album,
    this.artworkUrl,
    this.createdAt,
    this.track,
  });

  factory LibraryEntry.fromJson(Map<String, dynamic> c) {
    final name = asStringOr(c['name'], '');
    return LibraryEntry(
      name: name,
      path: asStringOr(c['path'], name),
      type: asStringOr(c['type'], 'file'),
      size: asDouble(c['size']),
      ext: asString(c['ext']),
      audio: asBool(c['audio']),
      title: asString(c['title']),
      artists: c['artists'] != null ? flexStringList(c['artists']) : null,
      album: asString(c['album']),
      artworkUrl: asString(c['artworkUrl']),
      createdAt: asString(c['createdAt']),
      track: asMap(c['track']) != null ? Track.fromJson(asMap(c['track'])!) : null,
    );
  }
}

class LibraryFile {
  final String id;
  final String platform;
  final String sourceId;
  final String? quality;
  final String title;
  final List<String> artists;
  final String? album;
  final double? durationMs;
  final String? artworkUrl;
  final String? relPath;
  final double? size;
  final String? streamUrl;
  final String? createdAt;

  const LibraryFile({
    required this.id,
    this.platform = '',
    this.sourceId = '',
    this.quality,
    this.title = '',
    this.artists = const [],
    this.album,
    this.durationMs,
    this.artworkUrl,
    this.relPath,
    this.size,
    this.streamUrl,
    this.createdAt,
  });

  factory LibraryFile.fromJson(Map<String, dynamic> c) => LibraryFile(
        id: c['id'] != null ? flexId(c['id']) : '',
        platform: asStringOr(c['platform'], ''),
        sourceId: c['sourceId'] != null ? flexId(c['sourceId']) : '',
        quality: asString(c['quality']),
        title: asStringOr(c['title'], ''),
        artists: flexStringList(c['artists']),
        album: asString(c['album']),
        durationMs: asDouble(c['durationMs']),
        artworkUrl: asString(c['artworkUrl']),
        relPath: asString(c['relPath']),
        size: asDouble(c['size']),
        streamUrl: asString(c['streamUrl']),
        createdAt: asString(c['createdAt']),
      );

  Track asTrack() => Track(
        id: sourceId.isEmpty ? id : sourceId,
        platform: platform.isEmpty ? 'localfile' : platform,
        title: title,
        artists: artists,
        album: album,
        durationMs: durationMs,
        artworkUrl: artworkUrl,
        streamUrl: streamUrl,
        playable: true,
      );
}

class LibraryRecordsBox {
  final List<LibraryFile>? items;
  final int? total;
  const LibraryRecordsBox({this.items, this.total});
  factory LibraryRecordsBox.fromJson(Map<String, dynamic> c) => LibraryRecordsBox(
        items: c['items'] is List ? decodeList(c['items'], LibraryFile.fromJson) : null,
        total: asInt(c['total']),
      );
}

class LibraryLookup {
  final LibraryFile? file;
  const LibraryLookup({this.file});
  factory LibraryLookup.fromJson(Map<String, dynamic> c) => LibraryLookup(
        file: asMap(c['file']) != null ? LibraryFile.fromJson(asMap(c['file'])!) : null,
      );
}
