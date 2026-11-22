import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_client.dart';
import '../models/trade_review.dart';

enum TradeParseFailureKind {
  network,
  unavailable,
  noTrades,
  invalidRequest,
  server,
  cancelled,
}

class TradeParseException implements Exception {
  const TradeParseException(this.kind, this.message);

  final TradeParseFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class TradeScreenshotPicker {
  TradeScreenshotPicker({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _maxWidth = 1800.0;
  static const _maxHeight = 3600.0;
  static const _quality = 92;

  Future<PickedTradeScreenshot?> fromGallery() => _pick(ImageSource.gallery);

  Future<PickedTradeScreenshot?> fromCamera() => _pick(ImageSource.camera);

  Future<PickedTradeScreenshot?> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: _maxWidth,
        maxHeight: _maxHeight,
        imageQuality: _quality,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const TradeParseException(
          TradeParseFailureKind.invalidRequest,
          '这张图片没有可读取的内容，请重新选择。',
        );
      }
      return PickedTradeScreenshot(
        bytes: bytes,
        mimeType: sniffImageMime(bytes, file.path),
      );
    } on TradeParseException {
      rethrow;
    } catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('camera_access_denied') ||
          text.contains('photo_access_denied')) {
        throw const TradeParseException(
          TradeParseFailureKind.cancelled,
          '没有获得相机或相册权限。请到系统设置中允许「嘻，AI」访问后重试。',
        );
      }
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        '无法读取这张图片，请重新选择一张清晰的成交记录截图。',
      );
    }
  }
}

class PickedTradeScreenshot {
  const PickedTradeScreenshot({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

class TradeScreenshotParser {
  TradeScreenshotParser({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  Future<ParsedTradesResult> parse({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    late Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/v1/portfolio/parse-trades',
        data: {
          'image_base64': base64Encode(imageBytes),
          'mime_type': mimeType,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
    } on DioException catch (error) {
      throw _networkFailure(error);
    }

    final data = response.data;
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300 || data == null) {
      throw _responseFailure(status, data);
    }

    try {
      final trades = [
        for (final row in (data['trades'] as List? ?? const []))
          if (row is Map) ParsedTrade.fromJson(Map<String, dynamic>.from(row)),
      ];
      if (trades.isEmpty) {
        throw const TradeParseException(
          TradeParseFailureKind.noTrades,
          '没有找到可确认的成交行，请换一张清晰的成交记录截图。',
        );
      }
      return ParsedTradesResult(
        brokerHint: (data['broker_hint'] ?? '').toString().trim(),
        currency: (data['currency'] ?? 'CNY').toString().trim(),
        trades: trades,
        warnings: [
          for (final row in (data['warnings'] as List? ?? const []))
            if (row != null) row.toString(),
        ],
      );
    } on TradeParseException {
      rethrow;
    } catch (_) {
      throw const TradeParseException(
        TradeParseFailureKind.server,
        '识别结果格式不完整，请重新上传一次。',
      );
    }
  }

  TradeParseException _networkFailure(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const TradeParseException(
        TradeParseFailureKind.cancelled,
        '已取消识别。',
      );
    }
    return const TradeParseException(
      TradeParseFailureKind.network,
      '网络连接失败。请检查网络后重试，截图不会保存在服务器。',
    );
  }

  TradeParseException _responseFailure(
    int status,
    Map<String, dynamic>? data,
  ) {
    final code = (data?['code'] ?? '').toString();
    final serverMessage = (data?['message'] ?? '').toString().trim();
    if (code == 'PORTFOLIO.VISION_UNAVAILABLE' || status == 503) {
      return const TradeParseException(
        TradeParseFailureKind.unavailable,
        '图片识别服务暂时不可用，请稍后再试。',
      );
    }
    if (code == 'PORTFOLIO.NO_TRADES' || code == 'PORTFOLIO.NO_HOLDINGS') {
      return const TradeParseException(
        TradeParseFailureKind.noTrades,
        '截图里没有识别到成交行。请确认这是「成交记录」或「历史成交」页面。',
      );
    }
    if (status == 413) {
      return const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        '截图体积过大，请裁剪到只保留成交记录后重试。',
      );
    }
    if (status >= 400 && status < 500) {
      return TradeParseException(
        TradeParseFailureKind.invalidRequest,
        serverMessage.isNotEmpty ? serverMessage : '这张截图无法识别，请换一张重试。',
      );
    }
    return const TradeParseException(
      TradeParseFailureKind.server,
      '识别服务遇到问题，请稍后重试。',
    );
  }
}

String sniffImageMime(List<int> bytes, String path) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
