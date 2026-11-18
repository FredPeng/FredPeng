/// Currency formatting info as returned by the WooCommerce Store API.
class CurrencyInfo {
  const CurrencyInfo({
    this.code = 'KES',
    this.minorUnit = 2,
    this.prefix = 'KSh ',
    this.suffix = '',
    this.thousandSeparator = ',',
    this.decimalSeparator = '.',
  });

  final String code;
  final int minorUnit;
  final String prefix;
  final String suffix;
  final String thousandSeparator;
  final String decimalSeparator;

  static const kes = CurrencyInfo();

  factory CurrencyInfo.fromJson(Map<String, dynamic> j) => CurrencyInfo(
        code: (j['currency_code'] as String?) ?? 'KES',
        minorUnit: (j['currency_minor_unit'] as num?)?.toInt() ?? 2,
        prefix: _decode((j['currency_prefix'] as String?) ?? ''),
        suffix: _decode((j['currency_suffix'] as String?) ?? ''),
        thousandSeparator: (j['currency_thousand_separator'] as String?) ?? ',',
        decimalSeparator: (j['currency_decimal_separator'] as String?) ?? '.',
      );

  Map<String, dynamic> toJson() => {
        'currency_code': code,
        'currency_minor_unit': minorUnit,
        'currency_prefix': prefix,
        'currency_suffix': suffix,
        'currency_thousand_separator': thousandSeparator,
        'currency_decimal_separator': decimalSeparator,
      };

  static String _decode(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#36;', r'$')
      .replaceAll('&amp;', '&');
}

/// An amount stored in minor units (e.g. cents), like the Store API.
class Money implements Comparable<Money> {
  const Money(this.minor, [this.currency = CurrencyInfo.kes]);

  final int minor;
  final CurrencyInfo currency;

  static Money parse(Object? raw, CurrencyInfo currency) {
    final v = raw == null ? 0 : int.tryParse(raw.toString()) ?? 0;
    return Money(v, currency);
  }

  bool get isZero => minor == 0;

  double get value {
    var d = minor.toDouble();
    for (var i = 0; i < currency.minorUnit; i++) {
      d /= 10;
    }
    return d;
  }

  Money operator +(Money o) => Money(minor + o.minor, currency);
  Money operator *(int n) => Money(minor * n, currency);

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  /// "KSh 1,250" — decimals are hidden when they are zero, to keep it clean.
  String format() {
    final unit = currency.minorUnit;
    var div = 1;
    for (var i = 0; i < unit; i++) {
      div *= 10;
    }
    final negative = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ div;
    final frac = abs % div;
    final wholeStr = whole.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => currency.thousandSeparator,
        );
    final fracStr = frac == 0 || unit == 0
        ? ''
        : '${currency.decimalSeparator}${frac.toString().padLeft(unit, '0')}';
    return '${negative ? '-' : ''}${currency.prefix}$wholeStr$fracStr${currency.suffix}';
  }

  @override
  String toString() => format();
}
