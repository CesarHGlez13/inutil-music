import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform/app_platform.dart';
import '../../platform_channels/android_file_export_channel.dart';
import 'moment_clip_models.dart';

abstract interface class MomentClipExportService {
  bool get isSupported;

  Future<MomentClipCapabilities?> probeCapabilities();

  Future<MomentClipExportResult> exportMoment(
    MomentClipExportRequest request, {
    void Function(MomentClipProgress progress)? onProgress,
  });

  Future<void> cancelExport({String? jobId});

  Future<void> shareClip({
    required String filePath,
    required String title,
    required Rect sharePositionOrigin,
  });

  Future<String?> saveClip({
    required String filePath,
    required String title,
  });
}

class MomentExportCancelledException implements Exception {
  const MomentExportCancelledException();

  @override
  String toString() => 'MomentExportCancelledException';
}

typedef MomentNativeShare = Future<void> Function(ShareParams params);
typedef MomentAndroidSave =
    Future<String?> Function({
      required String sourcePath,
      required String fileName,
      required String mimeType,
    });

/// Coordinates native Android Media3 + EGL moment clip generation, social
/// sharing (`share_plus`), and user-driven saving without storage permissions.
class DefaultMomentClipExportService implements MomentClipExportService {
  DefaultMomentClipExportService({
    AppPlatformType Function()? platform,
    MethodChannel? methodChannel,
    EventChannel? progressChannel,
    MomentNativeShare? nativeShare,
    MomentAndroidSave? androidSave,
    Future<Directory> Function()? temporaryDirectoryFactory,
    DateTime Function()? clock,
  }) : _platform = platform ?? _currentPlatform,
       _methodChannel =
           methodChannel ?? const MethodChannel('inutil_music/moment_exporter'),
       _progressChannel =
           progressChannel ??
           const EventChannel('inutil_music/moment_exporter/progress'),
       _nativeShare = nativeShare ?? _defaultShare,
       _androidSave = androidSave ?? _defaultAndroidSave,
       _temporaryDirectoryFactory =
           temporaryDirectoryFactory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final AppPlatformType Function() _platform;
  final MethodChannel _methodChannel;
  final EventChannel _progressChannel;
  final MomentNativeShare _nativeShare;
  final MomentAndroidSave _androidSave;
  final Future<Directory> Function() _temporaryDirectoryFactory;
  final DateTime Function() _clock;

  static const _directoryName = 'inutil-moment-clips';
  static const _markerName = '.inutil-moment-clip';
  static const _retention = Duration(days: 7);
  static const _maxCacheBytes = 160 * 1024 * 1024;

  @override
  bool get isSupported => _platform() == AppPlatformType.android;

  @override
  Future<MomentClipCapabilities?> probeCapabilities() async {
    if (!isSupported) return null;
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'probeCapabilities',
      );
      if (raw == null) return null;
      return MomentClipCapabilities(
        width: (raw['width'] as num?)?.toInt() ?? 1080,
        height: (raw['height'] as num?)?.toInt() ?? 1920,
        fps: (raw['fps'] as num?)?.toInt() ?? 60,
      );
    } catch (_) {
      return const MomentClipCapabilities(width: 1080, height: 1920, fps: 60);
    }
  }

  @override
  Future<MomentClipExportResult> exportMoment(
    MomentClipExportRequest request, {
    void Function(MomentClipProgress progress)? onProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Moment clip export is not supported on this platform.');
    }

    final outputFile = await _allocateOutputFile(request.title);
    StreamSubscription<dynamic>? progressSub;
    if (onProgress != null) {
      progressSub = _progressChannel.receiveBroadcastStream().listen((event) {
        if (event is! Map) return;
        final jobId = event['jobId']?.toString() ?? '';
        if (jobId != request.jobId) return;
        final stage = MomentExportStage.parse(event['stage']?.toString());
        final value = ((event['progress'] as num?)?.toDouble() ?? 0.0).clamp(
          0.0,
          1.0,
        );
        onProgress(
          MomentClipProgress(jobId: jobId, stage: stage, progress: value),
        );
      }, onError: (_) {});
    }

    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'exportMoment',
        request.toChannelMap(outputPath: outputFile.path),
      );
      if (raw == null) {
        throw StateError('Native moment exporter returned null result.');
      }
      final path = (raw['outputPath'] as String?)?.trim() ?? outputFile.path;
      return MomentClipExportResult(
        outputPath: path,
        width: (raw['width'] as num?)?.toInt() ?? 1080,
        height: (raw['height'] as num?)?.toInt() ?? 1920,
        fps: (raw['fps'] as num?)?.toInt() ?? 60,
        sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
        duration: Duration(
          milliseconds:
              (raw['durationMs'] as num?)?.toInt() ??
              (request.end - request.start).inMilliseconds,
        ),
      );
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        throw const MomentExportCancelledException();
      }
      rethrow;
    } finally {
      await progressSub?.cancel();
    }
  }

  @override
  Future<void> cancelExport({String? jobId}) async {
    if (!isSupported) return;
    try {
      await _methodChannel.invokeMethod<bool>('cancelExport', {
        'jobId': jobId,
      });
    } catch (_) {}
  }

  @override
  Future<void> shareClip({
    required String filePath,
    required String title,
    required Rect sharePositionOrigin,
  }) async {
    final fileName = _fileName(title);
    await _nativeShare(
      ShareParams(
        files: [XFile(filePath, name: fileName, mimeType: 'video/mp4')],
        fileNameOverrides: [fileName],
        title: title,
        subject: title,
        sharePositionOrigin: _safeOrigin(sharePositionOrigin),
      ),
    );
  }

  @override
  Future<String?> saveClip({
    required String filePath,
    required String title,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Moment clip saving is unavailable on this platform.');
    }
    return _androidSave(
      sourcePath: filePath,
      fileName: _fileName(title),
      mimeType: 'video/mp4',
    );
  }

  Future<File> _allocateOutputFile(String title) async {
    final tempDir = await _temporaryDirectoryFactory();
    final root = await Directory(
      p.join(tempDir.path, _directoryName),
    ).create(recursive: true);
    await _pruneExpiredExports(root);
    final dir = await root.createTemp('clip_');
    await File(p.join(dir.path, _markerName)).writeAsString('v1', flush: true);
    return File(p.join(dir.path, _fileName(title)));
  }

  Future<void> _pruneExpiredExports(Directory root) async {
    if (!await root.exists()) return;
    final cutoff = _clock().subtract(_retention);
    final kept = <({Directory dir, DateTime modified, int bytes})>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final marker = File(p.join(entity.path, _markerName));
      if (!await marker.exists()) continue;
      final stat = await marker.stat();
      var totalBytes = 0;
      await for (final child in entity.list(followLinks: false)) {
        if (child is File) {
          totalBytes += (await child.stat()).size;
        }
      }
      if (stat.modified.isBefore(cutoff)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      } else {
        kept.add((dir: entity, modified: stat.modified, bytes: totalBytes));
      }
    }

    kept.sort((a, b) => a.modified.compareTo(b.modified));
    var used = kept.fold<int>(0, (sum, item) => sum + item.bytes);
    for (final item in kept) {
      if (used <= _maxCacheBytes) break;
      try {
        await item.dir.delete(recursive: true);
        used -= item.bytes;
      } catch (_) {}
    }
  }

  static String _fileName(String title) {
    final cleaned = title
        .trim()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final safe = cleaned.isEmpty
        ? 'momento'
        : cleaned.substring(0, cleaned.length > 42 ? 42 : cleaned.length);
    return 'InutilMusic_$safe.mp4';
  }

  static Rect _safeOrigin(Rect origin) {
    if (origin.isEmpty || origin.width <= 0 || origin.height <= 0) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    return origin;
  }

  static AppPlatformType _currentPlatform() => AppPlatform.current;

  static Future<void> _defaultShare(ShareParams params) =>
      SharePlus.instance.share(params);

  static Future<String?> _defaultAndroidSave({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) => const AndroidFileExportChannel().saveFile(
    sourcePath: sourcePath,
    fileName: fileName,
    mimeType: mimeType,
  );
}
