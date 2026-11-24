import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Stores optional Echo Memory photos as bounded JPEGs inside private app
/// support storage so container relocations never leave broken absolute paths.
class EchoMemoryPhotoService {
  EchoMemoryPhotoService({
    Future<Directory> Function()? supportDirectoryProvider,
    this.maxSourceBytes = 25 * 1024 * 1024,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const int maxEdgePixels = 1600;
  static const int jpegQuality = 85;

  final Future<Directory> Function() _supportDirectoryProvider;
  final int maxSourceBytes;
  static final RegExp _validFileName = RegExp(
    r'^echo_memory_[0-9]+_[0-9]+\.jpg$',
  );

  Future<String> saveFile(File file) async {
    final length = await file.length();
    if (length <= 0 || length > maxSourceBytes) {
      throw const FormatException('La foto seleccionada supera el tamaño permitido.');
    }
    final rawBytes = await file.readAsBytes();
    final optimized = await compute(_optimizeEchoMemoryPhoto, rawBytes);
    final directory = await _photosDirectory();
    await directory.create(recursive: true);
    final fileName =
        'echo_memory_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}.jpg';
    final temp = File(path.join(directory.path, '$fileName.tmp'));
    final dest = File(path.join(directory.path, fileName));
    try {
      await temp.writeAsBytes(optimized, flush: true);
      await temp.rename(dest.path);
      return fileName;
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<String?> resolve(String? fileName) async {
    if (fileName == null || !_validFileName.hasMatch(fileName)) return null;
    final directory = await _photosDirectory();
    final file = File(path.join(directory.path, fileName));
    return await file.exists() ? file.path : null;
  }

  Future<void> delete(String? fileName) async {
    if (fileName == null || !_validFileName.hasMatch(fileName)) return;
    final directory = await _photosDirectory();
    final file = File(path.join(directory.path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _photosDirectory() async {
    final support = await _supportDirectoryProvider();
    return Directory(path.join(support.path, 'echo_memory_photos'));
  }
}

Uint8List _optimizeEchoMemoryPhoto(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('No se pudo leer la imagen seleccionada.');
  }
  final oriented = image.bakeOrientation(decoded);
  final maxEdge = EchoMemoryPhotoService.maxEdgePixels;
  final resized = (oriented.width > maxEdge || oriented.height > maxEdge)
      ? (oriented.width >= oriented.height
            ? image.copyResize(oriented, width: maxEdge)
            : image.copyResize(oriented, height: maxEdge))
      : oriented;
  return Uint8List.fromList(
    image.encodeJpg(resized, quality: EchoMemoryPhotoService.jpegQuality),
  );
}
