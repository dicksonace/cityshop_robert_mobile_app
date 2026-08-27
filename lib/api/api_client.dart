import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isNetwork = false});

  final String message;
  final int? statusCode;

  /// True for timeouts / unreachable host — not necessarily that the phone
  /// has no Wi‑Fi or mobile data.
  final bool isNetwork;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient() {
    // Do not set a global Content-Type. JSON requests get application/json from
    // Dio when the body is a Map; multipart must set its own boundary header.
    // A global application/json conflicts with FormData and throws:
    // "Unable to set different values for contentType and the content-type header".
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        // Ghana mobile networks often need a longer handshake than the default.
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 35),
        sendTimeout: const Duration(seconds: 35),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;

  /// `resetOnError: false` is critical: after a phone reboot Android Keystore
  /// can briefly fail to decrypt, and the package default (true) wipes the
  /// login token — user appears logged out until they sign in again.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  static const _prefsTokenKey = 'cityshop_auth_token_backup';

  Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: ApiConfig.tokenKey, value: token);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenKey, token);
  }

  Future<void> clearToken() async {
    try {
      await _storage.delete(key: ApiConfig.tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTokenKey);
    await prefs.remove(ApiConfig.userCacheKey);
  }

  /// Persist the last successful user profile so cold start offline still
  /// shows as logged in (token alone is not enough — UI keys off `user`).
  Future<void> saveUserCache(Map<String, dynamic> userJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ApiConfig.userCacheKey, jsonEncode(userJson));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUserCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(ApiConfig.userCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getToken() async {
    try {
      return await _readToken().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Keystore can hang after reboot — prefer the SharedPreferences backup.
      try {
        final prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 2));
        return prefs.getString(_prefsTokenKey);
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backup = prefs.getString(_prefsTokenKey);
      if (backup != null && backup.isNotEmpty) {
        // Prefer the fast backup so boot is never blocked on Keystore.
        unawaited(_syncSecureToken(backup));
        return backup;
      }
    } catch (_) {}

    try {
      final secure = await _storage.read(key: ApiConfig.tokenKey);
      if (secure != null && secure.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsTokenKey, secure);
        } catch (_) {}
        return secure;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _syncSecureToken(String token) async {
    try {
      await _storage.write(key: ApiConfig.tokenKey, value: token);
    } catch (_) {}
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) {
    return _withRetry(
      () => _dio.get(path, queryParameters: query),
      maxAttempts: maxAttempts,
    );
  }

  Future<List<int>> getBytes(String path) async {
    final res = await _withRetry(
      () => _dio.get(
        path,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    final data = res.data;
    if (data is List<int>) return data;
    return <int>[];
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    int maxAttempts = 2,
  }) {
    return _withRetry(
      () => _dio.post(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
      maxAttempts: maxAttempts,
    );
  }

  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
    int maxAttempts = 2,
  }) {
    return _withRetry(
      () => _dio.patch(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
      maxAttempts: maxAttempts,
    );
  }

  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    int maxAttempts = 2,
  }) {
    return _withRetry(
      () => _dio.put(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
      maxAttempts: maxAttempts,
    );
  }

  Future<Response<dynamic>> delete(
    String path, {
    Object? data,
    int maxAttempts = 2,
  }) {
    return _withRetry(
      () => _dio.delete(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
      maxAttempts: maxAttempts,
    );
  }

  Future<Response<dynamic>> postMultipart(
    String path, {
    required Map<String, dynamic> fields,
    required String fileField,
    required String filePath,
    String filename = 'upload.jpg',
    String? contentType,
  }) {
    return postForm(
      path,
      {
        ...fields,
        fileField: filePath,
      },
      fileFields: [fileField],
      filenames: {fileField: filename},
      contentTypes: {
        if (contentType != null) fileField: contentType,
      },
    );
  }

  /// Multipart POST. Values that are file paths (and listed in [fileFields])
  /// or [MultipartFile]s are uploaded; everything else is a form field.
  Future<Response<dynamic>> postForm(
    String path,
    Map<String, dynamic> data, {
    List<String>? fileFields,
    Map<String, String>? filenames,
    Map<String, String>? contentTypes,
    int maxAttempts = 4,
  }) {
    return _withRetry(
      () async {
        final map = <String, dynamic>{};
        for (final entry in data.entries) {
          final value = entry.value;
          if (value == null) continue;
          final isFile = value is MultipartFile ||
              (value is String &&
                  (fileFields?.contains(entry.key) == true || entry.key.startsWith('files[')));
          if (isFile && value is String) {
            map[entry.key] = await MultipartFile.fromFile(
              value,
              filename: filenames?[entry.key] ?? value.split('/').last,
              contentType: contentTypes?[entry.key] == null
                  ? null
                  : _parseMediaType(contentTypes![entry.key]!),
            );
          } else {
            map[entry.key] = value;
          }
        }
        return _dio.post(
          path,
          data: FormData.fromMap(map),
          options: Options(
            sendTimeout: const Duration(seconds: 180),
            receiveTimeout: const Duration(seconds: 180),
          ),
        );
      },
      maxAttempts: maxAttempts,
    );
  }

  Future<Response<dynamic>> _withRetry(
    Future<Response<dynamic>> Function() run, {
    int maxAttempts = 2,
  }) async {
    DioException? last;
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await run();
      } on DioException catch (e) {
        last = e;
        final canRetry = _isTransient(e) && attempt < attempts;
        if (!canRetry) throw _mapError(e);
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
      }
    }
    throw _mapError(last!);
  }

  /// Safe to retry: never got a usable HTTP response from the server.
  bool _isTransient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code == 502 || code == 503 || code == 504;
      default:
        return false;
    }
  }

  MediaType? _parseMediaType(String value) {
    final parts = value.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return MediaType(parts[0], parts[1]);
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    String message = 'Something went wrong. Please try again.';
    var isNetwork = false;

    if (data is Map) {
      if (data['message'] is String) {
        message = data['message'] as String;
      } else if (data['errors'] is Map) {
        final errors = data['errors'] as Map;
        final first = errors.values.expand((v) => v is List ? v : [v]).firstOrNull;
        if (first != null) message = first.toString();
      }
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      isNetwork = true;
      message = 'Connection is slow. Please try again.';
    } else if (e.type == DioExceptionType.connectionError) {
      isNetwork = true;
      // Phone often still has Wi‑Fi/data — CityShop just wasn't reachable this time.
      message = 'Couldn’t reach CityShop. Check your network and try again.';
    }

    return ApiException(
      message,
      statusCode: e.response?.statusCode,
      isNetwork: isNetwork,
    );
  }
}
