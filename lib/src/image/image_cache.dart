/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:typed_data';
import '../bus/bus.dart';
import '../auth/auth_events.dart';
import '../logging/logger.dart';

/// Cache entry for storing image data
class _CacheEntry {
  final Uint8List bytes;
  DateTime lastAccessed;
  final bool isPinned;

  _CacheEntry({
    required this.bytes,
    required this.lastAccessed,
    this.isPinned = false,
  });
}

/// Image cache statistics
class ImageCacheStats {
  /// Number of cached entries
  final int entries;

  /// Number of pinned entries
  final int pinnedEntries;

  /// Cache size in bytes
  final int sizeBytes;

  /// Cache size in MB
  final double sizeMB;

  /// Maximum number of entries allowed
  final int maxEntries;

  /// Maximum cache size in MB
  final double maxSizeMB;

  /// Number of cache hits
  final int hits;

  /// Number of cache misses
  final int misses;

  /// Hit rate (0.0 to 1.0)
  final double hitRate;

  const ImageCacheStats({
    required this.entries,
    required this.pinnedEntries,
    required this.sizeBytes,
    required this.sizeMB,
    required this.maxEntries,
    required this.maxSizeMB,
    required this.hits,
    required this.misses,
    required this.hitRate,
  });

  /// Get hit rate as percentage string
  String get hitRatePercent => '${(hitRate * 100).toStringAsFixed(1)}%';

  @override
  String toString() {
    return 'ImageCacheStats('
        'entries: $entries, '
        'pinnedEntries: $pinnedEntries, '
        'sizeMB: ${sizeMB.toStringAsFixed(2)}, '
        'hits: $hits, '
        'misses: $misses, '
        'hitRate: $hitRatePercent'
        ')';
  }
}

/// Image cache service for storing downloaded images in memory
///
/// Provides LRU cache with:
/// - Automatic eviction when limits are reached
/// - Pinning for important images (e.g., user avatar)
/// - Pending request deduplication
/// - Stats (hits, misses, hit rate)
/// - Clear on logout
class ImageCache {
  final Bus _bus;
  final _logger = getLogger('ImageCache');

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<Uint8List>> _pendingRequests = {};
  final Set<String> _pinnedPaths = {};

  /// Maximum number of images to cache
  final int maxCacheEntries;

  /// Maximum cache size in bytes
  final int maxCacheSizeBytes;

  int _cacheHits = 0;
  int _cacheMisses = 0;

  ImageCache(
    this._bus, {
    this.maxCacheEntries = 150,
    this.maxCacheSizeBytes = 50 * 1024 * 1024, // 50MB
  }) {
    _setupEventListeners();
  }

  void _setupEventListeners() {
    _bus.on<AuthLogoutEvent>().listen((_) {
      _logger.fine('Clearing image cache on logout');
      clearAllCache();
    });
  }

  /// Get cached image by URL
  ///
  /// Returns cached bytes if found, null otherwise.
  /// Updates lastAccessed timestamp and cache hit stats.
  Uint8List? getCachedImage(String url) {
    final entry = _cache[url];
    if (entry != null) {
      entry.lastAccessed = DateTime.now();
      _cacheHits++;
      return entry.bytes;
    }
    _cacheMisses++;
    return null;
  }

  /// Check if image is cached
  bool isCached(String url) {
    return _cache.containsKey(url);
  }

  /// Get pending request for URL
  ///
  /// Returns the ongoing Future if request is in progress, null otherwise.
  /// This prevents duplicate requests for the same image.
  Future<Uint8List>? getPendingRequest(String url) {
    return _pendingRequests[url];
  }

  /// Cache image bytes
  ///
  /// Stores image in cache and triggers eviction if needed.
  void cacheImage(String url, Uint8List bytes, {bool pinned = false}) {
    final isPinned = pinned || _isPinnedPath(url);

    _cache[url] = _CacheEntry(
      bytes: bytes,
      lastAccessed: DateTime.now(),
      isPinned: isPinned,
    );
    _pendingRequests.remove(url);

    _evictIfNeeded();
  }

  /// Set pending request
  ///
  /// Registers an ongoing request to prevent duplicates.
  void setPendingRequest(String url, Future<Uint8List> future) {
    _pendingRequests[url] = future;
  }

  /// Remove pending request
  ///
  /// Clears the pending request entry without affecting cached images.
  void removePendingRequest(String url) {
    _pendingRequests.remove(url);
  }

  /// Pin a path
  ///
  /// Marks all images starting with this path as pinned.
  /// Pinned images are not evicted from cache.
  void pinPath(String path) {
    _pinnedPaths.add(path);

    for (final key in _cache.keys) {
      if (key.contains(path)) {
        _cache[key] = _CacheEntry(
          bytes: _cache[key]!.bytes,
          lastAccessed: _cache[key]!.lastAccessed,
          isPinned: true,
        );
      }
    }
  }

  /// Unpin a path
  void unpinPath(String path) {
    _pinnedPaths.remove(path);

    for (final key in _cache.keys) {
      if (key.contains(path)) {
        _cache[key] = _CacheEntry(
          bytes: _cache[key]!.bytes,
          lastAccessed: _cache[key]!.lastAccessed,
          isPinned: false,
        );
      }
    }
  }

  bool _isPinnedPath(String key) {
    for (final pinnedPath in _pinnedPaths) {
      if (key.contains(pinnedPath)) {
        return true;
      }
    }
    return false;
  }

  /// Clear specific image from cache
  void clearCache(String url) {
    _cache.remove(url);
    _pendingRequests.remove(url);
  }

  /// Clear images by path prefix
  void clearCacheByPath(String path) {
    final keysToRemove = <String>[];
    for (final key in _cache.keys) {
      if (key.contains(path)) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    final pendingKeysToRemove = <String>[];
    for (final key in _pendingRequests.keys) {
      if (key.contains(path)) {
        pendingKeysToRemove.add(key);
      }
    }
    for (final key in pendingKeysToRemove) {
      _pendingRequests.remove(key);
    }
  }

  /// Clear all cache
  void clearAllCache() {
    _cache.clear();
    _pendingRequests.clear();
    _pinnedPaths.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  /// Reset cache statistics
  ///
  /// Resets hits and misses counters without clearing the cache.
  /// Useful to measure hit rate from a specific point in time.
  void resetStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  /// Evict entries if cache limits are exceeded
  ///
  /// Uses LRU eviction strategy, but preserves pinned entries.
  void _evictIfNeeded() {
    int currentSize = _getTotalCacheSize();
    int cacheCount = _cache.length;

    while ((cacheCount > maxCacheEntries || currentSize > maxCacheSizeBytes) &&
        _cache.isNotEmpty) {
      final unpinnedEntries = _cache.entries
          .where((entry) => !entry.value.isPinned)
          .toList();

      if (unpinnedEntries.isEmpty) {
        break;
      }

      unpinnedEntries.sort(
        (a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed),
      );

      final keyToRemove = unpinnedEntries.first.key;
      final removedSize = _cache[keyToRemove]!.bytes.length;
      _cache.remove(keyToRemove);

      currentSize -= removedSize;
      cacheCount--;
    }
  }

  int _getTotalCacheSize() {
    int total = 0;
    for (final entry in _cache.values) {
      total += entry.bytes.lengthInBytes;
    }
    return total;
  }

  /// Get cache size (number of entries)
  int get cacheSize => _cache.length;

  /// Get number of pinned entries
  int get pinnedCount => _cache.values.where((e) => e.isPinned).length;

  /// Get cache size in bytes
  int get cacheSizeBytes => _getTotalCacheSize();

  /// Get cache size in MB
  double get cacheSizeMB => cacheSizeBytes / (1024 * 1024);

  /// Get cache hits
  int get cacheHits => _cacheHits;

  /// Get cache misses
  int get cacheMisses => _cacheMisses;

  /// Get hit rate (0.0 to 1.0)
  double get hitRate => (_cacheHits + _cacheMisses) > 0
      ? _cacheHits / (_cacheHits + _cacheMisses)
      : 0.0;

  /// Get cache statistics
  ImageCacheStats getStats() {
    return ImageCacheStats(
      entries: cacheSize,
      pinnedEntries: pinnedCount,
      sizeBytes: cacheSizeBytes,
      sizeMB: cacheSizeMB,
      maxEntries: maxCacheEntries,
      maxSizeMB: maxCacheSizeBytes / (1024 * 1024),
      hits: cacheHits,
      misses: cacheMisses,
      hitRate: hitRate,
    );
  }

  /// Get all cache keys
  ///
  /// Returns a list of all cached image keys.
  /// Useful for debugging and analysis.
  List<String> getAllKeys() {
    return _cache.keys.toList();
  }

  /// Get cache entry info by key
  ///
  /// Returns information about a specific cache entry.
  /// Useful for debugging.
  Map<String, dynamic>? getCacheEntryInfo(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    return {
      'key': key,
      'sizeBytes': entry.bytes.lengthInBytes,
      'sizeMB': entry.bytes.lengthInBytes / (1024 * 1024),
      'isPinned': entry.isPinned,
      'lastAccessed': entry.lastAccessed.toIso8601String(),
    };
  }

  /// Get all cache entries info
  ///
  /// Returns detailed information about all cache entries.
  /// Useful for debugging and analysis.
  List<Map<String, dynamic>> getAllEntriesInfo() {
    return _cache.keys.map((key) => getCacheEntryInfo(key)!).toList();
  }
}
