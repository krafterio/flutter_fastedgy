/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'image_cache.dart';

/// The name [ApiImageCache] had, which crosses the `ImageCache` of the
/// painting layer: kept by `flutter_fastedgy.dart` alone, so that an
/// application that changes nothing sees nothing change.
typedef ImageCache = ApiImageCache;
