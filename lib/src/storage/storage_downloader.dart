/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../container/container.dart';
import '../fetcher/client.dart';
import '../logging/logger.dart';

/// Service for downloading files from FastEdgy storage
class StorageDownloader {
  final Fetcher _fetcher;
  final _logger = getLogger('StorageDownloader');

  StorageDownloader(this._fetcher);

  /// Factory to get StorageDownloader from DI container
  factory StorageDownloader.instance() {
    return StorageDownloader(getService<Fetcher>());
  }

  /// Download attachment as bytes
  ///
  /// Example:
  /// ```dart
  /// final downloader = StorageDownloader.instance();
  /// final bytes = await downloader.downloadAttachment(
  ///   123,
  ///   forceDownload: true,
  /// );
  /// ```
  Future<Uint8List> downloadAttachment(
    int attachmentId, {
    bool forceDownload = false,
    int? width,
    int? height,
    String? resizeMode,
    String? outputFormat,
  }) async {
    _logger.fine('Downloading attachment $attachmentId');

    final params = <String, dynamic>{};
    if (forceDownload) params['force_download'] = 'true';
    if (width != null) params['w'] = width.toString();
    if (height != null) params['h'] = height.toString();
    if (resizeMode != null) params['m'] = resizeMode;
    if (outputFormat != null) params['e'] = outputFormat;

    final response = await _fetcher.get(
      '/storage/download/attachments/$attachmentId',
      params: params,
      responseType: ResponseType.bytes,
    );

    final bytes = response.data as Uint8List;
    _logger.info('Downloaded attachment $attachmentId (${bytes.length} bytes)');

    return bytes;
  }

  /// Download attachment and save to file
  ///
  /// Example:
  /// ```dart
  /// final downloader = StorageDownloader.instance();
  /// final file = await downloader.downloadAttachmentToFile(
  ///   123,
  ///   '/path/to/save/file.pdf',
  /// );
  /// ```
  Future<File> downloadAttachmentToFile(
    int attachmentId,
    String localPath, {
    bool forceDownload = false,
  }) async {
    _logger.fine('Downloading attachment $attachmentId to $localPath');

    final bytes = await downloadAttachment(
      attachmentId,
      forceDownload: forceDownload,
    );

    final file = File(localPath);
    await file.writeAsBytes(bytes);

    _logger.info('Saved attachment $attachmentId to $localPath');

    return file;
  }

  /// Download file from storage path
  ///
  /// Example:
  /// ```dart
  /// final downloader = StorageDownloader.instance();
  /// final bytes = await downloader.downloadPath(
  ///   'documents/123/file.pdf',
  ///   forceDownload: true,
  /// );
  /// ```
  Future<Uint8List> downloadPath(
    String path, {
    bool forceDownload = false,
    int? width,
    int? height,
    String? resizeMode,
    String? outputFormat,
  }) async {
    _logger.fine('Downloading path: $path');

    final params = <String, dynamic>{};
    if (forceDownload) params['force_download'] = 'true';
    if (width != null) params['w'] = width.toString();
    if (height != null) params['h'] = height.toString();
    if (resizeMode != null) params['m'] = resizeMode;
    if (outputFormat != null) params['e'] = outputFormat;

    // Remove leading slash if present
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;

    final response = await _fetcher.get(
      '/storage/download/$cleanPath',
      params: params,
      responseType: ResponseType.bytes,
    );

    final bytes = response.data as Uint8List;
    _logger.info('Downloaded path $path (${bytes.length} bytes)');

    return bytes;
  }

  /// Download file from path and save to file
  Future<File> downloadPathToFile(
    String path,
    String localPath, {
    bool forceDownload = false,
  }) async {
    _logger.fine('Downloading path $path to $localPath');

    final bytes = await downloadPath(
      path,
      forceDownload: forceDownload,
    );

    final file = File(localPath);
    await file.writeAsBytes(bytes);

    _logger.info('Saved path $path to $localPath');

    return file;
  }

  /// Get attachment download URL
  ///
  /// Example:
  /// ```dart
  /// final url = downloader.getAttachmentUrl(123, forceDownload: true);
  /// // Returns: /storage/download/attachments/123?force_download=true
  /// ```
  String getAttachmentUrl(
    int attachmentId, {
    bool forceDownload = false,
    int? width,
    int? height,
    String? resizeMode,
    String? outputFormat,
  }) {
    final params = <String>[];
    if (forceDownload) params.add('force_download=true');
    if (width != null) params.add('w=$width');
    if (height != null) params.add('h=$height');
    if (resizeMode != null) params.add('m=$resizeMode');
    if (outputFormat != null) params.add('e=$outputFormat');

    final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';
    return '/storage/download/attachments/$attachmentId$queryString';
  }

  /// Get file download URL from path
  ///
  /// Example:
  /// ```dart
  /// final url = downloader.getFileUrl('documents/123/file.pdf');
  /// // Returns: /storage/download/documents/123/file.pdf
  /// ```
  String getFileUrl(
    String path, {
    bool forceDownload = false,
    int? width,
    int? height,
    String? resizeMode,
    String? outputFormat,
  }) {
    final params = <String>[];
    if (forceDownload) params.add('force_download=true');
    if (width != null) params.add('w=$width');
    if (height != null) params.add('h=$height');
    if (resizeMode != null) params.add('m=$resizeMode');
    if (outputFormat != null) params.add('e=$outputFormat');

    // Remove leading slash if present
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';

    return '/storage/download/$cleanPath$queryString';
  }
}
