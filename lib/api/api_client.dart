import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: ApiConfig.tokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) =>
      _storage.write(key: ApiConfig.tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: ApiConfig.tokenKey);

  Future<String?> getToken() => _storage.read(key: ApiConfig.tokenKey);

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
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _dio.post(path, data: data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> patch(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      return await _dio.patch(path, data: data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> delete(String path) async {
    try {
      return await _dio.delete(path);
    } on DioException catch (e) {
      throw _mapError(e);
    }
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
