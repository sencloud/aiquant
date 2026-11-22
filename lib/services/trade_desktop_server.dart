import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/trade_review.dart';
import 'trade_review_engine.dart';
import 'trade_review_repository.dart';

class TradeDesktopServer {
  TradeDesktopServer({
    TradeReviewEngine engine = const TradeReviewEngine(),
    TradeReviewStore? store,
    Random? random,
  })  : _engine = engine,
        _store = store ?? TradeReviewStore.instance,
        _random = random ?? Random.secure();

  static const _maxBodyBytes = 1024 * 1024;
  static const _maxTrades = 500;

  final TradeReviewEngine _engine;
  final TradeReviewStore _store;
  final Random _random;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  String _pairCode = '';
  List<String> _addresses = const ['127.0.0.1'];

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String get pairCode => _pairCode;
  List<String> get addresses => List.unmodifiable(_addresses);
  String? get primaryAddress => _addresses.isEmpty ? null : _addresses.first;
  String? get endpoint {
    final host = primaryAddress;
    final boundPort = port;
    if (host == null || boundPort == null) return null;
    return 'http://$host:$boundPort/api/trade-reviews';
  }

  Future<void> start() async {
    if (_server != null) return;
    _pairCode = _newPairCode();
    _addresses = await _lanAddresses();
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );
    _server = server;
    _subscription = server.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void rotatePairCode() {
    _pairCode = _newPairCode();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await _subscription?.cancel();
    _subscription = null;
    await server?.close(force: true);
  }

  String _newPairCode() => (100000 + _random.nextInt(900000)).toString();

  Future<List<String>> _lanAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final private = <String>[];
      final other = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final value = address.address;
          if (_isPrivateIpv4(value)) {
            private.add(value);
          } else {
            other.add(value);
          }
        }
      }
      final values = [...private, ...other];
      return values.isEmpty ? const ['127.0.0.1'] : values;
    } catch (_) {
      return const ['127.0.0.1'];
    }
  }

  static bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..contentType = ContentType.json;
    try {
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      if (request.uri.path != '/api/trade-reviews') {
        await _json(response, HttpStatus.notFound, {
          'code': 'NOT_FOUND',
          'message': '接口不存在。',
        });
        return;
      }
      if (request.method != 'POST') {
        response.headers.set('Allow', 'POST');
        await _json(response, HttpStatus.methodNotAllowed, {
          'code': 'METHOD_NOT_ALLOWED',
          'message': '只支持 POST 请求。',
        });
        return;
      }
      if (request.headers.value('X-Pair-Code') != _pairCode) {
        await _json(response, HttpStatus.unauthorized, {
          'code': 'PAIR_CODE_INVALID',
          'message': '配对码不正确，请在电脑端重新输入。',
        });
        return;
      }

      final body = await _readBody(request);
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        throw const FormatException('body must be an object');
      }
      final map = Map<String, dynamic>.from(decoded);
      final rows = map['trades'];
      if (rows is! List || rows.isEmpty) {
        await _json(response, HttpStatus.badRequest, {
          'code': 'TRADES_EMPTY',
          'message': '没有收到可分析的成交记录。',
        });
        return;
      }
      if (rows.length > _maxTrades) {
        await _json(response, HttpStatus.requestEntityTooLarge, {
          'code': 'TRADES_TOO_MANY',
          'message': '一次最多分析 500 笔成交。',
        });
        return;
      }

      final trades = <ParsedTrade>[];
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (row is! Map) {
          throw FormatException('第 ${index + 1} 笔成交格式无效');
        }
        trades.add(
          ParsedTrade.fromJson(
            Map<String, dynamic>.from(row),
          ).copyWith(sourceIndex: index),
        );
      }
      final warnings = [
        for (final row in (map['warnings'] as List? ?? const []))
          if (row != null) row.toString(),
      ];
      final report = _engine.analyze(
        trades: trades,
        brokerHint: (map['broker_hint'] ?? '电脑端').toString(),
        currency: (map['currency'] ?? 'CNY').toString(),
        parserWarnings: warnings,
      );
      await _store.save(report);
      await _json(response, HttpStatus.ok, {
        'review_id': report.id,
        'report': report.toJson(),
      });
    } on FormatException catch (error) {
      await _json(response, HttpStatus.badRequest, {
        'code': 'TRADES_INVALID',
        'message': '成交记录格式无效：${error.message}',
      });
    } on _BodyTooLarge {
      await _json(response, HttpStatus.requestEntityTooLarge, {
        'code': 'BODY_TOO_LARGE',
        'message': '请求超过 1MB，请减少成交行数。',
      });
    } catch (_) {
      await _json(response, HttpStatus.internalServerError, {
        'code': 'REVIEW_FAILED',
        'message': '生成复盘时遇到问题，请重试。',
      });
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The client may have disconnected while the report was generated.
      }
    }
  }

  Future<List<int>> _readBody(HttpRequest request) async {
    final declared = request.contentLength;
    if (declared > _maxBodyBytes) throw const _BodyTooLarge();
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBodyBytes) throw const _BodyTooLarge();
    }
    return bytes;
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = status;
    response.write(jsonEncode(body));
  }
}

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}
