/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Represents a paginated API response
///
/// Contains the list of items and pagination metadata from FastAPI.
class PaginationResult<T> {
  /// The list of items for the current page
  final List<T> items;

  /// Total number of items across all pages
  final int total;

  /// Maximum number of items per page (limit)
  final int limit;

  /// Number of items to skip (offset)
  final int offset;

  /// Total number of pages
  final int totalPages;

  /// Whether this page was served from the local mirror instead of the server.
  ///
  /// True when the server could not be reached and the offline engine fell back
  /// to the cache, or when the cache was queried directly: the data is as fresh
  /// as the last successful read, which a UI may want to signal.
  final bool fromCache;

  const PaginationResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.totalPages,
    this.fromCache = false,
  });

  /// Same page, marked as coming from the local mirror.
  PaginationResult<T> asCached() => fromCache
      ? this
      : PaginationResult<T>(
          items: items,
          total: total,
          limit: limit,
          offset: offset,
          totalPages: totalPages,
          fromCache: true,
        );

  /// Create from JSON response
  ///
  /// Expected format from FastAPI:
  /// ```json
  /// {
  ///   "items": [...],
  ///   "total": 100,
  ///   "limit": 25,
  ///   "offset": 0,
  ///   "total_pages": 4
  /// }
  /// ```
  factory PaginationResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonItem,
  ) {
    final items =
        (json['items'] as List<dynamic>?)
            ?.map((item) => fromJsonItem(item as Map<String, dynamic>))
            .toList() ??
        [];

    return PaginationResult<T>(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
      offset: json['offset'] as int? ?? 0,
      totalPages: json['total_pages'] as int? ?? 0,
    );
  }

  /// Create an empty result
  factory PaginationResult.empty() {
    return PaginationResult<T>(
      items: const [],
      total: 0,
      limit: 0,
      offset: 0,
      totalPages: 0,
    );
  }
}
