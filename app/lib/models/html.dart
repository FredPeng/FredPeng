final _tag = RegExp(r'<[^>]*>');
final _br = RegExp(r'<\s*(br|/p|/li|/h\d|/div)\s*/?>', caseSensitive: false);
final _li = RegExp(r'<\s*li[^>]*>', caseSensitive: false);
final _numeric = RegExp(r'&#(x?[0-9a-fA-F]+);');
final _blankLines = RegExp(r'\n\s*\n\s*\n+');

const _named = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&nbsp;': ' ',
  '&ndash;': '–',
  '&mdash;': '—',
  '&hellip;': '…',
  '&rsquo;': '’',
  '&lsquo;': '‘',
  '&ldquo;': '“',
  '&rdquo;': '”',
  '&times;': '×',
};

/// Decodes HTML entities (WooCommerce returns names like "Tops &#8211; Red").
String decodeEntities(String s) {
  if (!s.contains('&')) return s;
  var out = s.replaceAllMapped(_numeric, (m) {
    final g = m.group(1)!;
    final code = g.startsWith('x') ? int.tryParse(g.substring(1), radix: 16) : int.tryParse(g);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  _named.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

/// Turns product description HTML into readable plain text.
String htmlToText(String html) {
  if (html.isEmpty) return '';
  var s = html.replaceAll('\r', '').replaceAll(_li, '• ').replaceAll(_br, '\n');
  s = s.replaceAll(_tag, '');
  s = decodeEntities(s);
  s = s.split('\n').map((l) => l.trim()).join('\n').replaceAll(_blankLines, '\n\n');
  return s.trim();
}
