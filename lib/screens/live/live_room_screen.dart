import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/live.dart';
import '../../state/live_state.dart';
import '../../theme/app_theme.dart';

/// LiveRoomScreen — 单个直播间页:
///
///   ┌──────────────────────────────┐
///   │ AppBar  返回 / 标题 / LIVE 红点 │
///   ├──────────────────────────────┤
///   │  📊 主图(K 线 webview)         │ 35% 屏高
///   │     聚焦哪只 = current_focus    │
///   ├──────────────────────────────┤
///   │  聊天消息流 ListView           │ 剩余空间
///   │  主持人/嘉宾轮流发言            │
///   │  新消息自动滚到底               │
///   └──────────────────────────────┘
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key, required this.roomUUID});

  final String roomUUID;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final ScrollController _scrollCtl = ScrollController();
  late final WebViewController _webCtl;

  // 当前 webview 加载的 symbol,用于避免重复 loadHtmlString
  String _loadedSymbol = '';

  @override
  void initState() {
    super.initState();
    _webCtl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0E0E10))
      ..loadHtmlString(_placeholderHtml);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LiveState>().enterRoom(widget.roomUUID);
    });
  }

  @override
  void dispose() {
    // leaveRoom 是异步的,但 dispose 不能 await;Provider 内部会处理。
    context.read<LiveState>().leaveRoom();
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveState>();

    _syncKlineWebView(s);
    _autoScrollOnNewMessage(s.messages.length);

    final room = s.currentRoom;
    return Scaffold(
      backgroundColor: AppColors.bgSurface,
      appBar: _buildAppBar(context, room, s),
      body: s.enteringRoom && s.messages.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                _buildKlineSection(s),
                Divider(height: 1, color: AppColors.borderDim),
                Expanded(child: _buildChatList(s)),
              ],
            ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, LiveRoom? room, LiveState s) {
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          Expanded(
            child: Text(
              room?.title ?? 'AI 直播间',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (room != null) _statusBadge(room.status),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '刷新主图',
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: s.currentFocusSymbol.isEmpty
              ? null
              : () => context.read<LiveState>().reloadKline(),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    bool blink = false;
    switch (status) {
      case 'live':
        color = const Color(0xFFef4444);
        label = 'LIVE';
        blink = true;
        break;
      case 'ended':
        color = const Color(0xFF16a34a);
        label = '已结束';
        break;
      case 'ended_abnormal':
        color = AppColors.textTertiary;
        label = '已中断';
        break;
      default:
        color = AppColors.textTertiary;
        label = status;
    }
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blink)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ── 顶部 K 线主图 ──────────────────────────────────────────────────

  Widget _buildKlineSection(LiveState s) {
    final h = MediaQuery.of(context).size.height * 0.35;
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Container(
            color: const Color(0xFF0E0E10),
            child: WebViewWidget(controller: _webCtl),
          ),
          if (s.loadingKline)
            const Positioned(
              top: 8,
              right: 8,
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.amber),
                ),
              ),
            ),
          if (s.currentFocusSymbol.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.show_chart,
                        color: AppColors.amber, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      '等待主持人选股…',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 焦点 symbol 变了就重新 loadHtmlString。
  void _syncKlineWebView(LiveState s) {
    final sym = s.currentFocusSymbol;
    if (sym.isEmpty) return;
    final html = s.currentKlineHtml;
    if (html == null || html.isEmpty) return;
    if (sym == _loadedSymbol) return;
    _loadedSymbol = sym;
    // 异步加载;不 await,不阻塞 build
    _webCtl.loadHtmlString(html);
  }

  // ── 聊天消息流 ──────────────────────────────────────────────────────

  Widget _buildChatList(LiveState s) {
    if (s.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            s.enteringRoom ? '正在接入直播间…' : '直播即将开始',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollCtl,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: s.messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _MessageBubble(message: s.messages[i]),
    );
  }

  int _lastLen = 0;
  void _autoScrollOnNewMessage(int len) {
    if (len <= _lastLen) {
      _lastLen = len;
      return;
    }
    _lastLen = len;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtl.hasClients) return;
      _scrollCtl.animateTo(
        _scrollCtl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // 占位 HTML(进入页面时立刻显示一个深色空白,避免 webview 默认白闪)
  static const _placeholderHtml = '''
<!doctype html><html><head><meta charset="utf-8"/>
<style>html,body{margin:0;background:#0E0E10;color:#666;font-family:-apple-system,sans-serif;
display:flex;align-items:center;justify-content:center;height:100vh;font-size:12px;}</style>
</head><body>主图加载中…</body></html>
''';
}

/// _MessageBubble — 单条消息气泡。
///
///   - 主持人:左侧橙色头像 + 「主持人 老韩」标签 + 浅橙色背景
///   - 嘉宾:左侧多色头像(按 persona id 哈希分色) + 名字 + 默认背景
///   - system:居中浅灰小字
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final LiveMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.bgRaised,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    final avatarColor = _avatarColorFor(message);
    final bubbleBg = message.isHost
        ? AppColors.amber.withValues(alpha: 0.10)
        : AppColors.bgRaised;
    final nameColor = message.isHost
        ? AppColors.amber
        : AppColors.textPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(name: message.personaName, color: avatarColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    message.personaName,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _roleBadge(message.role),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  if (message.focusSymbol.isNotEmpty)
                    Text(
                      message.focusName.isEmpty
                          ? message.focusSymbol
                          : message.focusName,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: bubbleBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _roleBadge(String role) {
    switch (role) {
      case 'host_open':
        return '开场';
      case 'host_ask':
        return '提问';
      case 'host_switch':
        return '切话题';
      case 'host_close':
        return '收尾';
      case 'guest_answer':
        return '应答';
      case 'guest_react':
        return '插话';
    }
    return '';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final char = name.isEmpty ? '?' : name.characters.first;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        char,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// 一组协调的"嘉宾"配色,主持人专用橙。
const _guestPalette = <Color>[
  Color(0xFF60A5FA), // blue
  Color(0xFF34D399), // green
  Color(0xFFA78BFA), // violet
  Color(0xFFF472B6), // pink
  Color(0xFFFBBF24), // amber
];

Color _avatarColorFor(LiveMessage m) {
  if (m.isHost) return AppColors.amber;
  // 用 persona id 字符 sum 模哈希,稳定到颜色
  final id = m.persona;
  var sum = 0;
  for (final c in id.codeUnits) {
    sum += c;
  }
  return _guestPalette[sum % _guestPalette.length];
}
