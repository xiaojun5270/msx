import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// GitHub Releases based OTA updates.
///
/// Version scheme mirrors CI (scripts/prepare_app_version.py): the release
/// name is `MusicX 0.8.11(018)` and the app is built with
/// `--dart-define=APP_DISPLAY_VERSION=0.8.11(018)`. An update is available
/// when the release's (major, minor, patch, sequence) beats the local one.
class AppUpdateService {
  AppUpdateService._();

  static const _repo = 'xiaojun5270/msx';
  static const _apiBase = 'https://api.github.com/repos/$_repo/releases/latest';

  /// Download accelerators tried in order before falling back. Empty prefix
  /// means direct GitHub access. Prefixes are prepended to the full URL.
  static const mirrors = <String>[
    '',
    'https://gh-proxy.com/',
    'https://gh-proxy.net/',
    'https://ghfast.top/',
    'https://ghproxy.net/',
  ];

  /// Display version baked in at build time by CI; matches the release name.
  static String get currentVersion => const String.fromEnvironment(
      'APP_DISPLAY_VERSION',
      defaultValue: '0.7.8(001)');

  static final _versionRe =
      RegExp(r'(\d+)\.(\d+)\.(\d+)\((\d+)\)');

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

  /// Fetch the latest release. Tries GitHub API directly, then through each
  /// accelerator prefix. Returns null when every route fails.
  static Future<ReleaseInfo?> fetchLatest(
      {http.Client? client, void Function(String route)? onRoute}) async {
    final owned = client ?? http.Client();
    try {
      for (final mirror in mirrors) {
        onRoute?.call(mirror.isEmpty ? '直连 GitHub' : Uri.parse(mirror).host);
        try {
          final resp = await owned
              .get(Uri.parse('$mirror$_apiBase'),
                  headers: {
                    'Accept': 'application/vnd.github+json',
                  })
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode != 200) continue;
          final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map;
          return ReleaseInfo(
            tagName: json['tag_name'] as String? ?? '',
            displayName:
                json['name'] as String? ?? json['tag_name'] as String? ?? '',
            body: json['body'] as String? ?? '',
            apkUrl: _pickApk(json['assets'] as List? ?? const []),
          );
        } catch (_) {
          continue;
        }
      }
      return null;
    } finally {
      if (client == null) owned.close();
    }
  }

  static String? _pickApk(List assets) {
    for (final asset in assets) {
      if (asset is Map && (asset['name'] as String).endsWith('.apk')) {
        return asset['browser_download_url'] as String;
      }
    }
    return null;
  }

  /// Download the release APK, falling back through [mirrors]. Reports
  /// progress 0..1 plus the route currently being used. Cancels when the
  /// returned future is rejected via [cancelToken] closure set to true.
  static Future<File> downloadApk(
    String url, {
    void Function(double progress, String route)? onProgress,
    required bool Function() cancelled,
  }) async {
    final dir = await getTemporaryDirectory();
    final target = File(
        '${dir.path}${Platform.pathSeparator}musix-update-${DateTime.now().millisecondsSinceEpoch}.apk');
    http.Client? client;
    try {
      for (final mirror in mirrors) {
        final route = mirror.isEmpty ? '直连 GitHub' : Uri.parse(mirror).host;
        client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse('$mirror$url'));
          final resp =
              await client.send(request).timeout(const Duration(seconds: 20));
          if (resp.statusCode != 200) {
            client.close();
            continue;
          }
          final total = resp.contentLength ?? 0;
          final sink = target.openWrite();
          var received = 0;
          var lastReport = -1;
          var failed = false;
          try {
            await for (final chunk in resp.stream) {
              if (cancelled()) {
                failed = true;
                break;
              }
              received += chunk.length;
              sink.add(chunk);
              if (total > 0) {
                final percent = (received / total * 100).floor();
                if (percent != lastReport) {
                  lastReport = percent;
                  onProgress?.call(received / total, route);
                }
              }
            }
          } finally {
            await sink.flush();
            await sink.close();
          }
          if (failed) {
            if (target.existsSync()) target.deleteSync();
            return Future.error(const UpdateCancelled());
          }
          if (total > 0 && received < total) {
            // Truncated body — try the next route.
            if (target.existsSync()) target.deleteSync();
            continue;
          }
          onProgress?.call(1, route);
          return target;
        } catch (error) {
          if (error is UpdateCancelled) rethrow;
          if (cancelled()) return Future.error(const UpdateCancelled());
          if (target.existsSync()) target.deleteSync();
          continue;
        } finally {
          client.close();
        }
      }
      throw Exception('所有下载线路均失败');
    } finally {
      client?.close();
    }
  }
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

class ReleaseInfo {
  final String tagName;
  final String displayName;
  final String body;
  final String? apkUrl;
  const ReleaseInfo({
    required this.tagName,
    required this.displayName,
    required this.body,
    this.apkUrl,
  });

  /// "MusicX 0.8.11(018)" -> "0.8.11(018)".
  String get displayVersion =>
      AppUpdateService._displayRe.firstMatch(displayName)?.group(1) ??
      displayName;
}
