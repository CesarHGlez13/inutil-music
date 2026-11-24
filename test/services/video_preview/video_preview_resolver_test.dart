import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/services/video_preview/video_preview_resolver.dart';

void main() {
  group('VideoPreviewResolver', () {
    test(
      'parses iTunes musicVideo payload and upgrades artwork resolution',
      () {
        final clips = VideoPreviewResolver.parseItunesMusicVideoResults({
          'resultCount': 2,
          'results': [
            {
              'trackName': 'De Los Besos Que Te Di',
              'artistName': 'Christian Nodal',
              'primaryGenreName': 'Música Mexicana',
              'previewUrl':
                  'https://video-ssl.itunes.apple.com/assets/clip1.m4v',
              'artworkUrl100':
                  'https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg',
              'trackTimeMillis': 167000,
            },
            {
              'trackName': 'Sin preview',
              'artistName': 'Christian Nodal',
              'previewUrl': null,
            },
          ],
        });

        expect(clips, hasLength(1));
        expect(clips.first.title, 'De Los Besos Que Te Di');
        expect(clips.first.artist, 'Christian Nodal');
        expect(
          clips.first.videoUrl,
          Uri.parse('https://video-ssl.itunes.apple.com/assets/clip1.m4v'),
        );
        expect(
          clips.first.artworkUrl,
          'https://is1-ssl.mzstatic.com/image/thumb/x/600x600bb.jpg',
        );
        expect(clips.first.tags, contains('#música mexicana'));
        expect(clips.first.duration, const Duration(milliseconds: 167000));
      },
    );

    test(
      'resolveForTrack matches exact track and caches subsequent lookups',
      () async {
        var calls = 0;
        final resolver = VideoPreviewResolver(
          fetchJson: (uri) async {
            calls++;
            return {
              'results': [
                {
                  'trackName': 'Otra Canción',
                  'artistName': 'Christian Nodal',
                  'previewUrl': 'https://video-ssl.itunes.apple.com/other.m4v',
                },
                {
                  'trackName': 'De Los Besos Que Te Di',
                  'artistName': 'Christian Nodal',
                  'previewUrl': 'https://video-ssl.itunes.apple.com/besos.m4v',
                },
              ],
            };
          },
        );

        final first = await resolver.resolveForTrack(
          title: 'De Los Besos Que Te Di',
          artist: 'Christian Nodal',
        );
        final second = await resolver.resolveForTrack(
          title: 'De Los Besos Que Te Di',
          artist: 'Christian Nodal',
        );

        expect(
          first?.videoUrl.toString(),
          'https://video-ssl.itunes.apple.com/besos.m4v',
        );
        expect(second, equals(first));
        expect(calls, 1);
      },
    );

    test(
      'resolveClipsForArtist filters unrelated artists and deduplicates titles',
      () async {
        final resolver = VideoPreviewResolver(
          fetchJson: (_) async => {
            'results': [
              {
                'trackName': 'Adiós Amor',
                'artistName': 'Christian Nodal',
                'previewUrl': 'https://video-ssl.itunes.apple.com/a1.m4v',
              },
              {
                'trackName': 'Adiós Amor',
                'artistName': 'Christian Nodal',
                'previewUrl': 'https://video-ssl.itunes.apple.com/a2.m4v',
              },
              {
                'trackName': 'Cover Tribute',
                'artistName': 'Banda Ajena',
                'previewUrl': 'https://video-ssl.itunes.apple.com/other.m4v',
              },
              {
                'trackName': 'Se Me Olvidó',
                'artistName': 'Christian Nodal',
                'previewUrl': 'https://video-ssl.itunes.apple.com/s1.m4v',
              },
            ],
          },
        );

        final clips = await resolver.resolveClipsForArtist(
          artistName: 'Christian Nodal',
        );
        expect(clips.map((c) => c.title), ['Adiós Amor', 'Se Me Olvidó']);
      },
    );

    test('returns null/empty cleanly when network fails', () async {
      final resolver = VideoPreviewResolver(
        fetchJson: (_) async => throw StateError('offline'),
      );

      expect(
        await resolver.resolveForTrack(title: 'Test', artist: 'Artist'),
        isNull,
      );
      expect(
        await resolver.resolveClipsForArtist(artistName: 'Artist'),
        isEmpty,
      );
    });

    test(
      'resolveForTrack returns null instead of using another song by the same artist or unrelated title match',
      () async {
        final resolver = VideoPreviewResolver(
          fetchJson: (_) async => {
            'results': [
              {
                'trackName': 'Adiós Amor',
                'artistName': 'Christian Nodal',
                'previewUrl': 'https://video-ssl.itunes.apple.com/other.m4v',
              },
              {
                'trackName': 'Perdonarte',
                'artistName': 'Otro Artista Ajeno',
                'previewUrl': 'https://video-ssl.itunes.apple.com/wrong.m4v',
              },
            ],
          },
        );

        final resolved = await resolver.resolveForTrack(
          title: 'Perdonarte ¿Para Qué?',
          artist: 'Christian Nodal',
        );

        expect(resolved, isNull);
      },
    );

    test(
      'resolveForTrack finds exact match via title-only search when combined query returns nothing',
      () async {
        var queryCount = 0;
        // Combined "Artist Title" → empty; title-only → has the exact match.
        final resolver = VideoPreviewResolver(
          fetchJson: (uri) async {
            queryCount++;
            final term = uri.queryParameters['term'] ?? '';
            if (term == 'Christian Nodal Perdonarte Para Que' ||
                term == 'Christian Nodal') {
              return {'results': <dynamic>[]};
            }
            // title-only query
            return {
              'results': [
                {
                  'trackName': 'Perdonarte Para Que',
                  'artistName': 'Christian Nodal',
                  'previewUrl':
                      'https://video-ssl.itunes.apple.com/perdonarte.m4v',
                },
              ],
            };
          },
        );

        final resolved = await resolver.resolveForTrack(
          title: 'Perdonarte Para Que',
          artist: 'Christian Nodal',
        );

        expect(
          resolved?.videoUrl.toString(),
          'https://video-ssl.itunes.apple.com/perdonarte.m4v',
        );
        // Combined + title-only searches fired (artist-only not needed).
        expect(queryCount, 2);
      },
    );

    test(
      'resolveForTrack finds exact match via artist-only search when combined and title queries return nothing',
      () async {
        var queryCount = 0;
        final resolver = VideoPreviewResolver(
          fetchJson: (uri) async {
            queryCount++;
            final term = uri.queryParameters['term'] ?? '';
            if (term.contains('Nodal') && term.contains('Besos')) {
              return {'results': <dynamic>[]};
            }
            if (term == 'De Los Besos Que Te Di') {
              return {'results': <dynamic>[]};
            }
            // artist-only query returns the right clip
            return {
              'results': [
                {
                  'trackName': 'De Los Besos Que Te Di',
                  'artistName': 'Christian Nodal',
                  'previewUrl': 'https://video-ssl.itunes.apple.com/besos.m4v',
                },
              ],
            };
          },
        );

        final resolved = await resolver.resolveForTrack(
          title: 'De Los Besos Que Te Di',
          artist: 'Christian Nodal',
        );

        expect(
          resolved?.videoUrl.toString(),
          'https://video-ssl.itunes.apple.com/besos.m4v',
        );
        expect(queryCount, 3); // combined + title-only + artist-only
      },
    );

    test(
      'resolveForTrack still returns null when extended searches return only wrong artist',
      () async {
        final resolver = VideoPreviewResolver(
          fetchJson: (_) async => {
            'results': [
              {
                'trackName': 'De Los Besos Que Te Di',
                'artistName': 'Artista Incorrecto',
                'previewUrl': 'https://video-ssl.itunes.apple.com/wrong.m4v',
              },
            ],
          },
        );

        final resolved = await resolver.resolveForTrack(
          title: 'De Los Besos Que Te Di',
          artist: 'Christian Nodal',
        );

        expect(resolved, isNull);
      },
    );
  });
}
