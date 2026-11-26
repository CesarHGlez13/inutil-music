enum LyricsAnimationStyle {
  smooth,
  slide,
  highlight,
  karaoke,
  cinematic;

  String get code => name;

  static LyricsAnimationStyle fromCode(String? code) {
    return switch (code) {
      'slide' => LyricsAnimationStyle.slide,
      'highlight' => LyricsAnimationStyle.highlight,
      'karaoke' => LyricsAnimationStyle.karaoke,
      'cinematic' => LyricsAnimationStyle.cinematic,
      _ => LyricsAnimationStyle.smooth,
    };
  }
}
