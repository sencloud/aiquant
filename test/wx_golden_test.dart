import 'dart:io';

import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/social/social_state.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/ding_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:fincept_app/wx/chat_list_tab.dart';
import 'package:fincept_app/wx/me_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'miniapp_fakes.dart';

/// 微信式外壳的两张金图（消息列表 / 我）。
///
/// 生成方式与仓库里其它金图一致（字体来自 STRATEGY_FONT_DIR）：
///   STRATEGY_FONT_DIR=/path/to/fonts flutter test --update-goldens test/wx_golden_test.dart
class _Authed extends AuthState {
  @override
  bool get isAuthenticated => true;
  @override
  UserPublic? get currentUser => UserPublic(
        uuid: 'u-12345678',
        nickname: '老周',
        status: 'active',
        creditBalance: 860,
        hasPhone: true,
        hasApple: false,
        createdAt: DateTime(2026, 3, 1),
      );
}

class _QuietBilling extends BillingState {
  @override
  int get balance => 86;
  @override
  bool get loadingBalance => false;
  @override
  Future<void> refreshAll() async {}
  @override
  Future<void> refreshBalance() async {}
  @override
  Future<int> restoreUnverifiedPurchases() async => 0;
}

class _QuietDing extends DingState {
  @override
  int get unreadCount => 2;
}

Widget _host(Widget child, ChatState chat, SocialState social) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider<AuthState>(create: (_) => _Authed()),
        ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
        ChangeNotifierProvider<DingState>(create: (_) => _QuietDing()),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider<SocialState>.value(value: social),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: Scaffold(
          backgroundColor: AppColors.bgBase,
          body: child,
        ),
      ),
    );

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '1.3.0',
        buildNumber: '1',
        buildSignature: '');
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    final dir = await Directory.systemTemp.createTemp('hive_wx_golden');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
    await loadGoldenFonts();
  });

  ChatState seeded() {
    final now = DateTime(2026, 10, 16, 9, 12);
    final a = ChatSession(id: 'a', title: '棕榈油短期怎么看')
      ..updatedAt = now
      ..messages.addAll([
        ChatMessage(role: 'user', content: '棕榈油短期怎么看？'),
        ChatMessage(role: 'assistant', content: '短期偏强震荡，高库存压着上方空间。'),
      ]);
    final b = ChatSession(id: 'b', title: '沪深300 资金流', personaId: 'quant')
      ..updatedAt = now.subtract(const Duration(days: 1))
      ..messages.addAll([
        ChatMessage(role: 'assistant', content: '北向今天净流入 18 亿。'),
      ]);
    return ChatState(store: MemoryChatSessionStore())
      ..debugSeed([a, b], activeId: 'a');
  }

  testWidgets('金图：微信式「我」页', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      const WxMeTab(),
      seeded(),
      SocialState(store: MemorySocialStore()),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/wx_me.png'));
  }, skip: !Platform.environment.containsKey('STRATEGY_FONT_DIR'));

  testWidgets('金图：会话列表（消息页）', (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      const WxChatListTab(),
      seeded(),
      SocialState(store: MemorySocialStore()),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/wx_chats.png'));
  }, skip: !Platform.environment.containsKey('STRATEGY_FONT_DIR'));
}
