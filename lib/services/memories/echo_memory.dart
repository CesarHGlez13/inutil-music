import 'package:flutter/foundation.dart';

/// A personal memory attached by the user to a song ("Echo Memory").
@immutable
class EchoMemory {
  const EchoMemory({
    required this.id,
    required this.trackKey,
    required this.titleArtistKey,
    required this.trackTitle,
    required this.trackArtist,
    this.trackThumbnailUrl,
    required this.note,
    required this.memoryDate,
    this.photoFileName,
    this.showOnPlayback = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Canonical track identity (YouTube videoId when available, otherwise trackId).
  final String trackKey;

  /// Normalized `title::artist` fallback key so a memory still matches if the
  /// user plays a downloaded copy vs a streamed copy of the same song.
  final String titleArtistKey;
  final String trackTitle;
  final String trackArtist;
  final String? trackThumbnailUrl;
  final String note;
  final DateTime memoryDate;

  /// Relative filename stored privately by `EchoMemoryPhotoService`.
  final String? photoFileName;

  /// Privacy toggle per memory: when false, the floating banner never shows
  /// automatically during playback.
  final bool showOnPlayback;
  final DateTime createdAt;
  final DateTime updatedAt;

  EchoMemory copyWith({
    String? id,
    String? trackKey,
    String? titleArtistKey,
    String? trackTitle,
    String? trackArtist,
    String? trackThumbnailUrl,
    String? note,
    DateTime? memoryDate,
    Object? photoFileName = _unchanged,
    bool? showOnPlayback,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EchoMemory(
      id: id ?? this.id,
      trackKey: trackKey ?? this.trackKey,
      titleArtistKey: titleArtistKey ?? this.titleArtistKey,
      trackTitle: trackTitle ?? this.trackTitle,
      trackArtist: trackArtist ?? this.trackArtist,
      trackThumbnailUrl: trackThumbnailUrl ?? this.trackThumbnailUrl,
      note: note ?? this.note,
      memoryDate: memoryDate ?? this.memoryDate,
      photoFileName: identical(photoFileName, _unchanged)
          ? this.photoFileName
          : photoFileName as String?,
      showOnPlayback: showOnPlayback ?? this.showOnPlayback,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDbMap() => <String, Object?>{
    'id': id,
    'track_key': trackKey,
    'title_artist_key': titleArtistKey,
    'track_title': trackTitle,
    'track_artist': trackArtist,
    'track_thumbnail_url': trackThumbnailUrl,
    'note': note,
    'memory_date': memoryDate.toUtc().toIso8601String(),
    'photo_file_name': photoFileName,
    'show_on_playback': showOnPlayback ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory EchoMemory.fromDbMap(Map<String, Object?> map) {
    final now = DateTime.now().toUtc();
    return EchoMemory(
      id: (map['id'] ?? '').toString(),
      trackKey: (map['track_key'] ?? '').toString(),
      titleArtistKey: (map['title_artist_key'] ?? '').toString(),
      trackTitle: (map['track_title'] ?? '').toString(),
      trackArtist: (map['track_artist'] ?? '').toString(),
      trackThumbnailUrl: _nonEmpty(map['track_thumbnail_url']?.toString()),
      note: (map['note'] ?? '').toString(),
      memoryDate:
          DateTime.tryParse(map['memory_date']?.toString() ?? '') ?? now,
      photoFileName: _nonEmpty(map['photo_file_name']?.toString()),
      showOnPlayback: (map['show_on_playback'] as num?)?.toInt() != 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? now,
    );
  }

  Map<String, dynamic> toCloudJson() => <String, dynamic>{
    'id': id,
    'trackKey': trackKey,
    'titleArtistKey': titleArtistKey,
    'trackTitle': trackTitle,
    'trackArtist': trackArtist,
    if (trackThumbnailUrl != null) 'trackThumbnailUrl': trackThumbnailUrl,
    'note': note,
    'memoryDate': memoryDate.toUtc().toIso8601String(),
    if (photoFileName != null) 'photoFileName': photoFileName,
    'showOnPlayback': showOnPlayback,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static EchoMemory? fromCloudJson(Map<String, dynamic> json) {
    final id = _nonEmpty(json['id']?.toString());
    final note = _nonEmpty(json['note']?.toString());
    if (id == null || note == null) return null;
    final now = DateTime.now().toUtc();
    final trackTitle = (json['trackTitle'] ?? '').toString().trim();
    final trackArtist = (json['trackArtist'] ?? '').toString().trim();
    final trackKey = _nonEmpty(json['trackKey']?.toString()) ?? id;
    final titleArtistKey =
        _nonEmpty(json['titleArtistKey']?.toString()) ??
        normalizedEchoMemoryTitleArtistKey(trackTitle, trackArtist);
    return EchoMemory(
      id: id,
      trackKey: trackKey,
      titleArtistKey: titleArtistKey,
      trackTitle: trackTitle.isEmpty ? 'Canción' : trackTitle,
      trackArtist: trackArtist.isEmpty ? 'Inutix Music' : trackArtist,
      trackThumbnailUrl: _nonEmpty(json['trackThumbnailUrl']?.toString()),
      note: note,
      memoryDate:
          DateTime.tryParse(json['memoryDate']?.toString() ?? '') ?? now,
      photoFileName: _nonEmpty(json['photoFileName']?.toString()),
      showOnPlayback: json['showOnPlayback'] != false,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }

  bool matchesTrack({
    String? trackKey,
    String? title,
    String? artist,
  }) {
    final normalizedKey = trackKey?.trim() ?? '';
    if (normalizedKey.isNotEmpty && this.trackKey == normalizedKey) {
      return true;
    }
    final normalizedTitle = (title ?? '').trim();
    if (normalizedTitle.isEmpty) return false;
    final candidatePair = normalizedEchoMemoryTitleArtistKey(
      normalizedTitle,
      artist ?? '',
    );
    return candidatePair.isNotEmpty && candidatePair == titleArtistKey;
  }

  String formattedDate({bool spanish = true}) {
    final local = memoryDate.toLocal();
    const monthsEs = <String>[
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    const monthsEn = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = (spanish ? monthsEs : monthsEn)[(local.month - 1).clamp(0, 11)];
    return '${local.day} $month ${local.year}';
  }

  static const Object _unchanged = Object();

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// Normalizes `(title, artist)` for cross-source Echo Memory matching
/// (downloaded local file <-> YouTube Music stream).
String normalizedEchoMemoryTitleArtistKey(String title, String artist) {
  String clean(String input) {
    var text = input.toLowerCase().trim();
    text = text.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
    text = text.replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final normalizedTitle = clean(title);
  final normalizedArtist = clean(artist);
  if (normalizedTitle.isEmpty) return '';
  return '$normalizedTitle::$normalizedArtist';
}
