/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../base_model.dart';
import '../api_model.dart';

/// Attachment model
class Attachment extends BaseModel<Attachment> {
  Attachment(super.data);

  String get name => getString('name')!;
  set name(String value) => setString('name', value);

  String get extension => getString('extension')!;
  set extension(String value) => setString('extension', value);

  String get mimeType => getString('mime_type')!;
  set mimeType(String value) => setString('mime_type', value);

  int get sizeBytes => getInt('size_bytes')!;
  set sizeBytes(int value) => setInt('size_bytes', value);

  int? get width => getInt('width');
  set width(int? value) => setInt('width', value);

  int? get height => getInt('height');
  set height(int? value) => setInt('height', value);

  String get filename => extension.isNotEmpty ? '$name.$extension' : name;

  bool get isImage => mimeType.startsWith('image/');

  bool get isVideo => mimeType.startsWith('video/');

  bool get isAudio => mimeType.startsWith('audio/');

  /// The model the generic reference points at, and its id.
  String? get recordModel => getReferenceModel('record');
  int? get recordId => getReferenceId('record');

  /// Stages the attachment on any record the generic reference accepts — the
  /// value an upload sends as its `meta`, so the file is stored and associated
  /// in a single pass.
  Attachment attachToRecord(String model, int id) =>
      setReference('record', model, id);

  /// The rich text field this image is part of, or null when the file is a
  /// listed attachment rather than something written into the record.
  String? get inlineField => getField<String>('inline_field');

  /// Whether the file belongs to a field's text, and so is shown there rather
  /// than in the record's list of attachments.
  bool get isInline => (inlineField ?? '').isNotEmpty;

  /// Stages the attachment as part of [field]'s text.
  Attachment inlineOn(String field) => this..setField('inline_field', field);

  bool get isDocument =>
      mimeType.contains('pdf') ||
      mimeType.contains('document') ||
      mimeType.contains('text');
}

/// Attachment API
class AttachmentApi extends ApiModel<Attachment> {
  /// [modelName] is what earns the resource a replicated table of its own: keyed
  /// by the path alone, its records would mirror as opaque JSON, which no
  /// offline filter can reach.
  AttachmentApi(String? basePath)
    : super(basePath ?? '', modelName: 'attachment');

  @override
  Set<ApiAction> get disabledActions => {
    ApiAction.create,
    ApiAction.export,
    ApiAction.import,
    ApiAction.importTemplate,
  };

  /// The inherited default cannot build its own type: every resource declares
  /// one, and reads throw a cast error without it.
  @override
  Attachment fromJson(Map<String, dynamic> json) => Attachment(json);
}
