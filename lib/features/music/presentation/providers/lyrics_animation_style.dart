enum LyricsAnimationStyle {
  smooth,
  slide,
  highlight,
  karaoke,
  cinematic,
  zoom;

  String get code => name;

  static LyricsAnimationStyle fromCode(String? code) {
    return switch (code) {
      'slide' => LyricsAnimationStyle.slide,
      'highlight' => LyricsAnimationStyle.highlight,
      'karaoke' => LyricsAnimationStyle.karaoke,
      'cinematic' => LyricsAnimationStyle.cinematic,
      'zoom' => LyricsAnimationStyle.zoom,
      _ => LyricsAnimationStyle.smooth,
    };
  }
}
