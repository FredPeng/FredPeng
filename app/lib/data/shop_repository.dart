import '../models/address.dart';
import '../models/cart.dart';
import '../models/product.dart';

/// A user-facing error with a message that can be shown as-is.
class ShopException implements Exception {
  ShopException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Everything the UI needs from the shop backend.
abstract class ShopRepository {
  Future<ProductPage> products(ProductQuery query, {int page = 1, int perPage = 20});
  Future<Product> product(int id);
  Future<Product?> productBySlug(String slug);

  /// Categories; `parent: 0` returns only top-level ones (much faster on a
  /// store with hundreds of categories).
  Future<List<Category>> categories({int? parent});

  // Instant cached data (memory or disk) to show while the network loads.
  Future<ProductPage?> cachedProducts(ProductQuery query, {int perPage = 20}) async => null;
  Future<List<Category>?> cachedCategories({int? parent}) async => null;
  Future<Product?> cachedProduct(int id) async => null;

  Future<Cart> cart();
  Future<Cart> addToCart(int productId, int quantity, {Map<String, String> options = const {}});
  Future<Cart> updateItem(String key, int quantity);
  Future<Cart> removeItem(String key);
  Future<Cart> updateCustomer(Address address);
  Future<Cart> selectShippingRate(int packageId, String rateId);
  Future<Cart> applyCoupon(String code);
  Future<OrderResult> checkout(Address address, String paymentMethod, {String note = ''});
}
