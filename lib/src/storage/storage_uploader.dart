/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import '../fetcher/client.dart';
import '../fetcher/http_error.dart';
import '../logging/logger.dart';
import '../metadata/metadata_provider.dart';
import '../api/base/attachment_api.dart';
import '../offline/local_image_store.dart';
import '../offline/local_sequence.dart';
import '../offline/outbox.dart';
import '../offline/pending_upload_store.dart';
import 'models.dart';

/// Service for uploading files to FastEdgy storage
///
/// When the offline services are wired ([outbox] + [uploads]), an upload that
/// cannot reach the server is buffered instead of failing: the bytes are kept
/// locally (images already optimized) and the request is replayed by the
/// `SyncEngine` on reconnect — the same contract as a buffered create.
class StorageUploader {
  /// Metadata name of the Attachment model: the scope of a buffered
  /// attachment's temporary id, and the model a replayed upload belongs to.
  static const _attachmentModel = 'attachment';

  final Fetcher _fetcher;
  final String? prefix;
  final Outbox? outbox;
  final PendingUploadStore? uploads;
  final LocalSequence? sequence;
  final MetadataProvider? metadatas;
  final LocalImageStore? images;
  final _logger = getLogger('StorageUploader');

  StorageUploader(
    this._fetcher, {
    this.prefix,
    this.outbox,
    this.uploads,
    this.sequence,
    this.metadatas,
    this.images,
  });

  /// Make a buffered image displayable while it waits for its upload.
  ///
  /// Stored under the local reference the record carries, with no dimensions, so
  /// the image pipeline's `getBestVariant` fallback serves it as the original —
  /// the same path a mirrored image takes, no special case in the widgets.
  Future<void> _keepDisplayable(
    String ref,
    Uint8List bytes,
    String? mimeType,
  ) async {
    final store = images;

    if (store == null || !(mimeType ?? '').startsWith('image/')) {
      return;
    }

    try {
      await store.putVariant(ref, 'origin', bytes);
    } on Object catch (error) {
      // A preview is a nicety: never fail a buffered upload over it.
      _logger.warning('Could not keep $ref displayable', error);
    }
  }

  /// Resource path of a model, resolved through its `api_name` like
  /// [ApiModel.resolvePath] does — never guessed from the model name.
  ///
  /// Keys the buffered operation's base path, which is how a consumer (the
  /// pending-operations view) resolves the model back from it.
  Future<String> _resourcePath(String model) async {
    final apiName = (await metadatas?.getMetadata(model))?.apiName;

    return '/${apiName ?? model}';
  }

  /// Whether a failed upload can be buffered for a later replay.
  bool get canBuffer => outbox != null && uploads != null;

  bool _shouldBuffer(Object error) => canBuffer && isServerUnavailable(error);

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
    OutboxCacheContext? cache,
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

    try {
      final response = await _fetcher.post(
        url,
        formData,
        headers: {'Content-Type': 'multipart/form-data'},
        onSendProgress: onProgress,
      );

      final result = StorageUploadResult(response.data);
      _logger.fine('Upload successful: ${result.path}');

      return result;
    } on Object catch (error) {
      if (!_shouldBuffer(error)) {
        rethrow;
      }

      // The bytes buffered here are the ones that would have been sent
      // (compressed included), so the replay re-sends exactly this.
      final buffered = await uploads!.put(
        fileBytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      await _keepDisplayable(buffered.ref, fileBytes, mimeType);
      final basePath = await _resourcePath(model);

      await outbox!.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: PendingOperation.methodUpload,
          basePath: basePath,
          recordId: modelId,
          model: model,
          // Not sent; gives a pending-operations view a name to display.
          payload: {'name': fileName},
          createdAt: createdAt,
          cache: cache ?? OutboxCacheContext(kind: 'json', namespace: model),
          upload: PendingUploadRequest(
            kind: PendingUploadRequest.kindModelField,
            uploadId: buffered.id,
            fileName: fileName,
            mimeType: mimeType,
            field: field,
            prefix: prefix ?? '',
          ),
        ),
      );
      _logger.fine('Server unreachable, buffered the upload of $fileName');

      // The local reference stands in for the storage path until the replay
      // returns the real one.
      return StorageUploadResult({'path': buffered.ref});
    }
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

    _logger.fine('File deleted successfully');
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
    Map<String, dynamic>? meta,
    CompressionOptions? compression,
    OutboxCacheContext? cache,
  }) async {
    _logger.fine('Uploading ${files.length} attachments');

    // Read (and optionally optimize) up front: the same bytes are sent now or
    // buffered below, so a compressed image is never uploaded uncompressed.
    final prepared = <String, _CompressedFile>{};

    for (final entry in files.entries) {
      prepared[entry.key] = await _prepare(entry.value, compression);
    }

    return uploadAttachmentsFromBytes(
      {for (final entry in prepared.entries) entry.key: entry.value.bytes},
      filenames: {
        for (final entry in prepared.entries) entry.key: entry.value.fileName,
      },
      onProgress: onProgress,
      meta: meta,
      cache: cache,
    );
  }

  /// Read a file, applying [compression] when it is an image.
  Future<_CompressedFile> _prepare(
    File file,
    CompressionOptions? compression,
  ) async {
    if (compression != null && _isImage(file.path)) {
      _logger.finer('Compressing image with options: $compression');

      return _compressImage(file, compression);
    }

    return _CompressedFile(
      bytes: await file.readAsBytes(),
      fileName: path.basename(file.path),
      mimeType: _getMimeType(file.path) ?? 'application/octet-stream',
    );
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
    Map<String, dynamic>? meta,
    OutboxCacheContext? cache,
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

    // Attachment values applied server-side: the owner travels with the upload
    // so the record is created already associated, in a single request.
    if (meta != null && meta.isNotEmpty) {
      formData.fields.add(MapEntry('meta', jsonEncode(meta)));
    }

    // Upload all files
    final url = '${prefix ?? ''}/storage/upload/attachments';
    _logger.fine('Uploading to $url');

    final Response response;

    try {
      response = await _fetcher.post(
        url,
        formData,
        headers: {'Content-Type': 'multipart/form-data'},
        onSendProgress: onProgress,
      );
    } on Object catch (error) {
      if (!_shouldBuffer(error)) {
        rethrow;
      }

      return _bufferAttachments(
        filesBytes,
        filenames: filenames,
        meta: meta,
        cache: cache,
      );
    }

    final responseData = response.data as Map<String, dynamic>;
    final attachmentsList = responseData['attachments'] as List;

    final attachments = attachmentsList
        .map((item) => Attachment(item))
        .toList();

    _logger.fine('Uploaded ${attachments.length} attachments successfully');

    return attachments;
  }

  /// Buffer attachments the server could not receive, and return the optimistic
  /// local records standing in for them.
  ///
  /// Each file becomes one `UPLOAD` operation, so it is replayed — and counted
  /// in the pending badge — on its own. The returned records carry a negative
  /// temporary id and the local reference of their bytes, both swapped for the
  /// server values once replayed.
  Future<List<Attachment>> _bufferAttachments(
    Map<String, Uint8List> filesBytes, {
    required Map<String, String> filenames,
    Map<String, dynamic>? meta,
    OutboxCacheContext? cache,
  }) async {
    final store = uploads!;
    final queue = outbox!;
    final results = <Attachment>[];
    final attachmentPath = await _resourcePath(_attachmentModel);
    final context =
        cache ??
        const OutboxCacheContext(kind: 'json', namespace: 'attachment');

    for (final entry in filesBytes.entries) {
      final fileName = filenames[entry.key] ?? '${entry.key}.bin';
      final mimeType = _getMimeTypeFromFilename(fileName);
      final values = _attachmentMetaFor(meta, entry.key);
      final buffered = await store.put(
        entry.value,
        fileName: fileName,
        mimeType: mimeType,
      );
      await _keepDisplayable(buffered.ref, entry.value, mimeType);
      final tempId = await _nextAttachmentId();

      await queue.enqueue(
        (id, createdAt) => PendingOperation(
          id: id,
          method: PendingOperation.methodUpload,
          basePath: attachmentPath,
          recordId: tempId,
          model: _attachmentModel,
          // Not sent (the multipart is built from `upload`); carried so a
          // pending-operations view has something better to show than an id.
          payload: {'name': fileName},
          createdAt: createdAt,
          cache: context,
          upload: PendingUploadRequest(
            kind: PendingUploadRequest.kindAttachment,
            uploadId: buffered.id,
            fileName: fileName,
            mimeType: mimeType,
            meta: values,
            prefix: prefix ?? '',
          ),
        ),
      );

      results.add(
        Attachment({
          'id': tempId,
          'name': path.basenameWithoutExtension(fileName),
          'extension': path.extension(fileName).replaceFirst('.', ''),
          'mime_type': mimeType,
          'size_bytes': entry.value.length,
          ...?values,
          // Where the bytes are until the upload goes through.
          '_local_path': buffered.ref,
          '_offline_pending': true,
        }),
      );
    }

    _logger.fine(
      'Server unreachable, buffered ${results.length} attachment uploads',
    );

    return results;
  }

  /// The attachment values for one file: the flat form applies to every file,
  /// the keyed form only to its own (mirrors what the endpoint accepts).
  Map<String, dynamic>? _attachmentMetaFor(
    Map<String, dynamic>? meta,
    String fileKey,
  ) {
    if (meta == null || meta.isEmpty) {
      return null;
    }

    final own = meta[fileKey];

    if (own is Map<String, dynamic>) {
      return own;
    }

    return meta;
  }

  Future<int> _nextAttachmentId() async {
    final sequence = this.sequence;

    if (sequence == null) {
      return -DateTime.now().microsecondsSinceEpoch;
    }

    return sequence.nextTempId(_attachmentModel);
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
