/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'fetcher.dart';

/// Mixin that provides automatic Fetcher disposal
///
/// Use this mixin in your StatefulWidget's State to get automatic
/// request cancellation when the widget is disposed.
///
/// Example:
/// ```dart
/// class MyWidget extends StatefulWidget {
///   @override
///   State<MyWidget> createState() => _MyWidgetState();
/// }
///
/// class _MyWidgetState extends State<MyWidget> with FetcherMixin {
///   @override
///   void initState() {
///     super.initState();
///     loadData();
///   }
///
///   Future<void> loadData() async {
///     final response = await fetcher.get('/users');
///     // Handle response
///   }
/// }
/// ```
mixin FetcherMixin<T extends StatefulWidget> on State<T> {
  /// The Fetcher instance for this widget
  ///
  /// Automatically disposed when the widget is disposed
  late final Fetcher fetcher = Fetcher.create();

  @override
  void dispose() {
    fetcher.dispose(); // Auto-cancel all requests
    super.dispose();
  }
}
