import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_auth_service.dart';
import 'firebase_config.dart';

/// Servicio para Firebase Storage (subida de carátulas e imágenes de perfil).
class InutilStorageService {
  InutilStorageService._();
  static final InutilStorageService instance = InutilStorageService._();

  final InutilAuthService _auth = InutilAuthService.instance;

  String? get _idToken => _auth.currentUser?.idToken;

  /// Subir imagen (avatar de usuario o carátula propia) a Firebase Storage.
  Future<String?> uploadImage({
    required String storagePath,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final encodedPath = Uri.encodeComponent(storagePath);
    final url = Uri.parse(
      '${FirebaseConfig.storageBaseUrl}?name=$encodedPath',
    );

    final headers = {
      'Content-Type': contentType,
      if (_idToken != null && _idToken!.isNotEmpty)
        'Authorization': 'Bearer $_idToken',
    };

    final response = await http.post(url, headers: headers, body: bytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final downloadToken = json['downloadTokens'] as String?;
      final name = json['name'] as String? ?? storagePath;
      final encodedName = Uri.encodeComponent(name);
      return 'https://firebasestorage.googleapis.com/v0/b/${FirebaseConfig.storageBucket}/o/$encodedName?alt=media${downloadToken != null ? '&token=$downloadToken' : ''}';
    }

    debugPrint('Error subiendo imagen a Firebase Storage: ${response.body}');
    return null;
  }

  /// Subir archivo local desde ruta del sistema de archivos.
  Future<String?> uploadFile({
    required String storagePath,
    required File file,
    String contentType = 'image/jpeg',
  }) async {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return uploadImage(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
    );
  }
}
