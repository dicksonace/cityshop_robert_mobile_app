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
  bool imageSearchActive = false;
  String? imageSearchPreview;
  List<String> imageSearchKeywords = [];
  int? selectedCategoryId;
  bool filterInGhana = false;
  bool filterFreeShip = false;
  String sort = 'recommended';
  int totalProducts = 0;

  List<CartItem> cartItems = [];
  double cartSubtotal = 0;
  int cartCount = 0;
  Set<int> wishlistProductIds = {};
  List<WishlistItem> wishlist = [];
  List<OrderModel> orders = [];
  WalletInfo? wallet;
  List<ConversationModel> conversations = [];
  List<BuyerAddress> addresses = [];
  List<String> regions = [];
  Map<String, List<String>> citiesByRegion = {};

  bool get isLoggedIn => user != null;

  Future<void> init() async {
    booting = true;
    notifyListeners();
    try {
      final token = await _api.getToken();
      if (token != null && token.isNotEmpty) {
        await refreshMe();
        await Future.wait([
          loadCart(),
          loadWishlist(),
        ]);
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

  Future<({Product product, List<Product> related, List<Map<String, dynamic>> reviews})>
      fetchProductDetail(String slug) async {
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

    return (
      product: Product.fromJson(Map<String, dynamic>.from(data as Map)),
      related: related,
      reviews: reviews,
    );
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
    await Future.wait([loadCart(), loadWishlist()]);
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
    cartItems = [];
    cartSubtotal = 0;
    cartCount = 0;
    wishlist = [];
    wishlistProductIds = {};
    orders = [];
    wallet = null;
    conversations = [];
    addresses = [];
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
      user = AppUser.fromJson(Map<String, dynamic>.from(userJson));
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

  Future<void> loadCart() async {
    if (!isLoggedIn) return;
    try {
      final res = await _api.get('/cart');
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

  Future<void> loadWishlist() async {
    if (!isLoggedIn) return;
    try {
      final res = await _api.get('/wishlist');
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

  Future<bool> toggleWishlist(int productId) async {
    final res = await _api.post('/wishlist/toggle', data: {'product_id': productId});
    final wishlisted = res.data is Map ? res.data['wishlisted'] as bool? ?? false : false;
    if (wishlisted) {
      wishlistProductIds = {...wishlistProductIds, productId};
    } else {
      wishlistProductIds = {...wishlistProductIds}..remove(productId);
      wishlist = wishlist.where((w) => w.productId != productId).toList();
    }
    notifyListeners();
    if (wishlisted || wishlist.isEmpty) {
      await loadWishlist();
    }
    return wishlisted;
  }

  Future<void> loadOrders() async {
    final res = await _api.get('/orders', query: {'per_page': 50});
    final data = res.data is Map ? res.data['data'] : null;
    if (data is List) {
      orders = data
          .whereType<Map>()
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
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

  Future<void> loadWallet() async {
    final res = await _api.get('/wallet');
    final data = res.data is Map ? res.data['data'] : null;
    if (data is Map) {
      wallet = WalletInfo.fromJson(Map<String, dynamic>.from(data));
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> loadManualFunding() async {
    final res = await _api.get('/wallet/manual-funding');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> submitWalletTopUp({
    required double amount,
    required String network,
    required String proofPath,
    String? paymentReference,
    String? userNote,
  }) async {
    await _api.postMultipart(
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
  }

  Future<void> loadConversations() async {
    final res = await _api.get('/messages');
    final data = res.data is Map ? (res.data['data'] ?? res.data['conversations']) : null;
    if (data is List) {
      conversations = data
          .whereType<Map>()
          .map((e) => ConversationModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    notifyListeners();
  }

  Future<({ConversationModel conversation, List<ChatMessage> messages})> openConversation({
    required int sellerId,
    int? productId,
  }) async {
    final res = await _api.post('/messages', data: {
      'seller_id': sellerId,
      if (productId != null) 'product_id': productId,
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
    return (conversation: conversation, messages: messages);
  }

  Future<({ConversationModel conversation, List<ChatMessage> messages})> loadConversation(
    int id,
  ) async {
    final res = await _api.get('/messages/$id');
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
    return (conversation: conversation, messages: messages);
  }

  Future<ChatMessage> sendMessage(int conversationId, String body) async {
    final res = await _api.post('/messages/$conversationId/send', data: {'body': body});
    final msg = res.data['message'];
    return ChatMessage.fromJson(
      Map<String, dynamic>.from(msg as Map),
      myUserId: user?.id ?? 0,
    );
  }

  Future<List<ChatMessage>> pollMessages(int conversationId, int afterId) async {
    final res = await _api.get('/messages/$conversationId/poll', query: {'after': afterId});
    final msgs = res.data is Map ? res.data['messages'] : null;
    if (msgs is! List) return [];
    return msgs
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(
              Map<String, dynamic>.from(e),
              myUserId: user?.id ?? 0,
            ))
        .toList();
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
    final regs = res.data is Map ? res.data['regions'] : null;
    if (regs is List) {
      regions = regs.map((e) => e.toString()).toList();
    }
    final cities = res.data is Map ? res.data['cities_by_region'] : null;
    if (cities is Map) {
      citiesByRegion = cities.map(
        (k, v) => MapEntry(
          k.toString(),
          v is List ? v.map((e) => e.toString()).toList() : <String>[],
        ),
      );
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

  Future<Map<String, dynamic>> placeCheckout({
    required int addressId,
    required String paymentMethod,
    Map<String, dynamic>? sellerPayments,
  }) async {
    final res = await _api.post('/checkout', data: {
      'address_id': addressId,
      'payment_method': paymentMethod,
      if (sellerPayments != null && sellerPayments.isNotEmpty) 'seller_payments': sellerPayments,
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

  Future<void> payCheckoutWithWallet(int checkoutId) async {
    await _api.post('/checkouts/$checkoutId/pay/wallet');
    await loadCart();
    await loadWallet();
  }

  void clearCategoryFilter() => loadShop(clearCategory: true);

  void toggleInGhana() => loadShop(inGhana: !filterInGhana);

  void toggleFreeShip() => loadShop(freeShip: !filterFreeShip);
}
