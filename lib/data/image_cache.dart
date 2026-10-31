import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Disk image cache used by the preview gallery's
/// CachedNetworkImageProvider (DefaultCacheManager): its files live
/// under the temp directory's libCachedImageData folder. Only that
/// folder is measured and cleared; Flutter's in-memory image cache
/// is cleared alongside it.
class ImageCacheService {
  /// Disk bytes used by the cached images, 0 when the folder is absent.
  static Future<int> sizeBytes() async {
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/libCachedImageData');
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // A file vanishing mid-scan is not an error worth surfacing.
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clears disk + in-memory image caches. Returns the bytes freed
  /// (disk size before minus disk size after; in-memory bytes are
  /// not counted).
  static Future<int> clear() async {
    final before = await sizeBytes();
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {
      // Disk clear is best-effort; in-memory clear still runs.
    }
    imageCache.clear();
    final after = await sizeBytes();
    return before - after;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
