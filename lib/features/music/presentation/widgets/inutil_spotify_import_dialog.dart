import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/inutil_design_system.dart';
import '../../../../services/storage/library_csv_import_service.dart';
import '../../../../services/storage/library_csv_service.dart';
import '../providers/music_providers.dart';
import 'library_csv_import_dialog.dart';

const Color _spotifyNeonGreen = Color(0xFF1DB954);

/// Muestra el diálogo modal ultra-premium de importación de playlists de Spotify,
/// archivos CSV (Exportify / Soundiiz) y listas en texto libre para Inutix Music.
Future<void> showInutilSpotifyImportDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar importador de Spotify',
    barrierColor: Colors.black.withValues(alpha: 0.78),
    transitionDuration: InutilDesignSystem.durationNormal,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: InutilDesignSystem.spaceMd,
            vertical: InutilDesignSystem.spaceLg,
          ),
          child: _InutilSpotifyImportModal(
            parentContext: context,
            parentRef: ref,
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: InutilDesignSystem.curveEnter,
        reverseCurve: InutilDesignSystem.curveExit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SpotifyParsedTrack {
  const _SpotifyParsedTrack({
    required this.title,
    required this.artist,
    required this.artists,
    required this.durationMs,
    required this.uri,
  });

  final String title;
  final String artist;
  final List<String> artists;
  final int durationMs;
  final String uri;

  String get formattedDuration {
    if (durationMs <= 0) return '--:--';
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _SpotifyParsedEntity {
  const _SpotifyParsedEntity({
    required this.id,
    required this.type,
    required this.title,
    required this.coverUrl,
    required this.tracks,
  });

  final String id;
  final String type;
  final String title;
  final String? coverUrl;
  final List<_SpotifyParsedTrack> tracks;
}

class _InutilSpotifyImportModal extends ConsumerStatefulWidget {
  const _InutilSpotifyImportModal({
    required this.parentContext,
    required this.parentRef,
  });

  final BuildContext parentContext;
  final WidgetRef parentRef;

  @override
  ConsumerState<_InutilSpotifyImportModal> createState() =>
      _InutilSpotifyImportModalState();
}

class _InutilSpotifyImportModalState
    extends ConsumerState<_InutilSpotifyImportModal> {
  int _selectedTab = 0;

  // Tab 0: Enlace de Spotify
  final TextEditingController _spotifyUrlController = TextEditingController();
  final TextEditingController _spotifyPlaylistNameController =
      TextEditingController();
  bool _analyzingSpotify = false;
  String? _spotifyError;
  _SpotifyParsedEntity? _parsedSpotify;

  // Tab 1: Archivo CSV
  bool _pickingCsv = false;
  String? _csvError;

  // Tab 2: Texto Libre
  final TextEditingController _freeTextPlaylistController =
      TextEditingController(text: 'Mi Playlist Importada');
  final TextEditingController _freeTextLinesController =
      TextEditingController();
  String? _freeTextError;

  // Estado compartido de importación activa en este diálogo
  bool _importStartedHere = false;

  @override
  void dispose() {
    _spotifyUrlController.dispose();
    _spotifyPlaylistNameController.dispose();
    _freeTextPlaylistController.dispose();
    _freeTextLinesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PARSER Y EXTRACTOR DE SPOTIFY EMBED (__NEXT_DATA__)
  // ---------------------------------------------------------------------------
  ({String type, String id})? _extractSpotifyResource(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    // Formato URI: spotify:playlist:37i9dQZF1DXcBWIGoYBM5M o spotify:album:...
    final uriMatch = RegExp(
      r'spotify:(playlist|album):([A-Za-z0-9]{15,32})',
      caseSensitive: false,
    ).firstMatch(input);
    if (uriMatch != null) {
      return (type: uriMatch.group(1)!.toLowerCase(), id: uriMatch.group(2)!);
    }

    // Formato URL: https://open.spotify.com/(intl-xx/)?(embed/)?(playlist|album)/{id}
    final urlMatch = RegExp(
      r'open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?(?:embed/)?(playlist|album)/([A-Za-z0-9]{15,32})',
      caseSensitive: false,
    ).firstMatch(input);
    if (urlMatch != null) {
      return (type: urlMatch.group(1)!.toLowerCase(), id: urlMatch.group(2)!);
    }

    return null;
  }

  Future<void> _analyzeSpotifyUrl() async {
    final resource = _extractSpotifyResource(_spotifyUrlController.text);
    if (resource == null) {
      setState(() {
        _spotifyError =
            'Ingresa un enlace válido de playlist o álbum público de Spotify '
            '(ej. https://open.spotify.com/playlist/...).';
      });
      return;
    }

    setState(() {
      _analyzingSpotify = true;
      _spotifyError = null;
      _parsedSpotify = null;
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final embedUri = Uri.parse(
        'https://open.spotify.com/embed/${resource.type}/${resource.id}',
      );
      final request = await client.getUrl(embedUri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'es-ES,es;q=0.9,en;q=0.8',
      );

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw FormatException(
          'Spotify respondió con código HTTP ${response.statusCode}. '
          'Verifica que la ${resource.type == 'album' ? 'álbum' : 'playlist'} sea pública.',
        );
      }

      final html = await response.transform(utf8.decoder).join();
      final scriptMatch = RegExp(
        r'<script\s+id="__NEXT_DATA__"\s+type="application/json"[^>]*>([\s\S]*?)</script>',
        caseSensitive: false,
      ).firstMatch(html);

      if (scriptMatch == null || scriptMatch.group(1) == null) {
        throw const FormatException(
          'No se encontró el bloque __NEXT_DATA__ en la respuesta de Spotify.',
        );
      }

      final decoded = jsonDecode(scriptMatch.group(1)!) as Map<String, dynamic>;
      final props = decoded['props'] as Map<String, dynamic>?;
      final pageProps = props?['pageProps'] as Map<String, dynamic>?;
      final state = pageProps?['state'] as Map<String, dynamic>?;
      final data = state?['data'] as Map<String, dynamic>?;
      final entity = data?['entity'] as Map<String, dynamic>?;

      if (entity == null) {
        throw const FormatException(
          'No se pudo extraer la información de la entidad desde Spotify.',
        );
      }

      final rawTitle = (entity['title'] ?? entity['name'] ?? 'Spotify Playlist')
          .toString()
          .replaceAll('\u00a0', ' ')
          .trim();

      String? coverUrl;
      final coverArt = entity['coverArt'] as Map<String, dynamic>?;
      final sources = coverArt?['sources'] as List?;
      if (sources != null && sources.isNotEmpty) {
        for (final source in sources) {
          if (source is Map<String, dynamic>) {
            final url = source['url']?.toString().trim();
            if (url != null && url.isNotEmpty) {
              coverUrl = url;
              break;
            }
          }
        }
      }

      final rawTrackList = entity['trackList'] as List?;
      if (rawTrackList == null || rawTrackList.isEmpty) {
        throw const FormatException(
          'La playlist o álbum no contiene pistas públicas disponibles.',
        );
      }

      final parsedTracks = <_SpotifyParsedTrack>[];
      for (final item in rawTrackList) {
        if (item is! Map<String, dynamic>) continue;
        final trackTitle = (item['title'] ?? '')
            .toString()
            .replaceAll('\u00a0', ' ')
            .trim();
        if (trackTitle.isEmpty) continue;

        final rawSubtitle = (item['subtitle'] ?? '')
            .toString()
            .replaceAll('\u00a0', ' ')
            .trim();
        final artists = rawSubtitle
            .split(',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList(growable: false);
        final primaryArtist = artists.isNotEmpty ? artists.first : rawSubtitle;

        final rawDuration = item['duration'];
        final durationMs = switch (rawDuration) {
          final int ms => ms,
          final num ms => ms.toInt(),
          final String s => int.tryParse(s) ?? 0,
          _ => 0,
        };

        final uri = (item['uri'] ?? '').toString().trim();

        parsedTracks.add(
          _SpotifyParsedTrack(
            title: trackTitle,
            artist: primaryArtist,
            artists: artists,
            durationMs: durationMs,
            uri: uri,
          ),
        );
      }

      if (parsedTracks.isEmpty) {
        throw const FormatException(
          'No se pudieron extraer canciones válidas del enlace de Spotify.',
        );
      }

      if (!mounted) return;
      setState(() {
        _parsedSpotify = _SpotifyParsedEntity(
          id: resource.id,
          type: resource.type,
          title: rawTitle.isEmpty ? 'Playlist de Spotify' : rawTitle,
          coverUrl: coverUrl,
          tracks: parsedTracks,
        );
        _spotifyPlaylistNameController.text = rawTitle.isEmpty
            ? 'Playlist de Spotify'
            : rawTitle;
        _analyzingSpotify = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzingSpotify = false;
        _spotifyError = e.toString().replaceFirst(
          RegExp(r'^(FormatException|Exception):\s*'),
          '',
        );
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _importSpotifyEntity() async {
    final parsed = _parsedSpotify;
    if (parsed == null || parsed.tracks.isEmpty) return;

    final playlistName = _spotifyPlaylistNameController.text.trim().isEmpty
        ? parsed.title
        : _spotifyPlaylistNameController.text.trim();

    final csvTracks = <LibraryCsvTrack>[];
    for (var i = 0; i < parsed.tracks.length; i++) {
      final t = parsed.tracks[i];
      csvTracks.add(
        LibraryCsvTrack(
          rowNumber: i + 1,
          title: t.title,
          artist: t.artist,
          artists: t.artists,
          duration: t.durationMs > 0
              ? Duration(milliseconds: t.durationMs)
              : null,
          thumbnailUrl: parsed.coverUrl,
          sourceUri: t.uri.isEmpty ? null : t.uri,
          memberships: [LibraryCsvMembership(name: playlistName, position: i)],
        ),
      );
    }

    final document = LibraryCsvDocument(
      tracks: List.unmodifiable(csvTracks),
      detectedFormat: LibraryCsvDetectedFormat.exportify,
      defaultPlaylistName: playlistName,
      hasPlaylistColumn: true,
    );

    await _startDocumentImport(document);
  }

  // ---------------------------------------------------------------------------
  // IMPORTADOR DE TEXTO LIBRE (Artista - Canción)
  // ---------------------------------------------------------------------------
  Future<void> _importFreeText() async {
    final rawName = _freeTextPlaylistController.text.trim();
    final playlistName = rawName.isEmpty ? 'Mi Playlist Importada' : rawName;
    final rawLines = _freeTextLinesController.text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (rawLines.isEmpty) {
      setState(() {
        _freeTextError =
            'Pega al menos una línea con el formato "Artista - Canción".';
      });
      return;
    }

    final tracks = <LibraryCsvTrack>[];
    for (var i = 0; i < rawLines.length; i++) {
      var line = rawLines[i];
      // Limpia numeración inicial común: "1. ", "01 - ", "1) "
      line = line.replaceFirst(RegExp(r'^\d+\s*[\.\)\-]\s*'), '').trim();
      if (line.isEmpty) continue;

      String artist = '';
      String title = line;

      final dashParts = line.split(RegExp(r'\s+[\-–—]\s+'));
      if (dashParts.length >= 2) {
        artist = dashParts.first.trim();
        title = dashParts.sublist(1).join(' - ').trim();
      } else if (line.contains(' - ')) {
        final idx = line.indexOf(' - ');
        artist = line.substring(0, idx).trim();
        title = line.substring(idx + 3).trim();
      } else if (line.contains('-')) {
        final idx = line.indexOf('-');
        artist = line.substring(0, idx).trim();
        title = line.substring(idx + 1).trim();
      }

      if (title.isEmpty) {
        title = line;
      }

      final artists = artist
          .split(RegExp(r'[,;&/]'))
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList(growable: false);

      tracks.add(
        LibraryCsvTrack(
          rowNumber: i + 1,
          title: title,
          artist: artists.isNotEmpty ? artists.first : artist,
          artists: artists,
          memberships: [LibraryCsvMembership(name: playlistName, position: i)],
        ),
      );
    }

    if (tracks.isEmpty) {
      setState(() {
        _freeTextError = 'No se detectaron canciones válidas en el texto.';
      });
      return;
    }

    setState(() => _freeTextError = null);

    final document = LibraryCsvDocument(
      tracks: List.unmodifiable(tracks),
      detectedFormat: LibraryCsvDetectedFormat.generic,
      defaultPlaylistName: playlistName,
      hasPlaylistColumn: true,
    );

    await _startDocumentImport(document);
  }

  Future<void> _startDocumentImport(LibraryCsvDocument document) async {
    final notifier = ref.read(libraryCsvTransferControllerProvider.notifier);
    if (ref.read(libraryCsvTransferControllerProvider).isBusy) {
      return;
    }
    notifier.reset();
    setState(() => _importStartedHere = true);
    try {
      await notifier.importDocument(document);
    } catch (_) {
      // El estado de error ya es publicado por LibraryCsvTransferController
    }
  }

  // ---------------------------------------------------------------------------
  // SELECTOR DE ARCHIVO CSV
  // ---------------------------------------------------------------------------
  Future<void> _pickAndImportCsvFile() async {
    if (_pickingCsv) return;
    setState(() {
      _pickingCsv = true;
      _csvError = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Seleccionar Archivo CSV de Playlist',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        windowsOptions: const WindowsOptions(lockParentWindow: true),
        linuxOptions: const LinuxOptions(lockParentWindow: true),
      );

      if (!mounted) return;
      setState(() => _pickingCsv = false);

      final path = picked?.path;
      if (path == null || path.trim().isEmpty) {
        return;
      }

      final fileName = picked?.name;
      final parentCtx = widget.parentContext;
      final parentWidgetRef = widget.parentRef;

      Navigator.of(context).pop();
      if (parentCtx.mounted) {
        await showLibraryCsvImportFlow(
          context: parentCtx,
          ref: parentWidgetRef,
          path: path,
          fileName: fileName,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickingCsv = false;
        _csvError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final transferState = ref.watch(libraryCsvTransferControllerProvider);
    final isImporting =
        _importStartedHere &&
        transferState.phase == LibraryCsvTransferPhase.importing;
    final isCompletedOrFailed =
        _importStartedHere &&
        (transferState.phase == LibraryCsvTransferPhase.completed ||
            transferState.phase == LibraryCsvTransferPhase.failed);

    return PopScope(
      canPop: !isImporting,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: Material(
          color: colors.surfaceContainerHigh,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, isImporting: isImporting),
              if (!isImporting && !isCompletedOrFailed) _buildModeTabs(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildBody(
                    context,
                    transferState: transferState,
                    isImporting: isImporting,
                    isCompletedOrFailed: isCompletedOrFailed,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isImporting}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_spotifyNeonGreen, InutilDesignSystem.primaryNeon],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _spotifyNeonGreen.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: InutilDesignSystem.spaceMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importador Universal de Playlists',
                  style: TextStyle(
                    color: InutilDesignSystem.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Spotify Directo • Exportify / Soundiiz CSV • Texto Libre',
                  style: TextStyle(
                    color: InutilDesignSystem.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (!isImporting)
            IconButton(
              onPressed: () {
                ref.read(libraryCsvTransferControllerProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              icon: const Icon(
                Icons.close_rounded,
                color: InutilDesignSystem.textSecondary,
              ),
              tooltip: 'Cerrar',
            ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    final tabs = [
      (icon: Icons.link_rounded, label: 'Enlace de Spotify'),
      (
        icon: Icons.table_chart_rounded,
        label: 'Archivo CSV (Exportify / Soundiiz)',
      ),
      (icon: Icons.notes_rounded, label: 'Texto Libre (Artista - Canción)'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: InutilDesignSystem.spaceMd,
        vertical: InutilDesignSystem.spaceSm,
      ),
      decoration: const BoxDecoration(
        color: InutilDesignSystem.surfaceDark,
        border: Border(
          bottom: BorderSide(color: InutilDesignSystem.borderSubtle),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final selected = _selectedTab == index;
          final item = tabs[index];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: InutilDesignSystem.borderMd,
                onTap: () => setState(() => _selectedTab = index),
                child: AnimatedContainer(
                  duration: InutilDesignSystem.durationFast,
                  curve: InutilDesignSystem.curveSmooth,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              _spotifyNeonGreen.withValues(alpha: 0.25),
                              InutilDesignSystem.primaryNeon.withValues(
                                alpha: 0.22,
                              ),
                            ],
                          )
                        : null,
                    color: selected ? null : Colors.transparent,
                    borderRadius: InutilDesignSystem.borderMd,
                    border: Border.all(
                      color: selected
                          ? _spotifyNeonGreen.withValues(alpha: 0.65)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 16,
                        color: selected
                            ? _spotifyNeonGreen
                            : InutilDesignSystem.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? InutilDesignSystem.textPrimary
                                : InutilDesignSystem.textSecondary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required LibraryCsvTransferState transferState,
    required bool isImporting,
    required bool isCompletedOrFailed,
  }) {
    if (isImporting) {
      return _buildImportingProgressView(transferState);
    }
    if (isCompletedOrFailed) {
      return _buildImportResultView(transferState);
    }

    return switch (_selectedTab) {
      0 => _buildSpotifyLinkTab(),
      1 => _buildCsvPickerTab(),
      _ => _buildFreeTextTab(),
    };
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 1: ENLACE DE SPOTIFY
  // ---------------------------------------------------------------------------
  Widget _buildSpotifyLinkTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(InutilDesignSystem.spaceMd),
          decoration: InutilDesignSystem.glassDecoration(
            baseColor: InutilDesignSystem.surfaceElevated,
            borderColor: _spotifyNeonGreen.withValues(alpha: 0.28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: _spotifyNeonGreen,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Importación directa sin API Key ni cuenta de Spotify',
                      style: TextStyle(
                        color: InutilDesignSystem.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Pega el enlace de cualquier playlist o álbum público de Spotify. '
                'Inutix Music extraerá las canciones y las vinculará automáticamente con el motor de audio de alta fidelidad.',
                style: TextStyle(
                  color: InutilDesignSystem.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: InutilDesignSystem.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _spotifyUrlController,
                      style: const TextStyle(
                        color: InutilDesignSystem.textPrimary,
                        fontSize: 13.5,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
                        hintStyle: const TextStyle(
                          color: InutilDesignSystem.textMuted,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.link_rounded,
                          color: _spotifyNeonGreen,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Pegar del portapapeles',
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            color: InutilDesignSystem.textSecondary,
                            size: 18,
                          ),
                          onPressed: () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final text = data?.text?.trim();
                            if (text != null && text.isNotEmpty) {
                              _spotifyUrlController.text = text;
                            }
                          },
                        ),
                        filled: true,
                        fillColor: InutilDesignSystem.backgroundCarbon,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: InutilDesignSystem.borderMd,
                          borderSide: const BorderSide(
                            color: InutilDesignSystem.borderSubtle,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: InutilDesignSystem.borderMd,
                          borderSide: const BorderSide(
                            color: _spotifyNeonGreen,
                            width: 1.4,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _analyzeSpotifyUrl(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: InutilDesignSystem.spaceMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _analyzingSpotify ? null : _analyzeSpotifyUrl,
                  style: FilledButton.styleFrom(
                    backgroundColor: _spotifyNeonGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: InutilDesignSystem.borderMd,
                    ),
                  ),
                  icon: _analyzingSpotify
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.radar_rounded, size: 20),
                  label: Text(
                    _analyzingSpotify
                        ? 'Analizando enlace de Spotify...'
                        : 'Analizar Enlace de Spotify',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_spotifyError != null) ...[
          const SizedBox(height: InutilDesignSystem.spaceMd),
          _buildErrorBanner(_spotifyError!),
        ],
        if (_parsedSpotify != null) ...[
          const SizedBox(height: InutilDesignSystem.spaceMd),
          _buildSpotifyPreviewCard(_parsedSpotify!),
        ],
      ],
    );
  }

  Widget _buildSpotifyPreviewCard(_SpotifyParsedEntity entity) {
    return Container(
      padding: const EdgeInsets.all(InutilDesignSystem.spaceMd),
      decoration: InutilDesignSystem.glowCardDecoration(
        accentColor: _spotifyNeonGreen,
        radius: InutilDesignSystem.radiusLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: InutilDesignSystem.borderMd,
                child: entity.coverUrl != null && entity.coverUrl!.isNotEmpty
                    ? Image.network(
                        entity.coverUrl!,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildFallbackArtwork(),
                      )
                    : _buildFallbackArtwork(),
              ),
              const SizedBox(width: InutilDesignSystem.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _spotifyNeonGreen.withValues(alpha: 0.18),
                            borderRadius: InutilDesignSystem.borderFull,
                            border: Border.all(
                              color: _spotifyNeonGreen.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            '${entity.tracks.length} CANCIONES DETECTADAS',
                            style: const TextStyle(
                              color: _spotifyNeonGreen,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _spotifyPlaylistNameController,
                      style: const TextStyle(
                        color: InutilDesignSystem.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Nombre de la playlist en Inutix Music',
                        labelStyle: const TextStyle(
                          color: InutilDesignSystem.textSecondary,
                          fontSize: 12,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: InutilDesignSystem.backgroundCarbon,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: InutilDesignSystem.borderSm,
                          borderSide: const BorderSide(
                            color: InutilDesignSystem.borderSubtle,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: InutilDesignSystem.borderSm,
                          borderSide: const BorderSide(
                            color: _spotifyNeonGreen,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          Container(
            constraints: const BoxConstraints(maxHeight: 210),
            decoration: BoxDecoration(
              color: InutilDesignSystem.backgroundCarbon.withValues(
                alpha: 0.75,
              ),
              borderRadius: InutilDesignSystem.borderMd,
              border: Border.all(color: InutilDesignSystem.borderSubtle),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: entity.tracks.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                color: InutilDesignSystem.borderSubtle,
              ),
              itemBuilder: (context, index) {
                final track = entity.tracks[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: InutilDesignSystem.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: InutilDesignSystem.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (track.artist.isNotEmpty)
                              Text(
                                track.artists.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: InutilDesignSystem.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        track.formattedDuration,
                        style: const TextStyle(
                          color: InutilDesignSystem.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          FilledButton.icon(
            onPressed: _importSpotifyEntity,
            style: FilledButton.styleFrom(
              backgroundColor: InutilDesignSystem.primaryNeon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: InutilDesignSystem.borderMd,
              ),
            ),
            icon: const Icon(Icons.bolt_rounded, size: 20),
            label: Text(
              'Importar Playlist Ahora (${entity.tracks.length} canciones)',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackArtwork() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_spotifyNeonGreen, InutilDesignSystem.primaryNeon],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: InutilDesignSystem.borderMd,
      ),
      child: const Icon(Icons.album_rounded, color: Colors.white, size: 38),
    );
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 2: ARCHIVO CSV (EXPORTIFY / SOUNDIIZ)
  // ---------------------------------------------------------------------------
  Widget _buildCsvPickerTab() {
    return Container(
      padding: const EdgeInsets.all(InutilDesignSystem.spaceLg),
      decoration: InutilDesignSystem.glassDecoration(
        baseColor: InutilDesignSystem.surfaceElevated,
        borderColor: InutilDesignSystem.accentCyan.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: InutilDesignSystem.accentCyan.withValues(alpha: 0.16),
                  borderRadius: InutilDesignSystem.borderMd,
                ),
                child: const Icon(
                  Icons.table_view_rounded,
                  color: InutilDesignSystem.accentCyan,
                  size: 26,
                ),
              ),
              const SizedBox(width: InutilDesignSystem.spaceMd),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importación de Archivos .CSV',
                      style: TextStyle(
                        color: InutilDesignSystem.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Compatible con Exportify, Soundiiz, TuneMyMusic y respaldos de Inutix Music',
                      style: TextStyle(
                        color: InutilDesignSystem.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          const Text(
            'Si tienes playlists privadas grandes (+100 canciones) o colecciones exportadas desde '
            'Exportify (Spotify CSV), Soundiiz o TuneMyMusic, selecciona tu archivo .CSV para '
            'previsualizar e importar todas tus listas conservando su orden.',
            style: TextStyle(
              color: InutilDesignSystem.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFormatBadge('Exportify (Spotify CSV)', _spotifyNeonGreen),
              _buildFormatBadge(
                'Soundiiz / TuneMyMusic',
                InutilDesignSystem.accentCyan,
              ),
              _buildFormatBadge(
                'Inutix Music Backup',
                InutilDesignSystem.primaryNeon,
              ),
              _buildFormatBadge(
                'Harmony / MetroList',
                InutilDesignSystem.secondaryGlow,
              ),
            ],
          ),
          if (_csvError != null) ...[
            const SizedBox(height: InutilDesignSystem.spaceMd),
            _buildErrorBanner(_csvError!),
          ],
          const SizedBox(height: InutilDesignSystem.spaceLg),
          FilledButton.icon(
            onPressed: _pickingCsv ? null : _pickAndImportCsvFile,
            style: FilledButton.styleFrom(
              backgroundColor: InutilDesignSystem.accentCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: InutilDesignSystem.borderMd,
              ),
            ),
            icon: _pickingCsv
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.upload_file_rounded, size: 20),
            label: const Text(
              'Seleccionar Archivo .CSV',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: InutilDesignSystem.borderFull,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 3: TEXTO LIBRE (ARTISTA - CANCIÓN)
  // ---------------------------------------------------------------------------
  Widget _buildFreeTextTab() {
    return Container(
      padding: const EdgeInsets.all(InutilDesignSystem.spaceMd),
      decoration: InutilDesignSystem.glassDecoration(
        baseColor: InutilDesignSystem.surfaceElevated,
        borderColor: InutilDesignSystem.primaryNeon.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Crea una playlist pegando una lista de canciones (una por línea):',
            style: TextStyle(
              color: InutilDesignSystem.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceSm),
          TextField(
            controller: _freeTextPlaylistController,
            style: const TextStyle(
              color: InutilDesignSystem.textPrimary,
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              labelText: 'Nombre de la nueva Playlist',
              labelStyle: const TextStyle(
                color: InutilDesignSystem.textSecondary,
                fontSize: 12.5,
              ),
              prefixIcon: const Icon(
                Icons.playlist_add_check_rounded,
                color: InutilDesignSystem.primaryNeon,
              ),
              filled: true,
              fillColor: InutilDesignSystem.backgroundCarbon,
              enabledBorder: OutlineInputBorder(
                borderRadius: InutilDesignSystem.borderMd,
                borderSide: const BorderSide(
                  color: InutilDesignSystem.borderSubtle,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: InutilDesignSystem.borderMd,
                borderSide: const BorderSide(
                  color: InutilDesignSystem.primaryNeon,
                ),
              ),
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          TextField(
            controller: _freeTextLinesController,
            maxLines: 8,
            minLines: 6,
            style: const TextStyle(
              color: InutilDesignSystem.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText:
                  'Daft Punk - Instant Crush\n'
                  'The Weeknd - Blinding Lights\n'
                  'Gorillaz - Feel Good Inc.\n'
                  'Soda Stereo - De Música Ligera',
              hintStyle: const TextStyle(
                color: InutilDesignSystem.textMuted,
                fontSize: 12.5,
              ),
              filled: true,
              fillColor: InutilDesignSystem.backgroundCarbon,
              enabledBorder: OutlineInputBorder(
                borderRadius: InutilDesignSystem.borderMd,
                borderSide: const BorderSide(
                  color: InutilDesignSystem.borderSubtle,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: InutilDesignSystem.borderMd,
                borderSide: const BorderSide(
                  color: InutilDesignSystem.primaryNeon,
                ),
              ),
            ),
          ),
          if (_freeTextError != null) ...[
            const SizedBox(height: InutilDesignSystem.spaceMd),
            _buildErrorBanner(_freeTextError!),
          ],
          const SizedBox(height: InutilDesignSystem.spaceMd),
          FilledButton.icon(
            onPressed: _importFreeText,
            style: FilledButton.styleFrom(
              backgroundColor: InutilDesignSystem.primaryNeon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: InutilDesignSystem.borderMd,
              ),
            ),
            icon: const Icon(Icons.rocket_launch_rounded, size: 19),
            label: const Text(
              'Importar Lista de Canciones',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROGRESO EN TIEMPO REAL Y RESUMEN FINAL
  // ---------------------------------------------------------------------------
  Widget _buildImportingProgressView(LibraryCsvTransferState state) {
    final progress = state.progress;
    final processed = progress?.processed ?? 0;
    final total = progress?.total ?? state.document?.uniqueTrackCount ?? 1;
    final fraction = (total > 0 ? processed / total : 0.0).clamp(0.0, 1.0);
    final percent = (fraction * 100).round();
    final currentTitle = progress?.currentTitle.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(InutilDesignSystem.spaceLg),
      decoration: InutilDesignSystem.glowCardDecoration(
        accentColor: _spotifyNeonGreen,
        radius: InutilDesignSystem.radiusLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: CircularProgressIndicator(
                  value: fraction > 0 ? fraction : null,
                  strokeWidth: 6,
                  backgroundColor: InutilDesignSystem.borderSubtle,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    _spotifyNeonGreen,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: InutilDesignSystem.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          Text(
            state.cancelRequested
                ? 'Deteniendo después de la canción actual...'
                : 'Sincronizando canciones en tu biblioteca...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: InutilDesignSystem.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$processed de $total canciones procesadas',
            style: const TextStyle(
              color: _spotifyNeonGreen,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          ClipRRect(
            borderRadius: InutilDesignSystem.borderFull,
            child: LinearProgressIndicator(
              minHeight: 8,
              value: fraction > 0 ? fraction : null,
              backgroundColor: InutilDesignSystem.backgroundCarbon,
              valueColor: const AlwaysStoppedAnimation<Color>(
                _spotifyNeonGreen,
              ),
            ),
          ),
          if (currentTitle.isNotEmpty) ...[
            const SizedBox(height: InutilDesignSystem.spaceMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  color: InutilDesignSystem.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: InutilDesignSystem.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: InutilDesignSystem.spaceLg),
          OutlinedButton.icon(
            onPressed: state.cancelRequested
                ? null
                : () => ref
                      .read(libraryCsvTransferControllerProvider.notifier)
                      .requestCancel(),
            style: OutlinedButton.styleFrom(
              foregroundColor: InutilDesignSystem.secondaryGlow,
              side: BorderSide(
                color: InutilDesignSystem.secondaryGlow.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: InutilDesignSystem.borderMd,
              ),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: Text(
              state.cancelRequested
                  ? 'Cancelación solicitada...'
                  : 'Detener importación',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportResultView(LibraryCsvTransferState state) {
    final LibraryCsvImportResult? result = state.result;
    final failedPhase = state.phase == LibraryCsvTransferPhase.failed;

    if (failedPhase && result == null) {
      return Container(
        padding: const EdgeInsets.all(InutilDesignSystem.spaceLg),
        decoration: InutilDesignSystem.glowCardDecoration(
          accentColor: InutilDesignSystem.secondaryGlow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: InutilDesignSystem.secondaryGlow,
              size: 48,
            ),
            const SizedBox(height: InutilDesignSystem.spaceMd),
            const Text(
              'Error durante la importación',
              style: TextStyle(
                color: InutilDesignSystem.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              readableCsvError(state.error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: InutilDesignSystem.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: InutilDesignSystem.spaceLg),
            FilledButton(
              onPressed: () {
                ref.read(libraryCsvTransferControllerProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }

    final imported = result?.imported ?? 0;
    final reused = result?.reused ?? 0;
    final failed = result?.failed ?? 0;

    return Container(
      padding: const EdgeInsets.all(InutilDesignSystem.spaceLg),
      decoration: InutilDesignSystem.glowCardDecoration(
        accentColor: _spotifyNeonGreen,
        radius: InutilDesignSystem.radiusLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _spotifyNeonGreen.withValues(alpha: 0.18),
              border: Border.all(color: _spotifyNeonGreen, width: 1.5),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: _spotifyNeonGreen,
              size: 34,
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          Text(
            result?.cancelled == true
                ? 'Importación parcial completada'
                : '¡Playlist importada con éxito!',
            style: const TextStyle(
              color: InutilDesignSystem.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: InutilDesignSystem.spaceMd),
          Row(
            children: [
              Expanded(
                child: _buildStatMetric(
                  label: 'Nuevas',
                  value: '$imported',
                  color: _spotifyNeonGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatMetric(
                  label: 'Existentes',
                  value: '$reused',
                  color: InutilDesignSystem.accentCyan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatMetric(
                  label: 'No encontradas',
                  value: '$failed',
                  color: InutilDesignSystem.secondaryGlow,
                ),
              ),
            ],
          ),
          const SizedBox(height: InutilDesignSystem.spaceLg),
          if (result != null && result.failures.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: InutilDesignSystem.backgroundCarbon,
                borderRadius: InutilDesignSystem.borderMd,
                border: Border.all(
                  color: InutilDesignSystem.secondaryGlow.withValues(
                    alpha: 0.32,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Canciones no encontradas (${result.failures.length}):',
                    style: const TextStyle(
                      color: InutilDesignSystem.secondaryGlow,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: result.failures.length,
                      itemBuilder: (context, index) {
                        final failure = result.failures[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${failure.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: InutilDesignSystem.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: InutilDesignSystem.spaceMd),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(libraryCsvTransferControllerProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: _spotifyNeonGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: InutilDesignSystem.borderMd,
                ),
              ),
              icon: const Icon(Icons.done_all_rounded, size: 20),
              label: const Text(
                'Listo, ir a mis Playlists',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: InutilDesignSystem.backgroundCarbon,
        borderRadius: InutilDesignSystem.borderMd,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: InutilDesignSystem.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InutilDesignSystem.secondaryGlow.withValues(alpha: 0.12),
        borderRadius: InutilDesignSystem.borderMd,
        border: Border.all(
          color: InutilDesignSystem.secondaryGlow.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: InutilDesignSystem.secondaryGlow,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: InutilDesignSystem.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
