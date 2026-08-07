import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

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
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
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
  }) async {
    try {
      return await _dio.get(path, queryParameters: query);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.patch(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> put(
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> delete(String path, {Object? data}) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        options: data == null || data is FormData
            ? null
            : Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> postMultipart(
    String path, {
    required Map<String, dynamic> fields,
    required String fileField,
    required String filePath,
    String filename = 'upload.jpg',
    String? contentType,
  }) async {
    try {
      final form = FormData.fromMap({
        ...fields,
        fileField: await MultipartFile.fromFile(
          filePath,
          filename: filename,
          contentType: contentType == null ? null : _parseMediaType(contentType),
        ),
      });
      return await _dio.post(
        path,
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
    } on DioException catch (e) {
      throw _mapError(e);
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
    if (data is Map) {
      if (data['message'] is String) {
        message = data['message'] as String;
      } else if (data['errors'] is Map) {
        final errors = data['errors'] as Map;
        final first = errors.values.expand((v) => v is List ? v : [v]).firstOrNull;
        if (first != null) message = first.toString();
      }
    } else if (e.type == DioExceptionType.connectionError) {
      message = 'No internet connection.';
    }
    return ApiException(message, statusCode: e.response?.statusCode);
  }
}
