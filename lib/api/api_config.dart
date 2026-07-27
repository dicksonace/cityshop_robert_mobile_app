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

  /// Turn relative storage paths into absolute URLs for images/videos.
  static String resolveMediaUrl(String? pathOrUrl) {
    if (pathOrUrl == null) return '';
    final value = pathOrUrl.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    final base = mediaBaseUrl.endsWith('/') ? mediaBaseUrl.substring(0, mediaBaseUrl.length - 1) : mediaBaseUrl;
    if (value.startsWith('/')) return '$base$value';
    return '$base/$value';
  }

  static const tokenKey = 'cityshop_auth_token';
  static const deviceName = 'cityshop_mobile';
}
