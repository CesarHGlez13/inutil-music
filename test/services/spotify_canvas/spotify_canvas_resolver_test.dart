import 'package:inutil_music/services/spotify_canvas/spotify_canvas_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const track = SpotifyCanvasTrack(
    'Woman (Official Video)',
    'Doja Cat',
    Duration(seconds: 173),
  );

  test('resolves safely to null without contacting spotycovs.lol', () async {
    final requestedUris = <Uri>[];
    final resolver = SpotifyCanvasResolver(
      fetchJson: (uri) async {
        requestedUris.add(uri);
        return null;
      },
      probeMediaSize: (_) async => null,
    );

    final url = await resolver.resolve(track);
    expect(url, isNull);
    for (final uri in requestedUris) {
      expect(uri.host.contains('spotycovs'), isFalse);
    }
  });

  test('empty or invalid track returns null immediately', () async {
    final resolver = SpotifyCanvasResolver();
    expect(await resolver.resolve(const SpotifyCanvasTrack('', '', Duration.zero)), isNull);
    expect(await resolver.resolve(const SpotifyCanvasTrack('Title', '  ', Duration.zero)), isNull);
  });
}
