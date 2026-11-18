import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_auth_service.dart';
import 'firebase_config.dart';

/// Fallo al leer un documento de Firestore distinto de «no existe».
///
/// `toString()` se mantiene en una sola línea corta: los cuerpos de error de
/// Google son JSON de varias líneas y volcarlos completos inunda logcat cada
/// pocos segundos cuando el proyecto o sus reglas no permiten la lectura.
class FirestoreOperationException implements Exception {
  const FirestoreOperationException(this.path, this.statusCode, this.body);

  final String path;
  final int statusCode;
  final String body;

  @override
  String toString() =>
      'FirestoreOperationException($statusCode en $path): '
      '${InutilFirestoreService.briefErrorBody(body)}';
}

/// Servicio de Cloud Firestore multiplataforma mediante REST API optimizada.
class InutilFirestoreService {
  InutilFirestoreService._();
  static final InutilFirestoreService instance = InutilFirestoreService._();

  final InutilAuthService _auth = InutilAuthService.instance;

  String? get _idToken => _auth.currentUser?.idToken;

  /// Reduce el cuerpo de un error de Google a una sola línea legible.
  static String briefErrorBody(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return 'sin respuesta';
    return flat.length <= 180 ? flat : '${flat.substring(0, 180)}…';
  }
  String? get _uid => _auth.currentUser?.uid;

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (!FirebaseConfig.useEmulator) 'X-Goog-Api-Key': FirebaseConfig.apiKey,
      if (_idToken != null && _idToken!.isNotEmpty)
        'Authorization': 'Bearer $_idToken',
    };
  }

  // ---------------------------------------------------------------------------
  // 1. SERIALIZACIÓN FIRESTORE REST (Dart Map <-> Firestore Value Formats)
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _encodeFields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    for (final entry in data.entries) {
      fields[entry.key] = _encodeValue(entry.value);
    }
    return {'fields': fields};
  }

  Map<String, dynamic> _encodeValue(dynamic value) {
    if (value == null) {
      return {'nullValue': null};
    } else if (value is bool) {
      return {'booleanValue': value};
    } else if (value is int) {
      return {'integerValue': value.toString()};
    } else if (value is double) {
      return {'doubleValue': value};
    } else if (value is String) {
      return {'stringValue': value};
    } else if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    } else if (value is List) {
      return {
        'arrayValue': {
          'values': value.map(_encodeValue).toList(),
        },
      };
    } else if (value is Map<String, dynamic>) {
      final mapFields = <String, dynamic>{};
      for (final e in value.entries) {
        mapFields[e.key] = _encodeValue(e.value);
      }
      return {
        'mapValue': {'fields': mapFields},
      };
    }
    return {'stringValue': value.toString()};
  }

  Map<String, dynamic> _decodeDocument(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    final result = <String, dynamic>{};
    for (final entry in fields.entries) {
      result[entry.key] = _decodeValue(entry.value as Map<String, dynamic>);
    }
    return result;
  }

  dynamic _decodeValue(Map<String, dynamic> val) {
    if (val.containsKey('stringValue')) return val['stringValue'];
    if (val.containsKey('integerValue')) return int.tryParse(val['integerValue']) ?? 0;
    if (val.containsKey('doubleValue')) return (val['doubleValue'] as num).toDouble();
    if (val.containsKey('booleanValue')) return val['booleanValue'];
    if (val.containsKey('timestampValue')) return DateTime.tryParse(val['timestampValue']);
    if (val.containsKey('nullValue')) return null;
    if (val.containsKey('arrayValue')) {
      final values = val['arrayValue']['values'] as List?;
      if (values == null) return [];
      return values.map((e) => _decodeValue(e as Map<String, dynamic>)).toList();
    }
    if (val.containsKey('mapValue')) {
      final fields = val['mapValue']['fields'] as Map<String, dynamic>?;
      if (fields == null) return {};
      final res = <String, dynamic>{};
      for (final e in fields.entries) {
        res[e.key] = _decodeValue(e.value as Map<String, dynamic>);
      }
      return res;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 2. DOCUMENTOS Y COLECCIONES
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getDocument(String path) async {
    final url = Uri.parse('${FirebaseConfig.firestoreBaseUrl}/$path');
    final response = await http.get(url, headers: _headers());
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      // Un 403/500 no es «el documento no existe»: es que el proyecto o las
      // reglas no dejan leer. Se propaga como excepción para que el sondeo
      // pueda aplicar backoff en vez de reintentar cada 3 segundos.
      throw FirestoreOperationException(path, response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _decodeDocument(json);
  }

  /// Construye la URI de PATCH con `updateMask.fieldPaths` para actualizaciones
  /// parciales seguras (preservando `email`, `displayName`, `role`, etc.).
  @visibleForTesting
  static Uri buildPatchUri(
    String path,
    Iterable<String> fieldPaths, {
    bool merge = true,
  }) {
    final base = Uri.parse('${FirebaseConfig.firestoreBaseUrl}/$path');
    if (!merge || fieldPaths.isEmpty) return base;
    return base.replace(
      queryParameters: {
        'updateMask.fieldPaths': fieldPaths.toList(growable: false),
      },
    );
  }

  Future<bool> setDocument(
    String path,
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    final url = buildPatchUri(path, data.keys, merge: merge);
    final body = jsonEncode(_encodeFields(data));
    final response = await http.patch(url, headers: _headers(), body: body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
    debugPrint('Firestore PATCH error ($path): '
        '${briefErrorBody(response.body)}');
    return false;
  }

  Future<bool> deleteDocument(String path) async {
    final url = Uri.parse('${FirebaseConfig.firestoreBaseUrl}/$path');
    final response = await http.delete(url, headers: _headers());
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  // ---------------------------------------------------------------------------
  // 3. SINCRONIZACIÓN DE FAVORITOS
  // ---------------------------------------------------------------------------
  Future<void> syncFavoriteTrack({
    required String trackId,
    required String title,
    required String artist,
    required String? album,
    required String? thumbnailUrl,
    required bool isFavorite,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final path = 'users/$uid/favorites/$trackId';
    if (isFavorite) {
      await setDocument(path, {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'album': album ?? '',
        'thumbnailUrl': thumbnailUrl ?? '',
        'favoritedAt': DateTime.now(),
      });
    } else {
      await deleteDocument(path);
    }
  }

  // ---------------------------------------------------------------------------
  // 4. SINCRONIZACIÓN DE HISTORIAL
  // ---------------------------------------------------------------------------
  Future<void> recordHistory({
    required String trackId,
    required String title,
    required String artist,
    required String? album,
    required String? thumbnailUrl,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final path = 'users/$uid/history/$trackId';
    await setDocument(path, {
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'album': album ?? '',
      'thumbnailUrl': thumbnailUrl ?? '',
      'playedAt': DateTime.now(),
    });
  }

  // ---------------------------------------------------------------------------
  // 5. GESTIÓN Y SINCRONIZACIÓN DE PERFILES DE USUARIOS (ADMINISTRACIÓN)
  // ---------------------------------------------------------------------------
  Future<bool> saveUserProfile(InutilUser user) async {
    final path = 'users/${user.uid}';
    return await setDocument(path, {
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'role': user.role,
      'isActive': user.isActive,
      'accountExpiresAt': user.accountExpiresAt,
      'accountDurationDays': user.accountDurationDays,
      'lastLoginAt': DateTime.now(),
    });
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    return await getDocument('users/$uid');
  }

  Future<bool> adminUpdateUser(String uid, Map<String, dynamic> updates) async {
    final path = 'users/$uid';
    return await setDocument(path, updates);
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final url = Uri.parse('${FirebaseConfig.firestoreBaseUrl}/users?pageSize=100');
      final response = await http.get(url, headers: _headers()).timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != 200) {
        debugPrint('Firestore getAllUsers info: ${response.statusCode}');
        return [];
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = json['documents'] as List?;
      if (docs == null) return [];
      final result = <Map<String, dynamic>>[];
      for (final doc in docs) {
        if (doc is Map<String, dynamic>) {
          final fields = _decodeDocument(doc);
          final name = doc['name'] as String? ?? '';
          final docUid = name.split('/').last;
          if (!fields.containsKey('uid') || (fields['uid'] as String).isEmpty) {
            fields['uid'] = docUid;
          }
          result.add(fields);
        }
      }
      return result;
    } catch (e) {
      debugPrint('Firestore getAllUsers offline / fallback: $e');
      return [];
    }
  }
}
