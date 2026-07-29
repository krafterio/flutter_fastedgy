/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/material.dart';

import '../theme/component_theme.dart';
import 'rich_text_theme.dart';

/// A region that answers a tap and has no chrome of its own until an
/// application gives it some — a copy button, a cover action, a handle.
@immutable
class RichTextTapSpec {
  final VoidCallback onTap;
  final Widget child;

  /// Held open: a picker whose menu is up, a handle whose row is selected.
  final bool active;

  final BorderRadius? radius;

  /// What a pointer is told it is over, where the glyph alone says too little.
  final String? tooltip;

  const RichTextTapSpec({
    required this.onTap,
    required this.child,
    this.active = false,
    this.radius,
    this.tooltip,
  });
}

/// One choice offered by a [RichTextPickerSpec]. A null [value] is the
/// "no choice" entry — auto-detected language, no colour, default width.
@immutable
class RichTextPickerOption {
  final String? value;
  final String label;

  const RichTextPickerOption({required this.value, required this.label});
}

/// A label that opens a list of choices: the language of a code block, the
/// action on a table handle.
@immutable
class RichTextPickerSpec {
  final String label;
  final List<RichTextPickerOption> options;
  final String? selected;
  final void Function(String? value) onSelect;

  /// Drawn beside the label, where an application has a glyph for "opens".
  final Widget? indicator;

  const RichTextPickerSpec({
    required this.label,
    required this.options,
    required this.onSelect,
    this.selected,
    this.indicator,
  });
}

/// What a button is *for*, never what it looks like. An application maps these
/// onto its own variants; three is what an editing card ever needs.
enum RichTextButtonKind {
  /// What the card is there to do — save the link, insert the image.
  primary,

  /// An alternative that is not the point.
  neutral,

  /// Backing out. Reads as a way out rather than as a choice.
  quiet,
}

/// A labelled action.
@immutable
class RichTextButtonSpec {
  final String label;

  /// Null disables it — a card whose field does not yet hold a valid value.
  final VoidCallback? onTap;

  final RichTextButtonKind kind;

  const RichTextButtonSpec({
    required this.label,
    required this.onTap,
    this.kind = RichTextButtonKind.neutral,
  });
}

/// A single line of text being edited: a link's address, its title.
@immutable
class RichTextFieldSpec {
  final String label;
  final String placeholder;
  final TextEditingController controller;

  /// Drawn ahead of the text where the application has a glyph for the kind of
  /// value expected.
  final Widget? leading;

  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;

  const RichTextFieldSpec({
    required this.label,
    required this.placeholder,
    required this.controller,
    this.leading,
    this.autofocus = false,
    this.onChanged,
    this.onSubmit,
  });
}

/// The shape something not yet loaded will take.
///
/// A shape rather than a spinner: a card that settles into what its skeleton
/// promised does not jump, and a skeleton of the wrong size trades a blank for
/// a jolt.
@immutable
class RichTextPlaceholderSpec {
  final double width;
  final double height;
  final BorderRadius? radius;

  const RichTextPlaceholderSpec({
    required this.width,
    required this.height,
    this.radius,
  });
}

/// One entry of a [RichTextMenuSpec]: something to do, not a value to pick.
@immutable
class RichTextMenuAction {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  /// Removes, clears, empties. An application draws it as its own warnings look.
  final bool destructive;

  /// A rule above it, setting what follows apart from what came before.
  final bool separated;

  const RichTextMenuAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.destructive = false,
    this.separated = false,
  });
}

/// A list of actions hanging off something the module drew — a table handle, a
/// block grip.
@immutable
class RichTextMenuSpec {
  final List<RichTextMenuAction> actions;

  /// What the menu hangs from, drawn by the module. It is told whether the menu
  /// is up, so a grip can light while it is, and how to toggle it.
  final Widget Function(BuildContext context, bool isOpen, VoidCallback toggle)
  anchor;

  const RichTextMenuSpec({required this.actions, required this.anchor});
}

/// The controls an application lends to what the module draws **inside** a
/// document — as opposed to the surfaces it floats over one.
///
/// Each spec describes intent: what a tap does, what the choices are, which one
/// is current. None of them describes appearance, which is the whole point: a
/// desktop application hands its hover states and its menus, a mobile one hands
/// something else entirely, and the code block does not know the difference.
@immutable
class RichTextControls extends ComponentThemeData {
  final Widget Function(BuildContext context, RichTextTapSpec spec) tappable;
  final Widget Function(BuildContext context, RichTextPickerSpec spec) picker;
  final Widget Function(BuildContext context, RichTextButtonSpec spec) button;
  final Widget Function(BuildContext context, RichTextFieldSpec spec) field;
  final Widget Function(BuildContext context, RichTextMenuSpec spec) menu;
  final Widget Function(BuildContext context, RichTextPlaceholderSpec spec)
  placeholder;

  const RichTextControls({
    required this.tappable,
    required this.picker,
    required this.button,
    required this.field,
    required this.menu,
    required this.placeholder,
  });

  /// Plain Material, legible, and deliberately unremarkable — a package has to
  /// be usable before an application has written a single builder.
  ///
  /// Also where an application starts: `fallback.copyWith(tappable: …)` replaces
  /// the one control it cares about and keeps the rest working, instead of
  /// writing four to change one.
  static const RichTextControls fallback = RichTextControls(
    tappable: _fallbackTappable,
    picker: _fallbackPicker,
    button: _fallbackButton,
    field: _fallbackField,
    menu: _fallbackMenu,
    placeholder: _fallbackPlaceholder,
  );

  static RichTextControls of(BuildContext context) {
    return ComponentTheme.maybeOf<RichTextControls>(context) ?? fallback;
  }

  RichTextControls copyWith({
    Widget Function(BuildContext, RichTextTapSpec)? tappable,
    Widget Function(BuildContext, RichTextPickerSpec)? picker,
    Widget Function(BuildContext, RichTextButtonSpec)? button,
    Widget Function(BuildContext, RichTextFieldSpec)? field,
    Widget Function(BuildContext, RichTextMenuSpec)? menu,
    Widget Function(BuildContext, RichTextPlaceholderSpec)? placeholder,
  }) {
    return RichTextControls(
      tappable: tappable ?? this.tappable,
      picker: picker ?? this.picker,
      button: button ?? this.button,
      field: field ?? this.field,
      menu: menu ?? this.menu,
      placeholder: placeholder ?? this.placeholder,
    );
  }
}

Widget _fallbackTappable(BuildContext context, RichTextTapSpec spec) {
  final theme = RichTextTheme.of(context);
  final radius = spec.radius ?? theme.chipRadius;

  final button = Material(
    color: spec.active ? theme.selection : const Color(0x00000000),
    borderRadius: radius,
    child: InkWell(onTap: spec.onTap, borderRadius: radius, child: spec.child),
  );

  return spec.tooltip == null
      ? button
      : Tooltip(message: spec.tooltip!, child: button);
}

Widget _fallbackPicker(BuildContext context, RichTextPickerSpec spec) {
  final theme = RichTextTheme.of(context);

  return PopupMenuButton<String?>(
    tooltip: '',
    onSelected: spec.onSelect,
    itemBuilder: (context) => [
      for (final option in spec.options)
        PopupMenuItem<String?>(value: option.value, child: Text(option.label)),
    ],
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          spec.label,
          style: theme.codeText.copyWith(color: theme.mutedText),
        ),
        ?spec.indicator,
      ],
    ),
  );
}

Widget _fallbackButton(BuildContext context, RichTextButtonSpec spec) {
  return switch (spec.kind) {
    RichTextButtonKind.primary => FilledButton(
      onPressed: spec.onTap,
      child: Text(spec.label),
    ),
    RichTextButtonKind.neutral => OutlinedButton(
      onPressed: spec.onTap,
      child: Text(spec.label),
    ),
    RichTextButtonKind.quiet => TextButton(
      onPressed: spec.onTap,
      child: Text(spec.label),
    ),
  };
}

Widget _fallbackField(BuildContext context, RichTextFieldSpec spec) {
  final theme = RichTextTheme.of(context);

  return TextField(
    controller: spec.controller,
    autofocus: spec.autofocus,
    onChanged: spec.onChanged,
    onSubmitted: spec.onSubmit == null ? null : (_) => spec.onSubmit!(),
    style: theme.fieldText,
    decoration: InputDecoration(
      labelText: spec.label,
      hintText: spec.placeholder,
      prefixIcon: spec.leading,
      isDense: true,
      border: OutlineInputBorder(borderRadius: theme.chipRadius),
    ),
  );
}

Widget _fallbackMenu(BuildContext context, RichTextMenuSpec spec) {
  final theme = RichTextTheme.of(context);

  return MenuAnchor(
    menuChildren: [
      for (final action in spec.actions) ...[
        if (action.separated) const Divider(height: 1),
        MenuItemButton(
          onPressed: action.onTap,
          leadingIcon: action.icon == null ? null : Icon(action.icon, size: 16),
          child: Text(
            action.label,
            style: action.destructive
                ? theme.fieldText.copyWith(color: theme.danger)
                : theme.fieldText,
          ),
        ),
      ],
    ],
    builder: (context, controller, child) => spec.anchor(
      context,
      controller.isOpen,
      () => controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

Widget _fallbackPlaceholder(
  BuildContext context,
  RichTextPlaceholderSpec spec,
) {
  final theme = RichTextTheme.of(context);

  return Container(
    width: spec.width,
    height: spec.height,
    decoration: BoxDecoration(
      color: theme.subtleSurface,
      borderRadius: spec.radius ?? theme.chipRadius,
    ),
  );
}
