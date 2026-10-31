import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/chat.dart';
import '../../models/portfolio.dart';

const kBoxPortfolios = 'portfolios';
const kBoxTransactions = 'transactions';
const kBoxChatSessions = 'chat_sessions';
const kBoxPrefs = 'app_prefs';

bool _registered = false;

Future<void> registerHiveAdapters() async {
  if (_registered) return;
  Hive.registerAdapter(PortfolioAdapter());
  Hive.registerAdapter(PortfolioTransactionAdapter());
  Hive.registerAdapter(ToolCallAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(ChatSessionAdapter());
  _registered = true;
}

Future<void> openAppBoxes() async {
  await Future.wait<void>([
    Hive.openBox<Portfolio>(kBoxPortfolios),
    Hive.openBox<PortfolioTransaction>(kBoxTransactions),
    Hive.openBox<ChatSession>(kBoxChatSessions),
    Hive.openBox(kBoxPrefs),
  ]);
}

/// 行情首页只需要本机偏好，不启动聊天、组合等旧业务的数据表。
Future<void> openMarketBox() async {
  await Hive.openBox(kBoxPrefs);
}

Box<Portfolio> get portfoliosBox => Hive.box<Portfolio>(kBoxPortfolios);
Box<PortfolioTransaction> get transactionsBox =>
    Hive.box<PortfolioTransaction>(kBoxTransactions);
Box<ChatSession> get chatSessionsBox => Hive.box<ChatSession>(kBoxChatSessions);
Box get prefsBox => Hive.box(kBoxPrefs);
