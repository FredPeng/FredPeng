import 'disk_cache_stub.dart' if (dart.library.io) 'disk_cache_io.dart' as impl;

/// Small file cache for API responses (app cache directory, so Android can
/// reclaim it under storage pressure). Not SharedPreferences: that file is
/// loaded in full at every app start, so large JSON there slows launch.
abstract class DiskCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);

  static Future<DiskCache> open() => impl.openDiskCache();
}

/// Stable FNV-1a hash for file names (String.hashCode is not stable).
String cacheFileName(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return '${h.toRadixString(16)}_${key.length}';
}

class MemoryOnlyCache implements DiskCache {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
}
