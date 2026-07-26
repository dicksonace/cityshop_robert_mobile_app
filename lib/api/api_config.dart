import 'dart:io' show Platform;

/// CityShop mobile API endpoints.
/// Live site: https://cityunlock.net
class ApiConfig {
  static const productionBaseUrl = 'https://cityunlock.net/api/v1';
  static const productionMediaBaseUrl = 'https://cityunlock.net';

  /// Flip to `false` to hit production (live cityunlock.net data + login).
  static const useLocalBackend = false;

  /// Host machine from Android emulator; localhost elsewhere.
  static String get _localHost =>
      Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';

  static String get localBaseUrl => 'http://$_localHost:8000/api/v1';
  static String get localMediaBaseUrl => 'http://$_localHost:8000';

  static String get baseUrl =>
      useLocalBackend ? localBaseUrl : productionBaseUrl;
  static String get mediaBaseUrl =>
      useLocalBackend ? localMediaBaseUrl : productionMediaBaseUrl;

  static const tokenKey = 'cityshop_auth_token';
  static const deviceName = 'cityshop_mobile';
}
