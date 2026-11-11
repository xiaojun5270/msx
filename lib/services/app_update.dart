import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_mirror.dart';

/// GitHub Releases based OTA updates.
///
/// Version scheme mirrors CI (scripts/prepare_app_version.py): the release
/// name is `MusicX 0.8.11(018)` and the app is built with
/// `--dart-define=APP_DISPLAY_VERSION=0.8.11(018)`. An update is available
/// when the release's (major, minor, patch, sequence) beats the local one.
///
/// Both the API call and the APK download go through [UpdateMirrorStore]: the
/// user-selected accelerator is tried first, then direct GitHub, then the rest
/// of the built-in routes.
class AppUpdateService {
  AppUpdateService._();

  static const _repo = 'xiaojun5270/msx';
  static const _apiBase = 'https://api.github.com/repos/$_repo/releases/latest';

  /// Downloaded APKs older than this are pruned on the next update.
  static const Duration cachedApkTtl = Duration(days: 7);

  /// Display version baked in at build time by CI; matches the release name.
  static String get currentVersion => const String.fromEnvironment(
      'APP_DISPLAY_VERSION',
      defaultValue: '0.7.8(001)');

  static final _versionRe = RegExp(r'(\d+)\.(\d+)\.(\d+)\((\d+)\)');

  static final _displayRe = RegExp(r'MusicX\s+(.+)');

  /// Parsed display version: (major, minor, patch, sequence).
  static (int, int, int, int)? parseVersion(String text) {
    final m = _versionRe.firstMatch(text);
    if (m == null) return null;
    return (
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
    );
  }

  static bool isNewer(String releaseVersionText) {
    final release = parseVersion(releaseVersionText);
    final current = parseVersion(currentVersion);
    if (release == null || current == null) return false;
    final r = <int>[release.$1, release.$2, release.$3, release.$4];
    final c = <int>[current.$1, current.$2, current.$3, current.$4];
    for (var i = 0; i < 4; i++) {
      if (r[i] > c[i]) return true;
      if (r[i] < c[i]) return false;
    }
    return false;
  }

  /// Fetch the latest release.
  ///
  /// All routes race in parallel and the first valid answer wins: sequential
  /// probing would stall for a full timeout on the blocked direct route before
  /// ever reaching the accelerators. Worst case equals a single timeout.
  static Future<ReleaseInfo?> fetchLatest({http.Client? client}) async {
    final store = UpdateMirrorStore.instance;
    await store.ensureLoaded();
    final routes = store.probeOrder;
    if (routes.isEmpty) return null;

    final completer = Completer<ReleaseInfo?>();
    var pending = routes.length;

    void settle(ReleaseInfo? info) {
      if (info != null && !completer.isCompleted) completer.complete(info);
    }

    for (final mirror in routes) {
      final owned = client == null;
      final httpClient = client ?? http.Client();
      unawaited(() async {
        try {
          final resp = await httpClient
              .get(Uri.parse(mirror.resolve(_apiBase)), headers: {
            'Accept': 'application/vnd.github+json',
          }).timeout(const Duration(seconds: 12));
          if (resp.statusCode != 200) return;
          final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map;
          settle(ReleaseInfo(
            tagName: json['tag_name'] as String? ?? '',
            displayName:
                json['name'] as String? ?? json['tag_name'] as String? ?? '',
            body: json['body'] as String? ?? '',
            apkUrl: _pickApk(json['assets'] as List? ?? const []),
            apkSize: _pickApkSize(json['assets'] as List? ?? const []),
          ));
        } catch (_) {
          // Route unavailable — another route may still win.
        } finally {
          if (owned) httpClient.close();
          pending--;
          if (pending == 0 && !completer.isCompleted) completer.complete(null);
        }
      }());
    }
    return completer.future;
  }

  static String? _pickApk(List assets) {
    for (final asset in assets) {
      if (asset is Map && (asset['name'] as String).endsWith('.apk')) {
        return asset['browser_download_url'] as String;
      }
    }
    return null;
  }

  static int? _pickApkSize(List assets) {
    for (final asset in assets) {
      if (asset is Map && (asset['name'] as String).endsWith('.apk')) {
        final size = asset['size'];
        if (size is int) return size;
        return int.tryParse(size?.toString() ?? '');
      }
    }
    return null;
  }

  /// Download the release APK through [mirror].
  ///
  /// Accelerated routes are validated by their file header — a proxy that
  /// answers with an HTML error page would otherwise leave a broken "APK" on
  /// disk. When an accelerator fails (network error or non-APK payload) and
  /// [fallbackToDirect] is true, direct GitHub is retried once.
  static Future<File> downloadApk(
    String url, {
    UpdateMirror mirror = const UpdateMirror.direct(),
    bool fallbackToDirect = true,
    void Function(double progress, String route)? onProgress,
    required bool Function() cancelled,
  }) async {
    final attempts = <UpdateMirror>[
      mirror,
      if (fallbackToDirect && !mirror.isDirect) const UpdateMirror.direct(),
    ];
    Object? lastError;
    for (var index = 0; index < attempts.length; index++) {
      final current = attempts[index];
      try {
        return await _downloadOnce(
          url,
          current,
          onProgress: onProgress,
          cancelled: cancelled,
        );
      } catch (error) {
        if (error is UpdateCancelled) rethrow;
        if (cancelled()) throw const UpdateCancelled();
        lastError = error;
        if (index < attempts.length - 1) onProgress?.call(0, current.label);
      }
    }
    throw UpdateDownloadException(
      lastError == null ? '所有下载线路均失败' : '所有下载线路均失败：$lastError',
    );
  }

  static Future<File> _downloadOnce(
    String url,
    UpdateMirror mirror, {
    required void Function(double progress, String route)? onProgress,
    required bool Function() cancelled,
  }) async {
    final target = Uri.parse(mirror.resolve(url));
    final dir = await _updateCacheDirectory();
    final file = File('${dir.path}/${_fileName(target)}');
    if (file.existsSync()) file.deleteSync();

    final client = http.Client();
    try {
      final request = http.Request('GET', target);
      final resp =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw UpdateDownloadException('${mirror.label} HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      var cancelRequested = false;
      var lastReport = -1;
      try {
        await for (final chunk in resp.stream) {
          if (cancelled()) {
            cancelRequested = true;
            break;
          }
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            final percent = (received / total * 100).floor();
            if (percent != lastReport) {
              lastReport = percent;
              onProgress?.call(received / total, mirror.label);
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (cancelRequested) {
        _deleteQuietly(file);
        throw const UpdateCancelled();
      }
      if (received <= 0) {
        _deleteQuietly(file);
        throw UpdateDownloadException('${mirror.label} 返回空内容');
      }
      if (total > 0 && received < total) {
        _deleteQuietly(file);
        throw UpdateDownloadException('${mirror.label} 下载不完整');
      }
      if (!await _looksLikeApk(file)) {
        _deleteQuietly(file);
        throw UpdateDownloadException('${mirror.label} 返回的不是安装包');
      }
      onProgress?.call(1, mirror.label);
      return file;
    } catch (error) {
      if (error is! UpdateCancelled) _deleteQuietly(file);
      rethrow;
    } finally {
      client.close();
    }
  }

  /// APK is a ZIP container: the header must be `PK\x03\x04`. Broken
  /// accelerators tend to answer with an HTML error page instead.
  static Future<bool> _looksLikeApk(File file) async {
    try {
      final raf = await file.open();
      try {
        final header = await raf.read(4);
        return header.length >= 4 &&
            header[0] == 0x50 &&
            header[1] == 0x4B &&
            header[2] == 0x03 &&
            header[3] == 0x04;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Remove leftovers from previous updates so the temp dir does not grow.
  static Future<void> cleanupExpiredApkCache(
      {Duration maxAge = cachedApkTtl}) async {
    try {
      final dir = await _updateCacheDirectory();
      if (!dir.existsSync()) return;
      final now = DateTime.now();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.apk')) continue;
        final stat = await entity.stat();
        if (now.difference(stat.modified) > maxAge) {
          _deleteQuietly(entity);
        }
      }
    } catch (_) {}
  }

  static Future<Directory> _updateCacheDirectory() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/musix_app_updates');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static String _fileName(Uri target) {
    final segment = target.pathSegments.isEmpty
        ? ''
        : target.pathSegments.last.trim();
    final safe = segment.replaceAll(RegExp(r'[^\w.\-()+]'), '_');
    if (safe.toLowerCase().endsWith('.apk') && safe.length > 4) return safe;
    return 'musix-update-${DateTime.now().millisecondsSinceEpoch}.apk';
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReleaseInfo {
  final String tagName;
  final String displayName;
  final String body;
  final String? apkUrl;
  final int? apkSize;
  const ReleaseInfo({
    required this.tagName,
    required this.displayName,
    required this.body,
    this.apkUrl,
    this.apkSize,
  });

  /// "MusicX 0.8.11(018)" -> "0.8.11(018)".
  String get displayVersion =>
      AppUpdateService._displayRe.firstMatch(displayName)?.group(1) ??
      displayName;

  bool get hasApk => (apkUrl ?? '').isNotEmpty;
}
