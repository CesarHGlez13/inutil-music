import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AlgorithmPreset {
  balanced,
  discovery,
  nostalgia,
  noAlgorithm,
  custom;

  String label({bool spanish = true}) => switch (this) {
    AlgorithmPreset.balanced => spanish ? 'Equilibrado' : 'Balanced',
    AlgorithmPreset.discovery => spanish ? 'Descubrimiento' : 'Discovery',
    AlgorithmPreset.nostalgia => spanish ? 'Nostalgia' : 'Nostalgia',
    AlgorithmPreset.noAlgorithm => spanish ? 'Sin algoritmo' : 'No algorithm',
    AlgorithmPreset.custom => spanish ? 'Personalizado' : 'Custom',
  };
}

enum AlgorithmWeightSlot { known, discovery, forgotten, wildcard }

const supportedAntiRepetitionDays = <int>[0, 1, 3, 7, 14];

/// User-configurable rules that govern Inutix Music's recommendation engine,
/// nostalgia discovery, anti-repetition window, and automatic radio queue.
@immutable
class AlgorithmControlSettings {
  const AlgorithmControlSettings({
    this.knownPercent = 40,
    this.discoveryPercent = 35,
    this.forgottenPercent = 15,
    this.wildcardPercent = 10,
    this.algorithmDisabled = false,
    this.antiRepetitionDays = 3,
    this.penalizeSkippedTracks = true,
    this.prioritizeFavorites = true,
    this.avoidSameArtistBackToBack = true,
  });

  static const AlgorithmControlSettings defaults = AlgorithmControlSettings();

  final int knownPercent;
  final int discoveryPercent;
  final int forgottenPercent;
  final int wildcardPercent;

  /// When true ("Modo sin algoritmo"), Home hides algorithmic recommendation
  /// shelves and the player never appends automatic related-radio tracks.
  final bool algorithmDisabled;

  /// Excludes tracks played within the last [antiRepetitionDays] days from
  /// recommendations and automatic radio suggestions (`0` disables the rule).
  final int antiRepetitionDays;

  /// Demotes seeds and candidates that the listener repeatedly skipped early.
  final bool penalizeSkippedTracks;

  /// Boosts favorite and liked tracks when choosing recommendation seeds.
  final bool prioritizeFavorites;

  /// Prevents back-to-back tracks from the same artist in recommended lists.
  final bool avoidSameArtistBackToBack;

  bool get isDefault => this == defaults;

  AlgorithmPreset get activePreset {
    if (algorithmDisabled) return AlgorithmPreset.noAlgorithm;
    if (knownPercent == 40 &&
        discoveryPercent == 35 &&
        forgottenPercent == 15 &&
        wildcardPercent == 10 &&
        antiRepetitionDays == 3 &&
        penalizeSkippedTracks &&
        prioritizeFavorites &&
        avoidSameArtistBackToBack) {
      return AlgorithmPreset.balanced;
    }
    if (knownPercent == 15 &&
        discoveryPercent == 55 &&
        forgottenPercent == 10 &&
        wildcardPercent == 20 &&
        antiRepetitionDays == 7) {
      return AlgorithmPreset.discovery;
    }
    if (knownPercent == 25 &&
        discoveryPercent == 15 &&
        forgottenPercent == 50 &&
        wildcardPercent == 10 &&
        antiRepetitionDays == 7) {
      return AlgorithmPreset.nostalgia;
    }
    return AlgorithmPreset.custom;
  }

  factory AlgorithmControlSettings.forPreset(AlgorithmPreset preset) {
    return switch (preset) {
      AlgorithmPreset.balanced => defaults,
      AlgorithmPreset.discovery => const AlgorithmControlSettings(
        knownPercent: 15,
        discoveryPercent: 55,
        forgottenPercent: 10,
        wildcardPercent: 20,
        algorithmDisabled: false,
        antiRepetitionDays: 7,
        penalizeSkippedTracks: true,
        prioritizeFavorites: false,
        avoidSameArtistBackToBack: true,
      ),
      AlgorithmPreset.nostalgia => const AlgorithmControlSettings(
        knownPercent: 25,
        discoveryPercent: 15,
        forgottenPercent: 50,
        wildcardPercent: 10,
        algorithmDisabled: false,
        antiRepetitionDays: 7,
        penalizeSkippedTracks: true,
        prioritizeFavorites: true,
        avoidSameArtistBackToBack: true,
      ),
      AlgorithmPreset.noAlgorithm => const AlgorithmControlSettings(
        knownPercent: 100,
        discoveryPercent: 0,
        forgottenPercent: 0,
        wildcardPercent: 0,
        algorithmDisabled: true,
        antiRepetitionDays: 0,
        penalizeSkippedTracks: false,
        prioritizeFavorites: true,
        avoidSameArtistBackToBack: false,
      ),
      AlgorithmPreset.custom => defaults,
    };
  }

  /// Rebalances the 4 distribution weights cleanly so they always total 100%.
  AlgorithmControlSettings withWeightAdjusted(
    AlgorithmWeightSlot slot,
    int requestedPercent,
  ) {
    final target = requestedPercent.clamp(0, 100);
    final weights = <AlgorithmWeightSlot, int>{
      AlgorithmWeightSlot.known: knownPercent,
      AlgorithmWeightSlot.discovery: discoveryPercent,
      AlgorithmWeightSlot.forgotten: forgottenPercent,
      AlgorithmWeightSlot.wildcard: wildcardPercent,
    };
    weights[slot] = target;
    final remaining = 100 - target;
    final others = AlgorithmWeightSlot.values
        .where((candidate) => candidate != slot)
        .toList(growable: false);
    final currentOtherSum = others.fold<int>(
      0,
      (sum, key) => sum + (weights[key] ?? 0),
    );
    if (remaining == 0) {
      for (final key in others) {
        weights[key] = 0;
      }
    } else if (currentOtherSum <= 0) {
      final base = remaining ~/ others.length;
      var leftover = remaining - (base * others.length);
      for (final key in others) {
        weights[key] = base + (leftover > 0 ? 1 : 0);
        if (leftover > 0) leftover -= 1;
      }
    } else {
      var assigned = 0;
      final scaled = <AlgorithmWeightSlot, double>{};
      for (final key in others) {
        final raw = ((weights[key] ?? 0) * remaining) / currentOtherSum;
        final floored = raw.floor();
        weights[key] = floored;
        scaled[key] = raw - floored;
        assigned += floored;
      }
      var deficit = remaining - assigned;
      final byFraction = others.toList(growable: false)
        ..sort((a, b) => (scaled[b] ?? 0).compareTo(scaled[a] ?? 0));
      var index = 0;
      while (deficit > 0) {
        final key = byFraction[index % byFraction.length];
        weights[key] = (weights[key] ?? 0) + 1;
        deficit -= 1;
        index += 1;
      }
    }

    return copyWith(
      knownPercent: weights[AlgorithmWeightSlot.known],
      discoveryPercent: weights[AlgorithmWeightSlot.discovery],
      forgottenPercent: weights[AlgorithmWeightSlot.forgotten],
      wildcardPercent: weights[AlgorithmWeightSlot.wildcard],
      algorithmDisabled: false,
    );
  }

  AlgorithmControlSettings copyWith({
    int? knownPercent,
    int? discoveryPercent,
    int? forgottenPercent,
    int? wildcardPercent,
    bool? algorithmDisabled,
    int? antiRepetitionDays,
    bool? penalizeSkippedTracks,
    bool? prioritizeFavorites,
    bool? avoidSameArtistBackToBack,
  }) {
    return AlgorithmControlSettings(
      knownPercent: (knownPercent ?? this.knownPercent).clamp(0, 100),
      discoveryPercent: (discoveryPercent ?? this.discoveryPercent).clamp(
        0,
        100,
      ),
      forgottenPercent: (forgottenPercent ?? this.forgottenPercent).clamp(
        0,
        100,
      ),
      wildcardPercent: (wildcardPercent ?? this.wildcardPercent).clamp(0, 100),
      algorithmDisabled: algorithmDisabled ?? this.algorithmDisabled,
      antiRepetitionDays: _sanitizeAntiRepetitionDays(
        antiRepetitionDays ?? this.antiRepetitionDays,
      ),
      penalizeSkippedTracks:
          penalizeSkippedTracks ?? this.penalizeSkippedTracks,
      prioritizeFavorites: prioritizeFavorites ?? this.prioritizeFavorites,
      avoidSameArtistBackToBack:
          avoidSameArtistBackToBack ?? this.avoidSameArtistBackToBack,
    );
  }

  String summaryLabel({bool spanish = true}) {
    if (algorithmDisabled) {
      return spanish
          ? 'Modo sin algoritmo · Solo tu selección'
          : 'No-algorithm mode · Only your picks';
    }
    final presetText = activePreset.label(spanish: spanish);
    final antiRepText = antiRepetitionDays <= 0
        ? (spanish ? 'Sin anti-repetición' : 'No anti-repeat')
        : (spanish
              ? 'Anti-repetición ${antiRepetitionDays}d'
              : 'Anti-repeat ${antiRepetitionDays}d');
    return '$presetText · $antiRepText';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'knownPercent': knownPercent,
    'discoveryPercent': discoveryPercent,
    'forgottenPercent': forgottenPercent,
    'wildcardPercent': wildcardPercent,
    'algorithmDisabled': algorithmDisabled,
    'antiRepetitionDays': antiRepetitionDays,
    'penalizeSkippedTracks': penalizeSkippedTracks,
    'prioritizeFavorites': prioritizeFavorites,
    'avoidSameArtistBackToBack': avoidSameArtistBackToBack,
  };

  String toJsonString() => jsonEncode(toJson());

  static AlgorithmControlSettings fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;
      final known = _readInt(decoded['knownPercent'], 40).clamp(0, 100);
      final discovery = _readInt(decoded['discoveryPercent'], 35).clamp(0, 100);
      final forgotten = _readInt(decoded['forgottenPercent'], 15).clamp(0, 100);
      final wildcard = _readInt(decoded['wildcardPercent'], 10).clamp(0, 100);
      final sum = known + discovery + forgotten + wildcard;
      final normalizedKnown = sum == 100 ? known : 40;
      final normalizedDiscovery = sum == 100 ? discovery : 35;
      final normalizedForgotten = sum == 100 ? forgotten : 15;
      final normalizedWildcard = sum == 100 ? wildcard : 10;
      return AlgorithmControlSettings(
        knownPercent: normalizedKnown,
        discoveryPercent: normalizedDiscovery,
        forgottenPercent: normalizedForgotten,
        wildcardPercent: normalizedWildcard,
        algorithmDisabled: decoded['algorithmDisabled'] == true,
        antiRepetitionDays: _sanitizeAntiRepetitionDays(
          _readInt(decoded['antiRepetitionDays'], 3),
        ),
        penalizeSkippedTracks: decoded['penalizeSkippedTracks'] != false,
        prioritizeFavorites: decoded['prioritizeFavorites'] != false,
        avoidSameArtistBackToBack:
            decoded['avoidSameArtistBackToBack'] != false,
      );
    } catch (_) {
      return defaults;
    }
  }

  static int _readInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int _sanitizeAntiRepetitionDays(int days) {
    if (supportedAntiRepetitionDays.contains(days)) return days;
    if (days <= 0) return 0;
    for (final supported in supportedAntiRepetitionDays) {
      if (days <= supported) return supported;
    }
    return supportedAntiRepetitionDays.last;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AlgorithmControlSettings &&
            other.knownPercent == knownPercent &&
            other.discoveryPercent == discoveryPercent &&
            other.forgottenPercent == forgottenPercent &&
            other.wildcardPercent == wildcardPercent &&
            other.algorithmDisabled == algorithmDisabled &&
            other.antiRepetitionDays == antiRepetitionDays &&
            other.penalizeSkippedTracks == penalizeSkippedTracks &&
            other.prioritizeFavorites == prioritizeFavorites &&
            other.avoidSameArtistBackToBack == avoidSameArtistBackToBack;
  }

  @override
  int get hashCode => Object.hash(
    knownPercent,
    discoveryPercent,
    forgottenPercent,
    wildcardPercent,
    algorithmDisabled,
    antiRepetitionDays,
    penalizeSkippedTracks,
    prioritizeFavorites,
    avoidSameArtistBackToBack,
  );
}
