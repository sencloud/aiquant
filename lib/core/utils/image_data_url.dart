import 'dart:convert';
import 'dart:typed_data';

/// data URL（`data:image/jpeg;base64,...`）→ 原始字节。
///
/// 聊天区在流式输出期间会频繁重建，这里带一层轻量缓存，避免对同一张图反复
/// base64 解码；条数很少，缓存超过上限就整体丢弃重来。
final Map<String, Uint8List> _cache = <String, Uint8List>{};

Uint8List decodeImageDataUrl(String dataUrl) {
  final cached = _cache[dataUrl];
  if (cached != null) return cached;

  final comma = dataUrl.indexOf(',');
  Uint8List bytes;
  try {
    bytes =
        comma < 0 ? Uint8List(0) : base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    bytes = Uint8List(0);
  }
  if (_cache.length > 32) _cache.clear();
  _cache[dataUrl] = bytes;
  return bytes;
}
