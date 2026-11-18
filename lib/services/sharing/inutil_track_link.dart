import '../../features/music/domain/entities/track_info.dart';

/// A legacy Inutil link backed by a canonical YouTube video identity.
///
/// Stream URLs are deliberately never represented here: Google Video URLs
/// are signed, short lived, and may contain request credentials.
/// New outgoing shares use a recognized HTTPS URL; [appUri] remains available
/// only so links shared by older versions keep opening in Inútil Music.
final class InutilTrackLink {
  const InutilTrackLink({required this.videoId});

  final String videoId;

  Uri get appUri => Uri(
    scheme: InutilTrackLinkCodec.scheme,
    host: InutilTrackLinkCodec.host,
    pathSegments: [videoId],
  );

  Uri get youtubeUri =>
      Uri.https('www.youtube.com', '/watch', <String, String>{'v': videoId});

  Uri get youtubeMusicUri =>
      Uri.https('music.youtube.com', '/watch', <String, String>{'v': videoId});
}

/// Encodes and validates the public link contract used by Inútil Music.
class InutilTrackLinkCodec {
  const InutilTrackLinkCodec();

  static const scheme = 'inutilmusic';
  /// Esquema que usaron las versiones 2.0.x. Los enlaces ya compartidos
  /// (`bstreammusic://track/<id>`) siguen abriendo Inútil Music.
  static const legacyScheme = 'bstreammusic';
  static const host = 'track';
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  InutilTrackLink decode(Uri uri) {
    final decoded = tryDecode(uri);
    if (decoded == null) {
      throw FormatException('Invalid Inútil Music track link.', uri);
    }
    return decoded;
  }

  InutilTrackLink? tryDecode(Uri uri) {
    final schemeName = uri.scheme.toLowerCase();
    if (schemeName != scheme && schemeName != legacyScheme ||
        uri.host.toLowerCase() != host ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1) {
      return null;
    }
    final videoId = uri.pathSegments.single;
    return _videoIdPattern.hasMatch(videoId)
        ? InutilTrackLink(videoId: videoId)
        : null;
  }

  InutilTrackLink fromTrack(TrackInfo track) {
    final link = tryFromTrack(track);
    if (link == null) {
      throw const FormatException(
        'The track does not contain a shareable YouTube identity.',
      );
    }
    return link;
  }

  InutilTrackLink? tryFromTrack(TrackInfo track) {
    // Prefer the canonical catalog URL. An id is used only when the URL is
    // absent or not a recognized YouTube reference.
    final videoId = extractVideoId(track.url) ?? extractVideoId(track.id);
    return videoId == null ? null : InutilTrackLink(videoId: videoId);
  }

  /// Returns one canonical HTTPS link suitable for messaging applications.
  ///
  /// InnerTube metadata and an existing YouTube Music URL are treated as a
  /// positive signal that the Music link is available. Generic YouTube search
  /// results keep the regular watch URL instead of being mislabeled as Music.
  Uri shareUriForTrack(TrackInfo track) {
    final link = fromTrack(track);
    final sourceUri = Uri.tryParse(track.url.trim());
    final hasYouTubeMusicSource =
        track.metadataSource == TrackMetadataSource.youtubeMusic ||
        sourceUri?.host.toLowerCase() == 'music.youtube.com';
    return hasYouTubeMusicSource ? link.youtubeMusicUri : link.youtubeUri;
  }

  String? extractVideoId(String candidate) {
    final normalized = candidate.trim();
    if (_videoIdPattern.hasMatch(normalized)) {
      return normalized;
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme.toLowerCase() != 'https' &&
            uri.scheme.toLowerCase() != 'http')) {
      return null;
    }

    final normalizedHost = uri.host.toLowerCase();
    if (normalizedHost == 'youtu.be') {
      return _validVideoId(uri.pathSegments.firstOrNull);
    }
    final isYouTubeHost =
        normalizedHost == 'youtube.com' ||
        normalizedHost.endsWith('.youtube.com') ||
        normalizedHost == 'youtube-nocookie.com' ||
        normalizedHost.endsWith('.youtube-nocookie.com');
    if (!isYouTubeHost) {
      return null;
    }

    if (uri.path == '/watch') {
      return _validVideoId(uri.queryParameters['v']);
    }
    if (uri.pathSegments.length == 2 &&
        const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
      return _validVideoId(uri.pathSegments[1]);
    }
    return null;
  }

  String? _validVideoId(String? candidate) {
    return candidate != null && _videoIdPattern.hasMatch(candidate)
        ? candidate
        : null;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
