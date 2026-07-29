/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';

/// What a package declares when it needs more than the tokens to draw itself.
///
/// The convention every implementation follows — the framework cannot enforce
/// it, but nothing works without it:
///
/// ```dart
/// class RichTextTheme extends ComponentThemeData {
///   const RichTextTheme({required this.selection, ...});
///
///   /// Derived from the roles, so overriding one token makes every theme
///   /// follow instead of repeating a colour in five places.
///   factory RichTextTheme.from(FastEdgyThemeData theme) => RichTextTheme(...);
///
///   static RichTextTheme of(BuildContext context) =>
///       ComponentTheme.maybeOf<RichTextTheme>(context) ??
///       RichTextTheme.from(FastEdgyTheme.of(context));
/// }
/// ```
///
/// Never null, never a crash, and never a design decision the application did
/// not make.
@immutable
abstract class ComponentThemeData {
  const ComponentThemeData();
}

/// Carries one package's [ComponentThemeData] down the tree, keyed by its type.
///
/// One inherited widget per theme rather than a shared registry, which buys
/// three things: a package declares its theme without anyone maintaining a
/// central list; an application overrides **one** without knowing the others
/// exist; and a subtree overrides for itself — a compact editor inside a panel,
/// a denser thread inside a dock — without touching the rest of the tree.
///
/// This is the extension mechanism Dart does not give through the type system:
/// not declaration merging, but composition by type.
class ComponentTheme<T extends ComponentThemeData> extends InheritedTheme {
  final T data;

  const ComponentTheme({required this.data, required super.child, super.key});

  /// The theme of type [T] in scope. Asserts where none was mounted: a package
  /// resolving its own theme is expected to fall back on the tokens rather than
  /// to call this.
  static T of<T extends ComponentThemeData>(BuildContext context) {
    final data = maybeOf<T>(context);
    assert(data != null, 'No ComponentTheme<$T> found in this context');

    return data!;
  }

  /// The theme of type [T] in scope, or null when the application said nothing
  /// about it — the first term of every package's resolution order.
  static T? maybeOf<T extends ComponentThemeData>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ComponentTheme<T>>()
        ?.data;
  }

  @override
  Widget wrap(BuildContext context, Widget child) {
    return ComponentTheme<T>(data: data, child: child);
  }

  @override
  bool updateShouldNotify(ComponentTheme<T> oldWidget) =>
      data != oldWidget.data;
}
