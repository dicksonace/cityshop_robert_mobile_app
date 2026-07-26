/// Production API for CityShop mobile.
/// Live site: https://cityunlock.net
class ApiConfig {
  static const productionBaseUrl = 'https://cityunlock.net/api/v1';
  static const mediaBaseUrl = 'https://cityunlock.net';

  /// Always use production while building against the live marketplace.
  static const baseUrl = productionBaseUrl;

  static const tokenKey = 'cityshop_auth_token';
  static const deviceName = 'cityshop_android';
}
