/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:path/path.dart' as path;

/// Format file size from bytes to human readable format
///
/// Example:
/// ```dart
/// print(formatFileSize(1024)); // "1.0 KB"
/// print(formatFileSize(1536)); // "1.5 KB"
/// print(formatFileSize(1048576)); // "1.0 MB"
/// print(formatFileSize(0)); // "0 B"
/// ```
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];

  final i = (bytes == 0) ? 0 : (bytes.bitLength - 1) ~/ 10;
  final index = i.clamp(0, units.length - 1);

  final size = bytes / (1 << (index * 10));

  // Format with 1 decimal place, but remove .0 for whole numbers
  final formatted = size.toStringAsFixed(1);
  final cleaned = formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;

  return '$cleaned ${units[index]}';
}

/// Get Material icon name based on MIME type
///
/// Returns appropriate Material Icons name for the file type.
/// You can use these with Icons class from Flutter.
///
/// Example:
/// ```dart
/// final iconName = getFileTypeIcon('image/jpeg');
/// print(iconName); // "image"
///
/// final icon = Icons.fromString(iconName); // In practice use a map
/// ```
String getFileTypeIcon(String mimeType) {
  if (mimeType.isEmpty) return 'insert_drive_file';

  if (mimeType.startsWith('image/')) return 'image';
  if (mimeType.startsWith('video/')) return 'video_file';
  if (mimeType.startsWith('audio/')) return 'audio_file';

  if (mimeType.contains('pdf')) return 'picture_as_pdf';
  if (mimeType.contains('word') ||
      mimeType.contains('document') ||
      mimeType.contains('text/plain')) {
    return 'description';
  }
  if (mimeType.contains('sheet') ||
      mimeType.contains('excel') ||
      mimeType.contains('csv')) {
    return 'table_chart';
  }
  if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
    return 'slideshow';
  }
  if (mimeType.contains('zip') ||
      mimeType.contains('rar') ||
      mimeType.contains('7z') ||
      mimeType.contains('tar') ||
      mimeType.contains('gz')) {
    return 'folder_zip';
  }

  return 'insert_drive_file';
}

/// Get file extension from filename
///
/// Example:
/// ```dart
/// print(getFileExtension('document.pdf')); // "pdf"
/// print(getFileExtension('image.jpg')); // "jpg"
/// print(getFileExtension('noextension')); // ""
/// ```
String getFileExtension(String filename) {
  final ext = path.extension(filename);
  return ext.isEmpty ? '' : ext.substring(1); // Remove leading dot
}

/// Check if MIME type is an image
///
/// Example:
/// ```dart
/// print(isImageFile('image/jpeg')); // true
/// print(isImageFile('image/png')); // true
/// print(isImageFile('application/pdf')); // false
/// ```
bool isImageFile(String mimeType) {
  return mimeType.startsWith('image/');
}

/// Check if MIME type is a video
bool isVideoFile(String mimeType) {
  return mimeType.startsWith('video/');
}

/// Check if MIME type is audio
bool isAudioFile(String mimeType) {
  return mimeType.startsWith('audio/');
}

/// Check if MIME type is a document
bool isDocumentFile(String mimeType) {
  return mimeType.contains('pdf') ||
      mimeType.contains('document') ||
      mimeType.contains('word') ||
      mimeType.contains('text');
}

/// Get MIME type from file extension
///
/// Example:
/// ```dart
/// print(getMimeTypeFromExtension('jpg')); // "image/jpeg"
/// print(getMimeTypeFromExtension('pdf')); // "application/pdf"
/// ```
String? getMimeTypeFromExtension(String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');

  switch (ext) {
    // Images
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    case 'heic':
    case 'heif':
      return 'image/heic';

    // Documents
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'txt':
      return 'text/plain';
    case 'csv':
      return 'text/csv';

    // Archives
    case 'zip':
      return 'application/zip';
    case 'rar':
      return 'application/x-rar-compressed';
    case '7z':
      return 'application/x-7z-compressed';
    case 'tar':
      return 'application/x-tar';
    case 'gz':
      return 'application/gzip';

    // Video
    case 'mp4':
      return 'video/mp4';
    case 'avi':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';

    // Audio
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'm4a':
      return 'audio/mp4';

    default:
      return null;
  }
}
