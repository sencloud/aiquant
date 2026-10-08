import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 聊天图片附件：选图 → 压缩 → `data:image/...;base64,...`。
///
/// 走 image_picker 自带的 maxWidth/imageQuality，在系统侧就把长边压到 1600px、
/// 质量 80 的 JPEG，避免把相册原图（动辄 5–10MB）塞进 SSE 请求体。
class ImageAttachService {
  ImageAttachService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 与服务端 chat.MaxImagesPerMessage 对齐，单条消息最多几张图。
  static const int maxImages = 4;
  static const double _maxEdge = 1600;
  static const int _quality = 80;

  /// 从相册选择（可多选，最多 [maxImages] 张）。取消返回空列表。
  Future<List<String>> pickFromGallery() async {
    final files = await _picker.pickMultiImage(
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
    );
    if (files.isEmpty) return const [];
    return _encode(files.take(maxImages).toList());
  }

  /// 拍照（适合拍屏幕 / 纸质材料）。取消返回空列表。
  Future<List<String>> pickFromCamera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
    );
    if (file == null) return const [];
    return _encode([file]);
  }

  Future<List<String>> _encode(List<XFile> files) async {
    final out = <String>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) continue;
      out.add('data:${_sniffMime(bytes, f.path)};base64,${base64Encode(bytes)}');
    }
    return out;
  }

  /// 按文件头判断真实类型：iOS 相册常给出 .heic 路径，但设置了 imageQuality
  /// 后插件实际已转成 JPEG；凭扩展名会给出错误的 mime，导致服务端/模型拒收。
  static String _sniffMime(Uint8List b, String path) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[8] == 0x57 && // 'W'
        b[9] == 0x45 && // 'E'
        b[10] == 0x42 && // 'B'
        b[11] == 0x50) {
      return 'image/webp';
    }
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
