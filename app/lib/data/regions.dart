import 'dart:convert';

import 'package:flutter/services.dart';

class County {
  const County(this.code, this.name, this.areas);
  final String code;
  final String name;

  /// Delivery areas (the website's "Area" dropdown). Empty = free text.
  final List<String> areas;
}

/// Counties (WooCommerce states KE01–KE47) and their areas.
///
/// `assets/ke_regions.json` is generated from the `wc_city_select_cities`
/// list in the website's functions.php by `tool/gen_ke_regions.py`, so the
/// app offers exactly the same choices as the website checkout.
class Regions {
  Regions._(this.counties);
  final List<County> counties;

  static const _allCounties = [
    'Baringo', 'Bomet', 'Bungoma', 'Busia', 'Elgeyo-Marakwet', 'Embu', 'Garissa', 'Homa Bay', //
    'Isiolo', 'Kajiado', 'Kakamega', 'Kericho', 'Kiambu', 'Kilifi', 'Kirinyaga', 'Kisii', //
    'Kisumu', 'Kitui', 'Kwale', 'Laikipia', 'Lamu', 'Machakos', 'Makueni', 'Mandera', //
    'Marsabit', 'Meru', 'Migori', 'Mombasa', "Murang'a", 'Nairobi', 'Nakuru', 'Nandi', //
    'Narok', 'Nyamira', 'Nyandarua', 'Nyeri', 'Samburu', 'Siaya', 'Taita-Taveta', 'Tana River', //
    'Tharaka-Nithi', 'Trans Nzoia', 'Turkana', 'Uasin Gishu', 'Vihiga', 'Wajir', 'West Pokot',
  ];

  static Future<Regions> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/ke_regions.json')) as List;
    final areas = <String, List<String>>{
      for (final c in raw) c['code'] as String: [for (final a in c['areas'] as List) '$a'],
    };
    final list = <County>[
      for (final (i, name) in _allCounties.indexed)
        County('KE${(i + 1).toString().padLeft(2, '0')}', name, areas['KE${(i + 1).toString().padLeft(2, '0')}'] ?? const []),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return Regions._(list);
  }

  County? byCode(String code) {
    for (final c in counties) {
      if (c.code == code) return c;
    }
    return null;
  }
}
