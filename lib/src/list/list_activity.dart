/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

import '../api/api_holders.dart';

/// Pauses [list] while [child] is hidden, its tickers off (a route covering
/// it, a tab not shown) or [shown] false (a list the page leaves out for now):
/// what changes meanwhile is read once it shows again.
class ListActivity extends StatefulWidget {
  const ListActivity({
    required ActiveHolder this._list,
    required this.child,
    super.key,
    this.shown = true,
  }) : lists = const [];

  /// Pauses every one of [lists] the same way: the holders of one screen.
  const ListActivity.all({
    required this.lists,
    required this.child,
    super.key,
    this.shown = true,
  }) : _list = null;

  final ActiveHolder? _list;
  final List<ActiveHolder> lists;
  final Widget child;

  /// Whether the page shows the holders now, whatever its tickers say.
  final bool shown;

  ActiveHolder get list => _list ?? lists.first;

  List<ActiveHolder> get _holders => [?_list, ...lists];

  @override
  State<ListActivity> createState() => _ListActivityState();
}

class _ListActivityState extends State<ListActivity> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  @override
  void didUpdateWidget(ListActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    _apply();
  }

  void _apply() {
    final active = widget.shown && TickerMode.valuesOf(context).enabled;

    for (final holder in widget._holders) {
      if (holder.active != active) {
        holder.active = active;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
