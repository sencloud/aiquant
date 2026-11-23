import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_client.dart';
import '../models/trade_review.dart';

enum TradeParseFailureKind {
  network,
  timeout,
  unauthorized,
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

  static const maxGalleryImages = 20;
  static const _maxWidth = 1800.0;
  static const _maxHeight = 3600.0;
  static const _quality = 88;

  Future<List<PickedTradeScreenshot>> fromGallery() async {
    try {
      final files = await _picker.pickMultiImage(
        maxWidth: _maxWidth,
        maxHeight: _maxHeight,
        imageQuality: _quality,
        limit: maxGalleryImages,
        requestFullMetadata: false,
      );
      if (files.isEmpty) return const [];
      if (files.length > maxGalleryImages) {
        throw const TradeParseException(
          TradeParseFailureKind.invalidRequest,
          '一次最多选择 $maxGalleryImages 张成交截图，请分批上传。',
        );
      }
      return [
        for (final file in files) await _read(file),
      ];
    } on TradeParseException {
      rethrow;
    } catch (error) {
      throw _pickerFailure(error);
    }
  }

  Future<PickedTradeScreenshot?> fromCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxWidth,
        maxHeight: _maxHeight,
        imageQuality: _quality,
      );
      if (file == null) return null;
      return await _read(file);
    } on TradeParseException {
      rethrow;
    } catch (error) {
      throw _pickerFailure(error);
    }
  }

  Future<PickedTradeScreenshot> _read(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        '有一张图片没有可读取的内容，请重新选择。',
      );
    }
    return PickedTradeScreenshot(
      bytes: bytes,
      mimeType: sniffImageMime(bytes, file.path),
    );
  }

  TradeParseException _pickerFailure(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('camera_access_denied') ||
        text.contains('photo_access_denied')) {
      return const TradeParseException(
        TradeParseFailureKind.cancelled,
        '没有获得相机或相册权限。请到系统设置中允许「嘻，AI」访问后重试。',
      );
    }
    return const TradeParseException(
      TradeParseFailureKind.invalidRequest,
      '无法读取所选截图，请重新选择清晰的成交记录截图。',
    );
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
  TradeScreenshotParser({
    Dio? dio,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 450),
  }) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;
  final int maxAttempts;
  final Duration retryDelay;

  static const defaultConcurrency = 1;

  /// 相册多选后逐张识别。视觉模型对突发并发很敏感，串行处理更稳定，
  /// 也能保证相邻截图去重时顺序确定。
  Future<ParsedTradesResult> parseBatch(
    List<PickedTradeScreenshot> screenshots, {
    int concurrency = defaultConcurrency,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (screenshots.isEmpty) {
      throw const TradeParseException(
        TradeParseFailureKind.noTrades,
        '还没有选择成交截图。',
      );
    }

    final total = screenshots.length;
    final results = List<ParsedTradesResult?>.filled(total, null);
    final failures = List<TradeParseException?>.filled(total, null);
    var nextIndex = 0;
    var completed = 0;
    var workerCount = concurrency < 1 ? 1 : concurrency;
    if (workerCount > total) workerCount = total;
    onProgress?.call(0, total);

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= total) return;
        try {
          final screenshot = screenshots[index];
          results[index] = await _parseWithRetry(
            imageBytes: screenshot.bytes,
            mimeType: screenshot.mimeType,
          );
        } catch (error) {
          failures[index] = error is TradeParseException
              ? error
              : const TradeParseException(
                  TradeParseFailureKind.server,
                  '识别服务遇到问题，请稍后重试。',
                );
        } finally {
          completed++;
          onProgress?.call(completed, total);
        }
      }
    }

    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    final successfulIndices = [
      for (var index = 0; index < results.length; index++)
        if (results[index] != null) index,
    ];
    final successful = [
      for (final index in successfulIndices) results[index]!,
    ];
    if (successful.isEmpty) {
      final firstFailure = failures.firstWhere((failure) => failure != null)!;
      final allNoTrades = failures
          .every((failure) => failure?.kind == TradeParseFailureKind.noTrades);
      throw TradeParseException(
        allNoTrades ? TradeParseFailureKind.noTrades : firstFailure.kind,
        total == 1
            ? firstFailure.message
            : '$total 张截图都没有识别成功。${firstFailure.message}',
      );
    }

    final emptyPageWarnings = <String>[
      for (var i = 0; i < results.length; i++)
        if (results[i] != null && results[i]!.trades.isEmpty)
          i == 0
              ? '第 1 张没有发现成交行，可能截取到了表头或空白区域。'
              : '第 ${i + 1} 张没有发现新的成交行，可能和上一张重叠。',
    ];
    final merged = mergeParsedTradeResults(
      successful,
      screenshotCount: total,
      sourceScreenshotIndices: successfulIndices,
      failureWarnings: [
        for (var i = 0; i < failures.length; i++)
          if (failures[i] case final failure?)
            '第 ${i + 1} 张没有读取成功：${failure.message}',
      ],
    );
    if (merged.trades.isEmpty) {
      throw TradeParseException(
        TradeParseFailureKind.noTrades,
        '$total 张截图都没有识别到成交行。请确认包含「成交记录」或'
            '「历史成交」列表，并保留日期、方向、数量、价格这几列。',
      );
    }
    return ParsedTradesResult(
      brokerHint: merged.brokerHint,
      currency: merged.currency,
      trades: merged.trades,
      warnings: [...emptyPageWarnings, ...merged.warnings],
      screenshotCount: merged.screenshotCount,
      successfulScreenshotCount: merged.successfulScreenshotCount,
      duplicateTradeCount: merged.duplicateTradeCount,
      rawTradeCount: merged.rawTradeCount,
      validTradeCount: merged.validTradeCount,
      invalidRowCount: merged.invalidRowCount,
      dateFilteredOutTradeCount: merged.dateFilteredOutTradeCount,
      importSource: merged.importSource,
      periodStart: merged.periodStart,
      periodEnd: merged.periodEnd,
    );
  }

  Future<ParsedTradesResult> _parseWithRetry({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await parse(imageBytes: imageBytes, mimeType: mimeType);
      } on TradeParseException catch (error) {
        final canRetry = _isRetryable(error.kind) && attempt < maxAttempts;
        if (!canRetry) {
          if (attempt > 1 && _isRetryable(error.kind)) {
            throw TradeParseException(
              error.kind,
              '${error.message} 已自动重试 ${attempt - 1} 次。',
            );
          }
          rethrow;
        }
        final multiplier = 1 << (attempt - 1);
        await Future<void>.delayed(retryDelay * multiplier);
      }
    }
  }

  bool _isRetryable(TradeParseFailureKind kind) => switch (kind) {
        TradeParseFailureKind.network ||
        TradeParseFailureKind.timeout ||
        TradeParseFailureKind.unavailable ||
        TradeParseFailureKind.server =>
          true,
        _ => false,
      };

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
    return switch (error.type) {
      DioExceptionType.cancel => const TradeParseException(
          TradeParseFailureKind.cancelled,
          '已取消识别。',
        ),
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        const TradeParseException(
          TradeParseFailureKind.timeout,
          '图片识别等待超时，可能是识别服务繁忙。请重试，或先裁掉截图里的空白区域。',
        ),
      DioExceptionType.badResponse => _responseFailure(
          error.response?.statusCode ?? 0,
          error.response?.data is Map
              ? Map<String, dynamic>.from(
                  error.response!.data as Map,
                )
              : null,
        ),
      DioExceptionType.badCertificate => const TradeParseException(
          TradeParseFailureKind.network,
          '安全连接校验失败，请检查系统时间或网络代理后重试。',
        ),
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        const TradeParseException(
          TradeParseFailureKind.network,
          '无法连接识别服务。请检查网络后重试，截图不会保存在服务器。',
        ),
    };
  }

  TradeParseException _responseFailure(
    int status,
    Map<String, dynamic>? data,
  ) {
    final code = (data?['code'] ?? '').toString();
    final serverMessage = (data?['message'] ?? '').toString().trim();
    if (status == 401 || status == 403) {
      return TradeParseException(
        TradeParseFailureKind.unauthorized,
        serverMessage.isNotEmpty ? serverMessage : '登录已过期，请重新登录后识别。',
      );
    }
    if (status == 429) {
      return const TradeParseException(
        TradeParseFailureKind.unavailable,
        '识别请求过于频繁，请稍等片刻再试。',
      );
    }
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
    if (serverMessage.isNotEmpty && status >= 500) {
      return TradeParseException(
        TradeParseFailureKind.server,
        '识别服务暂时出错：$serverMessage',
      );
    }
    return TradeParseException(
      TradeParseFailureKind.server,
      status > 0 ? '识别服务返回 HTTP $status，请稍后重试。' : '识别服务遇到问题，请稍后重试。',
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
