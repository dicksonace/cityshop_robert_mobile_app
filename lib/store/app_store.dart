import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../models/models.dart';

class AppStore extends ChangeNotifier {
  AppStore(this._api);

  final ApiClient _api;

  AppUser? user;
  bool booting = true;
  bool loadingShop = false;
  String? shopError;

  List<ShopCategory> categories = [];
  List<Product> products = [];
  String searchQuery = '';
  int? selectedCategoryId;
  bool filterInGhana = false;
  bool filterFreeShip = false;
  String sort = 'recommended';
  int totalProducts = 0;

  bool get isLoggedIn => user != null;

  Future<void> init() async {
    booting = true;
    notifyListeners();
    try {
      final token = await _api.getToken();
      if (token != null && token.isNotEmpty) {
        await refreshMe();
      }
      await loadShop();
    } catch (_) {
      await _api.clearToken();
      user = null;
      await loadShop();
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> refreshMe() async {
    final res = await _api.get('/auth/me');
    final data = res.data;
    final userJson = data is Map ? (data['user'] ?? data['data'] ?? data) : null;
    if (userJson is Map) {
      user = AppUser.fromJson(Map<String, dynamic>.from(userJson));
    }
    notifyListeners();
  }

  Future<void> loadShop({
    String? search,
    int? categoryId,
    bool clearCategory = false,
    bool? inGhana,
    bool? freeShip,
    String? sortBy,
  }) async {
    loadingShop = true;
    shopError = null;
    if (search != null) searchQuery = search;
    if (clearCategory) {
      selectedCategoryId = null;
    } else if (categoryId != null) {
      selectedCategoryId = categoryId;
    }
    if (inGhana != null) filterInGhana = inGhana;
    if (freeShip != null) filterFreeShip = freeShip;
    if (sortBy != null) sort = sortBy;
    notifyListeners();

    try {
      final catsFuture = categories.isEmpty ? _api.get('/categories') : null;
      final query = <String, dynamic>{
        'per_page': 40,
        'sort': sort,
        if (searchQuery.trim().isNotEmpty) 'search': searchQuery.trim(),
        if (selectedCategoryId != null) 'category': selectedCategoryId,
        if (filterInGhana) 'in_ghana': 1,
        if (filterFreeShip) 'free_ship': 1,
      };
      final productsRes = await _api.get('/products', query: query);

      if (catsFuture != null) {
        final catsRes = await catsFuture;
        final list = catsRes.data is Map ? catsRes.data['data'] : catsRes.data;
        if (list is List) {
          categories = list
              .whereType<Map>()
              .map((e) => ShopCategory.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      final body = productsRes.data;
      if (body is Map) {
        final meta = body['meta'];
        totalProducts = (meta is Map ? meta['total'] as num? : null)?.toInt() ??
            (body['total'] as num?)?.toInt() ??
            0;
        final pdata = body['data'];
        if (pdata is List) {
          products = pdata
              .whereType<Map>()
              .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (totalProducts == 0) totalProducts = products.length;
        }
      }
    } on ApiException catch (e) {
      shopError = e.message;
    } catch (e) {
      shopError = e.toString();
    } finally {
      loadingShop = false;
      notifyListeners();
    }
  }

  Future<Product> fetchProduct(String slug) async {
    final res = await _api.get('/products/$slug');
    final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    return Product.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> login({required String login, required String password}) async {
    final res = await _api.post('/auth/login', data: {
      'login': login,
      'password': password,
      'portal': 'buyer',
      'device_name': ApiConfig.deviceName,
    });
    final token = res.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException('Login succeeded but no token returned.');
    }
    await _api.saveToken(token);
    final userJson = res.data['user'];
    if (userJson is Map) {
      user = AppUser.fromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await _api.post('/auth/register', data: {
      'name': name,
      'email': email,
      'mobile': mobile,
      'password': password,
      'password_confirmation': passwordConfirmation,
      'device_name': ApiConfig.deviceName,
    });
    final token = res.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException('Registration succeeded but no token returned.');
    }
    await _api.saveToken(token);
    final userJson = res.data['user'];
    if (userJson is Map) {
      user = AppUser.fromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}
    await _api.clearToken();
    user = null;
    notifyListeners();
  }

  void clearCategoryFilter() => loadShop(clearCategory: true);

  void toggleInGhana() => loadShop(inGhana: !filterInGhana);

  void toggleFreeShip() => loadShop(freeShip: !filterFreeShip);
}
