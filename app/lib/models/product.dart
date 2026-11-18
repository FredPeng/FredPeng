import 'html.dart';
import 'money.dart';

class ProductImage {
  const ProductImage({required this.src, required this.thumbnail, this.alt = ''});

  final String src;
  final String thumbnail;
  final String alt;

  factory ProductImage.fromJson(Map<String, dynamic> j) {
    final src = (j['src'] as String?) ?? '';
    return ProductImage(
      src: src,
      thumbnail: (j['thumbnail'] as String?)?.isNotEmpty == true ? j['thumbnail'] as String : src,
      alt: (j['alt'] as String?) ?? '',
    );
  }
}

class CategoryRef {
  const CategoryRef({required this.id, required this.name, required this.slug});
  final int id;
  final String name;
  final String slug;

  factory CategoryRef.fromJson(Map<String, dynamic> j) => CategoryRef(
        id: (j['id'] as num).toInt(),
        name: decodeEntities((j['name'] as String?) ?? ''),
        slug: (j['slug'] as String?) ?? '',
      );
}

class AttributeTerm {
  const AttributeTerm({required this.name, required this.slug});
  final String name;
  final String slug;
}

class ProductAttribute {
  const ProductAttribute({
    required this.name,
    required this.taxonomy,
    required this.hasVariations,
    required this.terms,
  });

  final String name;
  final String taxonomy;
  final bool hasVariations;
  final List<AttributeTerm> terms;

  factory ProductAttribute.fromJson(Map<String, dynamic> j) => ProductAttribute(
        name: decodeEntities((j['name'] as String?) ?? ''),
        taxonomy: (j['taxonomy'] as String?) ?? '',
        hasVariations: (j['has_variations'] as bool?) ?? false,
        terms: [
          for (final t in (j['terms'] as List? ?? const []))
            AttributeTerm(
              name: decodeEntities((t['name'] as String?) ?? ''),
              slug: (t['slug'] as String?) ?? '',
            ),
        ],
      );

  /// Whether a variation's attribute entry refers to this attribute.
  bool matches(String attrName) {
    final a = attrName.toLowerCase();
    return a == name.toLowerCase() || (taxonomy.isNotEmpty && a == taxonomy.toLowerCase());
  }
}

class Variation {
  const Variation({required this.id, required this.attributes});
  final int id;

  /// attribute name -> term slug ('' means "any").
  final Map<String, String> attributes;

  factory Variation.fromJson(Map<String, dynamic> j) => Variation(
        id: (j['id'] as num).toInt(),
        attributes: {
          for (final a in (j['attributes'] as List? ?? const []))
            (a['name'] as String? ?? ''): (a['value'] as String? ?? ''),
        },
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.slug,
    required this.permalink,
    required this.type,
    required this.price,
    required this.regularPrice,
    this.minPrice,
    this.maxPrice,
    required this.images,
    required this.categories,
    required this.onSale,
    required this.inStock,
    required this.purchasable,
    required this.hasOptions,
    required this.attributes,
    required this.variations,
    this.shortDescription = '',
    this.description = '',
    this.sku = '',
    this.rating = 0,
    this.reviewCount = 0,
    this.maxQuantity,
  });

  final int id;
  final String name;
  final String slug;
  final String permalink;
  final String type;
  final Money price;
  final Money regularPrice;
  final Money? minPrice;
  final Money? maxPrice;
  final List<ProductImage> images;
  final List<CategoryRef> categories;
  final bool onSale;
  final bool inStock;
  final bool purchasable;
  final bool hasOptions;
  final List<ProductAttribute> attributes;
  final List<Variation> variations;
  final String shortDescription;
  final String description;
  final String sku;
  final double rating;
  final int reviewCount;
  final int? maxQuantity;

  bool get isVariable => type == 'variable' && variations.isNotEmpty;

  List<ProductAttribute> get variationAttributes =>
      attributes.where((a) => a.hasVariations && a.terms.isNotEmpty).toList();

  String? get thumbnail => images.isEmpty ? null : images.first.thumbnail;

  /// Discount percentage, e.g. 25 for 25% off.
  int get discountPercent {
    if (!onSale || regularPrice.minor <= 0 || price.minor >= regularPrice.minor) return 0;
    return (100 - price.minor * 100 / regularPrice.minor).round();
  }

  /// "KSh 500" or "KSh 500 – KSh 900" for variable products.
  String get displayPrice {
    if (minPrice != null && maxPrice != null && minPrice!.minor != maxPrice!.minor) {
      return '${minPrice!.format()} – ${maxPrice!.format()}';
    }
    return price.format();
  }

  /// Finds the variation matching the selected options (attribute name -> term slug).
  Variation? findVariation(Map<String, String> selected) {
    for (final v in variations) {
      var ok = true;
      for (final attr in variationAttributes) {
        final entry = v.attributes.entries.where((e) => attr.matches(e.key));
        final value = entry.isEmpty ? '' : entry.first.value;
        final chosen = selected[attr.name];
        if (chosen == null) {
          ok = false;
          break;
        }
        if (value.isNotEmpty && value.toLowerCase() != chosen.toLowerCase()) {
          ok = false;
          break;
        }
      }
      if (ok) return v;
    }
    return null;
  }

  factory Product.fromJson(Map<String, dynamic> j) {
    final prices = (j['prices'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cur = CurrencyInfo.fromJson(prices);
    final range = (prices['price_range'] as Map?)?.cast<String, dynamic>();
    final stock = j['add_to_cart'] is Map ? (j['add_to_cart'] as Map)['maximum'] : null;
    return Product(
      id: (j['id'] as num).toInt(),
      name: decodeEntities((j['name'] as String?) ?? ''),
      slug: (j['slug'] as String?) ?? '',
      permalink: (j['permalink'] as String?) ?? '',
      type: (j['type'] as String?) ?? 'simple',
      price: Money.parse(prices['price'], cur),
      regularPrice: Money.parse(prices['regular_price'], cur),
      minPrice: range == null ? null : Money.parse(range['min_amount'], cur),
      maxPrice: range == null ? null : Money.parse(range['max_amount'], cur),
      images: [
        for (final i in (j['images'] as List? ?? const []))
          ProductImage.fromJson((i as Map).cast<String, dynamic>()),
      ],
      categories: [
        for (final c in (j['categories'] as List? ?? const []))
          CategoryRef.fromJson((c as Map).cast<String, dynamic>()),
      ],
      onSale: (j['on_sale'] as bool?) ?? false,
      inStock: (j['is_in_stock'] as bool?) ?? true,
      purchasable: (j['is_purchasable'] as bool?) ?? true,
      hasOptions: (j['has_options'] as bool?) ?? false,
      attributes: [
        for (final a in (j['attributes'] as List? ?? const []))
          ProductAttribute.fromJson((a as Map).cast<String, dynamic>()),
      ],
      variations: [
        for (final v in (j['variations'] as List? ?? const []))
          Variation.fromJson((v as Map).cast<String, dynamic>()),
      ],
      shortDescription: htmlToText((j['short_description'] as String?) ?? ''),
      description: htmlToText((j['description'] as String?) ?? ''),
      sku: (j['sku'] as String?) ?? '',
      rating: double.tryParse('${j['average_rating'] ?? 0}') ?? 0,
      reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
      maxQuantity: stock is num ? stock.toInt() : null,
    );
  }
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.parent,
    required this.count,
    this.image,
  });

  final int id;
  final String name;
  final String slug;
  final int parent;
  final int count;
  final String? image;

  factory Category.fromJson(Map<String, dynamic> j) {
    final img = j['image'];
    String? src;
    if (img is Map) src = (img['thumbnail'] as String?) ?? (img['src'] as String?);
    return Category(
      id: (j['id'] as num).toInt(),
      name: decodeEntities((j['name'] as String?) ?? ''),
      slug: (j['slug'] as String?) ?? '',
      parent: (j['parent'] as num?)?.toInt() ?? 0,
      count: (j['count'] as num?)?.toInt() ?? 0,
      image: (src == null || src.isEmpty) ? null : src,
    );
  }
}

enum ProductSort {
  popular('popularity', 'desc', 'Popular'),
  newest('date', 'desc', 'Newest'),
  priceLow('price', 'asc', 'Price: low to high'),
  priceHigh('price', 'desc', 'Price: high to low');

  const ProductSort(this.orderBy, this.order, this.label);
  final String orderBy;
  final String order;
  final String label;
}

class ProductQuery {
  const ProductQuery({
    this.categoryId,
    this.search,
    this.onSale = false,
    this.featured = false,
    this.sort = ProductSort.popular,
    this.include,
  });

  final int? categoryId;
  final String? search;
  final bool onSale;
  final bool featured;
  final ProductSort sort;
  final List<int>? include;
}

class ProductPage {
  const ProductPage(this.items, this.totalPages);
  final List<Product> items;
  final int totalPages;
}
