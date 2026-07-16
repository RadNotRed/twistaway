import 'dart:collection';

/// A small in-memory cache that expires stale values and evicts least-recently
/// used entries before it can grow without bound.
class ExpiringLruCache<K, V> {
  ExpiringLruCache({
    required this.maximumEntries,
    required this.timeToLive,
    DateTime Function()? clock,
  })  : assert(maximumEntries > 0),
        _clock = clock ?? DateTime.now;

  final int maximumEntries;
  final Duration timeToLive;
  final DateTime Function() _clock;
  final LinkedHashMap<K, _CacheEntry<V>> _entries = LinkedHashMap();

  int get length {
    _removeExpired();
    return _entries.length;
  }

  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (!entry.expiresAt.isAfter(_clock())) {
      return null;
    }
    _entries[key] = entry;
    return entry.value;
  }

  void put(K key, V value) {
    _removeExpired();
    _entries.remove(key);
    while (_entries.length >= maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CacheEntry(
      value: value,
      expiresAt: _clock().add(timeToLive),
    );
  }

  void clear() => _entries.clear();

  void _removeExpired() {
    final now = _clock();
    _entries.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
  }
}

class _CacheEntry<V> {
  const _CacheEntry({required this.value, required this.expiresAt});

  final V value;
  final DateTime expiresAt;
}
