enum PlayerStyle {
  inutilMusic,
  appleMusic,
  classicVinyl,
  spotifyMusic;

  String get code => switch (this) {
    PlayerStyle.inutilMusic => 'inutilMusic',
    PlayerStyle.appleMusic => 'appleMusic',
    PlayerStyle.classicVinyl => 'classicVinyl',
    PlayerStyle.spotifyMusic => 'spotifyMusic',
  };

  static PlayerStyle fromCode(String? code) {
    return switch (code) {
      'inutilMusic' => PlayerStyle.inutilMusic,
      'appleMusic' => PlayerStyle.appleMusic,
      'classicVinyl' => PlayerStyle.classicVinyl,
      'spotifyMusic' => PlayerStyle.spotifyMusic,
      _ => defaultPlayerStyle,
    };
  }
}

// Missing values belong to installations created before player styles were
// configurable, so they must retain Inutix Music's original player.
const defaultPlayerStyle = PlayerStyle.inutilMusic;
