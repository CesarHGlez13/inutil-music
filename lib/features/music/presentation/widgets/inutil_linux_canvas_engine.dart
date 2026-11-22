import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final class _MpvRenderParam extends ffi.Struct {
  @ffi.Int32()
  external int type;

  external ffi.Pointer<ffi.Void> data;
}

typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

typedef _MpvCreateNative = ffi.Pointer<ffi.Void> Function();
typedef _MpvCreateDart = ffi.Pointer<ffi.Void> Function();

typedef _MpvInitializeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _MpvInitializeDart = int Function(ffi.Pointer<ffi.Void>);

typedef _MpvSetOptionStringNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _MpvSetOptionStringDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );

typedef _MpvSetPropertyStringNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _MpvSetPropertyStringDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );

typedef _MpvGetPropertyStringNative =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _MpvGetPropertyStringDart =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
    );

typedef _MpvFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _MpvFreeDart = void Function(ffi.Pointer<ffi.Void>);

typedef _MpvCommandNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
    );
typedef _MpvCommandDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Uint8>>);

typedef _MpvRenderContextCreateNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<_MpvRenderParam>,
    );
typedef _MpvRenderContextCreateDart =
    int Function(
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<_MpvRenderParam>,
    );

typedef _MpvRenderContextUpdateNative =
    ffi.Uint64 Function(ffi.Pointer<ffi.Void>);
typedef _MpvRenderContextUpdateDart = int Function(ffi.Pointer<ffi.Void>);

typedef _MpvRenderContextRenderNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_MpvRenderParam>);
typedef _MpvRenderContextRenderDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_MpvRenderParam>);

typedef _MpvRenderContextFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _MpvRenderContextFreeDart = void Function(ffi.Pointer<ffi.Void>);

typedef _MpvTerminateDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _MpvTerminateDestroyDart = void Function(ffi.Pointer<ffi.Void>);

class _MpvBindings {
  _MpvBindings._() {
    final libc = ffi.DynamicLibrary.process();
    malloc = libc.lookupFunction<_MallocNative, _MallocDart>('malloc');
    free = libc.lookupFunction<_FreeNative, _FreeDart>('free');
    final mpv = _openMpv();
    mpvCreate = mpv.lookupFunction<_MpvCreateNative, _MpvCreateDart>(
      'mpv_create',
    );
    mpvInitialize = mpv
        .lookupFunction<_MpvInitializeNative, _MpvInitializeDart>(
          'mpv_initialize',
        );
    mpvSetOptionString = mpv
        .lookupFunction<_MpvSetOptionStringNative, _MpvSetOptionStringDart>(
          'mpv_set_option_string',
        );
    mpvSetPropertyString = mpv
        .lookupFunction<_MpvSetPropertyStringNative, _MpvSetPropertyStringDart>(
          'mpv_set_property_string',
        );
    mpvGetPropertyString = mpv
        .lookupFunction<_MpvGetPropertyStringNative, _MpvGetPropertyStringDart>(
          'mpv_get_property_string',
        );
    mpvFree = mpv.lookupFunction<_MpvFreeNative, _MpvFreeDart>('mpv_free');
    mpvCommand = mpv.lookupFunction<_MpvCommandNative, _MpvCommandDart>(
      'mpv_command',
    );
    mpvRenderContextCreate = mpv
        .lookupFunction<
          _MpvRenderContextCreateNative,
          _MpvRenderContextCreateDart
        >('mpv_render_context_create');
    mpvRenderContextUpdate = mpv
        .lookupFunction<
          _MpvRenderContextUpdateNative,
          _MpvRenderContextUpdateDart
        >('mpv_render_context_update');
    mpvRenderContextRender = mpv
        .lookupFunction<
          _MpvRenderContextRenderNative,
          _MpvRenderContextRenderDart
        >('mpv_render_context_render');
    mpvRenderContextFree = mpv
        .lookupFunction<_MpvRenderContextFreeNative, _MpvRenderContextFreeDart>(
          'mpv_render_context_free',
        );
    mpvTerminateDestroy = mpv
        .lookupFunction<_MpvTerminateDestroyNative, _MpvTerminateDestroyDart>(
          'mpv_terminate_destroy',
        );
  }

  static _MpvBindings? _instance;

  static _MpvBindings? tryLoad() {
    if (_instance != null) return _instance;
    try {
      return _instance = _MpvBindings._();
    } catch (_) {
      return null;
    }
  }

  static ffi.DynamicLibrary _openMpv() {
    for (final candidate in const ['libmpv.so.2', 'libmpv.so.1', 'libmpv.so']) {
      try {
        return ffi.DynamicLibrary.open(candidate);
      } catch (_) {}
    }
    throw StateError('libmpv shared library not available');
  }

  late final _MallocDart malloc;
  late final _FreeDart free;
  late final _MpvCreateDart mpvCreate;
  late final _MpvInitializeDart mpvInitialize;
  late final _MpvSetOptionStringDart mpvSetOptionString;
  late final _MpvSetPropertyStringDart mpvSetPropertyString;
  late final _MpvGetPropertyStringDart mpvGetPropertyString;
  late final _MpvFreeDart mpvFree;
  late final _MpvCommandDart mpvCommand;
  late final _MpvRenderContextCreateDart mpvRenderContextCreate;
  late final _MpvRenderContextUpdateDart mpvRenderContextUpdate;
  late final _MpvRenderContextRenderDart mpvRenderContextRender;
  late final _MpvRenderContextFreeDart mpvRenderContextFree;
  late final _MpvTerminateDestroyDart mpvTerminateDestroy;

  ffi.Pointer<ffi.Uint8> allocCString(String value) {
    final bytes = utf8.encode(value);
    final ptr = malloc(bytes.length + 1).cast<ffi.Uint8>();
    for (var i = 0; i < bytes.length; i++) {
      ptr[i] = bytes[i];
    }
    ptr[bytes.length] = 0;
    return ptr;
  }

  String? readCString(ffi.Pointer<ffi.Uint8> ptr) {
    if (ptr == ffi.nullptr) return null;
    var length = 0;
    while (ptr[length] != 0 && length < 4096) {
      length++;
    }
    return utf8.decode(ptr.asTypedList(length), allowMalformed: true);
  }
}

/// Motor de vídeo silencioso en Linux basado en `libmpv.so.2` (`MPV_RENDER_API_TYPE_SW`)
/// para reproducir Spotify Canvas y portadas animadas sin requerir plugins C++
/// adicionales ni interferir con el motor de audio principal.
class InutilLinuxCanvasEngine {
  InutilLinuxCanvasEngine._();

  @visibleForTesting
  static bool? debugOverrideSupported;

  static bool shouldUseNativeLinuxEngine(Object? videoPlayerPlatformInstance) {
    if (debugOverrideSupported != null) return debugOverrideSupported!;
    if (kIsWeb || !Platform.isLinux) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    final typeName = videoPlayerPlatformInstance?.runtimeType.toString() ?? '';
    return !typeName.contains('Fake');
  }

  static Future<InutilLinuxCanvasController> create({
    required Uri uri,
    required Duration startOffset,
    required Duration durationHint,
    required bool playing,
  }) async {
    final bindings = _MpvBindings.tryLoad();
    if (bindings == null) {
      throw StateError('libmpv unavailable for Linux Canvas engine');
    }
    final controller = InutilLinuxCanvasController._(
      bindings: bindings,
      uri: uri,
      startOffset: startOffset,
      durationHint: durationHint,
      initialPlaying: playing,
    );
    controller._initialize();
    return controller;
  }
}

class InutilLinuxCanvasController {
  InutilLinuxCanvasController._({
    required this._bindings,
    required this.uri,
    required this.startOffset,
    required this.durationHint,
    required bool initialPlaying,
  }) : _playing = initialPlaying;

  final _MpvBindings _bindings;
  final Uri uri;
  final Duration startOffset;
  final Duration durationHint;

  final ValueNotifier<ui.Image?> frameListenable = ValueNotifier<ui.Image?>(
    null,
  );

  VoidCallback? onReady;
  VoidCallback? onSizeChanged;
  VoidCallback? onError;

  Size _size = const Size(384, 640);
  Size get size => _size;

  bool _playing;
  bool _disposed = false;
  bool _readyNotified = false;
  bool _decodingImage = false;
  bool _dimensionsResolved = false;

  int _renderWidth = 384;
  int _renderHeight = 640;

  ffi.Pointer<ffi.Void> _mpvHandle = ffi.nullptr;
  ffi.Pointer<ffi.Void> _renderCtx = ffi.nullptr;
  ffi.Pointer<ffi.Int32> _sizePtr = ffi.nullptr;
  ffi.Pointer<ffi.Uint8> _formatPtr = ffi.nullptr;
  ffi.Pointer<ffi.IntPtr> _stridePtr = ffi.nullptr;
  ffi.Pointer<ffi.Int32> _blockPtr = ffi.nullptr;
  ffi.Pointer<ffi.Uint8> _pixelBuffer = ffi.nullptr;
  ffi.Pointer<_MpvRenderParam> _renderParams = ffi.nullptr;
  Timer? _frameTimer;

  void _setOption(String key, String value) {
    final k = _bindings.allocCString(key);
    final v = _bindings.allocCString(value);
    try {
      _bindings.mpvSetOptionString(_mpvHandle, k, v);
    } finally {
      _bindings.free(k.cast());
      _bindings.free(v.cast());
    }
  }

  void _setProperty(String key, String value) {
    if (_mpvHandle == ffi.nullptr) return;
    final k = _bindings.allocCString(key);
    final v = _bindings.allocCString(value);
    try {
      _bindings.mpvSetPropertyString(_mpvHandle, k, v);
    } finally {
      _bindings.free(k.cast());
      _bindings.free(v.cast());
    }
  }

  String? _getProperty(String key) {
    if (_mpvHandle == ffi.nullptr) return null;
    final k = _bindings.allocCString(key);
    try {
      final res = _bindings.mpvGetPropertyString(_mpvHandle, k);
      if (res == ffi.nullptr) return null;
      try {
        return _bindings.readCString(res);
      } finally {
        _bindings.mpvFree(res.cast());
      }
    } finally {
      _bindings.free(k.cast());
    }
  }

  void _initialize() {
    _mpvHandle = _bindings.mpvCreate();
    if (_mpvHandle == ffi.nullptr) {
      throw StateError('mpv_create failed');
    }
    _setOption('vo', 'libmpv');
    _setOption('ao', 'null');
    _setOption('aid', 'no');
    _setOption('sid', 'no');
    _setOption('loop-file', 'inf');
    _setOption('profile', 'sw-fast');
    _setOption('hwdec', 'no');
    _setOption('vd-lavc-threads', '2');
    if (startOffset > Duration.zero) {
      final sec = (startOffset.inMilliseconds / 1000.0).toStringAsFixed(2);
      _setOption('start', '+$sec');
      _setOption('ab-loop-a', sec);
    }
    final initRc = _bindings.mpvInitialize(_mpvHandle);
    if (initRc < 0) {
      _bindings.mpvTerminateDestroy(_mpvHandle);
      _mpvHandle = ffi.nullptr;
      throw StateError('mpv_initialize failed ($initRc)');
    }

    final resPtr = _bindings
        .malloc(ffi.sizeOf<ffi.Pointer<ffi.Void>>())
        .cast<ffi.Pointer<ffi.Void>>();
    resPtr.value = ffi.nullptr;
    final createParams = _bindings
        .malloc(ffi.sizeOf<_MpvRenderParam>() * 2)
        .cast<_MpvRenderParam>();
    final swStr = _bindings.allocCString('sw');
    try {
      (createParams + 0).ref.type = 1; // MPV_RENDER_PARAM_API_TYPE
      (createParams + 0).ref.data = swStr.cast();
      (createParams + 1).ref.type = 0; // MPV_RENDER_PARAM_INVALID
      (createParams + 1).ref.data = ffi.nullptr;
      final rc = _bindings.mpvRenderContextCreate(
        resPtr,
        _mpvHandle,
        createParams,
      );
      if (rc < 0 || resPtr.value == ffi.nullptr) {
        _bindings.mpvTerminateDestroy(_mpvHandle);
        _mpvHandle = ffi.nullptr;
        throw StateError('mpv_render_context_create failed ($rc)');
      }
      _renderCtx = resPtr.value;
    } finally {
      _bindings.free(swStr.cast());
      _bindings.free(createParams.cast());
      _bindings.free(resPtr.cast());
    }

    _allocateRenderBuffers(_renderWidth, _renderHeight);

    final target = uri.scheme == 'file'
        ? File.fromUri(uri).path
        : uri.toString();
    _command(['loadfile', target, 'replace']);
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 66),
      (_) => _pollFrame(),
    );
  }

  void _allocateRenderBuffers(int width, int height) {
    if (_pixelBuffer != ffi.nullptr) {
      _bindings.free(_pixelBuffer.cast());
      _pixelBuffer = ffi.nullptr;
    }
    if (_sizePtr == ffi.nullptr) {
      _sizePtr = _bindings
          .malloc(ffi.sizeOf<ffi.Int32>() * 2)
          .cast<ffi.Int32>();
    }
    if (_formatPtr == ffi.nullptr) {
      _formatPtr = _bindings.allocCString('rgb0');
    }
    if (_stridePtr == ffi.nullptr) {
      _stridePtr = _bindings
          .malloc(ffi.sizeOf<ffi.IntPtr>())
          .cast<ffi.IntPtr>();
    }
    if (_blockPtr == ffi.nullptr) {
      _blockPtr = _bindings.malloc(ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
      _blockPtr.value = 0;
    }
    if (_renderParams == ffi.nullptr) {
      _renderParams = _bindings
          .malloc(ffi.sizeOf<_MpvRenderParam>() * 6)
          .cast<_MpvRenderParam>();
    }

    _renderWidth = width;
    _renderHeight = height;
    final stride = width * 4;
    _sizePtr[0] = width;
    _sizePtr[1] = height;
    _stridePtr.value = stride;
    _pixelBuffer = _bindings.malloc(stride * height).cast<ffi.Uint8>();

    (_renderParams + 0).ref.type = 17; // MPV_RENDER_PARAM_SW_SIZE
    (_renderParams + 0).ref.data = _sizePtr.cast();
    (_renderParams + 1).ref.type = 18; // MPV_RENDER_PARAM_SW_FORMAT
    (_renderParams + 1).ref.data = _formatPtr.cast();
    (_renderParams + 2).ref.type = 19; // MPV_RENDER_PARAM_SW_STRIDE
    (_renderParams + 2).ref.data = _stridePtr.cast();
    (_renderParams + 3).ref.type = 20; // MPV_RENDER_PARAM_SW_POINTER
    (_renderParams + 3).ref.data = _pixelBuffer.cast();
    (_renderParams + 4).ref.type = 12; // MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME
    (_renderParams + 4).ref.data = _blockPtr.cast();
    (_renderParams + 5).ref.type = 0; // MPV_RENDER_PARAM_INVALID
    (_renderParams + 5).ref.data = ffi.nullptr;
  }

  void _command(List<String> args) {
    if (_mpvHandle == ffi.nullptr) return;
    final ptrs = <ffi.Pointer<ffi.Uint8>>[];
    final argv = _bindings
        .malloc(ffi.sizeOf<ffi.Pointer<ffi.Uint8>>() * (args.length + 1))
        .cast<ffi.Pointer<ffi.Uint8>>();
    try {
      for (var i = 0; i < args.length; i++) {
        final c = _bindings.allocCString(args[i]);
        ptrs.add(c);
        argv[i] = c;
      }
      argv[args.length] = ffi.nullptr;
      _bindings.mpvCommand(_mpvHandle, argv);
    } finally {
      for (final p in ptrs) {
        _bindings.free(p.cast());
      }
      _bindings.free(argv.cast());
    }
  }

  void _pollFrame() {
    if (_disposed ||
        _decodingImage ||
        _renderCtx == ffi.nullptr ||
        _mpvHandle == ffi.nullptr) {
      return;
    }
    if (_readyNotified && !_playing) {
      return;
    }

    if (!_dimensionsResolved) {
      final rawW = int.tryParse(_getProperty('video-params/w') ?? '');
      final rawH = int.tryParse(_getProperty('video-params/h') ?? '');
      if (rawW != null && rawH != null && rawW > 0 && rawH > 0) {
        _dimensionsResolved = true;
        final ratio = rawW / rawH;
        // Pick a compact 64-byte-stride-aligned resolution matching aspect ratio
        final int targetW;
        final int targetH;
        if (ratio < 0.75) {
          targetW = 320;
          targetH = 568;
        } else if (ratio <= 1.15) {
          targetW = 384;
          targetH = 384;
        } else {
          targetW = 480;
          targetH = 270;
        }
        if (targetW != _renderWidth || targetH != _renderHeight) {
          _allocateRenderBuffers(targetW, targetH);
        }
        _size = Size(rawW.toDouble(), rawH.toDouble());
        onSizeChanged?.call();
      } else {
        return;
      }
    }

    final flags = _bindings.mpvRenderContextUpdate(_renderCtx);
    if ((flags & 1) == 0 && _readyNotified) {
      return;
    }

    final rc = _bindings.mpvRenderContextRender(_renderCtx, _renderParams);
    if (rc < 0) return;

    final byteCount = _renderWidth * _renderHeight * 4;
    final rawView = _pixelBuffer.asTypedList(byteCount);
    final copy = Uint8List.fromList(rawView);
    final words = copy.buffer.asUint32List();
    // Ignore completely black uninitialized priming frames before first decode
    var nonZeroSamples = 0;
    final step = (words.length ~/ 32).clamp(1, 4096);
    for (var i = 0; i < words.length; i += step) {
      if ((words[i] & 0x00FFFFFF) != 0) {
        nonZeroSamples++;
      }
    }
    for (var i = 0; i < words.length; i++) {
      words[i] |= 0xFF000000;
    }
    if (!_readyNotified && nonZeroSamples == 0) {
      return;
    }

    _decodingImage = true;
    final w = _renderWidth;
    final h = _renderHeight;
    ui.decodeImageFromPixels(copy, w, h, ui.PixelFormat.rgba8888, (image) {
      _decodingImage = false;
      if (_disposed) {
        image.dispose();
        return;
      }
      final prev = frameListenable.value;
      frameListenable.value = image;
      if (prev != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => prev.dispose());
      }
      if (!_readyNotified) {
        _readyNotified = true;
        if (!_playing) {
          _setProperty('pause', 'yes');
        }
        onReady?.call();
      }
    });
  }

  Future<void> setPlaying(bool playing) async {
    if (_disposed || _playing == playing) return;
    _playing = playing;
    if (_readyNotified) {
      _setProperty('pause', playing ? 'no' : 'yes');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _frameTimer?.cancel();
    _frameTimer = null;
    final prev = frameListenable.value;
    frameListenable.value = null;
    if (prev != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => prev.dispose());
    }
    frameListenable.dispose();

    final rctx = _renderCtx;
    _renderCtx = ffi.nullptr;
    if (rctx != ffi.nullptr) {
      _bindings.mpvRenderContextFree(rctx);
    }
    final mpv = _mpvHandle;
    _mpvHandle = ffi.nullptr;
    if (mpv != ffi.nullptr) {
      _bindings.mpvTerminateDestroy(mpv);
    }

    for (final ptr in <ffi.Pointer<ffi.Void>>[
      _renderParams.cast(),
      _pixelBuffer.cast(),
      _blockPtr.cast(),
      _stridePtr.cast(),
      _formatPtr.cast(),
      _sizePtr.cast(),
    ]) {
      if (ptr != ffi.nullptr) {
        _bindings.free(ptr);
      }
    }
    _renderParams = ffi.nullptr;
    _pixelBuffer = ffi.nullptr;
    _blockPtr = ffi.nullptr;
    _stridePtr = ffi.nullptr;
    _formatPtr = ffi.nullptr;
    _sizePtr = ffi.nullptr;
  }
}

class InutilLinuxCanvasTextureView extends StatelessWidget {
  const InutilLinuxCanvasTextureView({required this.controller, super.key});

  final InutilLinuxCanvasController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ui.Image?>(
      valueListenable: controller.frameListenable,
      builder: (context, frame, _) {
        if (frame == null) return const SizedBox.shrink();
        return RawImage(
          image: frame,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}
