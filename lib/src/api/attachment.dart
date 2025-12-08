/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import '../api/api.dart';

/// Attachment model
class Attachment {
  final int id;
  final String name;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final DateTime createdAt;
  final DateTime updatedAt;

  Attachment({
    required this.id,
    required this.name,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as int,
      name: json['name'] as String,
      extension: json['extension'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int,
      width: json['width'] as int?,
      height: json['height'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'extension': extension,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'width': width,
      'height': height,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get the full filename with extension
  String get filename => extension.isNotEmpty ? '$name.$extension' : name;

  /// Check if this attachment is an image
  bool get isImage => mimeType.startsWith('image/');

  /// Check if this attachment is a video
  bool get isVideo => mimeType.startsWith('video/');

  /// Check if this attachment is audio
  bool get isAudio => mimeType.startsWith('audio/');

  /// Check if this attachment is a document
  bool get isDocument =>
      mimeType.contains('pdf') ||
      mimeType.contains('document') ||
      mimeType.contains('text');

  @override
  String toString() => 'Attachment(id: $id, name: $filename, size: $sizeBytes)';
}

/// Attachment API helper
///
/// Usage:
/// ```dart
/// final attachmentApi = AttachmentApi();
/// final attachments = await attachmentApi.list();
/// final attachment = await attachmentApi.get('1');
/// await attachmentApi.delete('1');
/// ```
class AttachmentApi extends ApiModel<Attachment> {
  AttachmentApi({String prefix = '/{app}'}) : super('$prefix/attachments');

  @override
  Attachment fromJson(Map<String, dynamic> json) => Attachment.fromJson(json);
}
