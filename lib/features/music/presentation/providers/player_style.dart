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
      // 'bstreamMusic' es el valor que escribieron en Preferencias las
      // versiones 2.0.x (nombre del proyecto original): se sigue aceptando
      // para que nadie pierda el estilo de reproductor elegido.
      'inutilMusic' || 'bstreamMusic' => PlayerStyle.inutilMusic,
      'appleMusic' => PlayerStyle.appleMusic,
      'classicVinyl' => PlayerStyle.classicVinyl,
      'spotifyMusic' => PlayerStyle.spotifyMusic,
      _ => defaultPlayerStyle,
    };
  }
}

// Missing values belong to installations created before player styles were
// configurable, so they must retain Inútil Music's original player.
const defaultPlayerStyle = PlayerStyle.inutilMusic;
