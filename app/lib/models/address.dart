import '../config.dart';

/// Checkout details. Fields mirror the website checkout (functions.php):
/// first/last name, County (state), Area (city), address, phone, optional
/// email; no postcode, company or address line 2.
class Address {
  const Address({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.email = '',
    this.county = '',
    this.area = '',
    this.address = '',
  });

  final String firstName;
  final String lastName;
  final String phone;
  final String email;

  /// WooCommerce state code, e.g. KE30 (Nairobi).
  final String county;
  final String area;
  final String address;

  bool get isComplete =>
      firstName.isNotEmpty && lastName.isNotEmpty && phone.isNotEmpty && county.isNotEmpty && area.isNotEmpty && address.isNotEmpty;

  Map<String, dynamic> toStoreApi({bool billing = true}) => {
        'first_name': firstName,
        'last_name': lastName,
        'company': '',
        'address_1': address,
        'address_2': '',
        'city': area,
        'state': county,
        'postcode': '',
        'country': AppConfig.country,
        'phone': phone,
        if (billing) 'email': email,
      };

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'email': email,
        'county': county,
        'area': area,
        'address': address,
      };

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        firstName: (j['firstName'] as String?) ?? '',
        lastName: (j['lastName'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        county: (j['county'] as String?) ?? '',
        area: (j['area'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
      );
}

/// An order placed from this device, kept locally for "My orders".
class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.date,
    required this.total,
    required this.summary,
    required this.paymentMethod,
  });

  final int id;
  final DateTime date;
  final String total;
  final String summary;
  final String paymentMethod;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'total': total,
        'summary': summary,
        'paymentMethod': paymentMethod,
      };

  factory OrderRecord.fromJson(Map<String, dynamic> j) => OrderRecord(
        id: (j['id'] as num).toInt(),
        date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
        total: '${j['total']}',
        summary: '${j['summary']}',
        paymentMethod: '${j['paymentMethod']}',
      );
}
