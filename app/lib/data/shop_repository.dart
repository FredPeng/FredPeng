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
  Future<List<Category>> categories();

  Future<Cart> cart();
  Future<Cart> addToCart(int productId, int quantity, {Map<String, String> options = const {}});
  Future<Cart> updateItem(String key, int quantity);
  Future<Cart> removeItem(String key);
  Future<Cart> updateCustomer(Address address);
  Future<Cart> selectShippingRate(int packageId, String rateId);
  Future<Cart> applyCoupon(String code);
  Future<OrderResult> checkout(Address address, String paymentMethod, {String note = ''});
}
