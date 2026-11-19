import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'disk_cache.dart';

Future<DiskCache> openDiskCache() async {
  try {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/store_api');
    await dir.create(recursive: true);
    return _FileCache(dir);
  } catch (_) {
    return MemoryOnlyCache();
  }
}

class _FileCache implements DiskCache {
  _FileCache(this._dir);
  final Directory _dir;

  File _file(String key) => File('${_dir.path}/${cacheFileName(key)}');

  @override
  Future<String?> read(String key) async {
    try {
      final f = _file(key);
      if (!await f.exists()) return null;
      final s = await f.readAsString();
      // First line holds the key, guarding against hash collisions.
      final nl = s.indexOf('\n');
      if (nl < 0 || s.substring(0, nl) != key) return null;
      return s.substring(nl + 1);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final f = _file(key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString('$key\n$value', flush: false);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}
