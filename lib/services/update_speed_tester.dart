import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_mirror.dart';

/// 单个下载线路的测速结果。
class MirrorSpeedResult {
  const MirrorSpeedResult({
    required this.mirrorId,
    required this.bytes,
    required this.elapsed,
    this.error,
  });

  final String mirrorId;
  final int bytes;
  final Duration elapsed;
  final String? error;

  bool get ok => error == null && bytes > 0;

  /// 字节/秒；无有效样本时为 0。
  double get bytesPerSecond {
    final micros = elapsed.inMicroseconds;
    if (micros <= 0 || bytes <= 0) return 0;
    return bytes * 1000000 / micros;
  }

  String get displaySpeed {
    if (!ok) return '失败';
    final mbps = bytesPerSecond / (1024 * 1024);
    if (mbps >= 1) return '${mbps.toStringAsFixed(1)} MB/s';
    final kbps = bytesPerSecond / 1024;
    return '${kbps.toStringAsFixed(0)} KB/s';
  }
}

/// 下载线路测速：对每条线路发带 Range 头的流式请求，在固定时间窗口内统计
/// 实际收到的字节数得到近似吞吐，窗口结束立即断开，不完整下载安装包。
class UpdateSpeedTester {
  static const Duration defaultBudget = Duration(seconds: 5);
  static const int maxBytes = 8 * 1024 * 1024;

  /// 没有 APK 地址时的测速目标，保证测的仍是同一条 GitHub 下载链路。
  static const String fallbackProbeUrl =
      'https://github.com/xiaojun5270/msx/archive/refs/heads/main.zip';

  static Future<MirrorSpeedResult> test(
    UpdateMirror mirror, {
    required String sourceUrl,
    Duration budget = defaultBudget,
  }) async {
    final target = mirror.resolve(sourceUrl.trim());
    final uri = Uri.tryParse(target);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return MirrorSpeedResult(
        mirrorId: mirror.id,
        bytes: 0,
        elapsed: Duration.zero,
        error: '地址无效',
      );
    }

    final client = http.Client();
    final stopwatch = Stopwatch()..start();
    final completer = Completer<MirrorSpeedResult>();
    var received = 0;
    Timer? deadline;

    void finish(String? error) {
      if (completer.isCompleted) return;
      stopwatch.stop();
      final result = MirrorSpeedResult(
        mirrorId: mirror.id,
        bytes: received,
        elapsed: stopwatch.elapsed,
        error: error,
      );
      completer.complete(result);
      // 提前中断流，避免已到时间窗口还继续下载。
      client.close();
    }

    deadline = Timer(budget, () => finish(received > 0 ? null : '超时'));

    try {
      final request = http.Request('GET', uri)
        ..headers['range'] = 'bytes=0-8388607';
      final response =
          await client.send(request).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) {
        finish('HTTP ${response.statusCode}');
      } else {
        await for (final chunk in response.stream) {
          if (completer.isCompleted) break;
          received += chunk.length;
          if (received >= maxBytes) {
            finish(null);
            break;
          }
        }
        finish(null);
      }
    } on TimeoutException {
      finish('连接超时');
    } catch (error) {
      // 到点后主动断开会被包成 ClientException，属正常结束。
      if (!completer.isCompleted) {
        finish(received > 0 && error is http.ClientException
            ? null
            : _describe(error));
      }
    } finally {
      deadline.cancel();
      client.close();
    }

    return completer.future;
  }

  static String _describe(Object error) {
    if (error is SocketException) return '无法连接';
    if (error is TimeoutException) return '连接超时';
    if (error is http.ClientException) return '网络错误';
    return '测速失败';
  }
}

/// 线路测速的界面状态：并发测速、单条重测与最快线路提示。
class MirrorSpeedController extends ChangeNotifier {
  final Map<String, MirrorSpeedResult> _results = {};
  final Set<String> _testing = {};

  bool _testingAll = false;
  bool _disposed = false;
  bool get testingAll => _testingAll;

  Map<String, MirrorSpeedResult> get results => Map.unmodifiable(_results);

  MirrorSpeedResult? resultFor(String id) => _results[id];

  bool isTesting(String id) => _testing.contains(id);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 面板关闭时测速请求可能还在飞行，结果回来不要再碰已销毁的通知器。
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> testOne(UpdateMirror mirror, {required String sourceUrl}) async {
    if (_testing.contains(mirror.id)) return;
    _testing.add(mirror.id);
    _notify();
    final result =
        await UpdateSpeedTester.test(mirror, sourceUrl: sourceUrl);
    if (_disposed) return;
    _testing.remove(mirror.id);
    _results[mirror.id] = result;
    _notify();
  }

  Future<void> testAll(
    List<UpdateMirror> mirrors, {
    required String sourceUrl,
  }) async {
    if (_testingAll) return;
    _testingAll = true;
    _results.clear();
    _testing.addAll(mirrors.map((mirror) => mirror.id));
    _notify();
    await Future.wait(mirrors.map((mirror) async {
      final result =
          await UpdateSpeedTester.test(mirror, sourceUrl: sourceUrl);
      if (_disposed) return;
      _testing.remove(mirror.id);
      _results[mirror.id] = result;
      _notify();
    }));
    if (_disposed) return;
    _testingAll = false;
    _notify();
  }

  void clear() {
    _results.clear();
    _testing.clear();
    _notify();
  }

  /// 基于本次测速结果给出最快线路提示。
  String? fastestHint(
    List<UpdateMirror> mirrors, {
    required String selectedId,
  }) {
    MirrorSpeedResult? best;
    UpdateMirror? bestMirror;
    for (final mirror in mirrors) {
      final result = _results[mirror.id];
      if (result == null || !result.ok) continue;
      if (best == null || result.bytesPerSecond > best.bytesPerSecond) {
        best = result;
        bestMirror = mirror;
      }
    }
    if (best == null || bestMirror == null) return null;
    if (bestMirror.id == selectedId) {
      return '当前线路实测 ${best.displaySpeed}，状态良好';
    }
    return '${bestMirror.label} 最快（${best.displaySpeed}），建议切换';
  }
}
