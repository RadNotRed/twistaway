import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'place_search_service.dart';

class PlaceHistory {
  PlaceHistory({int maximumEntries = 24}) : _maximumEntries = maximumEntries;

  factory PlaceHistory.decode(String? encoded, {int maximumEntries = 24}) {
    final history = PlaceHistory(maximumEntries: maximumEntries);
    if (encoded == null || encoded.isEmpty) return history;

    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      history._entries.addAll(
        values
            .whereType<Map<String, dynamic>>()
            .map(_PlaceHistoryEntry.fromJson)
            .whereType<_PlaceHistoryEntry>()
            .take(maximumEntries),
      );
    } catch (_) {
      // A damaged local history should never prevent location search.
    }
    return history;
  }

  final int _maximumEntries;
  final List<_PlaceHistoryEntry> _entries = [];
  final Distance _distance = const Distance();

  bool get isEmpty => _entries.isEmpty;

  void record(PlaceResult place, {DateTime? usedAt}) {
    final normalizedName = _normalize(place.name);
    final existingIndex = _entries.indexWhere(
      (entry) =>
          entry.normalizedName == normalizedName ||
          _distance.as(
                LengthUnit.Meter,
                entry.place.latLng,
                place.latLng,
              ) <
              25,
    );
    final existing =
        existingIndex < 0 ? null : _entries.removeAt(existingIndex);
    _entries.insert(
      0,
      _PlaceHistoryEntry(
        place: place,
        normalizedName: normalizedName,
        useCount: (existing?.useCount ?? 0) + 1,
        lastUsed: usedAt ?? DateTime.now(),
      ),
    );
    if (_entries.length > _maximumEntries) {
      _entries.removeRange(_maximumEntries, _entries.length);
    }
  }

  List<PlaceResult> suggestions(
    String query, {
    LatLng? center,
    int limit = 6,
  }) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.length < 2) return const [];

    final queryWords = normalizedQuery.split(' ');
    final matches = _entries.where((entry) {
      return queryWords.every(
        (word) => entry.normalizedName
            .split(RegExp(r'[ ,]+'))
            .any((part) => part.startsWith(word)),
      );
    }).map((entry) {
      final distanceMeters = center == null
          ? null
          : _distance.as(LengthUnit.Meter, center, entry.place.latLng);
      final relevance = entry.normalizedName == normalizedQuery
          ? 3
          : entry.normalizedName.startsWith(normalizedQuery)
              ? 2
              : 1;
      return (
        entry: entry,
        distanceMeters: distanceMeters,
        relevance: relevance,
      );
    }).toList();

    matches.sort((a, b) {
      final relevance = b.relevance.compareTo(a.relevance);
      if (relevance != 0) return relevance;
      final useCount = b.entry.useCount.compareTo(a.entry.useCount);
      if (useCount != 0) return useCount;
      final distance = (a.distanceMeters ?? double.infinity)
          .compareTo(b.distanceMeters ?? double.infinity);
      if (distance != 0) return distance;
      return b.entry.lastUsed.compareTo(a.entry.lastUsed);
    });

    return matches.take(math.max(0, limit)).map((match) {
      final place = match.entry.place;
      return PlaceResult(
        name: place.name,
        latLng: place.latLng,
        type: place.type,
        distanceMeters: match.distanceMeters,
      );
    }).toList(growable: false);
  }

  String encode() => jsonEncode(
        _entries.map((entry) => entry.toJson()).toList(growable: false),
      );

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class _PlaceHistoryEntry {
  const _PlaceHistoryEntry({
    required this.place,
    required this.normalizedName,
    required this.useCount,
    required this.lastUsed,
  });

  factory _PlaceHistoryEntry.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    final lastUsed = DateTime.tryParse(json['lastUsed'] as String? ?? '');
    if (name == null ||
        latitude == null ||
        longitude == null ||
        lastUsed == null) {
      throw const FormatException('Invalid place history entry');
    }
    return _PlaceHistoryEntry(
      place: PlaceResult(
        name: name,
        latLng: LatLng(latitude, longitude),
        type: json['type'] as String?,
      ),
      normalizedName: PlaceHistory._normalize(name),
      useCount: math.max(1, (json['useCount'] as num?)?.toInt() ?? 1),
      lastUsed: lastUsed,
    );
  }

  final PlaceResult place;
  final String normalizedName;
  final int useCount;
  final DateTime lastUsed;

  Map<String, Object?> toJson() => {
        'name': place.name,
        'latitude': place.latLng.latitude,
        'longitude': place.latLng.longitude,
        if (place.type != null) 'type': place.type,
        'useCount': useCount,
        'lastUsed': lastUsed.toIso8601String(),
      };
}
