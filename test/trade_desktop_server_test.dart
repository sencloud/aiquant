import 'dart:convert';
import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/services/trade_desktop_server.dart';
import 'package:fincept_app/services/trade_review_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late TradeDesktopServer server;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('xai-trade-server-test-');
    Hive.init(tempDir.path);
    await Hive.openBox(kBoxPrefs);
    await TradeReviewStore.instance.clear();
    server = TradeDesktopServer();
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('desktop handoff checks the pair code and saves a review', () async {
    final payload = jsonEncode({
      'broker_hint': '测试券商',
      'currency': 'CNY',
      'warnings': <String>[],
      'trades': [
        {
          'trade_date': '2026-11-01',
          'trade_time': '09:35:00',
          'symbol': '600519',
          'name': '贵州茅台',
          'side': 'buy',
          'quantity': 100,
          'price': 1500,
          'fee': 5,
          'source_index': 0,
        },
        {
          'trade_date': '2026-11-02',
          'trade_time': '14:10:00',
          'symbol': '600519',
          'name': '贵州茅台',
          'side': 'sell',
          'quantity': 100,
          'price': 1510,
          'fee': 5,
          'source_index': 1,
        },
      ],
    });
    final uri = Uri.parse(
      'http://127.0.0.1:${server.port}/api/trade-reviews',
    );

    final rejected = await _post(uri, payload, '000000');
    expect(rejected.statusCode, HttpStatus.unauthorized);
    expect(TradeReviewStore.instance.reports, isEmpty);

    final accepted = await _post(uri, payload, server.pairCode);
    expect(accepted.statusCode, HttpStatus.ok);
    final body = jsonDecode(accepted.body) as Map<String, dynamic>;
    final report = body['report'] as Map<String, dynamic>;
    expect(body['review_id'], isNotEmpty);
    expect(report['broker_hint'], '测试券商');
    expect((report['trades'] as List), hasLength(2));
    expect(
      (report['metrics'] as Map<String, dynamic>)['matched_sell_count'],
      1,
    );
    expect(TradeReviewStore.instance.reports.single.id, body['review_id']);
  });
}

Future<_HttpResult> _post(Uri uri, String payload, String pairCode) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('X-Pair-Code', pairCode);
    request.write(payload);
    final response = await request.close();
    return _HttpResult(
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

class _HttpResult {
  const _HttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
