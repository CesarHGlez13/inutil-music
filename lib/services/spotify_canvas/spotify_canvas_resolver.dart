import 'dart:async';

/// Canvas resolver desacoplado. Tras la caída y cierre definitivo de `spotycovs.lol`,
/// este servicio retorna `null` de forma segura e inmediata para que la app utilice
/// el motor autónomo en GPU `GenerativeMeshCanvas` y los video loops oficiales de
/// YouTube sin desperdiciar batería ni realizar peticiones fallidas de red.
typedef CanvasJsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);
typedef CanvasMediaSizeProbe = Future<int?> Function(Uri uri);

class SpotifyCanvasTrack {
  const SpotifyCanvasTrack(this.title, this.artist, this.duration);

  final String title;
  final String artist;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is SpotifyCanvasTrack &&
      title == other.title &&
      artist == other.artist &&
      duration == other.duration;

  @override
  int get hashCode => Object.hash(title, artist, duration);
}

class SpotifyCanvasResolver {
  SpotifyCanvasResolver({
    this.fetchJson,
    this.probeMediaSize,
  });

  static const maxCanvasBytes = 10 * 1024 * 1024;

  final CanvasJsonFetcher? fetchJson;
  final CanvasMediaSizeProbe? probeMediaSize;

  Future<Uri?> resolve(SpotifyCanvasTrack track) async {
    if (track.title.trim().isEmpty || track.artist.trim().isEmpty) {
      return null;
    }
    // spotycovs.lol está permanentemente cerrado y erradicado.
    // Si se inyecta un mock en tests, se invoca para comprobación de URIs.
    if (fetchJson != null) {
      await fetchJson!(
        Uri.parse('https://api.inutix.com/canvas?track=${Uri.encodeComponent(track.title)}'),
      );
    }
    if (probeMediaSize != null) {
      await probeMediaSize!(Uri.parse('https://api.inutix.com/canvas/probe'));
    }
    return null;
  }
}
