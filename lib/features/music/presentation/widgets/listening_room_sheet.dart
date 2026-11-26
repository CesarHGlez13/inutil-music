import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/firebase/listening_room_service.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../services/player/player_service.dart';
import '../../../../services/sharing/inutil_track_link.dart';
import '../providers/listening_room_providers.dart';
import '../providers/music_providers.dart';
import 'live_floating_reactions_overlay.dart';
import 'source_image.dart';

/// Interactive modal for Listening Rooms (create, join by code/QR, share invite,
/// live synchronized playback, collaborative upvoted queue, reactions & chat).
class ListeningRoomSheet extends ConsumerStatefulWidget {
  const ListeningRoomSheet({
    this.initialRoomCode,
    this.autoJoin = false,
    super.key,
  });

  final String? initialRoomCode;
  final bool autoJoin;

  static Future<void> show(
    BuildContext context, {
    String? initialRoomCode,
    bool autoJoin = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ListeningRoomSheet(
        initialRoomCode: initialRoomCode,
        autoJoin: autoJoin,
      ),
    );
  }

  @override
  ConsumerState<ListeningRoomSheet> createState() => _ListeningRoomSheetState();
}

class _ListeningRoomSheetState extends ConsumerState<ListeningRoomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _roomNameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  final _chatController = TextEditingController();
  final _queueSearchController = TextEditingController();
  final _reactionsController = LiveFloatingReactionsController();
  bool _allowGuestQueue = true;
  bool _searchingQueue = false;
  List<ListeningRoomTrack> _searchResults = const <ListeningRoomTrack>[];

  static const _quickEmojis = <String>[
    '🔥',
    '❤️',
    '🎵',
    '👏',
    '🤯',
    '🚀',
    '✨',
    '😭',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialRoomCode != null &&
        widget.initialRoomCode!.trim().isNotEmpty) {
      _joinCodeController.text = widget.initialRoomCode!.trim();
      if (widget.autoJoin) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final service = ref.read(listeningRoomServiceProvider);
          if (!service.isInRoom && !service.isBusy) {
            unawaited(_joinRoom(widget.initialRoomCode));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomNameController.dispose();
    _joinCodeController.dispose();
    _chatController.dispose();
    _queueSearchController.dispose();
    super.dispose();
  }

  ListeningRoomTrack? _currentPlayerTrack() {
    final snap = ref.read(playerControllerProvider).asData?.value;
    final rawId = snap?.trackId?.trim() ?? '';
    if (snap == null || rawId.isEmpty) return null;
    const codec = InutilTrackLinkCodec();
    final canonicalId =
        codec.extractVideoId(snap.sourceUrl ?? '') ??
        codec.extractVideoId(rawId) ??
        rawId;
    return ListeningRoomTrack(
      trackId: canonicalId,
      title: (snap.title ?? '').trim().isNotEmpty ? snap.title!.trim() : 'Canción',
      artist: (snap.artist ?? '').trim().isNotEmpty
          ? snap.artist!.trim()
          : 'Inutix Music',
      album: snap.album,
      thumbnailUrl: snap.thumbnailUrl,
      durationMs: snap.duration?.inMilliseconds ?? 0,
      url: snap.sourceUrl?.trim().isNotEmpty == true
          ? snap.sourceUrl!.trim()
          : 'https://music.youtube.com/watch?v=$canonicalId',
    );
  }

  Future<void> _createRoom() async {
    final service = ref.read(listeningRoomServiceProvider);
    final snap = ref.read(playerControllerProvider).asData?.value;
    final ok = await service.createRoom(
      name: _roomNameController.text,
      allowGuestQueue: _allowGuestQueue,
      initialTrack: _currentPlayerTrack(),
      positionMs: snap?.position.inMilliseconds ?? 0,
      isPlaying: snap?.status == PlayerStatus.playing,
    );
    if (!ok && mounted && service.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(service.lastError!)),
      );
    }
  }

  Future<void> _joinRoom([String? overrideCode]) async {
    final service = ref.read(listeningRoomServiceProvider);
    final input = overrideCode ?? _joinCodeController.text;
    final ok = await service.joinRoom(input);
    if (!ok && mounted && service.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(service.lastError!)),
      );
    }
  }

  Future<void> _scanQrAndJoin() async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var popped = false;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SizedBox(
            height: 360,
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (popped) return;
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue?.trim();
                      if (raw != null && raw.isNotEmpty) {
                        popped = true;
                        Navigator.of(dialogContext).pop(raw);
                        break;
                      }
                    }
                  },
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 14,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Apunta al código QR de una sala de Inutix Music',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (scanned != null && scanned.isNotEmpty) {
      _joinCodeController.text =
          ListeningRoomService.parseRoomCode(scanned) ?? scanned;
      await _joinRoom(scanned);
    }
  }

  Future<void> _searchSongsForQueue(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchResults = const <ListeningRoomTrack>[]);
      return;
    }
    setState(() => _searchingQueue = true);
    try {
      final results = await ref
          .read(youtubeMusicSearchProvider)
          .searchSongs(trimmed, limit: 8);
      if (!mounted) return;
      setState(() {
        _searchResults = results
            .map(
              (song) => ListeningRoomTrack(
                trackId: song.videoId,
                title: song.title,
                artist: song.artists.join(', '),
                album: song.album,
                thumbnailUrl: song.thumbnailUrl,
                durationMs: song.duration?.inMilliseconds ?? 0,
                url: 'https://music.youtube.com/watch?v=${song.videoId}',
              ),
            )
            .toList(growable: false);
      });
    } finally {
      if (mounted) setState(() => _searchingQueue = false);
    }
  }

  void _showQrDialog(ListeningRoomState room, bool spanish) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(room.name, textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: room.shareUri,
                  size: 210,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                room.code,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                spanish
                    ? 'Tus amigos pueden escanear este QR o escribir el código en Listening Rooms.'
                    : 'Friends can scan this QR or type the code in Listening Rooms.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(spanish ? 'Cerrar' : 'Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ensure player<->room bridge is active whenever ListeningRoomSheet is opened.
    ref.watch(listeningRoomPlayerBridgeProvider);
    final service = ref.watch(listeningRoomServiceProvider);
    final room = ref.watch(listeningRoomStateProvider).asData?.value ?? service.room;
    final spanish = ref.watch(appStringsProvider).language != 'en';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: room == null ? 0.72 : 0.90,
        minChildSize: 0.50,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1ED760).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: Color(0xFF1ED760),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room?.name ?? 'Listening Rooms',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              room == null
                                  ? (spanish
                                        ? 'Escucha música sincronizada con amigos en vivo'
                                        : 'Listen to music in sync with friends live')
                                  : (spanish
                                        ? 'Código ${room.code} · ${room.activeMembersAt(DateTime.now()).length} en sala'
                                        : 'Code ${room.code} · ${room.activeMembersAt(DateTime.now()).length} listening'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: room == null
                      ? _buildLobby(
                          context,
                          scrollController: scrollController,
                          service: service,
                          spanish: spanish,
                        )
                      : _buildActiveRoom(
                          context,
                          room: room,
                          service: service,
                          spanish: spanish,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLobby(
    BuildContext context, {
    required ScrollController scrollController,
    required ListeningRoomService service,
    required bool spanish,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // Create Room card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                spanish ? 'Crear una sala' : 'Create a room',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                spanish
                    ? 'Tú eres el anfitrión: lo que reproduzcas sonará sincronizado en el dispositivo de tus amigos.'
                    : 'You host playback: whatever you play syncs live on your friends’ devices.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('listening-room-name-field'),
                controller: _roomNameController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: spanish ? 'Nombre de la sala' : 'Room name',
                  hintText: spanish
                      ? 'Ej. Noche de clásicos, Viaje en carretera...'
                      : 'E.g. Late night classics, Road trip...',
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  spanish ? 'Cola colaborativa' : 'Collaborative queue',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  spanish
                      ? 'Permite que los invitados agreguen y voten canciones.'
                      : 'Allow guests to add and upvote songs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                value: _allowGuestQueue,
                onChanged: (value) => setState(() => _allowGuestQueue = value),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('listening-room-create-btn'),
                onPressed: service.isBusy ? null : _createRoom,
                icon: service.isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.podcasts_rounded),
                label: Text(
                  spanish ? 'Crear sala en vivo' : 'Start live room',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Join Room card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                spanish ? 'Unirse a una sala' : 'Join a room',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('listening-room-code-field'),
                controller: _joinCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: spanish
                      ? 'Código de 6 letras o enlace'
                      : '6-letter code or invite link',
                  hintText: 'K7M9P2',
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('listening-room-join-btn'),
                      onPressed: service.isBusy ? null : () => _joinRoom(),
                      icon: const Icon(Icons.login_rounded),
                      label: Text(spanish ? 'Unirse' : 'Join'),
                    ),
                  ),
                  if (AppPlatform.isMobile) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: service.isBusy ? null : _scanQrAndJoin,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('QR'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveRoom(
    BuildContext context, {
    required ListeningRoomState room,
    required ListeningRoomService service,
    required bool spanish,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final members = room.activeMembersAt(DateTime.now());
    final sortedQueue = room.sortedQueue;
    final myUid = service.myUid ?? '';
    final burstReactions = service.recentBurstReactions;

    return LiveFloatingReactionsOverlay(
      controller: _reactionsController,
      bottomOffset: 70,
      maxTravelHeight: 460,
      autoListenRoom: true,
      child: Column(
        children: [
          // Invite & quick actions bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1ED760).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.circle,
                        size: 8,
                        color: Color(0xFF1ED760),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        room.code,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: const Color(0xFF1ED760),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: spanish ? 'Copiar código' : 'Copy code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: room.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          spanish
                              ? 'Código ${room.code} copiado'
                              : 'Code ${room.code} copied',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: spanish ? 'Compartir invitación' : 'Share invite',
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: spanish
                            ? 'Únete a mi sala «${room.name}» en Inutix Music 🎧\nCódigo: ${room.code}\n${room.shareUri}'
                            : 'Join my Listening Room «${room.name}» on Inutix Music 🎧\nCode: ${room.code}\n${room.shareUri}',
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'QR',
                  onPressed: () => _showQrDialog(room, spanish),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  onPressed: () async {
                    await service.leaveRoom();
                  },
                  icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                  label: Text(
                    service.isHost
                        ? (spanish ? 'Cerrar' : 'End')
                        : (spanish ? 'Salir' : 'Leave'),
                  ),
                ),
              ],
            ),
          ),

          // Hero card: Now Playing con Live DJ, Equalizer dinámico y glow
          if (room.currentTrack != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.surfaceContainerHigh,
                      colors.surfaceContainerLow,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF1ED760).withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1ED760).withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: SourceImage(
                          source: room.currentTrack!.thumbnailUrl,
                          fit: BoxFit.cover,
                          fallback: ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: const Icon(Icons.music_note_rounded),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1ED760)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'EN VIVO',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1ED760),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'DJ: ${room.hostName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            room.currentTrack!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            room.currentTrack!.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LiveEqualizerBars(
                      isPlaying: room.isPlaying,
                      color: const Color(0xFF1ED760),
                    ),
                  ],
                ),
              ),
            ),

          // Members strip + live reaction bursts
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final member in members)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        member.isHost
                            ? Icons.headphones_rounded
                            : Icons.person_rounded,
                        size: 14,
                      ),
                      label: Text(
                        member.displayName,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                for (final burst in burstReactions)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${burst.emoji} ${burst.senderName}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Quick emoji reactions bar (TikTok / Stories style with physics bursts)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final emoji in _quickEmojis)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ReactionBurstButton(
                        emoji: emoji,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _reactionsController.spawnBurst(
                            emoji,
                            senderName: 'Tú',
                            count: 6,
                          );
                          unawaited(service.sendReaction(emoji));
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

        TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: spanish
                  ? 'Cola (${sortedQueue.length})'
                  : 'Queue (${sortedQueue.length})',
            ),
            Tab(
              text: spanish
                  ? 'Chat (${room.messages.length})'
                  : 'Chat (${room.messages.length})',
            ),
          ],
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Collaborative Queue
              Column(
                children: [
                  if (service.isHost || room.allowGuestQueue)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _queueSearchController,
                              onSubmitted: _searchSongsForQueue,
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                ),
                                hintText: spanish
                                    ? 'Buscar canción para la cola...'
                                    : 'Search song for queue...',
                                filled: true,
                                fillColor: colors.surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: _searchingQueue
                                    ? const Padding(
                                        padding: EdgeInsets.all(10),
                                        child: SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () => _searchSongsForQueue(
                                          _queueSearchController.text,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if (service.isHost && sortedQueue.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () async {
                                final next = await service.popNextQueuedTrack();
                                if (next != null) {
                                  await ref
                                      .read(playerControllerProvider.notifier)
                                      .playRemote(next.track.toTrackInfo());
                                }
                              },
                              child: Text(
                                spanish ? 'Siguiente' : 'Play next',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_searchResults.isNotEmpty)
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final track = _searchResults[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 38,
                                height: 38,
                                child: SourceImage(
                                  source: track.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  fallback: const Icon(Icons.music_note_rounded),
                                ),
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded),
                              onPressed: () async {
                                await service.addToQueue(track);
                                if (mounted) {
                                  setState(() {
                                    _searchResults = const [];
                                    _queueSearchController.clear();
                                  });
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  Expanded(
                    child: sortedQueue.isEmpty
                        ? Center(
                            child: Text(
                              spanish
                                  ? 'La cola colaborativa está vacía. ¡Busca una canción arriba!'
                                  : 'Collaborative queue is empty. Search a song above!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                            itemCount: sortedQueue.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = sortedQueue[index];
                              final voted = item.hasVoted(myUid);
                              final isTop1 = index == 0;
                              return Container(
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(14),
                                  border: isTop1
                                      ? Border.all(
                                          color: const Color(0xFFFFD700)
                                              .withValues(alpha: 0.45),
                                          width: 1.2,
                                        )
                                      : null,
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildRankBadge(index + 1),
                                      const SizedBox(width: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 42,
                                          height: 42,
                                          child: SourceImage(
                                            source: item.track.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            fallback: const Icon(
                                              Icons.music_note_rounded,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Text(
                                    item.track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.track.artist} · +${item.addedByName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: ActionChip(
                                    avatar: Icon(
                                      voted
                                          ? Icons.thumb_up_rounded
                                          : Icons.thumb_up_outlined,
                                      size: 15,
                                      color: voted ? colors.primary : null,
                                    ),
                                    label: Text('${item.votes}'),
                                    onPressed: () =>
                                        unawaited(service.toggleVote(item.id)),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),

              // Tab 2: Live Chat
              Column(
                children: [
                  Expanded(
                    child: room.messages.isEmpty
                        ? Center(
                            child: Text(
                              spanish
                                  ? 'Saluda a la sala o comenta la canción actual.'
                                  : 'Say hi to the room or comment on the track.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            itemCount: room.messages.length,
                            itemBuilder: (context, index) {
                              final msg = room.messages[index];
                              final mine = msg.senderUid == myUid;
                              final isDj = msg.senderUid == room.hostUid;
                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? colors.primary.withValues(alpha: 0.18)
                                        : colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(14),
                                    border: isDj
                                        ? Border.all(
                                            color: const Color(0xFFFFD700)
                                                .withValues(alpha: 0.35),
                                            width: 1,
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isDj) ...[
                                            const Text(
                                              '👑 DJ ',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFFFFD700),
                                              ),
                                            ),
                                          ],
                                          Text(
                                            msg.senderName,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: mine
                                                      ? colors.primary
                                                      : (isDj
                                                          ? const Color(0xFFFFD700)
                                                          : colors.onSurfaceVariant),
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(msg.text),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            onSubmitted: (value) async {
                              if (await service.sendMessage(value)) {
                                _chatController.clear();
                              }
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: spanish
                                  ? 'Escribe un mensaje...'
                                  : 'Write a message...',
                              filled: true,
                              fillColor: colors.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () async {
                            final text = _chatController.text;
                            if (await service.sendMessage(text)) {
                              _chatController.clear();
                            }
                          },
                          icon: const Icon(Icons.send_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }
}

Widget _buildRankBadge(int rank) {
  final Color bg;
  final Color fg;
  final String label;
  if (rank == 1) {
    bg = const Color(0xFFFFD700).withValues(alpha: 0.22);
    fg = const Color(0xFFFFD700);
    label = '👑 #1';
  } else if (rank == 2) {
    bg = const Color(0xFFC0C0C0).withValues(alpha: 0.20);
    fg = const Color(0xFFE0E0E0);
    label = '#2';
  } else if (rank == 3) {
    bg = const Color(0xFFCD7F32).withValues(alpha: 0.20);
    fg = const Color(0xFFE29B58);
    label = '#3';
  } else {
    bg = Colors.white.withValues(alpha: 0.06);
    fg = Colors.white70;
    label = '#$rank';
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: fg.withValues(alpha: 0.35), width: 1),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: fg,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _LiveEqualizerBars extends StatefulWidget {
  const _LiveEqualizerBars({
    this.isPlaying = true,
    this.color = const Color(0xFF1ED760),
  });

  final bool isPlaying;
  final Color color;

  @override
  State<_LiveEqualizerBars> createState() => _LiveEqualizerBarsState();
}

class _LiveEqualizerBarsState extends State<_LiveEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _LiveEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        final h1 = widget.isPlaying ? (0.35 + 0.65 * math.sin(t).abs()) : 0.25;
        final h2 = widget.isPlaying ? (0.25 + 0.75 * math.sin(t + 1.2).abs()) : 0.25;
        final h3 = widget.isPlaying ? (0.40 + 0.60 * math.sin(t + 2.4).abs()) : 0.25;
        final h4 = widget.isPlaying ? (0.30 + 0.70 * math.sin(t + 3.6).abs()) : 0.25;

        return SizedBox(
          width: 24,
          height: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(h1),
              _buildBar(h2),
              _buildBar(h3),
              _buildBar(h4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double heightFraction) {
    return Container(
      width: 3.5,
      height: 20 * heightFraction.clamp(0.2, 1.0),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: widget.isPlaying
            ? [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
    );
  }
}

class _ReactionBurstButton extends StatefulWidget {
  const _ReactionBurstButton({
    required this.emoji,
    required this.onTap,
  });

  final String emoji;
  final VoidCallback onTap;

  @override
  State<_ReactionBurstButton> createState() => _ReactionBurstButtonState();
}

class _ReactionBurstButtonState extends State<_ReactionBurstButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _scale = 0.82);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _scale = 1.15);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _scale = 1.0);
    });
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}
