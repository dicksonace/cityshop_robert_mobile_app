import '../data/ghana_banks.dart';

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

/// Compact card for the "Matches for recent views" carousel.
class RecentViewMatch {
  const RecentViewMatch({
    required this.id,
    required this.name,
    required this.slug,
    required this.price,
    this.discountPrice,
    this.imageUrl,
    this.categoryId,
    this.sellersInCategory = 1,
  });

  final int id;
  final String name;
  final String slug;
  final double price;
  final double? discountPrice;
  final String? imageUrl;
  final int? categoryId;
  final int sellersInCategory;

  double get fromPrice => discountPrice ?? price;

  factory RecentViewMatch.fromJson(Map<String, dynamic> json) {
    final price = (json['price'] as num?)?.toDouble() ?? 0;
    final discount = (json['discount_price'] as num?)?.toDouble();
    final effective = (json['effective_price'] as num?)?.toDouble();
    return RecentViewMatch(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      price: effective ?? discount ?? price,
      discountPrice: discount,
      imageUrl: json['image_url'] as String?,
      categoryId: (json['category_id'] as num?)?.toInt(),
      sellersInCategory: (json['sellers_in_category'] as num?)?.toInt() ?? 1,
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
    this.videoPlays = 0,
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
  final int videoPlays;
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
      videoPlays: (json['video_plays'] as num?)?.toInt() ?? 0,
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

class LivestreamRoom {
  const LivestreamRoom({
    required this.domain,
    required this.roomName,
    this.provider = 'jitsi',
  });

  final String domain;
  final String roomName;
  final String provider;

  factory LivestreamRoom.fromJson(Map<String, dynamic> json) {
    return LivestreamRoom(
      domain: json['domain'] as String? ?? 'jitsi.riot.im',
      roomName: json['room_name'] as String? ?? '',
      provider: json['provider'] as String? ?? 'jitsi',
    );
  }
}

class LivestreamCard {
  const LivestreamCard({
    required this.id,
    required this.storeName,
    required this.storeSlug,
    this.title,
    this.shopPhoto,
    this.room,
    this.hostJoined = false,
  });

  final int id;
  final String storeName;
  final String storeSlug;
  final String? title;
  final String? shopPhoto;
  final LivestreamRoom? room;
  final bool hostJoined;

  factory LivestreamCard.fromJson(Map<String, dynamic> json) {
    final photo = json['shop_photo'] as String?;
    final roomJson = json['room'];
    return LivestreamCard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      storeName: json['store_name'] as String? ?? 'Store',
      storeSlug: json['store_slug'] as String? ?? json['slug'] as String? ?? '',
      title: json['title'] as String?,
      shopPhoto: photo == null || photo.trim().isEmpty ? null : photo.trim(),
      room: roomJson is Map ? LivestreamRoom.fromJson(Map<String, dynamic>.from(roomJson)) : null,
      hostJoined: json['host_joined'] == true,
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
    this.followerCount = 0,
    this.isFollowing = false,
    this.city,
    this.region,
    this.email,
    this.mobile,
    this.whatsapp,
    this.digitalAddress,
    this.residentialAddress,
    this.isLive = false,
    this.livestream,
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
  final int followerCount;
  final bool isFollowing;
  final String? city;
  final String? region;
  final String? email;
  final String? mobile;
  final String? whatsapp;
  final String? digitalAddress;
  final String? residentialAddress;
  final bool isLive;
  final LivestreamCard? livestream;

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
    final liveJson = json['livestream'];
    final livestream = liveJson is Map
        ? LivestreamCard.fromJson(Map<String, dynamic>.from(liveJson))
        : null;
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
      followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
      isFollowing: json['is_following'] == true,
      city: json['city'] as String?,
      region: json['region'] as String?,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      whatsapp: json['whatsapp'] as String?,
      digitalAddress: json['digital_address'] as String?,
      residentialAddress: json['residential_address'] as String?,
      isLive: json['is_live'] == true || livestream != null,
      livestream: livestream,
    );
  }

  SellerStore copyWith({
    int? followerCount,
    bool? isFollowing,
    bool? isLive,
    LivestreamCard? livestream,
    bool clearLivestream = false,
  }) {
    return SellerStore(
      sellerId: sellerId,
      storeName: storeName,
      slug: slug,
      sellerName: sellerName,
      shopPhoto: shopPhoto,
      description: description,
      businessAddress: businessAddress,
      isBusinessRegistered: isBusinessRegistered,
      approvedAt: approvedAt,
      rating: rating,
      totalSales: totalSales,
      productCount: productCount,
      reviewCount: reviewCount,
      followerCount: followerCount ?? this.followerCount,
      isFollowing: isFollowing ?? this.isFollowing,
      city: city,
      region: region,
      email: email,
      mobile: mobile,
      whatsapp: whatsapp,
      digitalAddress: digitalAddress,
      residentialAddress: residentialAddress,
      isLive: isLive ?? this.isLive,
      livestream: clearLivestream ? null : (livestream ?? this.livestream),
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.mobile,
    this.country,
    this.role,
    this.region,
    this.city,
    this.avatar,
    this.hasPaymentPin = false,
  });

  final int id;
  final String name;
  final String email;
  final String? mobile;
  final String? country;
  final String? role;
  final String? region;
  final String? city;
  final String? avatar;
  final bool hasPaymentPin;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      mobile: json['mobile'] as String?,
      country: json['country'] as String?,
      role: json['role'] as String?,
      region: json['region'] as String?,
      city: json['city'] as String?,
      avatar: json['avatar'] as String?,
      hasPaymentPin: json['has_payment_pin'] == true,
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
    this.paystackFeePercent = 1.95,
    this.paystackFeeFlat = 0,
  });

  final double availableBalance;
  final double pendingBalance;
  final double totalEarnings;
  final double withdrawnAmount;
  final bool paystackConfigured;
  final bool manualTopUpEnabled;
  final double paystackFeePercent;
  final double paystackFeeFlat;

  WalletInfo copyWith({double? availableBalance, double? pendingBalance}) {
    return WalletInfo(
      availableBalance: availableBalance ?? this.availableBalance,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      totalEarnings: totalEarnings,
      withdrawnAmount: withdrawnAmount,
      paystackConfigured: paystackConfigured,
      manualTopUpEnabled: manualTopUpEnabled,
      paystackFeePercent: paystackFeePercent,
      paystackFeeFlat: paystackFeeFlat,
    );
  }

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    return WalletInfo(
      availableBalance: (json['available_balance'] as num?)?.toDouble() ?? 0,
      pendingBalance: (json['pending_balance'] as num?)?.toDouble() ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      withdrawnAmount: (json['withdrawn_amount'] as num?)?.toDouble() ?? 0,
      paystackConfigured: json['paystack_configured'] as bool? ?? false,
      manualTopUpEnabled: json['manual_top_up_enabled'] as bool? ?? false,
      paystackFeePercent: json['paystack_fee'] is Map
          ? (json['paystack_fee']['percent'] as num?)?.toDouble() ?? 1.95
          : 1.95,
      paystackFeeFlat: json['paystack_fee'] is Map
          ? (json['paystack_fee']['flat'] as num?)?.toDouble() ?? 0
          : 0,
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
    this.counterpartyName,
    this.counterpartyAvatar,
    this.counterpartyMobile,
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
  final String? counterpartyName;
  final String? counterpartyAvatar;
  final String? counterpartyMobile;

  bool get isCredit => amount > 0;

  factory WalletTransactionItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final party = json['counterparty'];
    Map<String, dynamic>? partyMap;
    if (party is Map) {
      partyMap = Map<String, dynamic>.from(party);
    }
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
      counterpartyName: partyMap?['name'] as String?,
      counterpartyAvatar: partyMap?['avatar'] as String?,
      counterpartyMobile: partyMap?['mobile'] as String?,
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

class WithdrawalItem {
  const WithdrawalItem({
    required this.id,
    required this.amount,
    required this.momoNumber,
    required this.accountName,
    required this.network,
    required this.networkLabel,
    required this.status,
    required this.statusLabel,
    this.payoutType = 'momo',
    this.payoutChannel,
    this.payoutChannelLabel,
    this.fee = 0,
    this.totalDebited,
    this.reference,
    this.rejectionReason,
    this.failureReason,
    this.adminNotes,
    this.proofUrl,
    this.createdAt,
    this.processedAt,
  });

  final int id;
  final double amount;
  final double fee;
  final double? totalDebited;
  final String momoNumber;
  final String accountName;
  final String network;
  final String networkLabel;
  final String payoutType;
  final String? payoutChannel;
  final String? payoutChannelLabel;
  final String? reference;
  final String status;
  final String statusLabel;
  final String? rejectionReason;
  final String? failureReason;
  final String? adminNotes;
  final String? proofUrl;
  final String? createdAt;
  final String? processedAt;

  bool get isOpen => status == 'pending' || status == 'processing';
  bool get isPaid => status == 'paid';
  bool get isRejected => status == 'rejected';

  double get debited => totalDebited ?? (amount + fee);

  factory WithdrawalItem.fromJson(Map<String, dynamic> json) {
    return WithdrawalItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      totalDebited: (json['total_debited'] as num?)?.toDouble(),
      momoNumber: json['momo_number'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      network: json['network'] as String? ?? '',
      networkLabel: json['network_label'] as String? ?? '',
      payoutType: json['payout_type'] as String? ?? 'momo',
      payoutChannel: json['payout_channel'] as String?,
      payoutChannelLabel: json['payout_channel_label'] as String?,
      reference: json['reference'] as String?,
      status: json['status'] as String? ?? 'pending',
      statusLabel: json['status_label'] as String? ?? 'Processing',
      rejectionReason: json['rejection_reason'] as String?,
      failureReason: json['failure_reason'] as String?,
      adminNotes: json['admin_notes'] as String?,
      proofUrl: json['proof_url'] as String?,
      createdAt: json['created_at'] as String?,
      processedAt: json['processed_at'] as String?,
    );
  }
}

/// One bank withdrawal fee band (amount range → fixed fee).
class BankFeeTier {
  const BankFeeTier({required this.min, this.max, required this.fee});

  final double min;
  final double? max;
  final double fee;
}

/// Withdrawal history plus the limits the withdraw screen enforces.
class WithdrawalOverview {
  const WithdrawalOverview({
    this.items = const [],
    this.availableBalance = 0,
    this.minimum = 10,
    this.hasPending = false,
    this.defaultMomoNumber,
    this.defaultAccountName,
    this.banks = const [],
    this.feeEnabled = true,
    this.feeAmount = 10,
    this.feeAppliesTo = 'bank',
    this.feeMode = 'flat',
    this.feePercent = 0,
    this.autoPaystack = false,
    this.bankTiers = const [],
  });

  final List<WithdrawalItem> items;
  final double availableBalance;
  final double minimum;
  final bool hasPending;
  final String? defaultMomoNumber;
  final String? defaultAccountName;
  final List<GhanaBank> banks;
  final bool feeEnabled;
  final double feeAmount;
  final String feeAppliesTo;
  final String feeMode;
  final double feePercent;
  final bool autoPaystack;
  final List<BankFeeTier> bankTiers;

  bool get canWithdraw => availableBalance >= minimum;

  static double feeFromBankTiers(double amount, List<BankFeeTier> tiers, [double fallback = 0]) {
    if (amount <= 0 || tiers.isEmpty) return fallback < 0 ? 0 : fallback;
    for (final tier in tiers) {
      final max = tier.max;
      if (amount + 0.0001 >= tier.min && (max == null || amount <= max + 0.0001)) {
        return tier.fee;
      }
    }
    if (amount < tiers.first.min) return tiers.first.fee;
    // Between bands → next (higher) fee so GH₵5,000 is not stuck on the GH₵10 band.
    for (var i = 0; i < tiers.length - 1; i++) {
      final currMax = tiers[i].max;
      final nextMin = tiers[i + 1].min;
      if (currMax != null && amount > currMax && amount < nextMin) {
        return tiers[i + 1].fee;
      }
    }
    return tiers.last.fee;
  }

  /// CityShop default when the API has not sent bank_tiers yet.
  static const List<BankFeeTier> defaultBankTiers = [
    BankFeeTier(min: 10, max: 999.99, fee: 10),
    BankFeeTier(min: 1000, max: 25000, fee: 20),
  ];

  static List<BankFeeTier> _normalizeBankTiers(List<BankFeeTier> tiers) {
    if (tiers.isEmpty) return defaultBankTiers;
    final onlyDefaultFees = tiers.every((tier) => tier.fee == 10 || tier.fee == 20);
    if (!onlyDefaultFees) return tiers;
    final feeAt999 = feeFromBankTiers(999, tiers, 10);
    final feeAt1000 = feeFromBankTiers(1000, tiers, 10);
    final feeAt1500 = feeFromBankTiers(1500, tiers, 10);
    if (feeAt999 == 10 && feeAt1000 >= 20 && feeAt1500 >= 20) return tiers;
    return defaultBankTiers;
  }

  double feeFor(String payoutType, [double amount = 0]) {
    if (!feeEnabled) return 0;
    if (feeMode == 'percent') {
      return feePercent > 0 ? double.parse((amount * feePercent / 100).toStringAsFixed(2)) : 0;
    }
    if (feeAppliesTo == 'none') return 0;
    final type = payoutType == 'bank' ? 'bank' : 'momo';
    if (!(feeAppliesTo == 'all' || feeAppliesTo == type)) return 0;
    if (type == 'bank') {
      final tiers = bankTiers.isNotEmpty ? bankTiers : defaultBankTiers;
      return feeFromBankTiers(amount, tiers, feeAmount);
    }
    return feeAmount > 0 ? feeAmount : 0;
  }

  double maxWithdrawable(String payoutType) {
    if (feeMode == 'percent' && feePercent > 0) {
      final max = availableBalance / (1 + feePercent / 100);
      return (max * 100).floorToDouble() / 100;
    }
    var lo = 0.0;
    var hi = availableBalance;
    for (var i = 0; i < 48; i++) {
      final mid = (lo + hi) / 2;
      final fee = feeFor(payoutType, mid);
      if (mid + fee <= availableBalance + 1e-9) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    var amount = double.parse(lo.toStringAsFixed(2));
    if (amount + feeFor(payoutType, amount) > availableBalance + 1e-9) {
      amount = double.parse((amount - 0.01).toStringAsFixed(2));
    }
    return amount.clamp(0, availableBalance);
  }

  factory WithdrawalOverview.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final summary = json['summary'] is Map ? Map<String, dynamic>.from(json['summary'] as Map) : const {};
    final bankRows = summary['banks'];
    final feeRaw = summary['withdrawal_fee'];
    final fee = feeRaw is Map ? Map<String, dynamic>.from(feeRaw) : const <String, dynamic>{};
    final tierRows = fee['bank_tiers'];
    final bankTiers = _normalizeBankTiers(tierRows is List
        ? tierRows.whereType<Map>().map((row) {
            final map = Map<String, dynamic>.from(row);
            return BankFeeTier(
              min: (map['min'] as num?)?.toDouble() ?? 0,
              max: map['max'] == null ? null : (map['max'] as num?)?.toDouble(),
              fee: (map['fee'] as num?)?.toDouble() ?? 0,
            );
          }).toList()
        : const <BankFeeTier>[]);
    return WithdrawalOverview(
      items: data is List
          ? data
              .whereType<Map>()
              .map((e) => WithdrawalItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      availableBalance: (summary['available_balance'] as num?)?.toDouble() ?? 0,
      minimum: (summary['minimum'] as num?)?.toDouble() ?? 10,
      hasPending: summary['has_pending'] == true,
      defaultMomoNumber: summary['default_momo_number'] as String?,
      defaultAccountName: summary['default_account_name'] as String?,
      banks: bankRows is List
          ? bankRows.whereType<Map>().map((row) {
              final map = Map<String, dynamic>.from(row);
              return GhanaBank(
                map['id'] as String? ?? '',
                map['label'] as String? ?? '',
              );
            }).where((b) => b.id.isNotEmpty).toList()
          : const [],
      feeEnabled: fee['enabled'] != false,
      feeAmount: (fee['amount'] as num?)?.toDouble() ?? 10,
      feeAppliesTo: fee['applies_to'] as String? ?? 'bank',
      feeMode: fee['mode'] as String? ?? 'flat',
      feePercent: (fee['percent'] as num?)?.toDouble() ?? 0,
      autoPaystack: fee['auto_paystack'] == true,
      bankTiers: bankTiers,
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
    this.autoConfirmIn,
    this.canRequestRefund = false,
    this.canReview = false,
    this.buyerReview,
    this.dispute,
    this.vehicleNumber,
    this.driverPhone,
    this.packageImageUrl,
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
  final String? autoConfirmIn;
  final bool canRequestRefund;
  final bool canReview;
  final Map<String, dynamic>? buyerReview;
  final Map<String, dynamic>? dispute;
  final String? vehicleNumber;
  final String? driverPhone;
  final String? packageImageUrl;

  bool get hasDeliveryDetails {
    return (vehicleNumber != null && vehicleNumber!.trim().isNotEmpty) ||
        (driverPhone != null && driverPhone!.trim().isNotEmpty) ||
        (packageImageUrl != null && packageImageUrl!.trim().isNotEmpty);
  }

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
      autoConfirmIn: json['auto_confirm_in'] as String?,
      canRequestRefund: json['can_request_refund'] == true,
      canReview: json['can_review'] == true,
      buyerReview: review is Map ? Map<String, dynamic>.from(review) : null,
      dispute: dispute is Map ? Map<String, dynamic>.from(dispute) : null,
      vehicleNumber: json['vehicle_number']?.toString(),
      driverPhone: json['driver_phone']?.toString(),
      packageImageUrl: json['package_image_url'] as String?,
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
    this.storeLogo,
    this.sellerId,
    this.sellerName,
    this.sellerMobile,
    this.sellerWhatsapp,
    this.sellerEmail,
    this.sellerAddress,
    this.sellerPaymentMethod,
    this.directPaymentReference,
    this.directPaymentProofPath,
    this.directPaymentSubmitted = false,
    this.directPaymentConfirmedAt,
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
  final String? storeLogo;
  final int? sellerId;
  final String? sellerName;
  final String? sellerMobile;
  final String? sellerWhatsapp;
  final String? sellerEmail;
  final String? sellerAddress;
  final Map<String, dynamic>? sellerPaymentMethod;
  final String? directPaymentReference;
  final String? directPaymentProofPath;
  final bool directPaymentSubmitted;
  final String? directPaymentConfirmedAt;
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

  bool get directPaymentRejected =>
      isDirectPayment &&
      (paymentStatus ?? '').toLowerCase() != 'paid' &&
      (directPaymentRejectionReason ?? '').trim().isNotEmpty;

  /// Buyer has sent the money to the seller but the seller has not confirmed it
  /// yet, so the payment status is still pending while the order moves along.
  bool get directPaymentUnderReview =>
      isDirectPayment &&
      (paymentStatus ?? '').toLowerCase() == 'pending' &&
      (status ?? '').toLowerCase() != 'cancelled' &&
      directPaymentSubmitted &&
      !directPaymentRejected;

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
      storeLogo: seller is Map ? (seller['store_logo'] as String?)?.trim() : null,
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
      directPaymentSubmitted: json['direct_payment_submitted'] == true ||
          (json['direct_payment_reference'] as String? ?? '').trim().isNotEmpty ||
          (json['direct_payment_proof_path'] as String? ?? '').trim().isNotEmpty,
      directPaymentConfirmedAt: json['direct_payment_confirmed_at'] as String?,
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

class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.name,
    this.mobile,
    this.avatar,
    this.online = false,
    this.lastSeenAt,
    this.isCreator = false,
  });

  final int id;
  final String name;
  final String? mobile;
  final String? avatar;
  final bool online;
  final String? lastSeenAt;
  final bool isCreator;

  String get presenceLabel {
    if (online) return 'Online';
    return formatChatLastSeen(lastSeenAt);
  }

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'User',
      mobile: json['mobile'] as String?,
      avatar: json['avatar'] as String?,
      online: json['online'] == true,
      lastSeenAt: json['last_seen_at'] as String?,
      isCreator: json['is_creator'] == true,
    );
  }
}

String formatChatLastSeen(String? iso) {
  if (iso == null || iso.trim().isEmpty) return 'Offline';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return 'Offline';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inMinutes < 1) return 'Last seen just now';
  if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Last seen yesterday';
  if (diff.inDays < 7) return 'Last seen ${diff.inDays} days ago';
  return 'Last seen ${dt.toLocal().day}/${dt.toLocal().month}/${dt.toLocal().year}';
}

class ConversationModel {
  const ConversationModel({
    required this.id,
    required this.otherName,
    this.otherId,
    this.otherAvatar,
    this.storeName,
    this.storeSlug,
    this.otherMobile,
    this.isSeller = false,
    this.isGroup = false,
    this.memberCount = 0,
    this.createdBy,
    this.participants = const [],
    this.canComplain = false,
    this.sellerId,
    this.productId,
    this.productName,
    this.productSlug,
    this.productImage,
    this.productPrice,
    this.latestBody,
    this.latestType,
    this.latestSenderId,
    this.unreadCount = 0,
    this.lastMessageAt,
    this.blocked = false,
    this.iBlocked = false,
    this.online = false,
    this.lastSeenAt,
    this.onlineCount = 0,
  });

  final int id;
  final int? otherId;
  final String otherName;
  final String? otherAvatar;
  final String? storeName;
  final String? storeSlug;
  final String? otherMobile;
  final bool isSeller;
  final bool isGroup;
  final int memberCount;
  final int? createdBy;
  final List<ChatParticipant> participants;
  /// True when the current user is the buyer in this chat (can report the seller).
  final bool canComplain;
  final int? sellerId;
  final int? productId;
  final String? productName;
  final String? productSlug;
  final String? productImage;
  final double? productPrice;
  final String? latestBody;
  final String? latestType;
  final int? latestSenderId;
  final int unreadCount;
  final String? lastMessageAt;
  final bool blocked;
  final bool iBlocked;
  final bool online;
  final String? lastSeenAt;
  final int onlineCount;

  String get presenceLabel {
    if (isGroup) {
      if (onlineCount > 0) {
        return onlineCount == 1 ? '1 online' : '$onlineCount online';
      }
      return 'Offline';
    }
    if (online) return 'Online';
    return formatChatLastSeen(lastSeenAt);
  }

  /// What the conversation list shows when the last message carries no text.
  String previewFor(int? viewerId) {
    final body = latestBody?.trim() ?? '';
    if (latestType == 'transfer') {
      return _transferPreview(body, viewerId);
    }
    if (body.isNotEmpty) return body;
    switch (latestType) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'voice':
        return 'Voice message';
      case 'product':
        return 'Product';
      case 'file':
        return 'File';
      case 'call_log':
        return 'Voice call';
      case null:
        return 'Start the conversation';
      default:
        return 'Start the conversation';
    }
  }

  /// Back-compat for tests / call sites that don't know the viewer.
  String get preview => previewFor(null);

  String _transferPreview(String body, int? viewerId) {
    final isReceiver =
        viewerId != null && latestSenderId != null && latestSenderId != viewerId;

    if (isReceiver) {
      if (body.isEmpty) return 'Transferred to you';
      if (body.startsWith('Transferred to you')) return body;
      if (body.startsWith('Transferred ')) {
        return 'Transferred to you ${body.substring('Transferred '.length)}';
      }
      return 'Transferred to you';
    }

    if (body.isEmpty) return 'Money transfer';
    return body;
  }

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    final other = json['other'];
    final product = json['product'];
    final latest = json['latest_message'];
    final participantsJson = json['participants'];
    final participants = participantsJson is List
        ? participantsJson
            .whereType<Map>()
            .map((e) => ChatParticipant.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ChatParticipant>[];
    final groupAvatar = json['avatar'] as String?;
    final otherAvatar = groupAvatar ?? (other is Map ? other['avatar'] as String? : null);

    return ConversationModel(
      id: json['id'] as int,
      otherId: other is Map ? other['id'] as int? : null,
      otherName: json['is_group'] == true
          ? (json['name'] as String? ??
              (other is Map ? other['name'] as String? : null) ??
              'Group')
          : (other is Map
              ? (other['store_name'] as String? ?? other['name'] as String? ?? 'User')
              : 'User'),
      otherAvatar: otherAvatar,
      storeName: other is Map ? other['store_name'] as String? : null,
      storeSlug: other is Map
          ? ((other['store_slug'] as String?)?.trim().isNotEmpty == true
              ? (other['store_slug'] as String).trim()
              : (other['seller_profile'] is Map
                  ? ((other['seller_profile'] as Map)['slug'] as String?)?.trim()
                  : null))
          : null,
      otherMobile: other is Map ? (other['mobile'] as String? ?? other['phone'] as String?) : null,
      isSeller: other is Map &&
          (other['is_seller'] == true ||
              other['store_slug'] != null ||
              (other['seller_profile'] is Map &&
                  ((other['seller_profile'] as Map)['slug'] as String?)?.trim().isNotEmpty == true)),
      isGroup: json['is_group'] == true,
      memberCount: (json['member_count'] as num?)?.toInt() ??
          (participants.isNotEmpty ? participants.length : null) ??
          (other is Map ? (other['member_count'] as num?)?.toInt() : null) ??
          0,
      createdBy: (json['created_by'] as num?)?.toInt(),
      participants: participants,
      canComplain: json['can_complain'] == true ||
          (json['buyer_id'] != null &&
              json['seller_id'] != null &&
              other is Map &&
              other['id'] == json['seller_id']),
      sellerId: (json['seller_id'] as num?)?.toInt() ??
          (other is Map && (other['is_seller'] == true || other['store_slug'] != null)
              ? (other['id'] as num?)?.toInt()
              : null),
      productId: product is Map ? product['id'] as int? : null,
      productName: product is Map ? product['name'] as String? : null,
      productSlug: product is Map ? (product['slug'] as String?)?.trim() : null,
      productImage: product is Map ? (product['image_url'] as String?)?.trim() : null,
      productPrice: product is Map ? (product['price'] as num?)?.toDouble() : null,
      latestBody: latest is Map ? latest['body'] as String? : null,
      latestType: latest is Map ? latest['type'] as String? : null,
      latestSenderId: latest is Map ? (latest['sender_id'] as num?)?.toInt() : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessageAt: json['last_message_at'] as String?,
      blocked: json['blocked'] == true,
      iBlocked: json['i_blocked'] == true,
      online: other is Map && other['online'] == true,
      lastSeenAt: other is Map ? other['last_seen_at'] as String? : null,
      onlineCount: other is Map
          ? ((other['online_count'] as num?)?.toInt() ?? (other['online'] == true ? 1 : 0))
          : 0,
    );
  }

  ConversationModel copyWith({
    bool? blocked,
    bool? iBlocked,
    int? productId,
    String? productName,
    String? productSlug,
    String? productImage,
    double? productPrice,
    String? latestBody,
    String? latestType,
    int? latestSenderId,
    String? lastMessageAt,
    int? unreadCount,
    String? otherAvatar,
    String? otherName,
    int? memberCount,
    List<ChatParticipant>? participants,
    int? createdBy,
    bool? online,
    String? lastSeenAt,
    int? onlineCount,
  }) {
    return ConversationModel(
      id: id,
      otherName: otherName ?? this.otherName,
      otherId: otherId,
      otherAvatar: otherAvatar ?? this.otherAvatar,
      storeName: storeName,
      storeSlug: storeSlug,
      otherMobile: otherMobile,
      isSeller: isSeller,
      isGroup: isGroup,
      memberCount: memberCount ?? this.memberCount,
      createdBy: createdBy ?? this.createdBy,
      participants: participants ?? this.participants,
      canComplain: canComplain,
      sellerId: sellerId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSlug: productSlug ?? this.productSlug,
      productImage: productImage ?? this.productImage,
      productPrice: productPrice ?? this.productPrice,
      latestBody: latestBody ?? this.latestBody,
      latestType: latestType ?? this.latestType,
      latestSenderId: latestSenderId ?? this.latestSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      blocked: blocked ?? this.blocked,
      iBlocked: iBlocked ?? this.iBlocked,
      online: online ?? this.online,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      onlineCount: onlineCount ?? this.onlineCount,
    );
  }
}

/// Product waiting for the buyer to tap Send in chat (not auto-posted).
class AttachProduct {
  const AttachProduct({
    required this.id,
    required this.name,
    required this.slug,
    this.price,
    this.imageUrl,
  });

  final int id;
  final String name;
  final String slug;
  final double? price;
  final String? imageUrl;

  factory AttachProduct.fromJson(Map<String, dynamic> json) {
    return AttachProduct(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? 'Product',
      slug: (json['slug'] as String? ?? '').trim(),
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: (json['image_url'] as String?)?.trim(),
    );
  }
}

/// Quoted message shown above a reply bubble (especially product cards).
class ChatReplyTo {
  const ChatReplyTo({
    required this.id,
    required this.body,
    required this.senderName,
    this.type,
    this.productId,
    this.productName,
    this.productSlug,
    this.productImage,
    this.productPrice,
  });

  final int id;
  final String body;
  final String senderName;
  final String? type;
  final int? productId;
  final String? productName;
  final String? productSlug;
  final String? productImage;
  final double? productPrice;

  bool get isProduct => type == 'product';

  factory ChatReplyTo.fromJson(Map<String, dynamic> json) {
    final productRaw = json['product'];
    final product = productRaw is Map ? Map<String, dynamic>.from(productRaw) : null;
    return ChatReplyTo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      body: json['body'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? 'User',
      type: json['type'] as String?,
      productId: product?['id'] is num ? (product!['id'] as num).toInt() : null,
      productName: product?['name'] as String?,
      productSlug: (product?['slug'] as String?)?.trim(),
      productImage: (product?['image_url'] as String?)?.trim(),
      productPrice: (product?['price'] as num?)?.toDouble(),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.mine,
    this.senderId,
    this.type = 'text',
    this.createdAt,
    this.imageUrl,
    this.videoUrl,
    this.voiceUrl,
    this.durationSeconds,
    this.metadata,
    this.callLog,
    this.productId,
    this.productName,
    this.productSlug,
    this.productImage,
    this.productPrice,
    this.transferAmount,
    this.transferCurrency,
    this.transferNote,
    this.transferReference,
    this.transferFromName,
    this.transferToName,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.replyTo,
    this.readAt,
    this.isDeleted = false,
    this.canDelete = false,
  });

  final int id;
  final String body;
  final bool mine;
  final int? senderId;
  final String type;
  final String? createdAt;
  final String? imageUrl;
  final String? videoUrl;
  final String? voiceUrl;
  final int? durationSeconds;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? callLog;
  final int? productId;
  final String? productName;
  final String? productSlug;
  final String? productImage;
  final double? productPrice;
  final double? transferAmount;
  final String? transferCurrency;
  final String? transferNote;
  final String? transferReference;
  final String? transferFromName;
  final String? transferToName;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;
  final ChatReplyTo? replyTo;
  final String? readAt;
  final bool isDeleted;
  final bool canDelete;

  /// Call setup rows share the message table but are not part of the chat.
  static const signallingTypes = {'call_offer', 'call_answer', 'call_ice', 'call_end'};

  bool get isSignalling => signallingTypes.contains(type);

  bool get isPhoto => type == 'image' && (imageUrl ?? '').isNotEmpty && !isDeleted;

  bool get isVideo => type == 'video' && (videoUrl ?? '').isNotEmpty && !isDeleted;

  bool get isVoice => type == 'voice' && (voiceUrl ?? '').isNotEmpty && !isDeleted;

  bool get isProduct => type == 'product' && !isDeleted;

  bool get isTransfer => type == 'transfer' && !isDeleted;

  bool get isFile => type == 'file' && (fileUrl ?? '').isNotEmpty && !isDeleted;

  bool get isMedia => isPhoto || isVideo || isVoice;

  bool get isEvent => type == 'call_log' || type == 'system';

  bool get isRead => readAt != null && readAt!.isNotEmpty;

  /// "Voice call · 1m 20s", "Call ended", "Missed call", ...
  String get eventLabel {
    if (type != 'call_log') return body.isEmpty ? 'Update' : body;

    final status = (callLog?['status'] as String? ?? '').toLowerCase();
    final seconds = (callLog?['duration_seconds'] as num?)?.toInt() ?? 0;
    final isVideo = (callLog?['call_kind'] as String?) == 'video';
    final kind = isVideo ? 'Video call' : 'Voice call';
    final missedKind = 'Missed ${isVideo ? 'video ' : ''}call';
    // `mine` ⇒ we are the sender of the log (= who ended / hung up).
    if (status == 'declined') return 'Call declined';
    if (status == 'cancelled') return mine ? 'Call ended' : missedKind;
    if (status == 'missed' || status == 'unanswered') {
      return mine ? 'No answer' : missedKind;
    }
    if (status == 'completed' && seconds <= 0) return 'Call ended';
    if (seconds <= 0) return kind;

    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    final duration = minutes > 0 ? '${minutes}m ${rest}s' : '${rest}s';
    return '$kind · $duration';
  }

  String get durationLabel {
    final seconds = durationSeconds ?? 0;
    if (seconds <= 0) return '';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return minutes > 0
        ? '$minutes:${rest.toString().padLeft(2, '0')}'
        : '0:${rest.toString().padLeft(2, '0')}';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, {required int myUserId}) {
    final meta = json['metadata'];
    final deleted = json['is_deleted'] == true ||
        (meta is Map && meta['deleted_at'] != null);
    String? media(String key) {
      if (deleted) return null;
      // Prefer top-level URL from formatMessage (rewritten for current APP_URL).
      final top = json[key] as String?;
      if (top != null && top.trim().isNotEmpty) return top;
      final fromMeta = meta is Map ? meta[key] as String? : null;
      return fromMeta;
    }

    final productRaw = deleted
        ? null
        : ((json['product'] is Map ? json['product'] : null) ??
            (meta is Map ? meta['product'] : null));
    final product = productRaw is Map ? Map<String, dynamic>.from(productRaw) : null;

    final transferRaw = deleted
        ? null
        : ((json['transfer'] is Map ? json['transfer'] : null) ??
            (meta is Map ? meta['transfer'] : null));
    final transfer = transferRaw is Map ? Map<String, dynamic>.from(transferRaw) : null;

    return ChatMessage(
      id: json['id'] as int,
      body: deleted ? '' : (json['body'] as String? ?? ''),
      mine: (json['sender_id'] as int?) == myUserId || json['is_mine'] == true,
      senderId: (json['sender_id'] as num?)?.toInt(),
      type: json['type'] as String? ?? 'text',
      createdAt: json['created_at'] as String?,
      imageUrl: media('image_url'),
      videoUrl: media('video_url'),
      voiceUrl: media('voice_url'),
      durationSeconds: () {
        final raw = (meta is Map ? meta['duration_seconds'] : null) ?? json['duration_seconds'];
        if (raw is num) return raw.toInt();
        if (raw is String) return int.tryParse(raw);
        return null;
      }(),
      metadata: meta is Map ? Map<String, dynamic>.from(meta) : null,
      callLog: () {
        final log = (meta is Map ? meta['call_log'] : null) ?? json['call_log'];
        return log is Map ? Map<String, dynamic>.from(log) : null;
      }(),
      productId: product?['id'] is num ? (product!['id'] as num).toInt() : null,
      productName: product?['name'] as String?,
      productSlug: (product?['slug'] as String?)?.trim(),
      productImage: (product?['image_url'] as String?)?.trim(),
      productPrice: (product?['price'] as num?)?.toDouble(),
      transferAmount: () {
        final raw = transfer?['amount'];
        if (raw is num) return raw.toDouble();
        if (raw is String) return double.tryParse(raw);
        return null;
      }(),
      transferCurrency: transfer?['currency'] as String? ?? 'GHS',
      transferNote: transfer?['note'] as String?,
      transferReference: transfer?['reference'] as String?,
      transferFromName: (transfer?['from_name'] as String?)?.trim(),
      transferToName: (transfer?['to_name'] as String?)?.trim(),
      fileUrl: media('file_url'),
      fileName: () {
        if (deleted) return null;
        final fromMeta = meta is Map ? meta['file_name'] as String? : null;
        return fromMeta ?? json['file_name'] as String?;
      }(),
      fileSize: () {
        if (deleted) return null;
        final raw = (meta is Map ? meta['file_size'] : null) ?? json['file_size'];
        if (raw is num) return raw.toInt();
        if (raw is String) return int.tryParse(raw);
        return null;
      }(),
      fileMime: () {
        if (deleted) return null;
        final fromMeta = meta is Map ? meta['file_mime'] as String? : null;
        return fromMeta ?? json['file_mime'] as String?;
      }(),
      replyTo: () {
        if (deleted) return null;
        final raw = (json['reply_to'] is Map ? json['reply_to'] : null) ??
            (meta is Map ? meta['reply_to'] : null);
        if (raw is! Map) return null;
        return ChatReplyTo.fromJson(Map<String, dynamic>.from(raw));
      }(),
      readAt: json['read_at'] as String?,
      isDeleted: deleted,
      canDelete: json['can_delete'] == true,
    );
  }

  ChatMessage copyWith({
    String? body,
    bool? isDeleted,
    bool? canDelete,
    String? imageUrl,
    String? readAt,
  }) {
    return ChatMessage(
      id: id,
      body: body ?? this.body,
      mine: mine,
      senderId: senderId,
      type: type,
      createdAt: createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl,
      voiceUrl: voiceUrl,
      durationSeconds: durationSeconds,
      metadata: metadata,
      callLog: callLog,
      productId: productId,
      productName: productName,
      productSlug: productSlug,
      productImage: productImage,
      productPrice: productPrice,
      transferAmount: transferAmount,
      transferCurrency: transferCurrency,
      transferNote: transferNote,
      transferReference: transferReference,
      transferFromName: transferFromName,
      transferToName: transferToName,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      fileMime: fileMime,
      replyTo: replyTo,
      readAt: readAt ?? this.readAt,
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

class FollowedSeller {
  const FollowedSeller({
    required this.id,
    required this.sellerId,
    required this.storeName,
    this.storeSlug,
    this.shopPhoto,
    this.rating,
    this.totalSales,
    this.followerCount = 0,
    this.followedAt,
  });

  final int id;
  final int sellerId;
  final String storeName;
  final String? storeSlug;
  final String? shopPhoto;
  final double? rating;
  final int? totalSales;
  final int followerCount;
  final DateTime? followedAt;

  factory FollowedSeller.fromJson(Map<String, dynamic> json) {
    final seller = json['seller'];
    final map = seller is Map ? Map<String, dynamic>.from(seller) : <String, dynamic>{};
    DateTime? followedAt;
    final raw = json['followed_at'];
    if (raw is String && raw.trim().isNotEmpty) {
      followedAt = DateTime.tryParse(raw);
    }

    return FollowedSeller(
      id: (json['id'] as num?)?.toInt() ?? 0,
      sellerId: (map['id'] as num?)?.toInt() ?? 0,
      storeName: map['store_name'] as String? ?? map['name'] as String? ?? 'Seller',
      storeSlug: map['store_slug'] as String?,
      shopPhoto: map['shop_photo'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      totalSales: (map['total_sales'] as num?)?.toInt(),
      followerCount: (map['follower_count'] as num?)?.toInt() ?? 0,
      followedAt: followedAt,
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
