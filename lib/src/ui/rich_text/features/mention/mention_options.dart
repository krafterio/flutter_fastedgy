/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// One thing a document can tell its mention sources.
///
/// Declared beside the source that understands it, never here: what an option
/// means is the source's business, and a document carrying one for a source it
/// does not offer simply carries something nobody reads.
///
/// Two of these declared `const` with the same name and the same default are
/// the *same* option — the language folds identical constants into one object,
/// and no amount of declaring them apart separates them. So name one after
/// what declares it (`user.system`) rather than after what it holds
/// (`enabled`), or two sources will silently read each other's.
class MentionOption<T> {
  /// Namespaced by its source, and what a log or a debugger shows.
  final String name;

  /// What every document says unless it says otherwise. The default belongs to
  /// the option rather than to the source, so a source reads one value and not
  /// a value-or-null it has to interpret.
  final T defaultValue;

  const MentionOption(this.name, this.defaultValue);

  @override
  String toString() => 'MentionOption($name)';
}

/// What a document says to the sources it offers.
///
/// The editor carries this without understanding any of it — which is the
/// point: a new kind of mention brings its own options and nothing between the
/// two has to learn them.
class MentionOptions {
  final Map<MentionOption<Object?>, Object?> values;

  const MentionOptions([this.values = const {}]);

  /// A document that says nothing, so every source reads its own defaults.
  static const none = MentionOptions();

  T of<T>(MentionOption<T> option) {
    final value = values[option];

    return value is T ? value : option.defaultValue;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other is! MentionOptions || other.values.length != values.length) {
      return false;
    }

    for (final entry in values.entries) {
      if (!other.values.containsKey(entry.key) ||
          other.values[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final entry in values.entries) (entry.key, entry.value),
  ]);
}
