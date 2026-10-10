import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../services/analytics.dart';
import '../../core/format/credit_fmt.dart';
import '../../core/utils/image_data_url.dart';
import '../../models/chat.dart';
import '../../models/persona.dart';
import '../../models/strategy.dart';
import '../../services/image_attach_service.dart';
import '../../services/market_briefing.dart';
import '../../state/auth_state.dart';
import '../../state/chat_state.dart';
import '../../state/portfolio_state.dart';
import '../../theme/app_theme.dart';
import '../ding/widgets/ding_task_editor.dart';
import '../settings/settings_screen.dart';
import 'widgets/message_bubble.dart';
import 'widgets/persona_picker.dart';
import 'widgets/session_drawer.dart';
// 「策略之王」入口暂时隐藏（代码保留）；恢复时取消下一行注释即可。
// import 'widgets/strategy_picker.dart';

/// AssistantScreen 的入参。
///
/// 跨 Tab 跳转（组合 → 助理）时，可通过 `Navigator.push(MaterialPageRoute(
///   settings: const RouteSettings(arguments: AssistantLaunch(...)), ...))`
/// 携带初始 prompt + 是否自动附带组合，省一次手动点击。
class AssistantLaunch {
  const AssistantLaunch({
    this.initialMessage,
    this.attachPortfolio = false,
    this.autoSend = false,
  });

  final String? initialMessage;
  final bool attachPortfolio;
  final bool autoSend;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.launch});

  /// 构造时显式传入的启动参数；优先级高于 ModalRoute.arguments。
  final AssistantLaunch? launch;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  /// 首屏入场动画（问候语与提问 pill 依次淡入上浮）。
  /// 空会话每次出现都重放一次 —— 冷启动、以及「新建对话」之后。
  late final AnimationController _entranceCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  String? _entranceSessionId;
  // 推理过程默认始终展示；不再提供顶部隐藏开关。
  static const bool _showReasoning = true;

  /// 是否把 PortfolioState.currentSummary 序列化进 SSE body 的
  /// portfolio_context 字段。仅由跨 Tab 跳转（AssistantLaunch.attachPortfolio）
  /// 打开；输入框上方不再提供手动开关。
  bool _attachPortfolio = false;
  bool _launchHandled = false;

  /// 首页空会话的快捷提问：按当前时段 + 开/收盘行情生成。
  /// 为 null / 空时回退到当前 Persona 的默认建议。
  final MarketBriefingService _briefing = MarketBriefingService();
  List<String>? _marketSuggestions;
  bool _loadingSuggestions = false;
  DateTime? _suggestionsLoadedAt;

  /// 待发送的图片（data URL）。发送成功后清空。
  final ImageAttachService _imageAttach = ImageAttachService();
  final List<String> _pendingImages = [];
  final Map<String, Uint8List> _pendingImageBytes = {};
  bool _pickingImage = false;

  /// 已经为哪个会话做过「进入即定位到最新消息」的初始滚动。
  /// 切换会话 / 首次进入聊天区时,自动跳到底部展示最新消息(而不是停在最老)。
  String? _scrolledSessionId;

  @override
  void initState() {
    super.initState();
    // ignore: unawaited_futures
    _loadMarketSuggestions();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    _entranceCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_launchHandled) return;
    _launchHandled = true;
    final launch = widget.launch ??
        (ModalRoute.of(context)?.settings.arguments as AssistantLaunch?);
    if (launch == null) return;
    if (launch.attachPortfolio) _attachPortfolio = true;
    if (launch.initialMessage != null && launch.initialMessage!.isNotEmpty) {
      if (launch.autoSend) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _send(launch.initialMessage);
        });
      } else {
        _input.text = launch.initialMessage!;
        _input.selection = TextSelection.fromPosition(
          TextPosition(offset: _input.text.length),
        );
      }
    }
  }

  /// 滚动到底部。
  /// - [animate]=false：用 jumpTo（流式期间使用，避免每帧都启动新的 animateTo
  ///   打断旧动画造成抖动闪烁）。
  /// - [animate]=true：用 animateTo（首次发送 / 接收完毕调用一次）。
  void _scrollToBottom({bool animate = true}) {
    // 注意:首帧 build 时 ScrollController 尚未 attach(hasClients=false),
    // 所以 hasClients 判断必须放进 postFrame 回调里,否则进入会话首次定位会被直接 return 掉。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  /// 进入 / 切换会话时的「定位到最新」。markdown / 图片会在首帧后继续撑开高度,
  /// 单次 jump 到首帧的 maxScrollExtent 往往偏短,这里首帧 + 延迟各跳一次,确保贴底。
  void _scrollToBottomInitial() {
    void jump() {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      Future.delayed(const Duration(milliseconds: 180), jump);
      Future.delayed(const Duration(milliseconds: 420), jump);
    });
  }

  Future<void> _send([String? override]) async {
    final raw = override ?? _input.text;
    final text = raw.trim();
    final images = List<String>.from(_pendingImages);
    // 允许「只发图不发文」。
    if (text.isEmpty && images.isEmpty) return;
    // 流式输出中不接受新消息：发送按钮此时是「停止」，但键盘回车仍会走到这里，
    // 不加这道闸会把输入框和已选图片白白清空。
    if (context.read<ChatState>().streaming) return;
    // 发送是需鉴权功能：未登录先弹登录，放弃则不发送（保留输入内容）。
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    _input.clear();
    if (images.isNotEmpty) {
      setState(() {
        _pendingImages.clear();
        _pendingImageBytes.clear();
      });
    }
    // 发送即收起键盘 + 失焦，让聊天区视野最大化
    _focus.unfocus();
    Map<String, dynamic>? ctxJson;
    if (_attachPortfolio) {
      final ps = context.read<PortfolioState>();
      final summary = ps.currentSummary;
      if (summary != null && summary.holdings.isNotEmpty) {
        ctxJson = summary.toAiContext();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前组合没有持仓，已忽略组合附带')),
        );
      }
    }
    await context
        .read<ChatState>()
        .sendMessage(text, portfolioContext: ctxJson, imageDataUrls: images);
    Analytics.instance.track(Analytics.evChatSend, {
      'chars': text.length,
      'images': images.length,
      'with_portfolio': ctxJson != null,
    });
    _scrollToBottom();
  }

  /// 选图：底部弹出「拍照 / 从相册选择」，成功后追加到待发送列表。
  Future<void> _pickImage() async {
    if (_pickingImage) return;
    final remaining = ImageAttachService.maxImages - _pendingImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多附带 ${ImageAttachService.maxImages} 张图片'),
        ),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.amber),
              title: const Text('拍照', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.amber),
              title: const Text('从相册选择', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '最多 ${ImageAttachService.maxImages} 张',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _pickingImage = true);
    List<String> picked = const [];
    try {
      picked = source == ImageSource.camera
          ? await _imageAttach.pickFromCamera()
          : await _imageAttach.pickFromGallery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      for (final url in picked.take(remaining)) {
        _pendingImages.add(url);
        _pendingImageBytes[url] = decodeImageDataUrl(url);
      }
      _pickingImage = false;
    });
  }

  /// 「喜点不足 / 扣费失败」弹窗：提示余额，并可一键跳到充值页。
  void _showChargeDialog(ChargeIssue issue) {
    // 后端 message 里塞了原始整数（如「当前余额 8」），直接展示会跟前端
    // ÷10 的显示口径不一致；这里只用 issue.balance 重新组装文案。
    final balanceLabel =
        issue.balance != null ? CreditFmt.balance(issue.balance!) : null;
    final content = balanceLabel != null
        ? '当前余额 $balanceLabel 喜点，已经不够本次对话啦。先去充点喜点再聊？'
        : '喜点不够本次对话啦，先去充点喜点再聊？';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('喜点不够啦'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ));
            },
            child: const Text('去充值'),
          ),
        ],
      ),
    );
  }

  /// 把当前对话最近一条用户提问 / 输入框正在输入的内容作为预填，弹出
  /// DING 任务编辑器供用户设置定时执行。
  void _addToDing(BuildContext context, ChatState chat) {
    final fromInput = _input.text.trim();
    String? promptInit;
    String? titleInit;
    if (fromInput.isNotEmpty) {
      promptInit = fromInput;
    } else {
      // 取当前会话最近的一条 user 消息
      for (final m in chat.messages.reversed) {
        if (m.role == 'user' && m.content.trim().isNotEmpty) {
          promptInit = m.content.trim();
          break;
        }
      }
    }
    if (promptInit != null && promptInit.isNotEmpty) {
      titleInit = promptInit.length > 14
          ? '${promptInit.substring(0, 14)}…'
          : promptInit;
    }
    DingTaskEditor.show(
      context,
      initialPrompt: promptInit,
      initialTitle: titleInit,
      initialPersonaId: chat.currentPersona.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final session = chat.active;
    final persona = chat.currentPersona;

    if (chat.streaming) _scrollToBottom(animate: false);

    // 进入聊天区 / 切换会话:首帧后定位到最新消息(底部),而非停在最老。
    if (session != null &&
        session.messages.isNotEmpty &&
        session.id != _scrolledSessionId) {
      _scrolledSessionId = session.id;
      _scrollToBottomInitial();
    }

    final issue = chat.chargeIssue;
    if (issue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = context.read<ChatState>();
        if (c.chargeIssue == null) return;
        c.consumeChargeIssue();
        _showChargeDialog(issue);
      });
    }

    // 空会话出现时重放入场动画：冷启动一次，之后每次「新建对话」再来一次。
    final isEmptySession = session == null || session.messages.isEmpty;
    final entranceKey = isEmptySession ? (session?.id ?? 'new') : null;
    if (entranceKey != null && entranceKey != _entranceSessionId) {
      _entranceSessionId = entranceKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entranceCtl.forward(from: 0);
      });
    }

    return Scaffold(
      // 导航栏透明、不带分割线，让背景一路铺到状态栏下面（元宝首页就是这么做的）。
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(),
        centerTitle: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpace.md),
          child: Center(
            child: _RoundIconButton(
              icon: Icons.menu_rounded,
              onTap: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        title: Row(
          children: [
            Text('喜爱',
                style: AppType.title.copyWith(fontSize: 18, letterSpacing: 1)),
            if (chat.totalTokens > 0) ...[
              const SizedBox(width: AppSpace.sm),
              Text('${chat.totalTokens} tok',
                  style: AppType.micro
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ],
        ),
        actions: [
          _RoundIconButton(
            icon: Icons.add_comment_rounded,
            tooltip: '新建对话',
            onTap: () => chat.newSession(),
          ),
          const SizedBox(width: AppSpace.sm),
          _RoundIconButton(
            icon: Icons.alarm_add_rounded,
            tooltip: '加入定时任务',
            onTap: () => _addToDing(context, chat),
          ),
          const SizedBox(width: AppSpace.md),
        ],
      ),
      drawer: const SessionDrawer(),
      body: Stack(
        children: [
          // 对话区背景：柔光纸面（自绘，不用位图 —— 任意尺寸都不糊）。
          const Positioned.fill(child: _ChatBackdrop()),
          Column(
            children: [
              Expanded(
                child: session == null || session.messages.isEmpty
                    ? SafeArea(top: true, child: _welcomePanel(persona))
                    : ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(
                            12,
                            MediaQuery.of(context).padding.top +
                                kToolbarHeight +
                                8,
                            12,
                            14),
                        itemCount: session.messages.length,
                        itemBuilder: (context, i) {
                          final msg = session.messages[i];
                          return MessageBubble(
                            message: msg,
                            allMessages: session.messages,
                            showReasoning: _showReasoning,
                          );
                        },
                      ),
              ),
              _composer(chat, persona, session),
            ],
          ),
        ],
      ),
    );
  }

  /// 输入框上方的快捷 pill 行（元宝的「快速 / AI创作 / 拍题答疑」那一排）：
  /// 角色切换、带上我的组合、加入定时任务。横向可滚，不挤成两行。
  Widget _quickActions(ChatState chat, Persona persona, ChatSession? session) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        children: [
          PersonaPicker(
            activeId: persona.id,
            disabled: chat.streaming,
            onPick: (id) async {
              final isNewSessionEmpty = (session?.messages.isEmpty ?? true);
              if (isNewSessionEmpty) {
                await chat.setPersona(id);
              } else {
                // 已有对话不切 persona，直接开新会话避免 prompt 跳变
                await chat.newSession(personaId: id);
              }
            },
          ),
          const SizedBox(width: AppSpace.sm),
          _quickPill(
            icon: Icons.pie_chart_rounded,
            label: '带上我的组合',
            active: _attachPortfolio,
            onTap: () => setState(() => _attachPortfolio = !_attachPortfolio),
          ),
          const SizedBox(width: AppSpace.sm),
          _quickPill(
            icon: Icons.alarm_add_rounded,
            label: '定时任务',
            onTap: () => _addToDing(context, chat),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
    );
  }

  /// 快捷 pill：白底圆角，选中态改主色浅底 + 主色字。
  Widget _quickPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final fg = active ? AppColors.amberDim : AppColors.textPrimary;
    return Material(
      color: active ? AppColors.accentSoft : AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      shadowColor: AppColors.shadow,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(label, style: AppType.caption.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  /// 「策略之王」气泡里点「立即运行」 → 直接发送策略 prompt 给 AI。
  ///
  /// 若用户已开启「@组合」，则把组合快照也带上，让 AI 在策略报告里参考
  /// 当前持仓做换仓建议。
  /// 入口暂时隐藏后本方法暂无调用方（代码保留，恢复入口时同步恢复调用）。
  // ignore: unused_element
  Future<void> _runStrategy(Strategy s) async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    Map<String, dynamic>? ctxJson;
    if (_attachPortfolio) {
      final ps = context.read<PortfolioState>();
      final summary = ps.currentSummary;
      if (summary != null && summary.holdings.isNotEmpty) {
        ctxJson = summary.toAiContext();
      }
    }
    await context
        .read<ChatState>()
        .sendMessage(s.prompt, portfolioContext: ctxJson);
    _scrollToBottom();
  }

  /// 空会话时的欢迎面板：结构照「元宝」首页 —— 上半留白把视线压到下方，
  /// 然后是左对齐的问候语、堆叠的提问 pill。每个元素按序淡入上浮
  /// （见 [_entrance]），一次编排，不逐帧堆特效。
  ///
  /// 快速提问优先用「当前时段 + 开/收盘行情」生成（见 [MarketBriefingService]）；
  /// 行情不可用时回退到当前 Persona 的默认建议。行情每 5 分钟视为过期，
  /// 展示时在后台静默刷新。
  Widget _welcomePanel(Persona persona) {
    final loadedAt = _suggestionsLoadedAt;
    if (loadedAt == null ||
        DateTime.now().difference(loadedAt) > const Duration(minutes: 5)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMarketSuggestions();
      });
    }
    final market = _marketSuggestions;
    final suggestions =
        (market != null && market.isNotEmpty) ? market : persona.welcomeSuggestions;

    // 问候语用昵称，没有昵称就叫「朋友」—— 跟元宝的「Hi, eric chan」同一个位置。
    final nickname = context.watch<AuthState>().currentUser?.nickname ?? '';
    final who = nickname.trim().isEmpty ? '朋友' : nickname.trim();

    var slot = 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          _entrance(
            slot++,
            Text(
              'Hi，$who',
              style: AppType.display.copyWith(
                  fontSize: 26, height: 1.3, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          for (final q in suggestions.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _entrance(slot++, _suggestion(q), from: 10),
            ),
          const SizedBox(height: AppSpace.xs),
        ],
      ),
    );
  }

  /// 拉取「当前时段 + 开/收盘行情」摘要并生成快捷提问；失败保持原建议。
  Future<void> _loadMarketSuggestions() async {
    if (_loadingSuggestions) return;
    _loadingSuggestions = true;
    try {
      final list = await _briefing.loadSuggestions();
      if (!mounted) return;
      setState(() {
        _marketSuggestions = list.isEmpty ? null : list;
        _suggestionsLoadedAt = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestionsLoadedAt = DateTime.now());
    } finally {
      _loadingSuggestions = false;
    }
  }

  /// 提问 pill：白底、胶囊形、宽度跟着文字走（元宝的提问就是一条条短 pill，
  /// 不是撑满整行的横条）。带一点极轻的投影，让它在纸底上浮起来。
  Widget _suggestion(String text) => Material(
        color: AppColors.bgSurface,
        elevation: 0,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        shadowColor: AppColors.shadow,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => _send(text),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: 13),
            child: Text(
              text,
              style: AppType.body.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
      );

  /// 入场动画：每个元素按 [slot] 依次淡入并上浮 [from] 像素。
  /// 整体 900ms、指数缓出，读完刚好结束 —— 只编排一处，不做重复入场。
  Widget _entrance(int slot, Widget child, {double from = 14}) {
    final start = (slot * 0.12).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: _entranceCtl,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (_, sub) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, from * (1 - curve.value)),
          child: sub,
        ),
      ),
      child: child,
    );
  }

  /// 输入区：上方一排快捷 pill，下面是圆角胶囊输入框，最底下一行免责说明。
  /// 结构照元宝，配色走我们自己的纸墨金。
  Widget _composer(ChatState chat, Persona persona, ChatSession? session) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.sm, AppSpace.md,
          AppSpace.sm + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pendingImages.isNotEmpty) _pendingImageStrip(),
          _quickActions(chat, persona, session),
          const SizedBox(height: AppSpace.sm),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 16,
                    offset: Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _attachButton(),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 6,
                    style: AppType.body.copyWith(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '发消息，或按住说话…',
                      hintStyle: AppType.body
                          .copyWith(fontSize: 14, color: AppColors.textTertiary),
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 0),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                _sendButton(chat),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('内容由 AI 生成，注意核实',
              textAlign: TextAlign.center,
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  /// 待发送图片的横向缩略图条（带右上角删除）。
  Widget _pendingImageStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingImages.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final url = _pendingImages[i];
            final bytes = _pendingImageBytes[url];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: bytes == null || bytes.isEmpty
                      ? Container(
                          width: 64,
                          height: 64,
                          color: AppColors.bgRaised,
                          child: Icon(Icons.broken_image_outlined,
                              size: 18, color: AppColors.textTertiary),
                        )
                      : Image.memory(
                          bytes,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() {
                      _pendingImages.removeAt(i);
                      _pendingImageBytes.remove(url);
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.borderDim),
                      ),
                      child: Icon(Icons.close,
                          size: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 输入框左侧「上传图片」入口：达到上限或正在选图时置灰。
  Widget _attachButton() {
    final full = _pendingImages.length >= ImageAttachService.maxImages;
    final disabled = full || _pickingImage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: disabled ? null : _pickImage,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.photo_camera_rounded,
            size: 22,
            color: disabled ? AppColors.textTertiary : AppColors.amber,
          ),
        ),
      ),
    );
  }

  Widget _sendButton(ChatState chat) {
    if (chat.streaming) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: AppColors.bgSurface,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.amber, width: 1.2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => chat.abort(),
            child: const SizedBox(
              width: 36,
              height: 36,
            child: Icon(Icons.stop_rounded, color: AppColors.amber, size: 20),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: AppColors.amber,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _send,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.arrow_upward_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// 对话区背景：柔光纸面。
///
/// 参考「元宝」首页那种"有张背景图"的感觉，但这里不用位图 —— 一张 PNG 换
/// 尺寸就发虚，还要多打包几百 KB，而且没法跟着主题走。几层渐变就能画出同样
/// 的柔光，任意屏幕上都是干净的。光带只做两处，不叠第三层。
class _ChatBackdrop extends StatelessWidget {
  const _ChatBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF9F5EC),
              Color(0xFFF1E9D9),
            ],
            stops: [0, 0.45, 1],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // 左上暖光：主光，落在问候语那一侧
            Positioned(
                left: -130,
                top: -90,
                child: _glow(340, AppColors.amber, 0.11)),
            // 右侧冷光：压在中间偏上，避免整页一个色调
            Positioned(
                right: -150,
                top: 120,
                child: _glow(380, const Color(0xFF6E93A6), 0.07)),
            // 底部暖雾：把视线兜在输入框这一带
            Positioned(
                left: -70,
                bottom: -160,
                child: _glow(400, AppColors.amberDim, 0.09)),
            // 斜向光带：背景里那道"透光"的感觉
            Center(
              child: Transform.rotate(
                angle: -0.62,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _streak(190, 0.55),
                    const SizedBox(height: 120),
                    _streak(90, 0.38),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一团柔光：径向渐变从颜色淡到全透明，边缘自然，不需要模糊滤镜。
  Widget _glow(double size, Color color, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      );

  /// 一条斜光带：中间亮、两端透明。
  Widget _streak(double height, double alpha) => Container(
        width: 260,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: alpha),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      );
}

/// 顶部圆按钮：白底圆形 + 极轻投影（对应元宝首页右上角那三个）。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: AppColors.bgSurface,
      shape: const CircleBorder(),
      shadowColor: AppColors.shadow,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
    return tooltip == null
        ? btn
        : Tooltip(message: tooltip!, child: btn);
  }
}

