/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../container/container.dart';
import 'storage_downloader.dart';

/// Helper class for storage download operations with automatic permission handling
class StorageDownloadHelper {
  /// Download an attachment to the user's Downloads folder
  ///
  /// Automatically handles:
  /// - Permission requests (Android)
  /// - Platform-specific download folders
  /// - Error handling
  ///
  /// Returns the local file path where the file was saved.
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   final path = await StorageDownloadHelper.downloadAttachment(
  ///     attachmentId: 123,
  ///     filename: 'document.pdf',
  ///   );
  ///   print('Downloaded to: $path');
  /// } catch (e) {
  ///   print('Download failed: $e');
  /// }
  /// ```
  static Future<String> downloadAttachment({
    required int attachmentId,
    required String filename,
    bool forceDownload = true,
  }) async {
    // Request storage permission on Android
    if (Platform.isAndroid) {
      final permissionGranted = await _requestStoragePermission();
      if (!permissionGranted) {
        throw StoragePermissionException('Storage permission denied');
      }
    }

    // Get the appropriate downloads directory
    final downloadsDir = await _getDownloadsDirectory();
    final localPath = '${downloadsDir.path}/$filename';

    // Download the file
    final downloader = getService<StorageDownloader>();
    await downloader.downloadAttachmentToFile(
      attachmentId,
      localPath,
      forceDownload: forceDownload,
    );

    return localPath;
  }

  /// Download a file from a storage path to the user's Downloads folder
  ///
  /// Example:
  /// ```dart
  /// final path = await StorageDownloadHelper.downloadFile(
  ///   storagePath: 'documents/123/file.pdf',
  ///   filename: 'my_document.pdf',
  /// );
  /// ```
  static Future<String> downloadFile({
    required String storagePath,
    required String filename,
    bool forceDownload = true,
  }) async {
    // Request storage permission on Android
    if (Platform.isAndroid) {
      final permissionGranted = await _requestStoragePermission();
      if (!permissionGranted) {
        throw StoragePermissionException('Storage permission denied');
      }
    }

    // Get the appropriate downloads directory
    final downloadsDir = await _getDownloadsDirectory();
    final localPath = '${downloadsDir.path}/$filename';

    // Download the file
    final downloader = getService<StorageDownloader>();
    await downloader.downloadPathToFile(
      storagePath,
      localPath,
      forceDownload: forceDownload,
    );

    return localPath;
  }

  /// Request storage permission on Android
  /// Returns true if permission is granted, false otherwise
  static Future<bool> _requestStoragePermission() async {
    // Try with storage permission first (Android < 13)
    var status = await Permission.storage.request();
    if (status.isGranted) {
      return true;
    }

    // For Android 13+ (API 33+), try with photos/media permissions
    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted) {
        return true;
      }

      // Try media permissions as fallback
      final mediaStatus = await Permission.manageExternalStorage.request();
      if (mediaStatus.isGranted) {
        return true;
      }
    }

    return false;
  }

  /// Get the appropriate downloads directory based on platform
  static Future<Directory> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      // On Android, use /storage/emulated/0/Download
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        return downloadsDir;
      }

      // Fallback to external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return externalDir;
      }

      throw StorageException('Could not access downloads directory on Android');
    } else if (Platform.isIOS) {
      // On iOS, use app documents directory (accessible via Files app)
      return await getApplicationDocumentsDirectory();
    }

    throw StorageException('Unsupported platform');
  }

  /// Get the Downloads directory path without creating any files
  /// Useful for displaying the path to the user
  static Future<String> getDownloadsPath() async {
    final dir = await _getDownloadsDirectory();
    return dir.path;
  }

  /// Check if storage permission is granted (Android only)
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) {
      return true; // iOS doesn't need explicit permission for app documents
    }

    final status = await Permission.storage.status;
    if (status.isGranted) {
      return true;
    }

    // Check photos permission for Android 13+
    final photosStatus = await Permission.photos.status;
    return photosStatus.isGranted;
  }
}

/// Exception thrown when storage permission is denied
class StoragePermissionException implements Exception {
  final String message;
  StoragePermissionException(this.message);

  @override
  String toString() => 'StoragePermissionException: $message';
}

/// Exception thrown when storage operations fail
class StorageException implements Exception {
  final String message;
  StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}
