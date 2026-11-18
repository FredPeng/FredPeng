import 'package:flutter_test/flutter_test.dart';
import 'package:sophie_shop/models/html.dart';
import 'package:sophie_shop/models/money.dart';
import 'package:sophie_shop/models/product.dart';

void main() {
  test('money formats KES without trailing zero decimals', () {
    expect(const Money(125000).format(), 'KSh 1,250');
    expect(const Money(125050).format(), 'KSh 1,250.50');
    expect(const Money(0).format(), 'KSh 0');
  });

  test('decodes WooCommerce entities and HTML', () {
    expect(decodeEntities('Tops &#8211; Red &amp; Blue'), 'Tops – Red & Blue');
    expect(htmlToText('<p>Soft cotton.</p><ul><li>Machine wash</li></ul>'), 'Soft cotton.\n• Machine wash');
  });

  test('parses a Store API variable product and matches variations', () {
    final p = Product.fromJson({
      'id': 10,
      'name': 'Dress',
      'type': 'variable',
      'prices': {
        'price': '250000',
        'regular_price': '300000',
        'currency_code': 'KES',
        'currency_minor_unit': 2,
        'currency_prefix': 'KSh&nbsp;',
        'price_range': {'min_amount': '250000', 'max_amount': '280000'},
      },
      'on_sale': true,
      'images': [
        {'src': 'https://x/a.jpg', 'thumbnail': 'https://x/a-300.jpg'},
      ],
      'attributes': [
        {
          'name': 'Size',
          'taxonomy': 'pa_size',
          'has_variations': true,
          'terms': [
            {'name': 'M', 'slug': 'm'},
            {'name': 'L', 'slug': 'l'},
          ],
        },
      ],
      'variations': [
        {'id': 11, 'attributes': [{'name': 'Size', 'value': 'm'}]},
        {'id': 12, 'attributes': [{'name': 'Size', 'value': 'l'}]},
      ],
    });
    expect(p.isVariable, isTrue);
    expect(p.displayPrice, 'KSh 2,500 – KSh 2,800');
    expect(p.discountPercent, 17);
    expect(p.findVariation({'Size': 'l'})?.id, 12);
    expect(p.findVariation({}), isNull);
    expect(p.thumbnail, 'https://x/a-300.jpg');
  });
}
