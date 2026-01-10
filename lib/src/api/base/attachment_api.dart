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

  bool get isDocument =>
      mimeType.contains('pdf') ||
      mimeType.contains('document') ||
      mimeType.contains('text');
}

/// Attachment API
class AttachmentApi extends ApiModel<Attachment> {
  AttachmentApi(String? basePath) : super('${basePath ?? ''}/attachments');

  @override
  Set<ApiAction> get disabledActions => {
    ApiAction.create,
    ApiAction.export,
    ApiAction.import,
    ApiAction.importTemplate,
  };
}
