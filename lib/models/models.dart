class ShopCategory {
  const ShopCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.productsCount = 0,
  });

  final int id;
  final String name;
  final String slug;
  final String? icon;
  final int productsCount;

  factory ShopCategory.fromJson(Map<String, dynamic> json) {
    return ShopCategory(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      icon: json['icon'] as String?,
      productsCount: (json['products_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProductImage {
  const ProductImage({required this.id, required this.url, this.isPrimary = false});

  final int id;
  final String url;
  final bool isPrimary;

  factory ProductImage.fromJson(Map<String, dynamic> json) {
    return ProductImage(
      id: json['id'] as int? ?? 0,
      url: json['url'] as String? ?? '',
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.slug,
    required this.price,
    required this.effectivePrice,
    this.discountPrice,
    this.description,
    this.brand,
    this.condition,
    this.rating = 0,
    this.reviewCount = 0,
    this.views = 0,
    this.wishlistAdds = 0,
    this.inGhana = false,
    this.freeShipping = false,
    this.deliveryFee,
    this.deliveryDays,
    this.isPreorder = false,
    this.cashOnDelivery = false,
    this.pickupAvailable = false,
    this.shipsNationwide = false,
    this.isNegotiable = false,
    this.specifications = const {},
    this.videoUrl,
    this.videoDuration,
    this.images = const [],
    this.categoryName,
    this.categoryId,
    this.categoryIcon,
    this.storeName,
    this.storeSlug,
    this.sellerId,
    this.sellerName,
    this.sellerPhoto,
    this.sellerRating,
    this.sellerSales,
    this.quantity = 0,
  });

  final int id;
  final String name;
  final String slug;
  final double price;
  final double effectivePrice;
  final double? discountPrice;
  final String? description;
  final String? brand;
  final String? condition;
  final double rating;
  final int reviewCount;
  final int views;
  final int wishlistAdds;
  final bool inGhana;
  final bool freeShipping;
  final double? deliveryFee;
  final int? deliveryDays;
  final bool isPreorder;
  final bool cashOnDelivery;
  final bool pickupAvailable;
  final bool shipsNationwide;
  final bool isNegotiable;
  final Map<String, dynamic> specifications;
  final String? videoUrl;
  final int? videoDuration;
  final List<ProductImage> images;
  final String? categoryName;
  final int? categoryId;
  final String? categoryIcon;
  final String? storeName;
  final String? storeSlug;
  final int? sellerId;
  final String? sellerName;
  final String? sellerPhoto;
  final double? sellerRating;
  final int? sellerSales;
  final int quantity;

  String? get primaryImageUrl {
    if (images.isEmpty) return null;
    final primary = images.where((i) => i.isPrimary).firstOrNull;
    return (primary ?? images.first).url;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final imagesJson = json['images'];
    final category = json['category'];
    final seller = json['seller'];
    final specs = json['specifications'];
    Map<String, dynamic> specMap = const {};
    if (specs is Map) {
      specMap = Map<String, dynamic>.from(specs);
    } else if (specs is List) {
      // web sometimes stores list of {key,value} or field map
      final mapped = <String, dynamic>{};
      for (final item in specs) {
        if (item is Map) {
          final key = item['key'] ?? item['label'] ?? item['name'];
          final value = item['value'] ?? item['text'];
          if (key != null) mapped['$key'] = value;
        }
      }
      specMap = mapped;
    }

    return Product(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      discountPrice: (json['discount_price'] as num?)?.toDouble(),
      effectivePrice: (json['effective_price'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble() ??
          0,
      description: json['description'] as String?,
      brand: json['brand'] as String?,
      condition: json['condition'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      views: (json['views'] as num?)?.toInt() ?? 0,
      wishlistAdds: (json['wishlist_adds'] as num?)?.toInt() ?? 0,
      inGhana: json['in_ghana'] as bool? ?? false,
      freeShipping: json['free_shipping'] as bool? ?? false,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
      deliveryDays: (json['delivery_days'] as num?)?.toInt(),
      isPreorder: json['is_preorder'] as bool? ?? false,
      cashOnDelivery: json['cash_on_delivery'] as bool? ?? false,
      pickupAvailable: json['pickup_available'] as bool? ?? false,
      shipsNationwide: json['ships_nationwide'] as bool? ?? false,
      isNegotiable: json['is_negotiable'] as bool? ?? false,
      specifications: specMap,
      videoUrl: json['video_url'] as String?,
      videoDuration: (json['video_duration'] as num?)?.toInt(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      images: imagesJson is List
          ? imagesJson
              .whereType<Map>()
              .map((e) => ProductImage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      categoryName: category is Map ? category['name'] as String? : null,
      categoryId: category is Map ? category['id'] as int? : null,
      categoryIcon: category is Map ? category['icon'] as String? : null,
      storeName: seller is Map
          ? (seller['store_name'] as String? ?? seller['name'] as String?)
          : null,
      storeSlug: seller is Map
          ? (seller['store_slug'] as String? ??
              (seller['seller_profile'] is Map
                  ? (seller['seller_profile'] as Map)['slug'] as String?
                  : null))
          : null,
      sellerId: seller is Map ? seller['id'] as int? : null,
      sellerName: seller is Map ? seller['name'] as String? : null,
      sellerPhoto: seller is Map
          ? () {
              final nested = seller['seller_profile'];
              final raw = seller['shop_photo'] as String? ??
                  (nested is Map ? nested['shop_photo'] as String? : null);
              if (raw == null || raw.trim().isEmpty) return null;
              return raw.trim();
            }()
          : null,
      sellerRating: seller is Map ? (seller['rating'] as num?)?.toDouble() : null,
      sellerSales: seller is Map ? (seller['total_sales'] as num?)?.toInt() : null,
    );
  }
}

class SellerStore {
  const SellerStore({
    required this.sellerId,
    required this.storeName,
    required this.slug,
    this.sellerName,
    this.shopPhoto,
    this.description,
    this.businessAddress,
    this.isBusinessRegistered = false,
    this.approvedAt,
    this.rating,
    this.totalSales,
    this.productCount = 0,
    this.reviewCount = 0,
    this.city,
    this.region,
    this.email,
    this.mobile,
    this.whatsapp,
    this.digitalAddress,
    this.residentialAddress,
  });

  final int sellerId;
  final String storeName;
  final String slug;
  final String? sellerName;
  final String? shopPhoto;
  final String? description;
  final String? businessAddress;
  final bool isBusinessRegistered;
  final DateTime? approvedAt;
  final double? rating;
  final int? totalSales;
  final int productCount;
  final int reviewCount;
  final String? city;
  final String? region;
  final String? email;
  final String? mobile;
  final String? whatsapp;
  final String? digitalAddress;
  final String? residentialAddress;

  String? get location {
    final parts = [city, region].whereType<String>().where((s) => s.trim().isNotEmpty);
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  factory SellerStore.fromJson(Map<String, dynamic> json) {
    DateTime? approvedAt;
    final rawApproved = json['approved_at'];
    if (rawApproved is String && rawApproved.trim().isNotEmpty) {
      approvedAt = DateTime.tryParse(rawApproved);
    }

    final photo = json['shop_photo'] as String?;
    return SellerStore(
      sellerId: (json['seller_id'] as num?)?.toInt() ?? 0,
      storeName: json['store_name'] as String? ?? 'Store',
      sellerName: json['seller_name'] as String?,
      slug: json['slug'] as String? ?? '',
      shopPhoto: photo == null || photo.trim().isEmpty ? null : photo.trim(),
      description: json['store_description'] as String?,
      businessAddress: json['business_address'] as String?,
      isBusinessRegistered: json['is_business_registered'] == true,
      approvedAt: approvedAt,
      rating: (json['rating'] as num?)?.toDouble(),
      totalSales: (json['total_sales'] as num?)?.toInt(),
      productCount: (json['product_count'] as num?)?.toInt() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      city: json['city'] as String?,
      region: json['region'] as String?,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      whatsapp: json['whatsapp'] as String?,
      digitalAddress: json['digital_address'] as String?,
      residentialAddress: json['residential_address'] as String?,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.mobile,
    this.role,
    this.region,
    this.city,
    this.avatar,
  });

  final int id;
  final String name;
  final String email;
  final String? mobile;
  final String? role;
  final String? region;
  final String? city;
  final String? avatar;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      mobile: json['mobile'] as String?,
      role: json['role'] as String?,
      region: json['region'] as String?,
      city: json['city'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
}

class CartItem {
  const CartItem({
    required this.id,
    required this.quantity,
    required this.subtotal,
    required this.product,
  });

  final int id;
  final int quantity;
  final double subtotal;
  final Product product;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as int,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      product: Product.fromJson(Map<String, dynamic>.from(json['product'] as Map)),
    );
  }
}

class BuyerAddress {
  const BuyerAddress({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.addressLine,
    required this.region,
    required this.city,
    this.secondaryPhone,
    this.additionalDetails,
    this.digitalAddress,
    this.isDefault = false,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String phone;
  final String? secondaryPhone;
  final String addressLine;
  final String? additionalDetails;
  final String region;
  final String city;
  final String? digitalAddress;
  final bool isDefault;

  String get fullName => '$firstName $lastName'.trim();

  factory BuyerAddress.fromJson(Map<String, dynamic> json) {
    return BuyerAddress(
      id: json['id'] as int,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      secondaryPhone: json['secondary_phone'] as String?,
      addressLine: json['address_line'] as String? ?? '',
      additionalDetails: json['additional_details'] as String?,
      region: json['region'] as String? ?? '',
      city: json['city'] as String? ?? '',
      digitalAddress: json['digital_address'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class WalletInfo {
  const WalletInfo({
    required this.availableBalance,
    required this.pendingBalance,
    this.totalEarnings = 0,
    this.withdrawnAmount = 0,
    this.paystackConfigured = false,
    this.manualTopUpEnabled = false,
  });

  final double availableBalance;
  final double pendingBalance;
  final double totalEarnings;
  final double withdrawnAmount;
  final bool paystackConfigured;
  final bool manualTopUpEnabled;

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    return WalletInfo(
      availableBalance: (json['available_balance'] as num?)?.toDouble() ?? 0,
      pendingBalance: (json['pending_balance'] as num?)?.toDouble() ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      withdrawnAmount: (json['withdrawn_amount'] as num?)?.toDouble() ?? 0,
      paystackConfigured: json['paystack_configured'] as bool? ?? false,
      manualTopUpEnabled: json['manual_top_up_enabled'] as bool? ?? false,
    );
  }
}

class WalletTransactionItem {
  const WalletTransactionItem({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.amount,
    required this.description,
    this.reference,
    this.createdAt,
    this.balanceBefore,
    this.balanceAfter,
  });

  final int id;
  final String type;
  final String typeLabel;
  final double amount;
  final String description;
  final String? reference;
  final String? createdAt;
  final double? balanceBefore;
  final double? balanceAfter;

  bool get isCredit => amount > 0;

  factory WalletTransactionItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    return WalletTransactionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: type,
      typeLabel: json['type_label'] as String? ?? type.replaceAll('_', ' '),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String? ?? '',
      reference: json['reference'] as String?,
      createdAt: json['created_at'] as String?,
      balanceBefore: (json['balance_before'] as num?)?.toDouble(),
      balanceAfter: (json['balance_after'] as num?)?.toDouble(),
    );
  }
}

class WalletTransactionPage {
  const WalletTransactionPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<WalletTransactionItem> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory WalletTransactionPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final meta = json['meta'];
    return WalletTransactionPage(
      items: data is List
          ? data
              .whereType<Map>()
              .map((e) => WalletTransactionItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      currentPage: meta is Map ? (meta['current_page'] as num?)?.toInt() ?? 1 : 1,
      lastPage: meta is Map ? (meta['last_page'] as num?)?.toInt() ?? 1 : 1,
    );
  }
}

class OrderItemModel {
  const OrderItemModel({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.productId,
    this.productSlug,
    this.status,
    this.fundsReleaseStatus,
    this.imageUrl,
    this.canRequestRefund = false,
    this.canReview = false,
    this.buyerReview,
    this.dispute,
  });

  final int id;
  final int? productId;
  final String? productSlug;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String? status;
  final String? fundsReleaseStatus;
  final String? imageUrl;
  final bool canRequestRefund;
  final bool canReview;
  final Map<String, dynamic>? buyerReview;
  final Map<String, dynamic>? dispute;

  double get displayTotal {
    if (lineTotal > 0) return lineTotal;
    if (unitPrice > 0) return unitPrice * quantity;
    return 0;
  }

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    final qty = _asInt(json['quantity']) ?? 1;
    final unit = _asDouble(json['unit_price']) ?? 0;
    var line = _asDouble(json['line_total']) ?? 0;
    if (line <= 0 && unit > 0) line = unit * qty;
    final dispute = json['dispute'];

    final review = json['buyer_review'];
    return OrderItemModel(
      id: _asInt(json['id']) ?? 0,
      productId: _asInt(json['product_id']),
      productSlug: json['product_slug'] as String?,
      productName: json['product_name'] as String? ?? '',
      quantity: qty,
      unitPrice: unit,
      lineTotal: line,
      status: json['status'] as String?,
      fundsReleaseStatus: json['funds_release_status'] as String?,
      imageUrl: json['image_url'] as String?,
      canRequestRefund: json['can_request_refund'] == true,
      canReview: json['can_review'] == true,
      buyerReview: review is Map ? Map<String, dynamic>.from(review) : null,
      dispute: dispute is Map ? Map<String, dynamic>.from(dispute) : null,
    );
  }
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', ''));
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

class OrderModel {
  const OrderModel({
    required this.id,
    required this.orderNumber,
    required this.total,
    this.status,
    this.paymentStatus,
    this.paymentChannel,
    this.paymentMethod,
    this.receiverName,
    this.receiverPhone,
    this.region,
    this.city,
    this.digitalAddress,
    this.deliveryNotes,
    this.subtotal = 0,
    this.shippingCost = 0,
    this.createdAt,
    this.storeName,
    this.storeSlug,
    this.sellerId,
    this.sellerName,
    this.sellerMobile,
    this.sellerWhatsapp,
    this.sellerEmail,
    this.sellerAddress,
    this.sellerPaymentMethod,
    this.directPaymentReference,
    this.directPaymentProofPath,
    this.directPaymentSubmittedAt,
    this.directPaymentRejectionReason,
    this.canRequestRefund = false,
    this.items = const [],
  });

  final int id;
  final String orderNumber;
  final String? status;
  final String? paymentStatus;
  final String? paymentChannel;
  final String? paymentMethod;
  final String? receiverName;
  final String? receiverPhone;
  final String? region;
  final String? city;
  final String? digitalAddress;
  final String? deliveryNotes;
  final double subtotal;
  final double shippingCost;
  final double total;
  final String? createdAt;
  final String? storeName;
  final String? storeSlug;
  final int? sellerId;
  final String? sellerName;
  final String? sellerMobile;
  final String? sellerWhatsapp;
  final String? sellerEmail;
  final String? sellerAddress;
  final Map<String, dynamic>? sellerPaymentMethod;
  final String? directPaymentReference;
  final String? directPaymentProofPath;
  final String? directPaymentSubmittedAt;
  final String? directPaymentRejectionReason;
  final bool canRequestRefund;
  final List<OrderItemModel> items;

  bool get hasShippingDetails =>
      (receiverName?.trim().isNotEmpty ?? false) ||
      (receiverPhone?.trim().isNotEmpty ?? false) ||
      (city?.trim().isNotEmpty ?? false) ||
      (region?.trim().isNotEmpty ?? false) ||
      (digitalAddress?.trim().isNotEmpty ?? false) ||
      (deliveryNotes?.trim().isNotEmpty ?? false);

  bool get isDirectPayment => (paymentChannel ?? '').toLowerCase() == 'direct';

  bool get needsDirectPaymentProof {
    if (!isDirectPayment) return false;
    final pay = (paymentStatus ?? '').toLowerCase();
    if (pay == 'paid') return false;
    return true;
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final seller = json['seller'];
    final itemsJson = json['items'];
    final method = json['seller_payment_method'];
    return OrderModel(
      id: json['id'] as int,
      orderNumber: json['order_number'] as String? ?? '',
      status: json['status'] as String?,
      paymentStatus: json['payment_status'] as String?,
      paymentChannel: json['payment_channel'] as String?,
      paymentMethod: json['payment_method'] as String?,
      receiverName: json['receiver_name'] as String?,
      receiverPhone: json['receiver_phone'] as String?,
      region: json['region'] as String?,
      city: json['city'] as String?,
      digitalAddress: json['digital_address'] as String?,
      deliveryNotes: json['delivery_notes'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] as String?,
      storeName: seller is Map ? seller['store_name'] as String? : null,
      storeSlug: seller is Map ? seller['store_slug'] as String? : null,
      sellerId: seller is Map ? seller['id'] as int? : null,
      sellerName: seller is Map ? seller['seller_name'] as String? : null,
      sellerMobile: seller is Map ? seller['mobile'] as String? : null,
      sellerWhatsapp: seller is Map ? seller['whatsapp'] as String? : null,
      sellerEmail: seller is Map ? seller['email'] as String? : null,
      sellerAddress: seller is Map
          ? [
              seller['business_address'],
              seller['city'],
              seller['region'],
            ]
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .join(', ')
          : null,
      sellerPaymentMethod: method is Map ? Map<String, dynamic>.from(method) : null,
      directPaymentReference: json['direct_payment_reference'] as String?,
      directPaymentProofPath: json['direct_payment_proof_path'] as String?,
      directPaymentSubmittedAt: json['direct_payment_submitted_at'] as String?,
      directPaymentRejectionReason: json['direct_payment_rejection_reason'] as String?,
      canRequestRefund: json['can_request_refund'] == true,
      items: itemsJson is List
          ? itemsJson
              .whereType<Map>()
              .map((e) => OrderItemModel.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class ConversationModel {
  const ConversationModel({
    required this.id,
    required this.otherName,
    this.otherId,
    this.otherAvatar,
    this.storeName,
    this.otherMobile,
    this.productId,
    this.productName,
    this.latestBody,
    this.unreadCount = 0,
    this.lastMessageAt,
  });

  final int id;
  final int? otherId;
  final String otherName;
  final String? otherAvatar;
  final String? storeName;
  final String? otherMobile;
  final int? productId;
  final String? productName;
  final String? latestBody;
  final int unreadCount;
  final String? lastMessageAt;

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    final other = json['other'];
    final product = json['product'];
    final latest = json['latest_message'];
    return ConversationModel(
      id: json['id'] as int,
      otherId: other is Map ? other['id'] as int? : null,
      otherName: other is Map
          ? (other['store_name'] as String? ?? other['name'] as String? ?? 'Seller')
          : 'Seller',
      otherAvatar: other is Map ? other['avatar'] as String? : null,
      storeName: other is Map ? other['store_name'] as String? : null,
      otherMobile: other is Map ? (other['mobile'] as String? ?? other['phone'] as String?) : null,
      productId: product is Map ? product['id'] as int? : null,
      productName: product is Map ? product['name'] as String? : null,
      latestBody: latest is Map ? latest['body'] as String? : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessageAt: json['last_message_at'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.mine,
    this.type = 'text',
    this.createdAt,
    this.imageUrl,
    this.isDeleted = false,
    this.canDelete = false,
  });

  final int id;
  final String body;
  final bool mine;
  final String type;
  final String? createdAt;
  final String? imageUrl;
  final bool isDeleted;
  final bool canDelete;

  factory ChatMessage.fromJson(Map<String, dynamic> json, {required int myUserId}) {
    final meta = json['metadata'];
    final deleted = json['is_deleted'] == true ||
        (meta is Map && meta['deleted_at'] != null);
    return ChatMessage(
      id: json['id'] as int,
      body: deleted ? '' : (json['body'] as String? ?? ''),
      mine: (json['sender_id'] as int?) == myUserId || json['is_mine'] == true,
      type: json['type'] as String? ?? 'text',
      createdAt: json['created_at'] as String?,
      imageUrl: deleted
          ? null
          : (meta is Map ? meta['image_url'] as String? : json['image_url'] as String?),
      isDeleted: deleted,
      canDelete: json['can_delete'] == true,
    );
  }

  ChatMessage copyWith({
    String? body,
    bool? isDeleted,
    bool? canDelete,
    String? imageUrl,
  }) {
    return ChatMessage(
      id: id,
      body: body ?? this.body,
      mine: mine,
      type: type,
      createdAt: createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      isDeleted: isDeleted ?? this.isDeleted,
      canDelete: canDelete ?? this.canDelete,
    );
  }
}

class WishlistItem {
  const WishlistItem({required this.id, required this.productId, required this.product});

  final int id;
  final int productId;
  final Product product;

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    return WishlistItem(
      id: json['id'] as int,
      productId: json['product_id'] as int? ?? (json['product'] is Map ? json['product']['id'] as int : 0),
      product: Product.fromJson(Map<String, dynamic>.from(json['product'] as Map)),
    );
  }
}

class CheckoutPreview {
  const CheckoutPreview({
    required this.subtotal,
    required this.shippingTotal,
    required this.grandTotal,
    required this.addresses,
    required this.walletAvailable,
    required this.paystackConfigured,
    this.sellerGroups = const [],
  });

  final double subtotal;
  final double shippingTotal;
  final double grandTotal;
  final List<BuyerAddress> addresses;
  final double walletAvailable;
  final bool paystackConfigured;
  final List<Map<String, dynamic>> sellerGroups;

  factory CheckoutPreview.fromJson(Map<String, dynamic> json) {
    final addresses = json['addresses'];
    final wallet = json['wallet'];
    final groups = json['seller_groups'];
    return CheckoutPreview(
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      shippingTotal: (json['shipping_total'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0,
      walletAvailable: wallet is Map
          ? (wallet['available_balance'] as num?)?.toDouble() ?? 0
          : 0,
      paystackConfigured: json['paystack_configured'] as bool? ?? false,
      addresses: addresses is List
          ? addresses
              .whereType<Map>()
              .map((e) => BuyerAddress.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      sellerGroups: groups is List
          ? groups.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [],
    );
  }
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data,
    this.readAt,
    this.createdAt,
  });

  final int id;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;
  final String? readAt;
  final String? createdAt;

  bool get isUnread => readAt == null || readAt!.isEmpty;

  int? get conversationId {
    final v = data?['conversation_id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  int? get orderId {
    final v = data?['order_id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  factory AppNotificationItem.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return AppNotificationItem(
      id: _asInt(json['id']) ?? 0,
      type: json['type'] as String? ?? 'notification',
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String?,
      data: data is Map ? Map<String, dynamic>.from(data) : null,
      readAt: json['read_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
