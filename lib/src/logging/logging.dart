/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Logging utilities for FastEdgy
///
/// This module provides a simple and extensible logging system based on
/// the `logging` package with support for multiple listeners.
library;

export './logger.dart';
export './log_listener.dart';
export './listeners/console_log_listener.dart';
export './listeners/flutter_log_listener.dart';
