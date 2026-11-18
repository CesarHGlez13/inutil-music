import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player style codes are stable and decode defensively', () {
    expect(PlayerStyle.inutilMusic.code, 'inutilMusic');
    expect(PlayerStyle.appleMusic.code, 'appleMusic');
    expect(PlayerStyle.classicVinyl.code, 'classicVinyl');
    expect(PlayerStyle.spotifyMusic.code, 'spotifyMusic');
    expect(PlayerStyle.fromCode('inutilMusic'), PlayerStyle.inutilMusic);
    expect(PlayerStyle.fromCode('appleMusic'), PlayerStyle.appleMusic);
    expect(PlayerStyle.fromCode('classicVinyl'), PlayerStyle.classicVinyl);
    expect(PlayerStyle.fromCode('spotifyMusic'), PlayerStyle.spotifyMusic);
    expect(PlayerStyle.fromCode(null), defaultPlayerStyle);
    expect(PlayerStyle.fromCode('futureStyle'), defaultPlayerStyle);
    expect(defaultPlayerStyle, PlayerStyle.inutilMusic);
  });
}
