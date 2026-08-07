import 'dart:async';

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
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
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
  }

  Future<String?> getToken() async {
    try {
      final secure = await _storage.read(key: ApiConfig.tokenKey);
      if (secure != null && secure.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_prefsTokenKey) != secure) {
          await prefs.setString(_prefsTokenKey, secure);
        }
        return secure;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final backup = prefs.getString(_prefsTokenKey);
    if (backup != null && backup.isNotEmpty) {
      try {
        await _storage.write(key: ApiConfig.tokenKey, value: backup);
      } catch (_) {}
      return backup;
    }
    return null;
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) {
    return _withRetry(() => _dio.get(path, queryParameters: query));
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
  }) {
    return _withRetry(
      () => _dio.post(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
    );
  }

  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
  }) {
    return _withRetry(
      () => _dio.patch(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
    );
  }

  Future<Response<dynamic>> put(
    String path, {
    Object? data,
  }) {
    return _withRetry(
      () => _dio.put(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
    );
  }

  Future<Response<dynamic>> delete(String path, {Object? data}) {
    return _withRetry(
      () => _dio.delete(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      ),
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
    return _withRetry(
      () async {
        final form = FormData.fromMap({
          ...fields,
          fileField: await MultipartFile.fromFile(
            filePath,
            filename: filename,
            contentType: contentType == null ? null : _parseMediaType(contentType),
          ),
        });
        return _dio.post(
          path,
          data: form,
          options: Options(
            sendTimeout: const Duration(seconds: 120),
            receiveTimeout: const Duration(seconds: 120),
          ),
        );
      },
      maxAttempts: 2,
    );
  }

  /// Retries brief network blips (common on mobile data) before surfacing an error.
  Future<Response<dynamic>> _withRetry(
    Future<Response<dynamic>> Function() run, {
    int maxAttempts = 3,
  }) async {
    DioException? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await run();
      } on DioException catch (e) {
        last = e;
        final canRetry = _isTransient(e) && attempt < maxAttempts;
        if (!canRetry) throw _mapError(e);
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
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
