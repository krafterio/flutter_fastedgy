/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../api/api_holders.dart';

/// Pauses [list] while [child] is hidden, its tickers off (a route covering
/// it, a tab not shown): what changes meanwhile is read once it shows again.
class ListActivity extends StatefulWidget {
  const ListActivity({required this.list, required this.child, super.key});

  final ActiveHolder list;
  final Widget child;

  @override
  State<ListActivity> createState() => _ListActivityState();
}

class _ListActivityState extends State<ListActivity> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.list.active = TickerMode.valuesOf(context).enabled;
  }

  @override
  void didUpdateWidget(ListActivity oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.list != widget.list) {
      widget.list.active = TickerMode.valuesOf(context).enabled;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
