import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/shell/xiai_shell.dart';
import 'services/trade_review_repository.dart';
import 'state/auth_state.dart';
import 'state/billing_state.dart';
import 'state/chat_state.dart';
import 'theme/app_theme.dart';

/// 嘻，AI：从成交记录里复盘交易逻辑、问题与改进措施。
class XiaiApp extends StatefulWidget {
  const XiaiApp({super.key});

  @override
  State<XiaiApp> createState() => _XiaiAppState();
}

class _XiaiAppState extends State<XiaiApp> {
  late final AuthState _auth = AuthState();
  late final BillingState _billing = BillingState();
  late final ChatState _chat = ChatState();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapStates());
  }

  Future<void> _bootstrapStates() async {
    await Future.wait<void>([
      _auth.bootstrap(),
      _chat.bootstrap(),
    ]);
    if (_auth.isAuthenticated) {
      await _billing.refreshAll();
    }
  }

  @override
  void dispose() {
    _auth.dispose();
    _billing.dispose();
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '嘻，AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      themeMode: ThemeMode.light,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthState>.value(value: _auth),
          ChangeNotifierProvider<BillingState>.value(value: _billing),
          ChangeNotifierProvider<ChatState>.value(value: _chat),
        ],
        child: const _XiaiRoot(),
      ),
    );
  }
}

class _XiaiRoot extends StatefulWidget {
  const _XiaiRoot();

  @override
  State<_XiaiRoot> createState() => _XiaiRootState();
}

class _XiaiRootState extends State<_XiaiRoot> {
  String? _boundAccount;
  bool _binding = false;
  Timer? _bindRetry;

  Future<void> _bindTradeReviews(AuthState auth) async {
    if (auth.bootstrapping || _binding) return;
    final account = auth.currentUser?.uuid;
    if (_boundAccount == account) return;
    _binding = true;
    try {
      final bound = await TradeReviewStore.instance.bindAccount(account);
      // 只有绑定流程真正走完才记住账号；异常或中途切换时下一帧会重试，
      // 不会把失败的绑定误认为已完成。
      if (!mounted) return;
      if (bound) {
        _bindRetry?.cancel();
        _boundAccount = account;
      } else if (auth.currentUser?.uuid == account) {
        _bindRetry?.cancel();
        _bindRetry = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() {});
        });
      }
    } catch (error, stack) {
      // 复盘绑定失败不应挡住 App；保留上次成功账号，让后续登录态变化触发重试。
      debugPrint('trade review account binding failed: $error\n$stack');
    } finally {
      _binding = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _bindRetry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.bootstrapping) {
      return Scaffold(backgroundColor: AppColors.bgSurface);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bindTradeReviews(auth));
    });
    return const XiaiShell();
  }
}
