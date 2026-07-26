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
    this.rating = 0,
    this.reviewCount = 0,
    this.inGhana = false,
    this.freeShipping = false,
    this.images = const [],
    this.categoryName,
    this.categoryId,
    this.storeName,
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
  final double rating;
  final int reviewCount;
  final bool inGhana;
  final bool freeShipping;
  final List<ProductImage> images;
  final String? categoryName;
  final int? categoryId;
  final String? storeName;
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
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      inGhana: json['in_ghana'] as bool? ?? false,
      freeShipping: json['free_shipping'] as bool? ?? false,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      images: imagesJson is List
          ? imagesJson
              .whereType<Map>()
              .map((e) => ProductImage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      categoryName: category is Map ? category['name'] as String? : null,
      categoryId: category is Map ? category['id'] as int? : null,
      storeName: seller is Map
          ? (seller['store_name'] as String? ?? seller['name'] as String?)
          : null,
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
  });

  final int id;
  final String name;
  final String email;
  final String? mobile;
  final String? role;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      mobile: json['mobile'] as String?,
      role: json['role'] as String?,
    );
  }
}
