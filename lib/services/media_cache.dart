import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_config.dart';

/// Downloads video/audio once, then replays from local disk (no data on next play).
class MediaCache {
  MediaCache._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
      followRedirects: true,
      validateStatus: (code) => code != null && code >= 200 && code < 400,
    ),
  );

  static final Map<String, Future<File>> _inFlight = {};

  /// Returns a local file for [url]. Downloads on first use, then reuses the cache.
  static Future<File> fileFor(String url) {
    final resolved = ApiConfig.resolveMediaUrl(url).trim();
    if (resolved.isEmpty) {
      return Future.error(StateError('Empty media URL'));
    }
    if (resolved.startsWith('file://')) {
      return Future.value(File(Uri.parse(resolved).toFilePath()));
    }
    if (!resolved.startsWith('http://') && !resolved.startsWith('https://')) {
      final local = File(resolved);
      if (local.existsSync()) return Future.value(local);
    }

    final existing = _inFlight[resolved];
    if (existing != null) return existing;

    final future = _download(resolved);
    _inFlight[resolved] = future;
    future.whenComplete(() => _inFlight.remove(resolved));
    return future;
  }

  static Future<File> _download(String resolved) async {
    final dir = await _cacheDir();
    final key = sha1.convert(utf8.encode(resolved)).toString();
    final ext = _extensionFor(resolved);
    final file = File('${dir.path}/$key$ext');

    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) return file;
      await file.delete();
    }

    final part = File('${file.path}.part');
    if (await part.exists()) {
      await part.delete();
    }

    try {
      await _dio.download(
        resolved,
        part.path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {
            'Accept': '*/*',
            'User-Agent': 'CityShopMobile/1.0',
          },
        ),
      );
      if (!await part.exists() || await part.length() <= 0) {
        throw StateError('Download produced an empty file');
      }
      if (await file.exists()) {
        await file.delete();
      }
      await part.rename(file.path);
      return file;
    } catch (e) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<Directory> _cacheDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/media_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _extensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    for (final ext in ['.mp4', '.mov', '.m4v', '.webm', '.3gp', '.m4a', '.aac', '.mp3', '.ogg', '.wav', '.caf']) {
      if (path.endsWith(ext)) return ext;
    }
    if (path.contains('/voice') || path.contains('audio')) return '.m4a';
    if (path.contains('video')) return '.mp4';
    return '.bin';
  }
}
