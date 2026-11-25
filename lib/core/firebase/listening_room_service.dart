import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../features/music/domain/entities/track_info.dart';
import 'firebase_auth_service.dart';
import 'firebase_firestore_service.dart';

typedef RoomDocGetter = Future<Map<String, dynamic>?> Function(String path);
typedef RoomDocSetter =
    Future<bool> Function(String path, Map<String, dynamic> data);
typedef RoomDocDeleter = Future<bool> Function(String path);

@immutable
class ListeningRoomTrack {
  const ListeningRoomTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnailUrl,
    this.durationMs = 0,
    this.url = '',
  });

  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnailUrl;
  final int durationMs;
  final String url;

  bool get isValid => trackId.trim().isNotEmpty && title.trim().isNotEmpty;

  String get resolvedUrl => url.trim().isNotEmpty
      ? url.trim()
      : 'https://music.youtube.com/watch?v=${trackId.trim()}';

  TrackInfo toTrackInfo() => TrackInfo(
    id: trackId,
    title: title,
    artist: artist,
    album: album,
    thumbnailUrl: thumbnailUrl,
    url: resolvedUrl,
    duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'trackId': trackId,
    'title': title,
    'artist': artist,
    if (album != null && album!.isNotEmpty) 'album': album,
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
      'thumbnailUrl': thumbnailUrl,
    'durationMs': durationMs,
    'url': resolvedUrl,
  };

  static ListeningRoomTrack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['trackId'] ?? '').toString().trim();
    final title = (map['title'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) return null;
    return ListeningRoomTrack(
      trackId: id,
      title: title,
      artist: (map['artist'] ?? 'Inutix Music').toString().trim(),
      album: map['album']?.toString(),
      thumbnailUrl: map['thumbnailUrl']?.toString(),
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      url: (map['url'] ?? '').toString(),
    );
  }
}

@immutable
class ListeningRoomMember {
  const ListeningRoomMember({
    required this.uid,
    required this.displayName,
    required this.lastSeenMs,
    required this.isHost,
  });

  final String uid;
  final String displayName;
  final int lastSeenMs;
  final bool isHost;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uid': uid,
    'displayName': displayName,
    'lastSeenMs': lastSeenMs,
    'isHost': isHost,
  };

  static ListeningRoomMember? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final uid = (map['uid'] ?? '').toString().trim();
    if (uid.isEmpty) return null;
    return ListeningRoomMember(
      uid: uid,
      displayName: (map['displayName'] ?? 'Invitado').toString(),
      lastSeenMs: (map['lastSeenMs'] as num?)?.toInt() ?? 0,
      isHost: map['isHost'] == true,
    );
  }
}

@immutable
class ListeningRoomQueueItem {
  const ListeningRoomQueueItem({
    required this.id,
    required this.track,
    required this.addedByUid,
    required this.addedByName,
    required this.addedAtMs,
    this.upvoterUids = const <String>[],
  });

  final String id;
  final ListeningRoomTrack track;
  final String addedByUid;
  final String addedByName;
  final int addedAtMs;
  final List<String> upvoterUids;

  int get votes => upvoterUids.length;

  bool hasVoted(String uid) => upvoterUids.contains(uid);

  ListeningRoomQueueItem withToggledVote(String uid) {
    final next = List<String>.of(upvoterUids);
    if (next.contains(uid)) {
      next.remove(uid);
    } else {
      next.add(uid);
    }
    return ListeningRoomQueueItem(
      id: id,
      track: track,
      addedByUid: addedByUid,
      addedByName: addedByName,
      addedAtMs: addedAtMs,
      upvoterUids: List<String>.unmodifiable(next),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'track': track.toJson(),
    'addedByUid': addedByUid,
    'addedByName': addedByName,
    'addedAtMs': addedAtMs,
    'upvoterUids': upvoterUids,
  };

  static ListeningRoomQueueItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['id'] ?? '').toString().trim();
    final track = ListeningRoomTrack.fromJson(map['track']);
    if (id.isEmpty || track == null) return null;
    final voters = (map['upvoterUids'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return ListeningRoomQueueItem(
      id: id,
      track: track,
      addedByUid: (map['addedByUid'] ?? '').toString(),
      addedByName: (map['addedByName'] ?? 'Invitado').toString(),
      addedAtMs: (map['addedAtMs'] as num?)?.toInt() ?? 0,
      upvoterUids: List<String>.unmodifiable(voters),
    );
  }
}

@immutable
class ListeningRoomReaction {
  const ListeningRoomReaction({
    required this.id,
    required this.emoji,
    required this.senderName,
    required this.createdAtMs,
  });

  final String id;
  final String emoji;
  final String senderName;
  final int createdAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'emoji': emoji,
    'senderName': senderName,
    'createdAtMs': createdAtMs,
  };

  static ListeningRoomReaction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['id'] ?? '').toString().trim();
    final emoji = (map['emoji'] ?? '').toString().trim();
    if (id.isEmpty || emoji.isEmpty) return null;
    return ListeningRoomReaction(
      id: id,
      emoji: emoji,
      senderName: (map['senderName'] ?? '').toString(),
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ListeningRoomMessage {
  const ListeningRoomMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.createdAtMs,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final int createdAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'senderUid': senderUid,
    'senderName': senderName,
    'text': text,
    'createdAtMs': createdAtMs,
  };

  static ListeningRoomMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['id'] ?? '').toString().trim();
    final text = (map['text'] ?? '').toString().trim();
    if (id.isEmpty || text.isEmpty) return null;
    return ListeningRoomMessage(
      id: id,
      senderUid: (map['senderUid'] ?? '').toString(),
      senderName: (map['senderName'] ?? 'Invitado').toString(),
      text: text,
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ListeningRoomState {
  const ListeningRoomState({
    required this.code,
    required this.name,
    required this.hostUid,
    required this.hostName,
    this.allowGuestQueue = true,
    this.currentTrack,
    this.positionMs = 0,
    this.isPlaying = false,
    this.playbackUpdatedAtMs = 0,
    this.members = const <ListeningRoomMember>[],
    this.queue = const <ListeningRoomQueueItem>[],
    this.reactions = const <ListeningRoomReaction>[],
    this.messages = const <ListeningRoomMessage>[],
    required this.createdAtMs,
  });

  final String code;
  final String name;
  final String hostUid;
  final String hostName;
  final bool allowGuestQueue;
  final ListeningRoomTrack? currentTrack;
  final int positionMs;
  final bool isPlaying;
  final int playbackUpdatedAtMs;
  final List<ListeningRoomMember> members;
  final List<ListeningRoomQueueItem> queue;
  final List<ListeningRoomReaction> reactions;
  final List<ListeningRoomMessage> messages;
  final int createdAtMs;

  String get shareUri => 'inutilmusic://room/$code';

  /// Collaborative queue sorted by upvotes descending, then oldest first.
  List<ListeningRoomQueueItem> get sortedQueue {
    final copy = List<ListeningRoomQueueItem>.of(queue);
    copy.sort((a, b) {
      final voteCmp = b.votes.compareTo(a.votes);
      if (voteCmp != 0) return voteCmp;
      return a.addedAtMs.compareTo(b.addedAtMs);
    });
    return List<ListeningRoomQueueItem>.unmodifiable(copy);
  }

  /// Host inactivity timeout after which a room with no host heartbeat or
  /// playback update is treated as abandoned/expired.
  static const int staleHostTtlMs = 10 * 60 * 1000;

  /// Active listeners seen within the last 90 seconds.
  List<ListeningRoomMember> activeMembersAt(DateTime now) {
    final cutoff = now.millisecondsSinceEpoch - 90000;
    return members
        .where((m) => m.isHost || m.lastSeenMs >= cutoff)
        .toList(growable: false);
  }

  /// True when the host has stopped sending heartbeats/updates for longer than
  /// [staleHostTtlMs] (e.g., host force-closed the app without tapping "End").
  bool isHostStaleAt(DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    var latestHostSignalMs = playbackUpdatedAtMs > createdAtMs
        ? playbackUpdatedAtMs
        : createdAtMs;
    for (final member in members) {
      if (member.isHost && member.lastSeenMs > latestHostSignalMs) {
        latestHostSignalMs = member.lastSeenMs;
      }
    }
    if (latestHostSignalMs <= 0) return false;
    return (nowMs - latestHostSignalMs) > staleHostTtlMs;
  }

  /// Drift-compensated target playback position for guests.
  int estimatedPositionMsAt(DateTime now) {
    if (!isPlaying || playbackUpdatedAtMs <= 0) {
      return positionMs.clamp(0, 1 << 30);
    }
    final elapsed = now.millisecondsSinceEpoch - playbackUpdatedAtMs;
    final raw = elapsed > 0 ? positionMs + elapsed : positionMs;
    final durationMs = currentTrack?.durationMs ?? 0;
    if (durationMs > 0 && raw > durationMs) return durationMs;
    return raw.clamp(0, 1 << 30);
  }

  static bool shouldResyncPosition({
    required int localMs,
    required int targetMs,
    int thresholdMs = 2200,
  }) => (localMs - targetMs).abs() >= thresholdMs;

  Map<String, dynamic> toFirestoreJson() => <String, dynamic>{
    'code': code,
    'name': name,
    'hostUid': hostUid,
    'hostName': hostName,
    'allowGuestQueue': allowGuestQueue,
    if (currentTrack != null) 'currentTrack': currentTrack!.toJson(),
    'positionMs': positionMs,
    'isPlaying': isPlaying,
    'playbackUpdatedAtMs': playbackUpdatedAtMs,
    'members': members.map((m) => m.toJson()).toList(growable: false),
    'queue': queue.map((q) => q.toJson()).toList(growable: false),
    'reactions': reactions.map((r) => r.toJson()).toList(growable: false),
    'messages': messages.map((m) => m.toJson()).toList(growable: false),
    'createdAtMs': createdAtMs,
  };

  static ListeningRoomState? fromFirestoreJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final code = (json['code'] ?? '').toString().trim().toUpperCase();
    final hostUid = (json['hostUid'] ?? '').toString().trim();
    if (code.isEmpty || hostUid.isEmpty) return null;
    return ListeningRoomState(
      code: code,
      name: (json['name'] ?? 'Sala de Inutix Music').toString(),
      hostUid: hostUid,
      hostName: (json['hostName'] ?? 'Anfitrión').toString(),
      allowGuestQueue: json['allowGuestQueue'] != false,
      currentTrack: ListeningRoomTrack.fromJson(json['currentTrack']),
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      isPlaying: json['isPlaying'] == true,
      playbackUpdatedAtMs: (json['playbackUpdatedAtMs'] as num?)?.toInt() ?? 0,
      members: (json['members'] as List? ?? const [])
          .map(ListeningRoomMember.fromJson)
          .whereType<ListeningRoomMember>()
          .toList(growable: false),
      queue: (json['queue'] as List? ?? const [])
          .map(ListeningRoomQueueItem.fromJson)
          .whereType<ListeningRoomQueueItem>()
          .toList(growable: false),
      reactions: (json['reactions'] as List? ?? const [])
          .map(ListeningRoomReaction.fromJson)
          .whereType<ListeningRoomReaction>()
          .toList(growable: false),
      messages: (json['messages'] as List? ?? const [])
          .map(ListeningRoomMessage.fromJson)
          .whereType<ListeningRoomMessage>()
          .toList(growable: false),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Manages real-time Firestore Listening Rooms (Host & Guest roles, drift-compensated
/// playback sync, collaborative upvoted queue, live emoji reactions, and chat).
class ListeningRoomService extends ChangeNotifier {
  ListeningRoomService({
    RoomDocGetter? getDocument,
    RoomDocSetter? setDocument,
    RoomDocDeleter? deleteDocument,
    String? Function()? currentUid,
    String Function()? currentDisplayName,
    DateTime Function()? clock,
  }) : _getDocument = getDocument ?? InutilFirestoreService.instance.getDocument,
       _setDocument = setDocument ?? InutilFirestoreService.instance.setDocument,
       _deleteDocument =
           deleteDocument ?? InutilFirestoreService.instance.deleteDocument,
       _currentUidProvider = currentUid,
       _currentDisplayNameProvider = currentDisplayName,
       _clock = clock ?? DateTime.now;

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const Duration _pollInterval = Duration(milliseconds: 2500);
  static const int _maxReactions = 20;
  static const int _maxMessages = 40;
  static const int _maxMissingPollsBeforeClose = 3;

  final RoomDocGetter _getDocument;
  final RoomDocSetter _setDocument;
  final RoomDocDeleter _deleteDocument;
  final String? Function()? _currentUidProvider;
  final String Function()? _currentDisplayNameProvider;
  final DateTime Function() _clock;
  final Random _random = Random.secure();

  ListeningRoomState? _room;
  String? _lastError;
  bool _busy = false;
  Timer? _pollTimer;
  int _lastHeartbeatMs = 0;
  int _consecutiveMissingPolls = 0;
  final Set<String> _seenReactionIds = <String>{};
  final List<ListeningRoomReaction> _recentBurstReactions =
      <ListeningRoomReaction>[];

  ListeningRoomState? get room => _room;
  bool get isInRoom => _room != null;
  bool get isBusy => _busy;
  String? get lastError => _lastError;
  List<ListeningRoomReaction> get recentBurstReactions =>
      List<ListeningRoomReaction>.unmodifiable(_recentBurstReactions);

  String? get myUid {
    final override = _currentUidProvider?.call();
    if (override != null && override.isNotEmpty) return override;
    return InutilAuthService.instance.currentUser?.uid;
  }

  String get myDisplayName {
    final override = _currentDisplayNameProvider?.call();
    if (override != null && override.trim().isNotEmpty) return override.trim();
    final user = InutilAuthService.instance.currentUser;
    if (user != null && user.displayName.trim().isNotEmpty) {
      return user.displayName.trim();
    }
    if (user != null && user.email.contains('@')) {
      return user.email.split('@').first;
    }
    return 'Oyente';
  }

  bool get isHost => _room != null && myUid != null && _room!.hostUid == myUid;
  bool get isGuest => _room != null && !isHost;

  /// Parses either a raw 6-char room code or a share/QR link
  /// (`inutilmusic://room/K7M9P2` or `https://.../room/K7M9P2`).
  static String? parseRoomCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'inutilmusic' ||
            uri.scheme == 'http' ||
            uri.scheme == 'https')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (uri.host.toLowerCase() == 'room' && segments.isNotEmpty) {
        return _cleanCode(segments.first);
      }
      final roomIdx = segments.indexWhere((s) => s.toLowerCase() == 'room');
      if (roomIdx >= 0 && roomIdx + 1 < segments.length) {
        return _cleanCode(segments[roomIdx + 1]);
      }
      final queryCode = uri.queryParameters['room'] ?? uri.queryParameters['code'];
      if (queryCode != null) return _cleanCode(queryCode);
    }
    return _cleanCode(trimmed);
  }

  static String? _cleanCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length < 4 || cleaned.length > 10) return null;
    return cleaned;
  }

  String _generateCode() {
    return List<String>.generate(
      6,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
  }

  String _docPath(String code) => 'listening_rooms/$code';

  Future<bool> createRoom({
    required String name,
    bool allowGuestQueue = true,
    ListeningRoomTrack? initialTrack,
    int positionMs = 0,
    bool isPlaying = false,
  }) async {
    final uid = myUid;
    if (uid == null || uid.isEmpty) {
      _lastError = 'Inicia sesión para crear una sala sincronizada.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _ensureFreshSessionBestEffort();
      final code = _generateCode();
      final nowMs = _clock().millisecondsSinceEpoch;
      final roomName = name.trim().isEmpty
          ? 'Sala de $myDisplayName'
          : name.trim();
      final state = ListeningRoomState(
        code: code,
        name: roomName,
        hostUid: uid,
        hostName: myDisplayName,
        allowGuestQueue: allowGuestQueue,
        currentTrack: initialTrack,
        positionMs: positionMs,
        isPlaying: isPlaying,
        playbackUpdatedAtMs: nowMs,
        members: <ListeningRoomMember>[
          ListeningRoomMember(
            uid: uid,
            displayName: myDisplayName,
            lastSeenMs: nowMs,
            isHost: true,
          ),
        ],
        createdAtMs: nowMs,
      );
      final ok = await _setDocument(_docPath(code), state.toFirestoreJson());
      if (!ok) {
        _lastError = 'No se pudo crear la sala. Verifica tu conexión.';
        return false;
      }
      _room = state;
      _consecutiveMissingPolls = 0;
      _seenReactionIds.clear();
      _recentBurstReactions.clear();
      _lastHeartbeatMs = nowMs;
      _startPolling();
      return true;
    } catch (error) {
      _lastError = 'Error al crear sala: $error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> joinRoom(String rawCodeOrLink) async {
    final uid = myUid;
    if (uid == null || uid.isEmpty) {
      _lastError = 'Inicia sesión para unirte a una sala.';
      notifyListeners();
      return false;
    }
    final code = parseRoomCode(rawCodeOrLink);
    if (code == null) {
      _lastError = 'Código de sala inválido.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _ensureFreshSessionBestEffort();
      final doc = await _getDocument(_docPath(code));
      final parsed = ListeningRoomState.fromFirestoreJson(doc);
      if (parsed == null) {
        _lastError = 'No existe ninguna sala activa con el código $code.';
        return false;
      }
      final now = _clock();
      if (parsed.hostUid != uid && parsed.isHostStaleAt(now)) {
        _lastError = 'Esta sala ya finalizó por inactividad del anfitrión.';
        return false;
      }
      final nowMs = now.millisecondsSinceEpoch;
      final updatedMembers = _upsertMember(
        parsed.members,
        ListeningRoomMember(
          uid: uid,
          displayName: myDisplayName,
          lastSeenMs: nowMs,
          isHost: parsed.hostUid == uid,
        ),
        nowMs: nowMs,
      );
      final ok = await _setDocument(_docPath(code), <String, dynamic>{
        'code': parsed.code,
        'hostUid': parsed.hostUid,
        'members': updatedMembers.map((m) => m.toJson()).toList(growable: false),
      });
      if (!ok) {
        _lastError = 'No se pudo entrar a la sala.';
        return false;
      }
      _room = ListeningRoomState(
        code: parsed.code,
        name: parsed.name,
        hostUid: parsed.hostUid,
        hostName: parsed.hostName,
        allowGuestQueue: parsed.allowGuestQueue,
        currentTrack: parsed.currentTrack,
        positionMs: parsed.positionMs,
        isPlaying: parsed.isPlaying,
        playbackUpdatedAtMs: parsed.playbackUpdatedAtMs,
        members: updatedMembers,
        queue: parsed.queue,
        reactions: parsed.reactions,
        messages: parsed.messages,
        createdAtMs: parsed.createdAtMs,
      );
      _consecutiveMissingPolls = 0;
      _seenReactionIds
        ..clear()
        ..addAll(parsed.reactions.map((r) => r.id));
      _recentBurstReactions.clear();
      _lastHeartbeatMs = nowMs;
      _startPolling();
      return true;
    } catch (error) {
      _lastError = 'No se pudo unir a la sala: $error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> publishHostPlayback({
    required ListeningRoomTrack? track,
    required int positionMs,
    required bool isPlaying,
  }) async {
    final current = _room;
    if (current == null || !isHost) return;
    final nowMs = _clock().millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      'code': current.code,
      'hostUid': current.hostUid,
      if (track != null) 'currentTrack': track.toJson(),
      'positionMs': positionMs.clamp(0, 1 << 30),
      'isPlaying': isPlaying,
      'playbackUpdatedAtMs': nowMs,
    };
    final ok = await _setDocument(_docPath(current.code), payload);
    if (ok && _room != null && _room!.code == current.code) {
      _room = ListeningRoomState(
        code: _room!.code,
        name: _room!.name,
        hostUid: _room!.hostUid,
        hostName: _room!.hostName,
        allowGuestQueue: _room!.allowGuestQueue,
        currentTrack: track ?? _room!.currentTrack,
        positionMs: positionMs.clamp(0, 1 << 30),
        isPlaying: isPlaying,
        playbackUpdatedAtMs: nowMs,
        members: _room!.members,
        queue: _room!.queue,
        reactions: _room!.reactions,
        messages: _room!.messages,
        createdAtMs: _room!.createdAtMs,
      );
      notifyListeners();
    }
  }

  Future<bool> addToQueue(ListeningRoomTrack track) async {
    final current = _room;
    final uid = myUid;
    if (current == null || uid == null) return false;
    if (!isHost && !current.allowGuestQueue) return false;
    final fresh = await _fetchLatestState(current.code) ?? current;
    final nowMs = _clock().millisecondsSinceEpoch;
    final item = ListeningRoomQueueItem(
      id: '${nowMs}_${_random.nextInt(99999)}',
      track: track,
      addedByUid: uid,
      addedByName: myDisplayName,
      addedAtMs: nowMs,
      upvoterUids: <String>[uid],
    );
    final updatedQueue = <ListeningRoomQueueItem>[...fresh.queue, item];
    final ok = await _setDocument(_docPath(fresh.code), <String, dynamic>{
      'code': fresh.code,
      'hostUid': fresh.hostUid,
      'queue': updatedQueue.map((q) => q.toJson()).toList(growable: false),
    });
    if (ok) {
      await pollNow();
    }
    return ok;
  }

  Future<bool> toggleVote(String queueItemId) async {
    final current = _room;
    final uid = myUid;
    if (current == null || uid == null) return false;
    final fresh = await _fetchLatestState(current.code) ?? current;
    final updatedQueue = fresh.queue
        .map(
          (item) =>
              item.id == queueItemId ? item.withToggledVote(uid) : item,
        )
        .toList(growable: false);
    final ok = await _setDocument(_docPath(fresh.code), <String, dynamic>{
      'code': fresh.code,
      'hostUid': fresh.hostUid,
      'queue': updatedQueue.map((q) => q.toJson()).toList(growable: false),
    });
    if (ok) {
      await pollNow();
    }
    return ok;
  }

  Future<ListeningRoomQueueItem?> popNextQueuedTrack() async {
    final current = _room;
    if (current == null || !isHost) return null;
    final fresh = await _fetchLatestState(current.code) ?? current;
    final sorted = fresh.sortedQueue;
    if (sorted.isEmpty) return null;
    final next = sorted.first;
    final remaining = fresh.queue
        .where((item) => item.id != next.id)
        .toList(growable: false);
    await _setDocument(_docPath(fresh.code), <String, dynamic>{
      'code': fresh.code,
      'hostUid': fresh.hostUid,
      'queue': remaining.map((q) => q.toJson()).toList(growable: false),
    });
    await pollNow();
    return next;
  }

  Future<bool> sendReaction(String emoji) async {
    final current = _room;
    if (current == null) return false;
    final cleanEmoji = emoji.trim();
    if (cleanEmoji.isEmpty) return false;
    final fresh = await _fetchLatestState(current.code) ?? current;
    final nowMs = _clock().millisecondsSinceEpoch;
    final reaction = ListeningRoomReaction(
      id: '${nowMs}_${_random.nextInt(99999)}',
      emoji: cleanEmoji,
      senderName: myDisplayName,
      createdAtMs: nowMs,
    );
    final nextReactions = <ListeningRoomReaction>[
      ...fresh.reactions,
      reaction,
    ];
    final trimmed = nextReactions.length > _maxReactions
        ? nextReactions.sublist(nextReactions.length - _maxReactions)
        : nextReactions;
    final ok = await _setDocument(_docPath(fresh.code), <String, dynamic>{
      'code': fresh.code,
      'hostUid': fresh.hostUid,
      'reactions': trimmed.map((r) => r.toJson()).toList(growable: false),
    });
    if (ok) {
      _ingestReactions(trimmed);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> sendMessage(String rawText) async {
    final current = _room;
    final uid = myUid;
    final text = rawText.trim();
    if (current == null || uid == null || text.isEmpty) return false;
    final fresh = await _fetchLatestState(current.code) ?? current;
    final nowMs = _clock().millisecondsSinceEpoch;
    final message = ListeningRoomMessage(
      id: '${nowMs}_${_random.nextInt(99999)}',
      senderUid: uid,
      senderName: myDisplayName,
      text: text.length > 240 ? text.substring(0, 240) : text,
      createdAtMs: nowMs,
    );
    final nextMessages = <ListeningRoomMessage>[...fresh.messages, message];
    final trimmed = nextMessages.length > _maxMessages
        ? nextMessages.sublist(nextMessages.length - _maxMessages)
        : nextMessages;
    final ok = await _setDocument(_docPath(fresh.code), <String, dynamic>{
      'code': fresh.code,
      'hostUid': fresh.hostUid,
      'messages': trimmed.map((m) => m.toJson()).toList(growable: false),
    });
    if (ok) {
      await pollNow();
    }
    return ok;
  }

  Future<void> leaveRoom() async {
    final current = _room;
    final uid = myUid;
    _stopPolling();
    _room = null;
    _recentBurstReactions.clear();
    _seenReactionIds.clear();
    notifyListeners();
    if (current == null || uid == null) return;
    try {
      if (current.hostUid == uid) {
        await _deleteDocument(_docPath(current.code));
      } else {
        final fresh = await _fetchLatestState(current.code);
        if (fresh != null) {
          final remaining = fresh.members
              .where((m) => m.uid != uid)
              .toList(growable: false);
          await _setDocument(_docPath(current.code), <String, dynamic>{
            'code': fresh.code,
            'hostUid': fresh.hostUid,
            'members': remaining.map((m) => m.toJson()).toList(growable: false),
          });
        }
      }
    } catch (_) {}
  }

  Future<void> pollNow() async {
    final current = _room;
    if (current == null) return;
    try {
      final fetched = await _fetchLatestState(current.code);
      if (fetched == null) {
        // Tolerate brief transient network blips before assuming the host
        // closed the room.
        _consecutiveMissingPolls++;
        if (_consecutiveMissingPolls < _maxMissingPollsBeforeClose) {
          return;
        }
        _stopPolling();
        _room = null;
        _consecutiveMissingPolls = 0;
        _lastError = 'El anfitrión cerró la sala.';
        notifyListeners();
        return;
      }
      _consecutiveMissingPolls = 0;
      final now = _clock();
      final uid = myUid;
      if (uid != null && fetched.hostUid != uid && fetched.isHostStaleAt(now)) {
        _stopPolling();
        _room = null;
        _lastError = 'La sala finalizó por inactividad del anfitrión.';
        notifyListeners();
        return;
      }
      _room = fetched;
      _ingestReactions(fetched.reactions);

      final nowMs = now.millisecondsSinceEpoch;
      if (uid != null && nowMs - _lastHeartbeatMs >= 30000) {
        _lastHeartbeatMs = nowMs;
        final updatedMembers = _upsertMember(
          fetched.members,
          ListeningRoomMember(
            uid: uid,
            displayName: myDisplayName,
            lastSeenMs: nowMs,
            isHost: fetched.hostUid == uid,
          ),
          nowMs: nowMs,
        );
        unawaited(
          _setDocument(_docPath(fetched.code), <String, dynamic>{
            'code': fetched.code,
            'hostUid': fetched.hostUid,
            'members': updatedMembers
                .map((m) => m.toJson())
                .toList(growable: false),
          }),
        );
      }
      notifyListeners();
    } catch (error) {
      debugPrint('ListeningRoom poll error: $error');
    }
  }

  Future<ListeningRoomState?> _fetchLatestState(String code) async {
    final doc = await _getDocument(_docPath(code));
    return ListeningRoomState.fromFirestoreJson(doc);
  }

  void _ingestReactions(List<ListeningRoomReaction> incoming) {
    final nowMs = _clock().millisecondsSinceEpoch;
    _recentBurstReactions.removeWhere((r) => nowMs - r.createdAtMs > 8000);
    for (final reaction in incoming) {
      if (_seenReactionIds.add(reaction.id) &&
          nowMs - reaction.createdAtMs <= 12000) {
        _recentBurstReactions.add(reaction);
      }
    }
    if (_recentBurstReactions.length > 6) {
      _recentBurstReactions.removeRange(0, _recentBurstReactions.length - 6);
    }
  }

  List<ListeningRoomMember> _upsertMember(
    List<ListeningRoomMember> members,
    ListeningRoomMember self, {
    required int nowMs,
  }) {
    final cutoff = nowMs - 120000;
    final result = <ListeningRoomMember>[
      for (final m in members)
        if (m.uid != self.uid && (m.isHost || m.lastSeenMs >= cutoff)) m,
      self,
    ];
    return List<ListeningRoomMember>.unmodifiable(result);
  }

  Future<void> _ensureFreshSessionBestEffort() async {
    if (_currentUidProvider != null) return;
    try {
      await InutilAuthService.instance.ensureFreshSession();
    } catch (_) {}
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(pollNow()));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
