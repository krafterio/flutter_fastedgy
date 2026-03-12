/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import '../fetcher/client.dart';
import '../logging/logger.dart';
import '../api/base/attachment_api.dart';
import 'models.dart';

/// Service for uploading files to FastEdgy storage
class StorageUploader {
  final Fetcher _fetcher;
  final String? prefix;
  final _logger = getLogger('StorageUploader');

  StorageUploader(this._fetcher, {this.prefix});

  /// Upload a file to a model field
  ///
  /// Example:
  /// ```dart
  /// final uploader = getService<StorageUploader>();
  /// final result = await uploader.uploadModelField(
  ///   model: 'user',
  ///   modelId: 123,
  ///   field: 'avatar',
  ///   file: File('/path/to/image.jpg'),
  ///   compression: CompressionOptions(
  ///     quality: 85,
  ///     maxSizeBytes: 1024 * 1024, // 1MB
  ///     format: ImageFormat.jpeg,
  ///   ),
  ///   onProgress: (sent, total) {
  ///     print('Progress: ${(sent / total * 100).toStringAsFixed(0)}%');
  ///   },
  /// );
  /// print('Uploaded to: ${result.path}');
  /// ```
  Future<StorageUploadResult> uploadModelField({
    required String model,
    required int modelId,
    required String field,
    required File file,
    CompressionOptions? compression,
    void Function(int sent, int total)? onProgress,
  }) async {
    _logger.fine('Uploading file to $model/$modelId/$field');

    // Prepare file bytes
    Uint8List fileBytes;
    String fileName;
    String? mimeType;

    if (compression != null && _isImage(file.path)) {
      _logger.finer('Compressing image with options: $compression');
      final compressed = await _compressImage(file, compression);
      fileBytes = compressed.bytes;
      fileName = compressed.fileName;
      mimeType = compressed.mimeType;
    } else {
      _logger.finer('Uploading original file without compression');
      fileBytes = await file.readAsBytes();
      fileName = path.basename(file.path);
      mimeType = _getMimeType(file.path);
    }

    // Create multipart file
    final multipartFile = MultipartFile.fromBytes(
      fileBytes,
      filename: fileName,
      contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
    );

    // Create form data
    final formData = FormData.fromMap({'file': multipartFile});

    // Upload with optional progress tracking
    final url = '${prefix ?? ''}/storage/upload/$model/$modelId/$field';
    _logger.fine('Uploading to $url (${fileBytes.length} bytes)');

    final response = await _fetcher.post(
      url,
      formData,
      headers: {'Content-Type': 'multipart/form-data'},
      onSendProgress: onProgress,
    );

    final result = StorageUploadResult(response.data);
    _logger.info('Upload successful: ${result.path}');

    return result;
  }

  /// Delete a file from a model field
  Future<void> deleteModelField({
    required String model,
    required int modelId,
    required String field,
  }) async {
    final url = '${prefix ?? ''}/storage/file/$model/$modelId/$field';
    _logger.fine('Deleting file at $url');

    await _fetcher.delete(url);

    _logger.info('File deleted successfully');
  }

  /// Check if file is an image based on extension
  bool _isImage(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'].contains(ext);
  }

  /// Get MIME type from file extension
  String? _getMimeType(String filePath) {
    final ext = path.extension(filePath).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  /// Compress an image file
  Future<_CompressedFile> _compressImage(
    File file,
    CompressionOptions options,
  ) async {
    // Read original image
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    _logger.finer('Original image: ${image.width}x${image.height}');

    // Resize if needed
    img.Image processedImage = image;
    if (options.maxWidth != null || options.maxHeight != null) {
      final maxWidth = options.maxWidth ?? image.width;
      final maxHeight = options.maxHeight ?? image.height;

      if (image.width > maxWidth || image.height > maxHeight) {
        processedImage = img.copyResize(
          image,
          width: image.width > maxWidth ? maxWidth : null,
          height: image.height > maxHeight ? maxHeight : null,
          maintainAspect: true,
        );
        _logger.finer(
          'Resized to: ${processedImage.width}x${processedImage.height}',
        );
      }
    }

    // Encode with specified format and quality
    List<int> compressed = options.format.encode(
      processedImage,
      quality: options.quality,
    );

    // If maxSizeBytes is specified and compressed size is still too large,
    // reduce quality iteratively
    if (options.maxSizeBytes != null &&
        compressed.length > options.maxSizeBytes!) {
      _logger.finer(
        'Compressed size ${compressed.length} exceeds max ${options.maxSizeBytes}, reducing quality',
      );

      int quality = options.quality;
      while (compressed.length > options.maxSizeBytes! && quality > 10) {
        quality -= 10;
        compressed = options.format.encode(processedImage, quality: quality);
        _logger.finer(
          'Reduced quality to $quality, size: ${compressed.length}',
        );
      }
    }

    final originalName = path.basenameWithoutExtension(file.path);
    final newFileName = '$originalName.${options.format.value}';

    _logger.fine(
      'Compressed image: ${compressed.length} bytes, quality: ${options.quality}',
    );

    return _CompressedFile(
      bytes: Uint8List.fromList(compressed),
      fileName: newFileName,
      mimeType: options.format.mimeType,
    );
  }

  /// Upload multiple attachments
  ///
  /// Example:
  /// ```dart
  /// final uploader = getService<StorageUploader>();
  /// final attachments = await uploader.uploadAttachments(
  ///   {
  ///     'file1': File('/path/to/file1.pdf'),
  ///     'file2': File('/path/to/file2.jpg'),
  ///   },
  ///   onProgress: (sent, total) {
  ///     print('Progress: ${(sent / total * 100).toStringAsFixed(0)}%');
  ///   },
  /// );
  /// print('Uploaded ${attachments.length} attachments');
  /// ```
  Future<List<Attachment>> uploadAttachments(
    Map<String, File> files, {
    void Function(int sent, int total)? onProgress,
  }) async {
    _logger.fine('Uploading ${files.length} attachments');

    // Create form data with all files
    final formData = FormData();

    for (final entry in files.entries) {
      final file = entry.value;
      final fileName = path.basename(file.path);
      final mimeType = _getMimeType(file.path);

      final multipartFile = await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
      );

      formData.files.add(MapEntry(entry.key, multipartFile));
    }

    // Upload all files
    final url = '${prefix ?? ''}/storage/upload/attachments';
    _logger.fine('Uploading to $url');

    final response = await _fetcher.post(
      url,
      formData,
      headers: {'Content-Type': 'multipart/form-data'},
      onSendProgress: onProgress,
    );

    final responseData = response.data as Map<String, dynamic>;
    final attachmentsList = responseData['attachments'] as List;

    final attachments = attachmentsList
        .map((item) => Attachment(item))
        .toList();

    _logger.info('Uploaded ${attachments.length} attachments successfully');

    return attachments;
  }

  /// Upload multiple attachments from bytes
  ///
  /// Example:
  /// ```dart
  /// final uploader = getService<StorageUploader>();
  /// final attachments = await uploader.uploadAttachmentsFromBytes(
  ///   {
  ///     'file1': bytes1,
  ///     'file2': bytes2,
  ///   },
  ///   filenames: {
  ///     'file1': 'document.pdf',
  ///     'file2': 'image.jpg',
  ///   },
  /// );
  /// ```
  Future<List<Attachment>> uploadAttachmentsFromBytes(
    Map<String, Uint8List> filesBytes, {
    required Map<String, String> filenames,
    void Function(int sent, int total)? onProgress,
  }) async {
    _logger.fine('Uploading ${filesBytes.length} attachments from bytes');

    // Create form data with all files
    final formData = FormData();

    for (final entry in filesBytes.entries) {
      final fileName = filenames[entry.key] ?? '${entry.key}.bin';
      final mimeType = _getMimeTypeFromFilename(fileName);

      final multipartFile = MultipartFile.fromBytes(
        entry.value,
        filename: fileName,
        contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
      );

      formData.files.add(MapEntry(entry.key, multipartFile));
    }

    // Upload all files
    final url = '${prefix ?? ''}/storage/upload/attachments';
    _logger.fine('Uploading to $url');

    final response = await _fetcher.post(
      url,
      formData,
      headers: {'Content-Type': 'multipart/form-data'},
      onSendProgress: onProgress,
    );

    final responseData = response.data as Map<String, dynamic>;
    final attachmentsList = responseData['attachments'] as List;

    final attachments = attachmentsList
        .map((item) => Attachment(item))
        .toList();

    _logger.info('Uploaded ${attachments.length} attachments successfully');

    return attachments;
  }

  /// Get MIME type from filename
  String? _getMimeTypeFromFilename(String fileName) {
    final ext = path.extension(fileName).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return null;
    }
  }
}

/// Internal class for compressed file data
class _CompressedFile {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  _CompressedFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}
