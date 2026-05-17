import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/chat.dart';
import '../../models/ding.dart';
import '../../models/portfolio.dart';

const kBoxPortfolios = 'portfolios';
const kBoxTransactions = 'transactions';
const kBoxChatSessions = 'chat_sessions';
const kBoxDingTasks = 'ding_tasks';
const kBoxDingMessages = 'ding_messages';
const kBoxPrefs = 'app_prefs';

bool _registered = false;

Future<void> registerHiveAdapters() async {
  if (_registered) return;
  Hive.registerAdapter(PortfolioAdapter());
  Hive.registerAdapter(PortfolioTransactionAdapter());
  Hive.registerAdapter(ToolCallAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(ChatSessionAdapter());
  Hive.registerAdapter(DingTaskAdapter());
  Hive.registerAdapter(DingMessageAdapter());
  _registered = true;
}

Future<void> openAppBoxes() async {
  await Future.wait<void>([
    Hive.openBox<Portfolio>(kBoxPortfolios),
    Hive.openBox<PortfolioTransaction>(kBoxTransactions),
    Hive.openBox<ChatSession>(kBoxChatSessions),
    Hive.openBox<DingTask>(kBoxDingTasks),
    Hive.openBox<DingMessage>(kBoxDingMessages),
    Hive.openBox(kBoxPrefs),
  ]);
}

Box<Portfolio> get portfoliosBox => Hive.box<Portfolio>(kBoxPortfolios);
Box<PortfolioTransaction> get transactionsBox =>
    Hive.box<PortfolioTransaction>(kBoxTransactions);
Box<ChatSession> get chatSessionsBox =>
    Hive.box<ChatSession>(kBoxChatSessions);
Box<DingTask> get dingTasksBox => Hive.box<DingTask>(kBoxDingTasks);
Box<DingMessage> get dingMessagesBox =>
    Hive.box<DingMessage>(kBoxDingMessages);
Box get prefsBox => Hive.box(kBoxPrefs);
