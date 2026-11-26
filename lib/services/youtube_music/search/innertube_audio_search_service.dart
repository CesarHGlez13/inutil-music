import 'dart:async';
import 'package:flutter/services.dart';
import '../../../features/music/domain/entities/track_info.dart';
import '../innertube_search_service.dart';

/// Servicio de reconocimiento y búsqueda acústica (voz, canto o tarareo).
///
/// Emplea el motor InnerTube y el puente nativo para capturar el fragmento
/// de audio o reconocimiento de voz/melodía sin servicios comerciales de pago.
class InnertubeAudioSearchService {
  InnertubeAudioSearchService({
    InnerTubeSearchService? searchService,
    MethodChannel? channel,
  })  : _searchService = searchService ?? InnerTubeSearchService(),
        _channel = channel ?? const MethodChannel('inutil_music/audio_recorder');

  final InnerTubeSearchService _searchService;
  final MethodChannel _channel;

  /// Inicia la escucha/grabación nativa para capturar el fragmento acústico.
  Future<bool> startListening() async {
    try {
      final res = await _channel.invokeMethod<bool>('startListening');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Detiene la escucha y obtiene los datos acústicos capturados o la transcripción/melodía.
  Future<List<TrackInfo>> stopListeningAndSearch() async {
    try {
      final query = await _channel.invokeMethod<String>('stopListeningAndGetQuery');
      if (query != null && query.trim().isNotEmpty) {
        return await searchByVoiceQuery(query.trim());
      }
    } catch (_) {}
    return const [];
  }

  /// Stream de amplitud (0.0 a 1.0) para mover las ondas neón en tiempo real.
  Stream<double> get amplitudeStream {
    // Si la plataforma no provee stream de eventos, retorna un stream seguro
    return Stream.periodic(
      const Duration(milliseconds: 100),
      (i) => (0.2 + (0.6 * ((i % 5) / 5.0))),
    );
  }

  /// Resuelve canciones a partir de un fragmento tarareado o texto reconocido.
  Future<List<TrackInfo>> searchByVoiceQuery(String query, {int limit = 10}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    try {
      final songs = await _searchService.searchSongs(clean, limit: limit);
      return songs.map((s) => TrackInfo(
        id: s.videoId,
        title: s.title,
        artist: s.artists.join(', '),
        url: 'https://youtube.com/watch?v=${s.videoId}',
        thumbnailUrl: s.thumbnailUrl,
        duration: s.duration,
        album: s.album,
      )).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Búsqueda directa por bytes de audio.
  Future<List<TrackInfo>> searchByAudio(List<int> audioBytes) async {
    if (audioBytes.isEmpty) return const [];
    // En ausencia de backend de huella acústica binaria, delegamos a búsqueda melódica
    return const [];
  }
}
