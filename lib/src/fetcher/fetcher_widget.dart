/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import 'fetcher.dart';

/// A widget that provides a Fetcher instance with automatic disposal
///
/// Use this widget when you need a Fetcher in your widget tree
/// without creating a StatefulWidget.
///
/// Example:
/// ```dart
/// FetcherWidget(
///   builder: (context, fetcher) {
///     return ElevatedButton(
///       onPressed: () async {
///         final response = await fetcher.get('/users');
///         // Handle response
///       },
///       child: Text('Load Users'),
///     );
///   },
/// )
/// ```
class FetcherWidget extends StatefulWidget {
  /// Builder function that receives the Fetcher instance
  final Widget Function(BuildContext context, Fetcher fetcher) builder;

  const FetcherWidget({required this.builder, super.key});

  @override
  State<FetcherWidget> createState() => _FetcherWidgetState();
}

class _FetcherWidgetState extends State<FetcherWidget> with FetcherMixin {
  @override
  Widget build(BuildContext context) {
    return widget.builder(context, fetcher);
  }
}
