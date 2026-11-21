import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Puente Dart para el motor nativo Android dedicado exclusivamente a video
/// de fondo (`InutilCanvasEnginePlugin`).
///
/// Ventajas frente a `video_player`:
///  - Cero AudioRenderer / AudioTrack / AudioFlinger: jamás interfiere con el
///    stream musical ni con salidas Bluetooth.
///  - Hilo de reproducción aislado de baja prioridad (`InutilCanvasPlayback`).
///  - Bucle en hardware sin lecturas GPU->CPU (`toImage`) ni sondeos por frame.
class InutilCanvasEngine {
  InutilCanvasEngine._();

  static const MethodChannel _method = MethodChannel(
    'inutil_music/canvas_video',
  );
  static const EventChannel _events = EventChannel(
    'inutil_music/canvas_video/events',
  );

  @visibleForTesting
  static bool? debugOverrideSupported;

  /// En Android real el motor dedicado sustituye a `video_player` para fondos
  /// silenciados. Las pruebas pueden anularlo con [debugOverrideSupported], o
  /// cuando sustituyen `VideoPlayerPlatform.instance` por un doble de test.
  static bool get isSupported {
    if (debugOverrideSupported != null) return debugOverrideSupported!;
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Platform.isAndroid;
  }

  static bool shouldUseNativeAndroidEngine(
    Object? videoPlayerPlatformInstance,
  ) {
    if (debugOverrideSupported != null) return debugOverrideSupported!;
    if (!isSupported) return false;
    final typeName = videoPlayerPlatformInstance?.runtimeType.toString() ?? '';
    return typeName == 'AndroidVideoPlayer' ||
        typeName == 'MethodChannelVideoPlayer';
  }

  static Stream<Map<dynamic, dynamic>>? _broadcastEvents;

  static Stream<Map<dynamic, dynamic>> get events {
    return _broadcastEvents ??= _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .cast<Map<dynamic, dynamic>>();
  }

  static Future<InutilCanvasController> create({
    required Uri uri,
    required Duration startOffset,
    required Duration durationHint,
    required bool playing,
  }) async {
    final result = await _method.invokeMapMethod<String, dynamic>('create', {
      'uri': uri.toString(),
      'startOffsetMs': startOffset.inMilliseconds,
      'durationHintMs': durationHint.inMilliseconds,
      'playing': playing,
    });
    if (result == null) {
      throw PlatformException(
        code: 'null_result',
        message: 'Canvas engine returned null',
      );
    }
    final playerId = (result['playerId'] as num).toInt();
    final textureId = (result['textureId'] as num).toInt();
    return InutilCanvasController._(playerId: playerId, textureId: textureId);
  }

  static Future<void> setPlaying(int playerId, bool playing) async {
    try {
      await _method.invokeMethod<void>('setPlaying', {
        'playerId': playerId,
        'playing': playing,
      });
    } catch (_) {}
  }

  static Future<void> disposePlayer(int playerId) async {
    try {
      await _method.invokeMethod<void>('dispose', {'playerId': playerId});
    } catch (_) {}
  }
}

class InutilCanvasController {
  InutilCanvasController._({required this.playerId, required this.textureId}) {
    _subscription = InutilCanvasEngine.events.listen(_handleEvent);
  }

  final int playerId;
  final int textureId;

  StreamSubscription<Map<dynamic, dynamic>>? _subscription;
  VoidCallback? onReady;
  VoidCallback? onSizeChanged;
  VoidCallback? onError;

  bool _ready = false;
  bool _disposed = false;
  Size _size = Size.zero;
  int _rotation = 0;

  bool get isReady => _ready;
  bool get isDisposed => _disposed;
  Size get size => _size;
  int get rotationDegrees => _rotation;

  void _handleEvent(Map<dynamic, dynamic> event) {
    if (_disposed) return;
    final eventPlayerId = (event['playerId'] as num?)?.toInt();
    if (eventPlayerId != playerId) return;
    switch (event['event']) {
      case 'ready':
        _size = Size(
          (event['width'] as num?)?.toDouble() ?? 0,
          (event['height'] as num?)?.toDouble() ?? 0,
        );
        _rotation = (event['rotation'] as num?)?.toInt() ?? 0;
        _ready = true;
        onReady?.call();
        break;
      case 'size':
        _size = Size(
          (event['width'] as num?)?.toDouble() ?? _size.width,
          (event['height'] as num?)?.toDouble() ?? _size.height,
        );
        _rotation = (event['rotation'] as num?)?.toInt() ?? _rotation;
        onSizeChanged?.call();
        break;
      case 'error':
        _ready = false;
        onError?.call();
        break;
    }
  }

  Future<void> setPlaying(bool playing) async {
    if (_disposed) return;
    await InutilCanvasEngine.setPlaying(playerId, playing);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    onReady = null;
    onSizeChanged = null;
    onError = null;
    final sub = _subscription;
    _subscription = null;
    unawaited(sub?.cancel());
    await InutilCanvasEngine.disposePlayer(playerId);
  }
}

class InutilCanvasTextureView extends StatelessWidget {
  const InutilCanvasTextureView({required this.controller, super.key});

  final InutilCanvasController controller;

  @override
  Widget build(BuildContext context) {
    final child = Texture(textureId: controller.textureId);
    final quarterTurns = (controller.rotationDegrees ~/ 90) % 4;
    if (quarterTurns == 0) return child;
    return RotatedBox(quarterTurns: quarterTurns, child: child);
  }
}
