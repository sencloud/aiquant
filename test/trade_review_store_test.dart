import 'dart:async';
import 'dart:io';

import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/trade_review.dart';
import 'package:fincept_app/services/trade_review_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('trade-review-store-');
    Hive.init(tempDir.path);
    await Hive.openBox(kBoxPrefs);
  });

  setUp(() async {
    await prefsBox.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('切换账号时不会闪现或继承访客复盘', () async {
    final accountReports = Completer<List<TradeReviewReport>>();
    final store = TradeReviewStore.forTesting(
      cloudLoader: (account) =>
          account == 'account-a' ? accountReports.future : Future.value([]),
    );

    expect(await store.bindAccount(null), isTrue);
    await store.save(_report('guest-report'));
    expect(store.reports.map((item) => item.id), contains('guest-report'));

    final binding = store.bindAccount('account-a');
    expect(store.reports, isEmpty);

    accountReports.complete([_report('account-report')]);
    expect(await binding, isTrue);
    expect(store.reports.map((item) => item.id), ['account-report']);

    expect(await store.bindAccount(null), isTrue);
    expect(store.reports.map((item) => item.id), ['guest-report']);
  });

  test('账号绑定失败后可以直接重试', () async {
    var calls = 0;
    final store = TradeReviewStore.forTesting(
      cloudLoader: (account) async {
        calls++;
        if (calls == 1) {
          throw ApiException(
            code: 'TRADE_REVIEW.SYNC_FAILED',
            message: '暂时离线',
            statusCode: 0,
          );
        }
        return [_report('retry-report')];
      },
    );

    expect(await store.bindAccount('account-a'), isFalse);
    expect(store.syncError, '暂时离线');
    expect(store.reports, isEmpty);

    expect(await store.bindAccount('account-a'), isTrue);
    expect(calls, 2);
    expect(store.syncError, isNull);
    expect(store.reports.map((item) => item.id), ['retry-report']);
  });

  test('旧账号请求晚返回时不会覆盖新账号数据', () async {
    final accountA = Completer<List<TradeReviewReport>>();
    final store = TradeReviewStore.forTesting(
      cloudLoader: (account) => account == 'account-a'
          ? accountA.future
          : Future.value([
              _report('account-b-report'),
            ]),
    );

    final bindingA = store.bindAccount('account-a');
    await Future<void>.delayed(Duration.zero);
    expect(await store.bindAccount('account-b'), isTrue);

    accountA.complete([_report('late-account-a-report')]);
    expect(await bindingA, isFalse);
    expect(store.reports.map((item) => item.id), ['account-b-report']);
  });
}

TradeReviewReport _report(String id) {
  return TradeReviewReport.fromJson({
    'id': id,
    'created_at': '2026-11-22T09:30:00Z',
    'title': id,
    'broker_hint': '测试券商',
    'currency': 'CNY',
    'trades': <Object>[],
    'metrics': <String, Object>{},
    'logic': <Object>[],
    'problems': <Object>[],
    'improvements': <Object>[],
    'warnings': <Object>[],
  });
}
