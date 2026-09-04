import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/chat_realtime.dart';
import '../models/models.dart';
import '../services/chat_thread_cache.dart';
import '../services/recent_views.dart';
import '../widgets/ghana_location_fields.dart';
import '../widgets/product_image_limits.dart';

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
  bool imageSearchActive = false;
  String? imageSearchPreview;
  List<String> imageSearchKeywords = [];
  int? selectedCategoryId;
  bool filterInGhana = false;
  bool filterFreeShip = false;
  String sort = 'recommended';
  int totalProducts = 0;
  int _shopLoadGen = 0;

  List<CartItem> cartItems = [];
  double cartSubtotal = 0;
  int cartCount = 0;
  Set<int> wishlistProductIds = {};
  List<WishlistItem> wishlist = [];
  Set<int> followingSellerIds = {};
  List<FollowedSeller> following = [];
  List<OrderModel> orders = [];
  WalletInfo? wallet;
  List<ConversationModel> conversations = [];
  StatusFeed? statusFeed;
  List<BuyerAddress> addresses = [];
  List<String> regions = [];
  Map<String, List<String>> citiesByRegion = {};
  List<AppNotificationItem> notifications = [];
  int unreadNotifications = 0;
  int unreadMessages = 0;
  int activeOrders = 0;
  int totalOrders = 0;

  bool get isLoggedIn => user != null;

  bool get isSeller => user?.isSeller == true;

  String get homePath => isSeller ? '/seller' : '/shop';

  Future<String?> get apiToken => _api.getToken();

  /// Lets splash / Skip intro enter the app even if network init is still running.
  void finishBoot() {
    if (!booting) return;
    booting = false;
    notifyListeners();
  }

  Future<void> init() async {
    booting = true;
    notifyListeners();
    try {
      final token = await _api.getToken();
      if (token != null && token.isNotEmpty) {
        // Restore cached profile immediately so offline reopen stays logged in
        // (Login button keys off `user`, not the token alone).
        final cached = await _api.getUserCache();
        if (cached != null) {
          try {
            user = AppUser.fromJson(cached);
            notifyListeners();
          } catch (_) {}
        }
        try {
          // Boot must stay snappy — one attempt each, then enter the shop.
          await refreshMe(maxAttempts: 1);
          if (isSeller) {
            await refreshNotificationCounts(maxAttempts: 1)
                .timeout(const Duration(seconds: 8));
          } else {
            await Future.wait([
              loadCart(maxAttempts: 1),
              loadWishlist(maxAttempts: 1),
              loadFollowing(maxAttempts: 1),
              refreshNotificationCounts(maxAttempts: 1),
            ]).timeout(const Duration(seconds: 8));
          }
        } on ApiException catch (e) {
          // Only log out when the server rejects the session — never on
          // network blips / offline (keep token + cached user).
          if (e.statusCode == 401 || e.statusCode == 403) {
            await _api.clearToken();
            user = null;
          }
        } catch (_) {
          // Keep the saved token + cached user for offline use.
        }
      }
      if (!isSeller) {
        try {
          await loadShop(maxAttempts: 1).timeout(const Duration(seconds: 10));
        } catch (_) {
          shopError ??= 'Something went wrong. Please try again.';
        }
      }
    } finally {
      finishBoot();
    }
  }

  Future<void> _setUserFromJson(Map<String, dynamic> userJson) async {
    user = AppUser.fromJson(userJson);
    await _api.saveUserCache(userJson);
  }

  Future<void> refreshMe({int maxAttempts = 2}) async {
    final res = await _api.get('/auth/me', maxAttempts: maxAttempts);
    final data = res.data;
    final userJson = data is Map ? (data['user'] ?? data['data'] ?? data) : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
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
    int maxAttempts = 2,
  }) async {
    loadingShop = true;
    shopError = null;
    if (search != null) {
      searchQuery = search;
      imageSearchActive = false;
      imageSearchPreview = null;
      imageSearchKeywords = [];
    }
    if (clearCategory) {
      selectedCategoryId = null;
    } else if (categoryId != null) {
      selectedCategoryId = categoryId;
    }
    if (inGhana != null) filterInGhana = inGhana;
    if (freeShip != null) filterFreeShip = freeShip;
    if (sortBy != null) sort = sortBy;
    final gen = ++_shopLoadGen;
    notifyListeners();

    try {
      final catsFuture = categories.isEmpty
          ? _api.get('/categories', maxAttempts: maxAttempts)
          : null;
      final query = <String, dynamic>{
        'per_page': 40,
        'sort': sort,
        if (searchQuery.trim().isNotEmpty) 'search': searchQuery.trim(),
        if (selectedCategoryId != null) 'category': selectedCategoryId,
        if (filterInGhana) 'in_ghana': 1,
        if (filterFreeShip) 'free_ship': 1,
      };
      final productsRes = await _api.get(
        '/products',
        query: query,
        maxAttempts: maxAttempts,
      );

      if (gen != _shopLoadGen) return;

      if (catsFuture != null) {
        final catsRes = await catsFuture;
        if (gen != _shopLoadGen) return;
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
      if (gen != _shopLoadGen) return;
      shopError = e.message;
    } catch (e) {
      if (gen != _shopLoadGen) return;
      shopError = e.toString();
    } finally {
      if (gen == _shopLoadGen) {
        loadingShop = false;
        notifyListeners();
      }
    }
  }

  Future<void> searchByImage(String filePath) async {
    loadingShop = true;
    shopError = null;
    notifyListeners();

    try {
      final res = await _api.postMultipart(
        '/search/image',
        fields: const {},
        fileField: 'image',
        filePath: filePath,
        filename: 'search.jpg',
      );
      final body = res.data;
      if (body is Map) {
        final meta = body['meta'];
        final pdata = body['data'];
        imageSearchActive = true;
        searchQuery = '';
        selectedCategoryId = null;
        if (meta is Map) {
          imageSearchPreview = meta['preview'] as String?;
          final keywords = meta['keywords'];
          imageSearchKeywords = keywords is List
              ? keywords.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
              : [];
        }
        if (pdata is List) {
          products = pdata
              .whereType<Map>()
              .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          totalProducts = products.length;
        } else {
          products = [];
          totalProducts = 0;
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

  void clearImageSearch() {
    imageSearchActive = false;
    imageSearchPreview = null;
    imageSearchKeywords = [];
    loadShop(search: '');
  }

  Future<Product> fetchProduct(String slug) async {
    final res = await _api.get('/products/$slug');
    final body = res.data;
    final data = body is Map ? (body['data'] ?? body) : body;
    return Product.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Products similar to locally stored recent views (same categories).
  /// Falls back to recommended shop picks when there are no recent views yet.
  Future<List<RecentViewMatch>> fetchMatchesForRecentViews() async {
    final ids = await RecentViews.getIds();
    final res = await _api.get(
      '/products/matches-for-recent-views',
      query: {
        if (ids.isNotEmpty) 'ids': ids.join(','),
      },
    );
    final body = res.data;
    final list = body is Map ? body['products'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => RecentViewMatch.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0 && e.slug.isNotEmpty)
        .toList();
  }

  Future<void> recordProductView(Product product) async {
    await RecentViews.record(id: product.id, categoryId: product.categoryId);
  }

  Future<int?> recordProductVideoPlay(String slug) async {
    try {
      final res = await _api.post('/products/$slug/video-play');
      final body = res.data;
      if (body is Map && body['video_plays'] != null) {
        return (body['video_plays'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  Future<List<LivestreamCard>> fetchLiveNow() async {
    final res = await _api.get('/livestreams');
    final body = res.data;
    final list = body is Map ? body['data'] : body;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => LivestreamCard.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.storeSlug.isNotEmpty)
        .toList();
  }

  Future<LivestreamCard?> fetchLivestream(String slug) async {
    final res = await _api.get('/livestreams/$slug');
    final body = res.data;
    final data = body is Map ? body['data'] : body;
    if (data is! Map) return null;
    final card = LivestreamCard.fromJson(Map<String, dynamic>.from(data));
    if (card.storeSlug.isEmpty && card.room == null) return null;
    return card;
  }

  Future<({SellerStore store, List<Product> products})> fetchSellerStore(
    String slug, {
    String? search,
  }) async {
    final query = <String, dynamic>{
      'per_page': 40,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final res = await _api.get('/stores/$slug', query: query);
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final data = body['data'];
    final productsBody = body['products'];
    final list = productsBody is Map ? productsBody['data'] : productsBody;
    final store = SellerStore.fromJson(Map<String, dynamic>.from(data as Map));
    final products = list is List
        ? list
            .whereType<Map>()
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Product>[];
    return (store: store, products: products);
  }

  Future<({
    Product product,
    List<Product> related,
    List<Map<String, dynamic>> reviews,
    Map<String, dynamic>? reviewable,
    bool isFollowingSeller,
  })> fetchProductDetail(String slug) async {
    final res = await _api.get('/products/$slug');
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final data = body['data'] ?? body;
    final relatedJson = body['related'];
    final reviewsJson = body['reviews'] is Map ? body['reviews']['data'] : body['reviews'];

    final related = relatedJson is List
        ? relatedJson
            .whereType<Map>()
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Product>[];

    final reviews = reviewsJson is List
        ? reviewsJson.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    final reviewableRaw = body['reviewable'];
    Map<String, dynamic>? reviewable;
    if (reviewableRaw is Map) {
      final map = Map<String, dynamic>.from(reviewableRaw);
      final orderId = (map['order_id'] as num?)?.toInt() ?? 0;
      final itemId = (map['order_item_id'] as num?)?.toInt() ?? 0;
      if (orderId > 0 && itemId > 0) {
        reviewable = {'order_id': orderId, 'order_item_id': itemId};
      }
    }

    final product = Product.fromJson(Map<String, dynamic>.from(data as Map));
    final isFollowingSeller = body['is_following_seller'] == true;
    if (isFollowingSeller && product.sellerId != null) {
      followingSellerIds = {...followingSellerIds, product.sellerId!};
    }

    return (
      product: product,
      related: related,
      reviews: reviews,
      reviewable: reviewable,
      isFollowingSeller: isFollowingSeller,
    );
  }

  Future<void> login({
    required String login,
    required String password,
    String portal = 'buyer',
  }) async {
    final res = await _api.post('/auth/login', data: {
      'login': login,
      'password': password,
      'portal': portal,
      'device_name': ApiConfig.deviceName,
    });
    final token = res.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException('Login succeeded but no token returned.');
    }
    await _api.saveToken(token);
    final userJson = res.data['user'];
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    if (isSeller) {
      await refreshNotificationCounts();
    } else {
      await Future.wait([loadCart(), loadWishlist(), loadFollowing(), refreshNotificationCounts()]);
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> loadSellerDashboard() async {
    final res = await _api.get('/seller/dashboard');
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  Future<Map<String, dynamic>> loadSellerOrders({
    String stage = 'all',
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get('/seller/orders', query: {
      'stage': stage,
      'page': page,
      'per_page': perPage,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerOrder(int id) async {
    final res = await _api.get('/seller/orders/$id');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return body;
  }

  Future<Map<String, dynamic>> updateSellerOrder(
    int id, {
    String? status,
    String? vehicleNumber,
    String? driverPhone,
    String? packageImagePath,
    bool saveDeliveryDetails = false,
  }) async {
    final fields = <String, dynamic>{
      if (status != null) 'status': status,
      if (saveDeliveryDetails || vehicleNumber != null) 'vehicle_number': vehicleNumber ?? '',
      if (saveDeliveryDetails || driverPhone != null) 'driver_phone': driverPhone ?? '',
    };
    if (packageImagePath != null && packageImagePath.isNotEmpty) {
      final res = await _api.postForm(
        '/seller/orders/$id',
        {...fields, 'package_image': packageImagePath},
        fileFields: const ['package_image'],
      );
      return Map<String, dynamic>.from(res.data as Map);
    }
    final res = await _api.post('/seller/orders/$id', data: fields);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> rejectSellerOrder(
    int id, {
    required String cancellationCode,
    String? reason,
  }) async {
    final res = await _api.post('/seller/orders/$id/reject', data: {
      'cancellation_code': cancellationCode,
      if (reason != null && reason.trim().isNotEmpty) 'rejection_reason': reason.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> confirmSellerDirectPayment(int orderItemId) async {
    final res = await _api.post('/seller/orders/$orderItemId/confirm-direct-payment');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> rejectSellerDirectPayment(int orderItemId, String reason) async {
    final res = await _api.post('/seller/orders/$orderItemId/reject-direct-payment', data: {
      'reason': reason,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerProducts({
    String? status,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get('/seller/products', query: {
      if (status != null && status.isNotEmpty) 'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'per_page': perPage,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerProduct(int id) async {
    final res = await _api.get('/seller/products/$id');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return body;
  }

  Future<Map<String, dynamic>> createSellerProduct({
    required String name,
    required double price,
    required int quantity,
    String? description,
    int? categoryId,
    double? discountPrice,
    required List<String> imagePaths,
    String? videoPath,
    int? videoDuration,
    Map<String, dynamic> listing = const {},
  }) async {
    if (imagePaths.isEmpty) {
      throw ApiException('Add at least one product photo.');
    }
    if (imagePaths.length > ProductImageLimits.maxImages) {
      throw ApiException('Maximum ${ProductImageLimits.maxImages} photos per product.');
    }

    // First request: enough photos to create + optional video. Rest uploaded in batches
    // so hosts with low max_file_uploads still accept 50+ galleries.
    final initialCount = videoPath != null
        ? (ProductImageLimits.uploadBatchSize - 1).clamp(1, imagePaths.length)
        : ProductImageLimits.uploadBatchSize.clamp(1, imagePaths.length);
    final initial = imagePaths.take(initialCount).toList();
    final remaining = imagePaths.skip(initialCount).toList();

    final data = <String, dynamic>{
      'name': name,
      'price': price,
      'quantity': quantity,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (categoryId != null) 'category_id': categoryId,
      if (discountPrice != null) 'discount_price': discountPrice,
      'image_count': initial.length,
      if (videoDuration != null) 'video_duration': videoDuration,
      ..._flattenSellerListing(listing, form: true),
    };
    final fileFields = <String>[];
    for (var i = 0; i < initial.length; i++) {
      data['images[$i]'] = initial[i];
      fileFields.add('images[$i]');
    }
    if (videoPath != null) {
      data['video'] = videoPath;
      fileFields.add('video');
    }
    final res = await _api.postForm('/seller/products', data, fileFields: fileFields);
    final body = Map<String, dynamic>.from(res.data as Map);
    final productData = body['data'];
    final productId = productData is Map ? (productData['id'] as num?)?.toInt() : null;

    if (remaining.isNotEmpty && productId != null) {
      await uploadSellerProductImages(productId, remaining);
    }

    return body;
  }

  Future<Map<String, dynamic>> updateSellerProduct(
    int id, {
    String? name,
    String? description,
    double? price,
    double? discountPrice,
    int? quantity,
    int? categoryId,
    Map<String, dynamic> listing = const {},
    List<int> removeImageIds = const [],
  }) async {
    final res = await _api.patch('/seller/products/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (price != null) 'price': price,
      if (discountPrice != null) 'discount_price': discountPrice,
      if (quantity != null) 'quantity': quantity,
      if (categoryId != null) 'category_id': categoryId,
      ..._flattenSellerListing(listing, form: false),
      if (removeImageIds.isNotEmpty) 'remove_image_ids': removeImageIds,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadSellerProductImages(int id, List<String> imagePaths) async {
    if (imagePaths.isEmpty) {
      return {};
    }
    Map<String, dynamic> last = {};
    for (var start = 0; start < imagePaths.length; start += ProductImageLimits.uploadBatchSize) {
      final end = (start + ProductImageLimits.uploadBatchSize).clamp(0, imagePaths.length);
      final chunk = imagePaths.sublist(start, end);
      final data = <String, dynamic>{};
      final fileFields = <String>[];
      for (var i = 0; i < chunk.length; i++) {
        data['images[$i]'] = chunk[i];
        fileFields.add('images[$i]');
      }
      final res = await _api.postForm('/seller/products/$id/images', data, fileFields: fileFields);
      last = Map<String, dynamic>.from(res.data as Map);
    }
    return last;
  }

  Future<Map<String, dynamic>> bulkSellerProducts({
    required String action,
    required List<int> productIds,
    int? categoryId,
  }) async {
    final res = await _api.post('/seller/products/bulk', data: {
      'action': action,
      'product_ids': productIds,
      if (categoryId != null) 'category_id': categoryId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Map<String, dynamic> _flattenSellerListing(Map<String, dynamic> listing, {required bool form}) {
    final out = <String, dynamic>{};
    listing.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (key == 'specifications' && value is Map) {
        if (form) {
          value.forEach((specKey, specValue) {
            if (specValue != null && specValue.toString().trim().isNotEmpty) {
              out['specifications[$specKey]'] = specValue.toString();
            }
          });
        } else {
          out['specifications'] = value;
        }
        return;
      }
      if (value is bool && form) {
        out[key] = value ? 1 : 0;
        return;
      }
      out[key] = value;
    });
    return out;
  }

  Future<Map<String, dynamic>> toggleSellerProductVisibility(int id) async {
    final res = await _api.post('/seller/products/$id/visibility');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deleteSellerProduct(int id) async {
    await _api.delete('/seller/products/$id');
  }

  Future<Map<String, dynamic>> loadSellerPaymentMethods() async {
    final res = await _api.get('/seller/payment-methods');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateSellerPaymentSettings({
    required bool acceptMarketplace,
    required bool acceptDirect,
    required bool cashOnDelivery,
  }) async {
    final res = await _api.patch('/seller/payment-methods/settings', data: {
      'accept_marketplace_payments': acceptMarketplace,
      'accept_direct_payments': acceptDirect,
      'cash_on_delivery_enabled': cashOnDelivery,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> addSellerPaymentMethod({
    required String type,
    required String accountName,
    required String accountNumber,
    String? network,
    String? bankName,
    String? label,
    bool isDefault = false,
  }) async {
    final res = await _api.post('/seller/payment-methods', data: {
      'type': type,
      'account_name': accountName,
      'account_number': accountNumber,
      if (network != null) 'network': network,
      if (bankName != null) 'bank_name': bankName,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      'is_default': isDefault,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> deleteSellerPaymentMethod(int id) async {
    final res = await _api.delete('/seller/payment-methods/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> duplicateSellerProduct(int id) async {
    final res = await _api.post('/seller/products/$id/duplicate');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerProductAnalytics(int id) async {
    final res = await _api.get('/seller/products/$id/analytics');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadSellerProductVideo(
    int id, {
    required String filePath,
    int? duration,
    String filename = 'product.mp4',
  }) async {
    var name = filename.trim();
    if (name.isEmpty) name = 'product.mp4';
    final lower = name.toLowerCase();
    if (!lower.endsWith('.mp4') &&
        !lower.endsWith('.mov') &&
        !lower.endsWith('.webm') &&
        !lower.endsWith('.m4v') &&
        !lower.endsWith('.3gp') &&
        !lower.endsWith('.3gpp')) {
      name = '$name.mp4';
    }
    final res = await _api.postForm(
      '/seller/products/$id/video',
      {
        'video': filePath,
        if (duration != null) 'video_duration': duration,
      },
      fileFields: const ['video'],
      filenames: {'video': name},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> removeSellerProductVideo(int id) async {
    final res = await _api.post('/seller/products/$id/video', data: {
      'remove_video': true,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerReviews({String filter = 'all', int page = 1}) async {
    final res = await _api.get('/seller/reviews', query: {
      'filter': filter,
      'page': page,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> replySellerReview(int id, String reply) async {
    final res = await _api.post('/seller/reviews/$id/reply', data: {
      'seller_reply': reply,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerPromotions({int page = 1}) async {
    final res = await _api.get('/seller/promotions', query: {'page': page});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createSellerPromotion(Map<String, dynamic> payload) async {
    final res = await _api.post('/seller/promotions', data: payload);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateSellerPromotion(int id, {required bool isActive}) async {
    final res = await _api.patch('/seller/promotions/$id', data: {'is_active': isActive});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deleteSellerPromotion(int id) async {
    await _api.delete('/seller/promotions/$id');
  }

  Future<Map<String, dynamic>> loadSellerFollowers({int page = 1}) async {
    final res = await _api.get('/seller/followers', query: {'page': page});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerRefunds({String status = 'open', int page = 1}) async {
    final res = await _api.get('/seller/refunds', query: {
      'status': status,
      'page': page,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerStore() async {
    final res = await _api.get('/seller/store');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateSellerStore({
    String? storeName,
    String? description,
    String? slogan,
    String? preset,
    bool? announcementEnabled,
    String? announcementText,
    bool? promoEnabled,
    String? promoText,
    String? socialFacebook,
    String? socialInstagram,
    String? website,
    Map<String, bool>? sectionsEnabled,
    List<String>? removeHeroPaths,
    bool removePromoImage = false,
  }) async {
    final res = await _api.patch('/seller/store', data: {
      if (storeName != null) 'store_name': storeName,
      if (description != null) 'description': description,
      if (slogan != null) 'slogan': slogan,
      if (preset != null) 'preset': preset,
      if (announcementEnabled != null) 'announcement_enabled': announcementEnabled,
      if (announcementText != null) 'announcement_text': announcementText,
      if (promoEnabled != null) 'promo_enabled': promoEnabled,
      if (promoText != null) 'promo_text': promoText,
      if (socialFacebook != null) 'social_facebook': socialFacebook,
      if (socialInstagram != null) 'social_instagram': socialInstagram,
      if (website != null) 'website': website,
      if (sectionsEnabled != null) 'sections_enabled': sectionsEnabled,
      if (removeHeroPaths != null && removeHeroPaths.isNotEmpty) 'remove_hero_paths': removeHeroPaths,
      if (removePromoImage) 'remove_promo_image': true,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadSellerStoreHero(List<String> paths) async {
    final data = <String, dynamic>{};
    final fileFields = <String>[];
    for (var i = 0; i < paths.length; i++) {
      data['hero_images[$i]'] = paths[i];
      fileFields.add('hero_images[$i]');
    }
    final res = await _api.postForm('/seller/store/hero', data, fileFields: fileFields);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadSellerStorePromo(String path) async {
    final res = await _api.postMultipart(
      '/seller/store/promo',
      fields: const {},
      fileField: 'promo_image',
      filePath: path,
      filename: 'promo.jpg',
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> loadSellerAccount() async {
    final res = await _api.get('/seller/account');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateSellerOrderSms({
    String? mobile1,
    String? mobile2,
  }) async {
    final res = await _api.patch('/seller/account/order-sms', data: {
      'order_sms_mobile_1': mobile1 ?? '',
      'order_sms_mobile_2': mobile2 ?? '',
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> paySellerActivation(String paymentPin) async {
    final res = await _api.post('/seller/activation/pay', data: {
      'payment_pin': paymentPin,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadSellerStoreLogo(String path) async {
    final res = await _api.postMultipart(
      '/seller/store/logo',
      fields: const {},
      fileField: 'logo',
      filePath: path,
      filename: 'logo.jpg',
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadSellerStoreCover(String path) async {
    final res = await _api.postMultipart(
      '/seller/store/cover',
      fields: const {},
      fileField: 'cover',
      filePath: path,
      filename: 'cover.jpg',
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> publishSellerStore() async {
    final res = await _api.post('/seller/store/publish');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> completeSellerStoreSetup() async {
    final res = await _api.post('/seller/store/complete-setup');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<int>> downloadSellerOrderPdf(int id) {
    return _api.getBytes('/seller/orders/$id/pdf');
  }

  Future<Map<String, dynamic>> forgotPassword({
    required String login,
    String via = 'email',
  }) async {
    final res = await _api.post('/auth/forgot-password', data: {
      'login': login,
      'via': via,
    });
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'message': 'If that account exists, a reset code was sent.'};
  }

  Future<String> resetPassword({
    required String login,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await _api.post('/auth/reset-password', data: {
      'login': login,
      'code': code,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });
    final data = res.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return 'Password updated. You can log in with your new password.';
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceName,
  }) async {
    await _api.post('/device-tokens', data: {
      'token': token,
      'platform': platform,
      'device_name': (deviceName != null && deviceName.isNotEmpty)
          ? deviceName
          : ApiConfig.deviceName,
    });
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _api.delete('/device-tokens', data: {
      'token': token,
    });
  }

  Future<void> register({
    required String name,
    String? email,
    required String mobile,
    required String country,
    required String region,
    required String city,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await _api.post('/auth/register', data: {
      'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      'mobile': mobile,
      'country': country,
      'region': region,
      'city': city,
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
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    await refreshNotificationCounts();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}
    await _api.clearToken();
    user = null;
    cartItems = [];
    cartSubtotal = 0;
    cartCount = 0;
    wishlist = [];
    wishlistProductIds = {};
    following = [];
    followingSellerIds = {};
    orders = [];
    wallet = null;
    conversations = [];
    addresses = [];
    notifications = [];
    unreadNotifications = 0;
    unreadMessages = 0;
    activeOrders = 0;
    totalOrders = 0;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String email,
    String? mobile,
    String? region,
    String? city,
  }) async {
    final res = await _api.patch('/profile', data: {
      'name': name,
      'email': email,
      if (mobile != null) 'mobile': mobile,
      if (region != null) 'region': region,
      if (city != null) 'city': city,
    });
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    notifyListeners();
  }

  Future<void> uploadAvatar(String filePath, {String? filename, String? contentType}) async {
    final name = (filename != null && filename.trim().isNotEmpty)
        ? filename.trim()
        : filePath.split(RegExp(r'[\\/]')).last;
    final res = await _api.postMultipart(
      '/profile/avatar',
      fields: const {},
      fileField: 'avatar',
      filePath: filePath,
      filename: name.isEmpty ? 'avatar.jpg' : name,
      contentType: contentType,
    );
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    notifyListeners();
  }

  Future<void> removeAvatar() async {
    final res = await _api.delete('/profile/avatar');
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
    } else {
      await refreshMe();
    }
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    await _api.put('/profile/password', data: {
      'current_password': currentPassword,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });
  }

  Future<KycInfo> loadKyc() async {
    final res = await _api.get('/kyc');
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : body;
    final info = KycInfo.fromJson(data);
    if (user != null) {
      user = AppUser(
        id: user!.id,
        name: user!.name,
        email: user!.email,
        mobile: user!.mobile,
        country: user!.country,
        role: user!.role,
        region: user!.region,
        city: user!.city,
        avatar: user!.avatar,
        hasPaymentPin: user!.hasPaymentPin,
        kyc: info,
        sellerStoreName: user!.sellerStoreName,
        sellerSlug: user!.sellerSlug,
        sellerStatus: user!.sellerStatus,
        sellerStoreSetupComplete: user!.sellerStoreSetupComplete,
      );
      notifyListeners();
    }
    return info;
  }

  Future<KycInfo> submitKyc({
    required String ghanaCardNumber,
    String? fullName,
    required String frontPath,
    required String backPath,
    String? selfiePath,
  }) async {
    final res = await _api.postForm(
      '/kyc',
      {
        'ghana_card_number': ghanaCardNumber,
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
        'front': frontPath,
        'back': backPath,
        if (selfiePath != null) 'selfie': selfiePath,
      },
      fileFields: [
        'front',
        'back',
        if (selfiePath != null) 'selfie',
      ],
    );
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : body;
    final info = KycInfo.fromJson(data);
    await refreshMe();
    return info;
  }

  Future<void> setPaymentPin({
    required String pin,
    required String pinConfirmation,
  }) async {
    final res = await _api.post('/profile/payment-pin', data: {
      'pin': pin,
      'pin_confirmation': pinConfirmation,
    });
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
      notifyListeners();
    } else {
      await refreshMe();
    }
  }

  Future<void> changePaymentPin({
    required String currentPin,
    required String pin,
    required String pinConfirmation,
  }) async {
    final res = await _api.put('/profile/payment-pin', data: {
      'current_pin': currentPin,
      'pin': pin,
      'pin_confirmation': pinConfirmation,
    });
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
      notifyListeners();
    } else {
      await refreshMe();
    }
  }

  /// Returns via + masked hint when a PIN reset code is sent.
  Future<Map<String, dynamic>> forgotPaymentPin({String via = 'email'}) async {
    final res = await _api.post('/profile/payment-pin/forgot', data: {'via': via});
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    return {'via': via};
  }

  Future<void> resetPaymentPin({
    required String code,
    required String pin,
    required String pinConfirmation,
  }) async {
    final res = await _api.post('/profile/payment-pin/reset', data: {
      'code': code,
      'pin': pin,
      'pin_confirmation': pinConfirmation,
    });
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      await _setUserFromJson(Map<String, dynamic>.from(userJson));
      notifyListeners();
    } else {
      await refreshMe();
    }
  }

  void _applyCart(dynamic body) {
    if (body is! Map) return;
    final data = body['data'];
    if (data is List) {
      cartItems = data
          .whereType<Map>()
          .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    cartSubtotal = (body['subtotal'] as num?)?.toDouble() ?? 0;
    cartCount = cartItems.fold(0, (sum, i) => sum + i.quantity);
  }

  Future<void> loadCart({int maxAttempts = 2}) async {
    if (!isLoggedIn) return;
    try {
      final res = await _api.get('/cart', maxAttempts: maxAttempts);
      _applyCart(res.data);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> addToCart(int productId, {int quantity = 1}) async {
    final res = await _api.post('/cart', data: {
      'product_id': productId,
      'quantity': quantity,
    });
    _applyCart(res.data);
    notifyListeners();
  }

  Future<void> updateCartItem(int cartItemId, int quantity) async {
    final res = await _api.patch('/cart/$cartItemId', data: {'quantity': quantity});
    _applyCart(res.data);
    notifyListeners();
  }

  Future<void> removeCartItem(int cartItemId) async {
    final res = await _api.delete('/cart/$cartItemId');
    _applyCart(res.data);
    notifyListeners();
  }

  Future<void> loadWishlist({int maxAttempts = 2}) async {
    if (!isLoggedIn) return;
    try {
      final res = await _api.get('/wishlist', maxAttempts: maxAttempts);
      final data = res.data is Map ? res.data['data'] : null;
      if (data is List) {
        wishlist = data
            .whereType<Map>()
            .map((e) => WishlistItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        wishlistProductIds = wishlist.map((e) => e.productId).toSet();
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Flips the heart before the request goes out so the tap feels instant, then
  /// settles on whatever the server says (or rolls back if it never answers).
  Future<bool> toggleWishlist(int productId) async {
    final was = wishlistProductIds.contains(productId);
    _setWishlisted(productId, !was);

    try {
      final res = await _api.post('/wishlist/toggle', data: {'product_id': productId});
      final wishlisted = res.data is Map ? res.data['wishlisted'] as bool? ?? !was : !was;
      if (wishlisted == was) _setWishlisted(productId, wishlisted);
      if (wishlisted || wishlist.isEmpty) {
        unawaited(loadWishlist());
      }
      return wishlisted;
    } catch (_) {
      _setWishlisted(productId, was);
      rethrow;
    }
  }

  void _setWishlisted(int productId, bool on) {
    if (on) {
      wishlistProductIds = {...wishlistProductIds, productId};
    } else {
      wishlistProductIds = {...wishlistProductIds}..remove(productId);
      wishlist = wishlist.where((w) => w.productId != productId).toList();
    }
    notifyListeners();
  }

  Future<void> loadFollowing({int maxAttempts = 2}) async {
    try {
      final res = await _api.get('/following', maxAttempts: maxAttempts);
      final data = res.data is Map ? res.data['data'] : null;
      if (data is List) {
        following = data
            .whereType<Map>()
            .map((e) => FollowedSeller.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        followingSellerIds = following.map((e) => e.sellerId).toSet();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> toggleFollowSeller(int sellerId) async {
    final was = followingSellerIds.contains(sellerId);
    _setFollowing(sellerId, !was);

    try {
      final res = await _api.post('/following/toggle', data: {'seller_id': sellerId});
      final followingNow = res.data is Map ? res.data['following'] as bool? ?? !was : !was;
      if (followingNow == was) _setFollowing(sellerId, followingNow);
      if (followingNow || following.isEmpty) {
        await loadFollowing();
      } else if (!followingNow) {
        following = following.where((f) => f.sellerId != sellerId).toList();
        notifyListeners();
      }
      return followingNow;
    } catch (_) {
      _setFollowing(sellerId, was);
      rethrow;
    }
  }

  void _setFollowing(int sellerId, bool on) {
    if (on) {
      followingSellerIds = {...followingSellerIds, sellerId};
    } else {
      followingSellerIds = {...followingSellerIds}..remove(sellerId);
    }
    notifyListeners();
  }

  Future<void> loadOrders() async {
    final res = await _api.get('/orders', query: {'per_page': 50});
    final data = res.data is Map ? res.data['data'] : null;
    if (data is List) {
      orders = data
          .whereType<Map>()
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final meta = res.data is Map ? res.data['meta'] : null;
      final total = meta is Map ? (meta['total'] as num?)?.toInt() : null;
      totalOrders = total ?? orders.length;
      // Only retally locally when this page holds every order; otherwise the
      // count from /notifications/counts stays authoritative.
      if (total == null || total <= orders.length) {
        activeOrders = orders.where((o) {
          final status = (o.status ?? '').toLowerCase();
          return !const {'delivered', 'cancelled', 'refunded'}.contains(status);
        }).length;
      }
    }
    notifyListeners();
  }

  Future<OrderModel> fetchOrder(int id) async {
    final res = await _api.get('/orders/$id');
    final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    return OrderModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> confirmDelivery(int orderId, int itemId) async {
    await _api.post('/orders/$orderId/items/$itemId/confirm-delivery');
    await loadOrders();
  }

  Future<void> requestRefund({
    required int orderId,
    required int orderItemId,
    required String reason,
    required String description,
  }) async {
    await _api.post('/orders/$orderId/disputes', data: {
      'order_item_id': orderItemId,
      'reason': reason,
      'description': description,
    });
    await loadOrders();
  }

  Future<void> cancelRefund(int disputeId) async {
    await _api.post('/disputes/$disputeId/cancel');
    await loadOrders();
  }

  Future<void> submitReview({
    required int orderId,
    required int orderItemId,
    required int rating,
    String? comment,
  }) async {
    await _api.post('/orders/$orderId/reviews', data: {
      'order_item_id': orderItemId,
      'rating': rating,
      'comment': comment,
    });
    await loadOrders();
  }

  Future<void> loadWallet() async {
    final res = await _api.get('/wallet');
    final data = res.data is Map ? res.data['data'] : null;
    if (data is Map) {
      wallet = WalletInfo.fromJson(Map<String, dynamic>.from(data));
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> loadQrReceiveCode({double? amount, String? reason}) async {
    final cleanedReason = reason?.trim();
    final res = await _api.get('/wallet/qr/receive', query: {
      if (amount != null) 'amount': amount,
      if (cleanedReason != null && cleanedReason.isNotEmpty) 'reason': cleanedReason,
    });
    final data = res.data is Map ? res.data['data'] : null;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw ApiException('Could not load your receive QR.');
  }

  Future<Map<String, dynamic>> resolveQrPayment(String payload) async {
    final res = await _api.post('/wallet/qr/resolve', data: {'payload': payload});
    final data = res.data is Map ? res.data['data'] : null;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw ApiException('Could not read that QR code.');
  }

  Future<Map<String, dynamic>> payWithQr({
    required String payload,
    required double amount,
    required String paymentPin,
    String? note,
  }) async {
    final res = await _api.post('/wallet/qr/pay', data: {
      'payload': payload,
      'amount': amount,
      'payment_pin': paymentPin,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final walletJson = body['wallet'];
    if (walletJson is Map && wallet != null) {
      wallet = wallet!.copyWith(
        availableBalance: (walletJson['available_balance'] as num?)?.toDouble(),
        pendingBalance: (walletJson['pending_balance'] as num?)?.toDouble(),
      );
    } else {
      await loadWallet();
    }
    notifyListeners();
    final data = body['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return body;
  }

  /// One page of the wallet ledger. Paging stays with the screen so the list
  /// can grow without holding every page in the store.
  Future<WalletTransactionPage> fetchWalletTransactions({
    int page = 1,
    int perPage = 20,
    String currency = 'all',
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (currency == 'GHS' || currency == 'RMB') {
      query['currency'] = currency;
    }
    final res = await _api.get('/wallet/transactions', query: query);
    return WalletTransactionPage.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<WalletTransactionItem?> fetchWalletTransactionByReference(String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return null;
    try {
      final res = await _api.get('/wallet/transactions/by-reference/${Uri.encodeComponent(ref)}');
      final data = res.data is Map ? res.data['transaction'] : null;
      if (data is Map) {
        return WalletTransactionItem.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<WithdrawalOverview> loadWithdrawals() async {
    final res = await _api.get('/wallet/withdrawals');
    return WithdrawalOverview.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// Requests a MoMo or bank payout. The balance drops straight away, so refresh the
  /// wallet the screens read from.
  Future<WithdrawalItem> requestWithdrawal({
    required double amount,
    required String momoNumber,
    required String accountName,
    required String network,
    required String paymentPin,
    String payoutType = 'momo',
  }) async {
    final res = await _api.post('/wallet/withdraw', data: {
      'amount': amount,
      'payout_type': payoutType,
      'momo_number': momoNumber,
      'account_name': accountName,
      'network': network,
      'payment_pin': paymentPin,
    });
    final body = Map<String, dynamic>.from(res.data as Map);
    final walletJson = body['wallet'];
    if (walletJson is Map && wallet != null) {
      wallet = wallet!.copyWith(
        availableBalance: (walletJson['available_balance'] as num?)?.toDouble(),
        pendingBalance: (walletJson['pending_balance'] as num?)?.toDouble(),
      );
      notifyListeners();
    } else {
      await loadWallet();
    }
    return WithdrawalItem.fromJson(Map<String, dynamic>.from(body['data'] as Map));
  }

  Future<Map<String, dynamic>> loadManualFunding() async {
    final res = await _api.get('/wallet/manual-funding');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> submitWalletTopUp({
    required double amount,
    required String network,
    required String proofPath,
    String? paymentReference,
    String? userNote,
  }) async {
    final res = await _api.postMultipart(
      '/wallet/manual-top-up',
      fields: {
        'amount': amount,
        'network': network,
        if (paymentReference != null && paymentReference.isNotEmpty)
          'payment_reference': paymentReference,
        if (userNote != null && userNote.isNotEmpty) 'user_note': userNote,
      },
      fileField: 'proof',
      filePath: proofPath,
    );
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> fetchManualTopUp(int id) async {
    final res = await _api.get('/wallet/manual-top-up/$id');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> cancelManualTopUp(int id) async {
    final res = await _api.post('/wallet/manual-top-up/$id/cancel');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> loadChinaTransfers() async {
    final res = await _api.get('/wallet/china-transfer');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> convertQuote({
    required String direction,
    required double amount,
  }) async {
    final res = await _api.post('/wallet/convert/quote', data: {
      'direction': direction,
      'amount': amount,
    });
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> convertWallet({
    required String direction,
    required double amount,
    required String paymentPin,
  }) async {
    final res = await _api.post('/wallet/convert', data: {
      'direction': direction,
      'amount': amount,
      'payment_pin': paymentPin,
    });
    await loadWallet();
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> fetchChinaTransfer(int id) async {
    final res = await _api.get('/wallet/china-transfer/$id');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> submitChinaTransfer({
    String? ghsAmount,
    String? rmbAmount,
    String fundingSource = 'ghs_wallet',
    int? paymentMethodId,
    required String paymentPin,
    required Map<int, String> fields,
    required Map<int, dynamic> files,
  }) async {
    final payload = <String, dynamic>{
      'funding_source': fundingSource,
      'payment_pin': paymentPin,
    };
    if (fundingSource == 'rmb_wallet') {
      payload['rmb_amount'] = rmbAmount ?? '';
    } else {
      payload['ghs_amount'] = ghsAmount ?? '';
      if (fundingSource == 'external' && paymentMethodId != null) {
        payload['payment_method_id'] = paymentMethodId;
      }
    }
    fields.forEach((id, value) {
      payload['fields[$id]'] = value;
    });
    files.forEach((id, file) {
      payload['files[$id]'] = '${file.path}';
    });
    final res = await _api.postForm('/wallet/china-transfer', payload);
    await loadWallet();
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> cancelChinaTransfer(int id) async {
    final res = await _api.post('/wallet/china-transfer/$id/cancel');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> loadSellRmb() async {
    final res = await _api.get('/wallet/sell-rmb');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> fetchSellRmb(int id) async {
    final res = await _api.get('/wallet/sell-rmb/$id');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> submitSellRmb({
    required String rmbAmount,
    required String payoutCurrency,
    required int receiveMethodId,
    required Map<int, String> fields,
    required Map<int, dynamic> files,
  }) async {
    final payload = <String, dynamic>{
      'rmb_amount': rmbAmount,
      'payout_currency': payoutCurrency,
      'receive_method_id': receiveMethodId,
    };
    fields.forEach((id, value) {
      payload['fields[$id]'] = value;
    });
    files.forEach((id, file) {
      payload['files[$id]'] = '${file.path}';
    });
    final res = await _api.postForm('/wallet/sell-rmb', payload);
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<Map<String, dynamic>> cancelSellRmb(int id) async {
    final res = await _api.post('/wallet/sell-rmb/$id/cancel');
    final body = Map<String, dynamic>.from(res.data as Map);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  Future<void> loadConversations() async {
    final userId = user?.id;
    try {
      final res = await _api.get('/messages');
      final data = res.data is Map ? (res.data['data'] ?? res.data['conversations']) : null;
      if (data is List) {
        final raw = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (userId != null) {
          await ChatThreadCache.saveInbox(userId: userId, conversations: raw);
        }
        conversations = raw
            .map((e) => ConversationModel.fromJson(e))
            .toList();
      }
      notifyListeners();
    } catch (_) {
      if (userId != null) {
        final cached = await ChatThreadCache.loadInbox(userId: userId);
        if (cached != null && cached.isNotEmpty) {
          conversations = cached;
          notifyListeners();
          return;
        }
      }
      rethrow;
    }
  }

  Future<void> refreshNotificationCounts({int maxAttempts = 2}) async {
    if (!isLoggedIn) {
      unreadNotifications = 0;
      unreadMessages = 0;
      activeOrders = 0;
      totalOrders = 0;
      notifyListeners();
      return;
    }
    try {
      final res = await _api.get('/notifications/counts', maxAttempts: maxAttempts);
      final data = res.data is Map ? res.data : null;
      if (data is Map) {
        unreadNotifications = (data['unread_notifications'] as num?)?.toInt() ?? 0;
        unreadMessages = (data['unread_messages'] as num?)?.toInt() ?? 0;
        activeOrders = (data['active_orders'] as num?)?.toInt() ?? activeOrders;
        totalOrders = (data['total_orders'] as num?)?.toInt() ?? totalOrders;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadNotifications() async {
    final res = await _api.get('/notifications');
    final data = res.data is Map ? res.data['notifications'] : null;
    if (data is List) {
      notifications = data
          .whereType<Map>()
          .map((e) => AppNotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (res.data is Map && res.data['unread_count'] != null) {
      unreadNotifications = (res.data['unread_count'] as num?)?.toInt() ?? unreadNotifications;
    } else {
      unreadNotifications = notifications.where((n) => n.isUnread).length;
    }
    notifyListeners();
  }

  Future<void> markNotificationRead(int id) async {
    final res = await _api.post('/notifications/$id/read');
    notifications = notifications
        .map((n) => n.id == id
            ? AppNotificationItem(
                id: n.id,
                type: n.type,
                title: n.title,
                body: n.body,
                data: n.data,
                readAt: n.readAt ?? DateTime.now().toIso8601String(),
                createdAt: n.createdAt,
              )
            : n)
        .toList();
    if (res.data is Map && res.data['unread_count'] != null) {
      unreadNotifications = (res.data['unread_count'] as num?)?.toInt() ?? unreadNotifications;
    } else {
      unreadNotifications = notifications.where((n) => n.isUnread).length;
    }
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await _api.post('/notifications/read-all');
    final now = DateTime.now().toIso8601String();
    notifications = notifications
        .map((n) => AppNotificationItem(
              id: n.id,
              type: n.type,
              title: n.title,
              body: n.body,
              data: n.data,
              readAt: n.readAt ?? now,
              createdAt: n.createdAt,
            ))
        .toList();
    unreadNotifications = 0;
    notifyListeners();
  }

  Future<({ConversationModel conversation, List<ChatMessage> messages, AttachProduct? attachProduct})>
      openConversation({
    required int sellerId,
    int? productId,
    int? userId,
  }) async {
    final peerId = userId ?? sellerId;
    final res = await _api.post('/messages', data: {
      if (userId != null) 'user_id': userId,
      if (userId == null) 'seller_id': peerId,
      if (productId != null) 'product_id': productId,
    });
    final convJson = res.data['conversation'];
    final msgs = res.data['messages'];
    final attachRaw = res.data['attach_product'];
    final conversation = ConversationModel.fromJson(Map<String, dynamic>.from(convJson as Map));
    final messages = msgs is List
        ? msgs
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: user?.id ?? 0,
                ))
            .toList()
        : <ChatMessage>[];
    final attachProduct = attachRaw is Map
        ? AttachProduct.fromJson(Map<String, dynamic>.from(attachRaw))
        : null;
    return (conversation: conversation, messages: messages, attachProduct: attachProduct);
  }

  Future<Map<String, dynamic>?> lookupUserByMobile(String mobile) async {
    final res = await _api.get('/users/lookup', query: {'mobile': mobile.trim()});
    final userJson = res.data is Map ? res.data['user'] : null;
    if (userJson is Map) {
      return Map<String, dynamic>.from(userJson);
    }
    return null;
  }

  Future<({ConversationModel conversation, List<ChatMessage> messages})> createGroupChat({
    required String name,
    required List<int> memberIds,
  }) async {
    final res = await _api.post('/messages/groups', data: {
      'name': name.trim(),
      'member_ids': memberIds,
    });
    final convJson = res.data['conversation'];
    final msgs = res.data['messages'];
    final conversation = ConversationModel.fromJson(Map<String, dynamic>.from(convJson as Map));
    final messages = msgs is List
        ? msgs
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: user?.id ?? 0,
                ))
            .toList()
        : <ChatMessage>[];
    await loadConversations();
    return (conversation: conversation, messages: messages);
  }

  Future<ConversationModel> addGroupMembers(int conversationId, List<int> memberIds) async {
    final res = await _api.post('/messages/$conversationId/members', data: {
      'member_ids': memberIds,
    });
    final convJson = res.data['conversation'];
    final conversation = ConversationModel.fromJson(Map<String, dynamic>.from(convJson as Map));
    _upsertConversation(conversation);
    notifyListeners();
    return conversation;
  }

  Future<void> leaveGroup(int conversationId) async {
    await _api.post('/messages/$conversationId/leave');
    conversations = conversations.where((c) => c.id != conversationId).toList();
    notifyListeners();
  }

  Future<ConversationModel> removeGroupMember(int conversationId, int userId) async {
    final res = await _api.delete('/messages/$conversationId/members/$userId');
    if (res.data is Map && res.data['conversation'] is Map) {
      final conversation = ConversationModel.fromJson(
        Map<String, dynamic>.from(res.data['conversation'] as Map),
      );
      _upsertConversation(conversation);
      notifyListeners();
      return conversation;
    }
    await loadConversations();
    return conversations.firstWhere((c) => c.id == conversationId);
  }

  Future<ConversationModel> blockGroupMember(int conversationId, int userId) async {
    final res = await _api.post('/messages/$conversationId/members/$userId/block');
    if (res.data is Map && res.data['conversation'] is Map) {
      final conversation = ConversationModel.fromJson(
        Map<String, dynamic>.from(res.data['conversation'] as Map),
      );
      _upsertConversation(conversation);
      notifyListeners();
      return conversation;
    }
    await loadConversations();
    return conversations.firstWhere((c) => c.id == conversationId);
  }

  Future<ConversationModel> uploadGroupAvatar(
    int conversationId,
    String filePath, {
    String? filename,
    String? contentType,
  }) async {
    final name = (filename != null && filename.trim().isNotEmpty)
        ? filename.trim()
        : filePath.split(RegExp(r'[\\/]')).last;
    final res = await _api.postMultipart(
      '/messages/$conversationId/avatar',
      fields: const {},
      fileField: 'avatar',
      filePath: filePath,
      filename: name.isEmpty ? 'group.jpg' : name,
      contentType: contentType,
    );
    final convJson = res.data is Map ? res.data['conversation'] : null;
    final conversation = ConversationModel.fromJson(Map<String, dynamic>.from(convJson as Map));
    _upsertConversation(conversation);
    notifyListeners();
    return conversation;
  }

  void _upsertConversation(ConversationModel conversation) {
    final idx = conversations.indexWhere((c) => c.id == conversation.id);
    if (idx >= 0) {
      conversations = [...conversations]..[idx] = conversation;
    } else {
      conversations = [conversation, ...conversations];
    }
  }

  Future<ChatMessage> sendTransferMessage(
    int conversationId, {
    required double amount,
    String? note,
    required String paymentPin,
  }) async {
    final res = await _api.post('/messages/$conversationId/transfer', data: {
      'amount': amount,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'payment_pin': paymentPin,
    });
    final walletJson = res.data is Map ? res.data['wallet'] : null;
    if (walletJson is Map && wallet != null) {
      wallet = wallet!.copyWith(
        availableBalance: (walletJson['available_balance'] as num?)?.toDouble(),
      );
      notifyListeners();
    } else {
      await loadWallet();
    }
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<
      ({
        ConversationModel conversation,
        List<ChatMessage> messages,
        List<ChatMessage> pendingCallSignals,
        Map<String, dynamic>? clearRequest,
      })> loadConversation(
    int id,
  ) async {
    final res = await _api.get('/messages/$id');
    final convJson = res.data['conversation'];
    final msgs = res.data['messages'];
    final signals = res.data['pending_call_signals'];
    final clearReq = res.data['clear_request'];
    final conversation = ConversationModel.fromJson(Map<String, dynamic>.from(convJson as Map));
    final myId = user?.id ?? 0;
    final messages = msgs is List
        ? msgs
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: myId,
                ))
            .toList()
        : <ChatMessage>[];
    final pendingCallSignals = signals is List
        ? signals
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: myId,
                ))
            .toList()
        : <ChatMessage>[];
    if (myId > 0) {
      await ChatThreadCache.saveThread(
        userId: myId,
        conversationId: id,
        conversation: Map<String, dynamic>.from(convJson as Map),
        messages: msgs is List
            ? msgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : const [],
      );
    }
    return (
      conversation: conversation,
      messages: messages,
      pendingCallSignals: pendingCallSignals,
      clearRequest: clearReq is Map ? Map<String, dynamic>.from(clearReq) : null,
    );
  }

  Future<void> blockUser(int userId) async {
    await _api.post('/blocks', data: {'user_id': userId});
  }

  Future<void> unblockUser(int userId) async {
    await _api.delete('/blocks/$userId');
  }

  Future<int> forwardMessageToMembers({
    required int conversationId,
    required int messageId,
    required List<int> memberIds,
  }) async {
    final res = await _api.post(
      '/messages/$conversationId/messages/$messageId/forward',
      data: {'member_ids': memberIds},
    );
    return (res.data['sent'] as num?)?.toInt() ?? memberIds.length;
  }

  Future<List<ChatParticipant>> fetchForwardTargets() async {
    final res = await _api.get('/messages/forward-targets');
    final data = res.data is Map ? res.data['data'] : null;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => ChatParticipant.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id > 0)
        .toList();
  }

  Future<ChatMessage> sendMessage(
    int conversationId,
    String body, {
    int? replyToId,
  }) async {
    final res = await _api.post('/messages/$conversationId/send', data: {
      'body': body,
      if (replyToId != null) 'reply_to_id': replyToId,
    });
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<ChatMessage> sendProductMessage(int conversationId, int productId) async {
    final res = await _api.post('/messages/$conversationId/product', data: {
      'product_id': productId,
    });
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<ChatMessage> sendImageMessage(
    int conversationId,
    String filePath, {
    String? caption,
    String filename = 'chat.jpg',
    bool viewOnce = false,
  }) async {
    final res = await _api.postMultipart(
      '/messages/$conversationId/image',
      fields: {
        if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
        if (viewOnce) 'view_once': '1',
      },
      fileField: 'image',
      filePath: filePath,
      filename: filename,
    );
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<ChatMessage> sendVideoMessage(
    int conversationId,
    String filePath, {
    String? caption,
    String filename = 'chat.mp4',
    int? durationSeconds,
    bool viewOnce = false,
  }) async {
    final res = await _api.postMultipart(
      '/messages/$conversationId/video',
      fields: {
        if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
        if (durationSeconds != null) 'duration_seconds': '$durationSeconds',
        if (viewOnce) 'view_once': '1',
      },
      fileField: 'video',
      filePath: filePath,
      filename: filename,
    );
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<({ChatMessage message, String? imageUrl, String? videoUrl})> openViewOnce(
    int conversationId,
    int messageId,
  ) async {
    final res = await _api.post('/messages/$conversationId/messages/$messageId/view-once');
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final msg = data['message'];
    return (
      message: ChatMessage.fromJson(
        Map<String, dynamic>.from(msg as Map? ?? const {}),
        myUserId: user?.id ?? 0,
      ),
      imageUrl: data['image_url'] as String?,
      videoUrl: data['video_url'] as String?,
    );
  }

  Future<void> loadStatusFeed() async {
    if (!isLoggedIn) {
      statusFeed = null;
      notifyListeners();
      return;
    }
    try {
      final res = await _api.get('/status');
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      if (data != null) {
        statusFeed = StatusFeed.fromJson(data);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> postStatus({
    String? imagePath,
    String? videoPath,
    String? caption,
    String? backgroundColor,
    String filename = 'status.jpg',
    bool refreshFeed = true,
  }) async {
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final hasVideo = videoPath != null && videoPath.isNotEmpty;
    final res = hasVideo
        ? await _api.postMultipart(
            '/status',
            fields: {
              if (caption != null && caption.trim().isNotEmpty) 'body': caption.trim(),
              if (backgroundColor != null) 'background_color': backgroundColor,
            },
            fileField: 'video',
            filePath: videoPath,
            filename: filename.isNotEmpty ? filename : 'status.mp4',
          )
        : hasImage
            ? await _api.postMultipart(
                '/status',
                fields: {
                  if (caption != null && caption.trim().isNotEmpty) 'body': caption.trim(),
                  if (backgroundColor != null) 'background_color': backgroundColor,
                },
                fileField: 'image',
                filePath: imagePath,
                filename: filename,
              )
            : await _api.post('/status', data: {
                if (caption != null) 'body': caption,
                if (backgroundColor != null) 'background_color': backgroundColor,
              });
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw ApiException('Could not post status.');
    }
    if (refreshFeed) {
      await loadStatusFeed();
    }
  }

  Future<void> viewStatus(int statusId) async {
    await _api.post('/status/$statusId/view');
  }

  Future<StatusViewsPage> loadStatusViews(int statusId) async {
    final res = await _api.get('/status/$statusId/views');
    final data = res.data is Map ? res.data['data'] : null;
    if (data is Map) {
      return StatusViewsPage.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Could not load status views.');
  }

  Future<void> deleteStatus(int statusId) async {
    await _api.delete('/status/$statusId');
    await loadStatusFeed();
  }

  Future<ChatMessage> sendFileMessage(
    int conversationId,
    String filePath, {
    String? caption,
    String filename = 'file',
  }) async {
    final res = await _api.postMultipart(
      '/messages/$conversationId/file',
      fields: {
        if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
      },
      fileField: 'file',
      filePath: filePath,
      filename: filename,
    );
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<ChatMessage> sendVoiceMessage(
    int conversationId,
    String filePath, {
    String filename = 'voice.m4a',
    int? durationSeconds,
  }) async {
    var path = filePath.trim();
    if (path.startsWith('file://')) {
      path = Uri.parse(path).toFilePath();
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ApiException('Recording file was not saved. Try again.');
    }
    if (await file.length() < 64) {
      throw ApiException('Recording was too short or empty. Hold longer, then send.');
    }

    final res = await _api.postMultipart(
      '/messages/$conversationId/voice',
      fields: {
        if (durationSeconds != null && durationSeconds > 0) 'duration_seconds': '$durationSeconds',
      },
      fileField: 'voice',
      filePath: path,
      filename: filename.toLowerCase().endsWith('.m4a') ? filename : 'voice.m4a',
      // AAC in an m4a container — matches what Android MediaRecorder writes.
      contentType: 'audio/mp4',
    );
    final data = res.data;
    if (data is! Map || data['message'] is! Map) {
      throw ApiException('Voice uploaded but the reply was incomplete. Pull to refresh.');
    }
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(data['message'] as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<void> deleteConversation(int conversationId) async {
    await _api.delete('/messages/$conversationId');
  }

  Future<({List<ChatMessage> messages, Map<String, dynamic>? clearRequest})> clearChatHistory(
    int conversationId,
  ) async {
    final res = await _api.post('/messages/$conversationId/clear');
    final msgs = res.data is Map ? res.data['messages'] : null;
    final clearReq = res.data is Map ? res.data['clear_request'] : null;
    final messages = msgs is List
        ? msgs
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: user?.id ?? 0,
                ))
            .toList()
        : <ChatMessage>[];
    return (
      messages: messages,
      clearRequest: clearReq is Map ? Map<String, dynamic>.from(clearReq) : null,
    );
  }

  Future<Map<String, dynamic>?> requestClearBoth(int conversationId) async {
    final res = await _api.post('/messages/$conversationId/clear-request');
    final clearReq = res.data is Map ? res.data['clear_request'] : null;
    return clearReq is Map ? Map<String, dynamic>.from(clearReq) : null;
  }

  Future<({List<ChatMessage>? messages, Map<String, dynamic>? clearRequest})> respondClearBoth({
    required int conversationId,
    required int clearRequestId,
    required bool accept,
  }) async {
    final res = await _api.post(
      '/messages/$conversationId/clear-request/$clearRequestId',
      data: {'accept': accept},
    );
    final msgs = res.data is Map ? res.data['messages'] : null;
    final clearReq = res.data is Map ? res.data['clear_request'] : null;
    final messages = msgs is List
        ? msgs
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: user?.id ?? 0,
                ))
            .toList()
        : null;
    return (
      messages: messages,
      clearRequest: clearReq is Map ? Map<String, dynamic>.from(clearReq) : null,
    );
  }

  Future<List<ChatMessage>> searchMessages(int conversationId, String query) async {
    final res = await _api.get('/messages/$conversationId/search', query: {'q': query});
    final msgs = res.data is Map ? res.data['messages'] : null;
    return msgs is List
        ? msgs
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: user?.id ?? 0,
                ))
            .toList()
        : <ChatMessage>[];
  }

  Future<void> reportSeller({
    required int sellerId,
    required String reason,
    String? details,
    int? productId,
  }) async {
    await _api.post('/sellers/report', data: {
      'seller_id': sellerId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
      if (productId != null) 'product_id': productId,
    });
  }

  Future<ChatMessage> updateMessage(int conversationId, int messageId, String body) async {
    final res = await _api.patch('/messages/$conversationId/messages/$messageId', data: {
      'body': body,
    });
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<ChatMessage> reactToMessage(int conversationId, int messageId, String emoji) async {
    final res = await _api.post('/messages/$conversationId/messages/$messageId/react', data: {
      'emoji': emoji,
    });
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<ChatMessage> deleteMessage(int conversationId, int messageId) async {
    final res = await _api.delete('/messages/$conversationId/messages/$messageId');
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<Map<String, dynamic>> sendCallSignal(
    int conversationId,
    String type, {
    String body = '',
    Map<String, dynamic>? metadata,
  }) async {
    final res = await _api.post('/messages/$conversationId/signal', data: {
      'type': type,
      'body': body,
      if (metadata != null) 'metadata': metadata,
    });
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<({List<ChatMessage> messages, List<ChatMessage> updated, List<int> readMessageIds, Map<String, dynamic>? other})>
      pollMessages(
    int conversationId,
    int afterId, {
    String? updatedAfter,
  }) async {
    final res = await _api.get('/messages/$conversationId/poll', query: {
      'after': afterId,
      if (updatedAfter != null && updatedAfter.isNotEmpty) 'updated_after': updatedAfter,
    });
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    ChatMessage parse(Map e) => ChatMessage.fromJson(
          Map<String, dynamic>.from(e),
          myUserId: user?.id ?? 0,
        );
    final msgs = data['messages'];
    final updatedRaw = data['updated'];
    final readIds = data['read_message_ids'];
    final messages = msgs is List
        ? msgs.whereType<Map>().map(parse).toList()
        : <ChatMessage>[];
    final updated = updatedRaw is List
        ? updatedRaw.whereType<Map>().map(parse).toList()
        : <ChatMessage>[];
    final readMessageIds = readIds is List
        ? readIds.whereType<num>().map((e) => e.toInt()).toList()
        : <int>[];
    final otherRaw = data['other'];
    final other = otherRaw is Map ? Map<String, dynamic>.from(otherRaw) : null;
    return (messages: messages, updated: updated, readMessageIds: readMessageIds, other: other);
  }

  Future<RealtimeConfig?> fetchRealtimeConfig() async {
    try {
      final res = await _api.get('/realtime/config');
      final data = res.data;
      if (data is! Map) return null;
      return RealtimeConfig.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>>? _iceServers;

  static const _iceFallback = <Map<String, dynamic>>[
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
    },
  ];

  /// STUN/TURN servers for calls. Cached for the app session and hard-bounded:
  /// this sits on the call-start path, so a slow network must never hold up
  /// ringing or answering. On timeout we fall back to public STUN.
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final cached = _iceServers;
    if (cached != null) return cached;
    try {
      final res = await _api
          .get('/calls/ice-servers')
          .timeout(const Duration(seconds: 3));
      final data = res.data;
      final raw = data is Map ? data['ice_servers'] : null;
      if (raw is List && raw.isNotEmpty) {
        final servers = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (servers.isNotEmpty) {
          _iceServers = servers;
          return servers;
        }
      }
    } catch (_) {
      // fall through to defaults
    }
    return _iceFallback;
  }

  /// Warm the ICE cache while the chat screen loads so the call path never waits.
  void primeIceServers() {
    if (_iceServers == null) unawaited(fetchIceServers());
  }

  Future<void> loadGhanaLocations() async {
    Map<String, List<String>>? remoteCities;
    try {
      final res = await _api.get('/locations/ghana');
      final cities = res.data is Map ? res.data['cities_by_region'] : null;
      if (cities is Map && cities.isNotEmpty) {
        remoteCities = cities.map(
          (k, v) => MapEntry(
            k.toString(),
            v is List ? v.map((e) => e.toString()).toList() : <String>[],
          ),
        );
      }
    } catch (_) {
      // Offline signup still works with bundled defaults in ghana_location_fields.dart.
    }

    citiesByRegion = ghanaCitiesCatalog(remote: remoteCities);
    regions = ghanaRegions(citiesByRegion: citiesByRegion);
    notifyListeners();
  }

  Future<void> loadAddresses() async {
    final res = await _api.get('/addresses');
    final data = res.data is Map ? res.data['data'] : null;
    if (data is List) {
      addresses = data
          .whereType<Map>()
          .map((e) => BuyerAddress.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final cities = res.data is Map ? res.data['cities_by_region'] : null;
    if (cities is Map) {
      final remoteCities = cities.map(
        (k, v) => MapEntry(
          k.toString(),
          v is List ? v.map((e) => e.toString()).toList() : <String>[],
        ),
      );
      citiesByRegion = ghanaCitiesCatalog(remote: remoteCities);
      regions = ghanaRegions(citiesByRegion: citiesByRegion);
    }
    notifyListeners();
  }

  Future<void> saveAddress(Map<String, dynamic> payload, {int? id}) async {
    if (id == null) {
      await _api.post('/addresses', data: payload);
    } else {
      await _api.patch('/addresses/$id', data: payload);
    }
    await loadAddresses();
  }

  Future<void> deleteAddress(int id) async {
    await _api.delete('/addresses/$id');
    await loadAddresses();
  }

  Future<void> setDefaultAddress(int id) async {
    await _api.post('/addresses/$id/default');
    await loadAddresses();
  }

  Future<CheckoutPreview> loadCheckoutPreview() async {
    final res = await _api.get('/checkout');
    return CheckoutPreview.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<Map<String, dynamic>> applyCheckoutCoupons(Map<String, String> sellerCoupons) async {
    final res = await _api.post('/checkout/apply-coupons', data: {
      'seller_coupons': sellerCoupons,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> placeCheckout({
    required int addressId,
    required String paymentMethod,
    Map<String, dynamic>? sellerPayments,
    Map<String, String>? sellerCoupons,
    String? paymentPin,
  }) async {
    final res = await _api.post('/checkout', data: {
      'address_id': addressId,
      'payment_method': paymentMethod,
      if (sellerPayments != null && sellerPayments.isNotEmpty) 'seller_payments': sellerPayments,
      if (sellerCoupons != null && sellerCoupons.isNotEmpty) 'seller_coupons': sellerCoupons,
      if (paymentPin != null && paymentPin.isNotEmpty) 'payment_pin': paymentPin,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    // Keep cart until payment/proof is submitted (draft flows).
    if (data['next'] != 'direct_pay' && data['next'] != 'paystack') {
      await loadCart();
    }
    return data;
  }

  Future<Map<String, dynamic>> fetchDirectPayDraft() async {
    final res = await _api.get('/checkout/direct-pay');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> submitDirectPayDraft({
    required int sellerId,
    String? reference,
    String? proofPath,
  }) async {
    if (proofPath != null && proofPath.isNotEmpty) {
      final res = await _api.postMultipart(
        '/checkout/direct-pay/$sellerId',
        fields: {
          if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
        },
        fileField: 'proof',
        filePath: proofPath,
      );
      await loadCart();
      return Map<String, dynamic>.from(res.data as Map);
    }
    final res = await _api.post('/checkout/direct-pay/$sellerId', data: {
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
    });
    await loadCart();
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> submitDirectPayment({
    required int orderId,
    String? reference,
    String? proofPath,
  }) async {
    if (proofPath != null && proofPath.isNotEmpty) {
      final res = await _api.postMultipart(
        '/orders/$orderId/direct-payment',
        fields: {
          if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
        },
        fileField: 'proof',
        filePath: proofPath,
      );
      return Map<String, dynamic>.from(res.data as Map);
    }
    final res = await _api.post('/orders/$orderId/direct-payment', data: {
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> initializePaystack(int checkoutId) async {
    final res = await _api.post('/checkouts/$checkoutId/pay/initialize');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyPaystack({
    required int checkoutId,
    required String reference,
  }) async {
    final res = await _api.post('/checkouts/$checkoutId/pay/verify', data: {
      'reference': reference,
    });
    await loadCart();
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> initializeDraftPaystack() async {
    final res = await _api.post('/checkout/paystack/initialize');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyDraftPaystack(String reference) async {
    final res = await _api.post('/checkout/paystack/verify', data: {
      'reference': reference,
    });
    await loadCart();
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> initializeDraftFlutterwave() async {
    final res = await _api.post('/checkout/flutterwave/initialize');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyDraftFlutterwave(String reference) async {
    final res = await _api.post('/checkout/flutterwave/verify', data: {
      'reference': reference,
    });
    await loadCart();
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> initializeFlutterwave(int checkoutId) async {
    final res = await _api.post('/checkouts/$checkoutId/pay/flutterwave/initialize');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyFlutterwave({
    required int checkoutId,
    required String reference,
  }) async {
    final res = await _api.post('/checkouts/$checkoutId/pay/flutterwave/verify', data: {
      'reference': reference,
    });
    await loadCart();
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> initializeWalletPaystack({
    required double amount,
    required String method,
  }) async {
    final res = await _api.post('/wallet/paystack/initialize', data: {
      'amount': amount,
      'method': method,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyWalletPaystack(String reference) async {
    final res = await _api.post('/wallet/paystack/verify', data: {
      'reference': reference,
    });
    final body = Map<String, dynamic>.from(res.data as Map);
    final walletJson = body['wallet'];
    if (walletJson is Map) {
      wallet = WalletInfo.fromJson(Map<String, dynamic>.from(walletJson));
      notifyListeners();
    } else {
      await loadWallet();
    }
    return body;
  }

  Future<Map<String, dynamic>> initializeWalletFlutterwave({
    required double amount,
    required String method,
  }) async {
    final res = await _api.post('/wallet/flutterwave/initialize', data: {
      'amount': amount,
      'method': method,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyWalletFlutterwave(String reference) async {
    final res = await _api.post('/wallet/flutterwave/verify', data: {
      'reference': reference,
    });
    final body = Map<String, dynamic>.from(res.data as Map);
    final walletJson = body['wallet'];
    if (walletJson is Map) {
      wallet = WalletInfo.fromJson(Map<String, dynamic>.from(walletJson));
      notifyListeners();
    } else {
      await loadWallet();
    }
    return body;
  }

  Future<void> payCheckoutWithWallet(int checkoutId, {required String paymentPin}) async {
    await _api.post('/checkouts/$checkoutId/pay/wallet', data: {
      'payment_pin': paymentPin,
    });
    await loadCart();
    await loadWallet();
  }

  void clearCategoryFilter() => loadShop(clearCategory: true);

  void toggleInGhana() => loadShop(inGhana: !filterInGhana);

  void toggleFreeShip() => loadShop(freeShip: !filterFreeShip);
}
