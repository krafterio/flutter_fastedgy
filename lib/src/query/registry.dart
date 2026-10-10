/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api_model.dart';
import '../metadata/models.dart';
import 'builder.dart';
import 'catalog.dart';
import 'query_expression.dart';

/// A rule as the inputs are chosen for it: the metadata type of its field,
/// its kind, its operator and the arity of its operator.
typedef FilterInputRule = ({
  String? type,
  FieldKind? kind,
  String operator,
  Arity arity,
});

/// The rules an input of a value is for. Every criterion declared must hold
/// the rule's value, and each one held counts: the entry holding the most
/// wins (see [resolveFilterInput]).
class FilterInputMatch {
  const FilterInputMatch({this.types, this.kinds, this.operators, this.arity});

  /// Metadata types (`date`, `many2one`).
  final List<String>? types;

  final List<FieldKind>? kinds;

  /// Operators (`between`, `in`).
  final List<String>? operators;

  final Arity? arity;

  int _score(FilterInputRule rule) {
    var count = 0;

    for (final (declared, value) in [
      (types, rule.type),
      (kinds, rule.kind),
      (operators, rule.operator),
      (arity == null ? null : [arity], rule.arity),
    ]) {
      if (declared == null) {
        continue;
      }

      if (!declared.contains(value)) {
        return -1;
      }

      count += 1;
    }

    return count;
  }
}

/// Inputs of values, `B` being what draws one, in the order they are read:
/// the package's, then the application's, so a later one wins a tie.
typedef FilterInputs<B> = List<(FilterInputMatch, B)>;

/// The input of [rule]: among [inputs] then the [local] ones of a list, the
/// entry matching the most of what it declares, the later one on a tie; null
/// when none matches.
B? resolveFilterInput<B>(
  FilterInputRule rule,
  FilterInputs<B> inputs, {
  FilterInputs<B>? local,
}) {
  B? best;
  var bestScore = -1;

  for (final (match, input) in [...inputs, ...?local]) {
    final score = match._score(rule);

    if (score >= 0 && score >= bestScore) {
      best = input;
      bestScore = score;
    }
  }

  return best;
}

/// Where the records of a model are listed and read again for the value of a
/// relation, and how one shows. What a source leaves out comes from
/// [defaultValueSource].
class ValueSource {
  const ValueSource({
    this.reader,
    this.fields,
    this.label,
    this.subtitle,
    this.image,
    this.searchFilter,
  });

  /// What lists the records and reads them again, an api model.
  final ApiModel? reader;

  /// What a record is read with.
  final List<String>? fields;

  final String Function(Map<String, dynamic> record)? label;
  final String? Function(Map<String, dynamic> record)? subtitle;
  final String? Function(Map<String, dynamic> record)? image;

  /// The filter of a search typed in.
  final Object? Function(String text)? searchFilter;
}

/// What a value source is built in: the prefix of the list, its metadata, the
/// sources it declares for itself.
class ValueSourceContext {
  const ValueSourceContext({
    this.prefix = '',
    this.metadatas,
    this.valueSources = const {},
  });

  final String prefix;
  final Map<String, MetadataModel>? metadatas;
  final Map<String, ValueSourceBuilder> valueSources;
}

typedef ValueSourceBuilder = ValueSource Function(ValueSourceContext context);

final _valueSources = <String, ValueSourceBuilder>{};

/// Says where the records of [target] (its metadata name) are listed and read
/// again, when it is not its own API, or not the way the default reads it.
/// The source a list declares wins over this one.
void registerValueSource(String target, ValueSourceBuilder source) =>
    _valueSources[target] = source;

const _labelFields = [
  'display_name',
  'name',
  'title',
  'label',
  'code',
  'email',
];
const _imageFields = ['avatar', 'image', 'logo', 'cover'];
const _textTypes = ['char', 'text', 'email'];

/// How the records of [target] are offered when nobody said otherwise: listed
/// by the API of the model under [prefix], searched on its fulltext field or
/// on its text fields, shown by the first of the fields that name a record.
ValueSource defaultValueSource(
  String target, {
  String prefix = '',
  Map<String, MetadataModel>? metadatas,
}) {
  final fields = metadatas?[target]?.fields ?? const <String, MetadataField>{};
  final labelField = _labelFields.where(fields.containsKey).firstOrNull;
  final subtitleField = labelField != 'email' && fields.containsKey('email')
      ? 'email'
      : null;
  final imageField = _imageFields.where(fields.containsKey).firstOrNull;
  final texts = [
    for (final field in fields.values)
      if (_textTypes.contains(field.type) &&
          field.filterOperators.contains('icontains'))
        field.name,
  ];
  final fulltext = fields.values
      .where((field) => field.type == 'fulltext')
      .firstOrNull;

  return ValueSource(
    reader: GenericApiModel(prefix, modelName: target),
    fields: [?labelField, ?subtitleField, ?imageField],
    label: (record) => switch (labelField == null ? null : record[labelField]) {
      null || '' => '#${record['id']}',
      final value => '$value',
    },
    subtitle: subtitleField == null
        ? null
        : (record) => record[subtitleField]?.toString(),
    image: imageField == null
        ? null
        : (record) => record[imageField]?.toString(),
    searchFilter: (text) {
      if (fulltext != null) {
        return [fulltext.name, 'search_fuzzy', text];
      }

      final rules = [
        for (final name in texts) [name, 'icontains', text],
      ];

      return rules.length > 1
          ? ['|', rules]
          : rules.firstOrNull ?? ['id', '=', readNumber(text) ?? 0];
    },
  );
}

/// The source of the values of [target]: the list's, the application's, laid
/// over the default one.
ValueSource resolveValueSource(String target, ValueSourceContext context) {
  final declared = (context.valueSources[target] ?? _valueSources[target])
      ?.call(context);
  final fallback = defaultValueSource(
    target,
    prefix: context.prefix,
    metadatas: context.metadatas,
  );

  if (declared == null) {
    return fallback;
  }

  return ValueSource(
    reader: declared.reader ?? fallback.reader,
    fields: declared.fields ?? fallback.fields,
    label: declared.label ?? fallback.label,
    subtitle: declared.subtitle ?? fallback.subtitle,
    image: declared.image ?? fallback.image,
    searchFilter: declared.searchFilter ?? fallback.searchFilter,
  );
}
