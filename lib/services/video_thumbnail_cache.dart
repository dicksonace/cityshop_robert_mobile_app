import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_config.dart';
import 'media_cache.dart';

/// Generates and caches a JPEG frame from a chat video URL (no full player init).
class VideoThumbnailCache {
  VideoThumbnailCache._();

  static final Map<String, Future<File?>> _inFlight = {};

  static Future<File?> thumbnailFor(String url, {int maxWidth = 420}) {
    final resolved = ApiConfig.resolveMediaUrl(url).trim();
    if (resolved.isEmpty) return Future.value(null);

    final existing = _inFlight[resolved];
    if (existing != null) return existing;

    final future = _load(resolved, maxWidth: maxWidth);
    _inFlight[resolved] = future;
    future.whenComplete(() => _inFlight.remove(resolved));
    return future;
  }

  static Future<File?> _load(String resolved, {required int maxWidth}) async {
    final dir = await _cacheDir();
    final key = sha1.convert(utf8.encode(resolved)).toString();
    final file = File('${dir.path}/$key.jpg');
    if (await file.exists() && await file.length() > 0) return file;

    File? generated;
    try {
      generated = await _fromSource(resolved, file, maxWidth: maxWidth);
    } catch (_) {}

    if (generated == null) {
      try {
        final local = await MediaCache.fileFor(resolved);
        generated = await _fromSource(local.path, file, maxWidth: maxWidth);
      } catch (_) {}
    }
    return generated;
  }

  static Future<File?> _fromSource(
    String video,
    File dest, {
    required int maxWidth,
  }) async {
    final thumb = await VideoThumbnail.thumbnailFile(
      video: video,
      thumbnailPath: dest.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: maxWidth,
      quality: 80,
      timeMs: 800,
    );
    final out = File(thumb.path);
    if (await out.exists() && await out.length() > 0) return out;
    return null;
  }

  static Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/video_thumbs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
