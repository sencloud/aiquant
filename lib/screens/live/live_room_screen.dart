import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

  // K 线页是否就绪(loadHtmlString 之后 onPageFinished 才能 runJavaScript)
  bool _kPageReady = false;

  // 已注入的 annotations 序号 — 等于 LiveState.annotationsSeq 就跳过
  int _lastAnnotSeq = -1;

  // K 线主图是否折叠(用户可手动收起,腾出更多聊天空间)
  bool _klineCollapsed = false;

  // 发言输入框
  final TextEditingController _composerCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _webCtl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0E0E10))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) return;
          _kPageReady = true;
          // 页面就绪 → 立刻把当前已积累的 annotations 推一次
          _injectAnnotationsNow();
        },
      ))
      ..loadHtmlString(_placeholderHtml, baseUrl: _kWebBaseUrl);
    _scrollCtl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LiveState>().enterRoom(widget.roomUUID);
    });
  }

  @override
  void dispose() {
    // leaveRoom 是异步的,但 dispose 不能 await;Provider 内部会处理。
    context.read<LiveState>().leaveRoom();
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    _composerCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveState>();

    _syncKlineWebView(s);
    _syncAnnotations(s);
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
                Expanded(child: Stack(children: [
                  _buildChatList(s),
                  if (_pendingNewCount > 0) _buildNewMessageBadge(),
                ])),
                if (s.canPost) _buildComposer(s),
              ],
            ),
    );
  }

  // ── 观众发言输入框(仅本人房间 + 直播中) ──────────────────────────

  Widget _buildComposer(LiveState s) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.bgRaised,
          border: Border(top: BorderSide(color: AppColors.borderDim)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composerCtl,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComposer(s),
                decoration: InputDecoration(
                  hintText: '参与讨论(每条 1 喜点)…',
                  hintStyle:
                      TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.bgSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.amber,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: s.posting ? null : () => _sendComposer(s),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: s.posting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.send, size: 18, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendComposer(LiveState s) async {
    final text = _composerCtl.text.trim();
    if (text.isEmpty || s.posting) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.postMessage(text);
      _composerCtl.clear();
      _userPinnedToBottom = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } catch (e) {
      final code = RegExp(r'LIVE\.[A-Z_]+').firstMatch(e.toString())?.group(0);
      if (code == 'LIVE.INSUFFICIENT_BALANCE') {
        messenger.showSnackBar(const SnackBar(
            content: Text('喜点不足,发言需要 1 喜点,请先到「我的」充值')));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text('发言失败:$e',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ));
      }
    }
  }

  Widget _buildNewMessageBadge() {
    return Positioned(
      bottom: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: AppColors.amber,
          borderRadius: BorderRadius.circular(20),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _jumpToBottom,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_downward,
                      size: 14, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    '$_pendingNewCount 条新消息',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _jumpToBottom() {
    if (!_scrollCtl.hasClients) return;
    _scrollCtl.animateTo(
      _scrollCtl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
    setState(() => _pendingNewCount = 0);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildKlineHeader(s),
        // 折叠时高度收为 0;展开时显示 webview。webview 始终保留在树里
        // (Offstage),避免折叠/展开反复重建 + 重新加载 K 线。
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: SizedBox(
            height: _klineCollapsed ? 0 : h,
            width: double.infinity,
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
          ),
        ),
      ],
    );
  }

  /// K 线标题栏:品种切换器(横向 chips)+ 折叠/展开按钮。
  /// 主图上方的品种切换 chip(含「跟随」)。
  Widget _klineSymbolChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.amber.withValues(alpha: 0.18)
              : AppColors.bgRaised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.amber : AppColors.borderDim,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.amber : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildKlineHeader(LiveState s) {
    final symbols = s.discussedSymbols;
    return Container(
      color: const Color(0xFF0E0E10),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      child: Row(
        children: [
          const Icon(Icons.candlestick_chart, color: AppColors.amber, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: symbols.isEmpty
                ? Text(
                    s.currentFocusName.isEmpty
                        ? (s.currentFocusSymbol.isEmpty
                            ? '主图 K 线'
                            : s.currentFocusSymbol)
                        : s.currentFocusName,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : SizedBox(
                    height: 26,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // index 0 = 「跟随」(回到直播当前焦点),其余为讨论过的品种。
                      itemCount: symbols.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final following = s.manualSymbolOverride.isEmpty;
                          return _klineSymbolChip(
                            label: '跟随',
                            selected: following,
                            onTap: () =>
                                context.read<LiveState>().selectSymbol('', ''),
                          );
                        }
                        final item = symbols[i - 1];
                        final selected = s.manualSymbolOverride.isNotEmpty &&
                            item.symbol == s.currentFocusSymbol;
                        return _klineSymbolChip(
                          label: item.name,
                          selected: selected,
                          onTap: () => context
                              .read<LiveState>()
                              .selectSymbol(item.symbol, item.name),
                        );
                      },
                    ),
                  ),
          ),
          IconButton(
            tooltip: _klineCollapsed ? '展开 K 线' : '折叠 K 线',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _klineCollapsed ? Icons.expand_more : Icons.expand_less,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _klineCollapsed = !_klineCollapsed),
          ),
        ],
      ),
    );
  }

  /// 焦点 symbol 变了就重新 loadHtmlString。
  ///
  /// baseUrl 关键:不传 baseUrl 时 iOS WKWebView 把页面当 about:blank,
  /// 外部 https:// script(ECharts CDN)会被 ATS / origin 策略屏蔽,
  /// 表现为 "ECharts 加载失败"。传一个真实 https 域名作为 baseUrl
  /// 让 webview 把页面当 https 页面,加载同/跨 https 资源正常。
  void _syncKlineWebView(LiveState s) {
    final sym = s.currentFocusSymbol;
    if (sym.isEmpty) return;
    final html = s.currentKlineHtml;
    if (html == null || html.isEmpty) return;
    if (sym == _loadedSymbol) return;
    _loadedSymbol = sym;
    // 切焦点:webview 重新加载 → 旧 chart 实例被销毁,需要等 onPageFinished
    // 再注入新焦点的 annotations。这里 reset 两个标志。
    _kPageReady = false;
    _lastAnnotSeq = -1;
    _webCtl.loadHtmlString(html, baseUrl: _kWebBaseUrl);
  }

  /// 嘉宾发言提到的支撑/压力/止损/目标位通过这里推给主图 ECharts。
  /// 用 annotationsSeq 做幂等:LiveState 那边变化时 seq++,这里只在变化时推。
  void _syncAnnotations(LiveState s) {
    if (!_kPageReady) return; // 页面没就绪先攒着,onPageFinished 会补推
    if (s.annotationsSeq == _lastAnnotSeq) return;
    _lastAnnotSeq = s.annotationsSeq;
    _injectAnnotationsNow();
  }

  /// 不查缓存直接把当前 LiveState.currentAnnotations 推一次给 webview。
  void _injectAnnotationsNow() {
    if (!mounted) return;
    final s = context.read<LiveState>();
    final list = s.currentAnnotations.map((a) => a.toWebJson()).toList();
    final jsArr = jsonEncode(list);
    // window.__setAnnotations 可能在页面还未完全 load 时不存在 → 用 && 保护
    _webCtl.runJavaScript(
        'window.__setAnnotations && window.__setAnnotations($jsArr);');
    _lastAnnotSeq = s.annotationsSeq;
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

  // ── 智能跟随滚动 ──────────────────────────────────────────────────
  //
  // 行为:
  //   * 用户贴近底部(distFromBottom < 100px)时 → 新消息自动滚到底
  //   * 用户已往上翻看历史 → 不打断;改为攒计数显示「↓ N 条新消息」浮按钮
  //   * 用户点浮按钮 → 跳到底部 + 清零计数
  //   * 用户主动滚到底 → 清零计数(_onScroll 监听)

  int _lastLen = 0;
  int _pendingNewCount = 0;
  bool _userPinnedToBottom = true; // 默认贴底

  static const double _kStickThreshold = 100.0;

  void _onScroll() {
    if (!_scrollCtl.hasClients) return;
    final pos = _scrollCtl.position;
    final dist = pos.maxScrollExtent - pos.pixels;
    final pinned = dist < _kStickThreshold;
    if (pinned != _userPinnedToBottom) {
      setState(() {
        _userPinnedToBottom = pinned;
        if (pinned) _pendingNewCount = 0; // 滚回底部自动清零
      });
    } else if (pinned && _pendingNewCount > 0) {
      setState(() => _pendingNewCount = 0);
    }
  }

  void _autoScrollOnNewMessage(int len) {
    final newCount = len - _lastLen;
    if (newCount <= 0) {
      _lastLen = len;
      return;
    }
    _lastLen = len;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtl.hasClients) return;
      if (_userPinnedToBottom) {
        _scrollCtl.animateTo(
          _scrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        setState(() => _pendingNewCount += newCount);
      }
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

// baseUrl for webview_flutter loadHtmlString:让 WKWebView 把 HTML 当 https 页面
// 处理,允许加载 https script(ECharts CDN)。具体域名不重要,只要是 https 即可。
const String _kWebBaseUrl = 'https://lib.baomitu.com/';

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

    const userColor = Color(0xFF38bdf8);
    final isUser = message.isUser;
    final avatarColor = isUser ? userColor : _avatarColorFor(message);
    final bubbleBg = isUser
        ? userColor.withValues(alpha: 0.12)
        : (message.isHost
            ? AppColors.amber.withValues(alpha: 0.10)
            : AppColors.bgRaised);
    final nameColor = isUser
        ? userColor
        : (message.isHost ? AppColors.amber : AppColors.textPrimary);

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
                  Flexible(
                    child: Text(
                      message.personaName,
                      style: TextStyle(
                        color: nameColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (isUser)
                    _miniTag('观众', userColor)
                  else
                    _aiRoleTag(context),
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
                child: MarkdownBody(
                  data: message.content,
                  shrinkWrap: true,
                  styleSheet: _chatMdStyle,
                  softLineBreak: true,
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
      case 'user':
        return '发言';
    }
    return '';
  }

  /// 「AI 虚拟角色」标签 + 信息图标,点击弹免责说明(规避侵权/法律风险)。
  Widget _aiRoleTag(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAiDisclaimer(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF8b5cf6).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AI 虚拟角色',
              style: TextStyle(
                color: Color(0xFFc4b5fd),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 2),
            Icon(Icons.info_outline, color: Color(0xFFc4b5fd), size: 10),
          ],
        ),
      ),
    );
  }

  Widget _miniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// AI 虚拟角色免责声明(规避侵权与投资建议法律风险)。
const String kAiPersonaDisclaimer =
    '本直播间所有发言均由 AI 生成的虚拟角色演绎。角色名称与风格仅为模拟,'
    '不代表任何真实人物的真实言论、观点或立场,与相关人物本人无关。'
    '全部内容由人工智能自动生成,仅供娱乐与学习参考,不构成任何投资建议,'
    '据此操作风险自负。';

void _showAiDisclaimer(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined,
                    color: Color(0xFFc4b5fd), size: 20),
                const SizedBox(width: 8),
                Text(
                  'AI 虚拟角色说明',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              kAiPersonaDisclaimer,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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

// 聊天 bubble 内的 markdown 样式表 — 与直播间深色 + 紧凑 bubble 协调。
final MarkdownStyleSheet _chatMdStyle = MarkdownStyleSheet(
  p: TextStyle(
    color: AppColors.textPrimary,
    fontSize: 13,
    height: 1.55,
  ),
  strong: TextStyle(
    color: AppColors.amber,
    fontWeight: FontWeight.w800,
    fontSize: 13,
  ),
  em: TextStyle(
    color: AppColors.textPrimary,
    fontStyle: FontStyle.italic,
    fontSize: 13,
  ),
  listBullet: TextStyle(color: AppColors.amber, fontSize: 13),
  blockquote: TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
    fontStyle: FontStyle.italic,
  ),
  blockquoteDecoration: BoxDecoration(
    color: AppColors.bgSurface,
    border: Border(
      left: BorderSide(color: AppColors.amber, width: 3),
    ),
  ),
  blockquotePadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
  listIndent: 18,
  // 禁用 h1-h3 大字号(prompt 已禁标题但留兜底:不让 # 把样式撑爆)
  h1: TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  ),
  h2: TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  ),
  h3: TextStyle(
    color: AppColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  ),
);

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
