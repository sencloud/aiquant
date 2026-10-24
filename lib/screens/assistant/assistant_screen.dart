import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../core/format/credit_fmt.dart';
import '../../core/utils/image_data_url.dart';
import '../../models/chat.dart';
import '../../models/persona.dart';
import '../../services/analytics.dart';
import '../../services/image_attach_service.dart';
import '../../services/market_briefing.dart';
import '../../services/companion_voice.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../state/chat_state.dart';
import '../../state/companion_state.dart';
import '../../state/portfolio_state.dart';
import '../../theme/app_theme.dart';
import '../../wx/wx_kit.dart';
import '../settings/account_kit.dart';
import '../companion/companion_avatar.dart';
import '../companion/interests_sheet.dart';
import '../companion/companion_moments_screen.dart';
import '../companion/her_screen.dart';
import '../companion/live_avatar.dart';
import '../../models/companion_mood.dart';
import 'widgets/message_bubble.dart';
import 'widgets/persona_picker.dart';

/// 聊天页。版式照微信：灰底、白牙栏居中写对方的名字、气泡左右分色、
/// 底部一条输入栏，右边一个绿色「发送」。
///
/// 一个会话 = 一段话题，跟哪一位助手聊写在标题上。会话列表在「消息」页签，
/// 所以这一页是**二级页**（左上角是返回），不再是页签之一。
///
/// 逻辑（发送、流式、图片、余额不足、重新生成、推荐追问）与重构前一致，
/// 这次只换了外观与入口。
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
  const AssistantScreen({super.key, this.launch, this.briefing});

  /// 构造时显式传入的启动参数；优先级高于 ModalRoute.arguments。
  final AssistantLaunch? launch;

  /// 快捷提问的数据源；测试 / 截图时注入假实现，默认走网络。
  final MarketBriefingService? briefing;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  /// 空会话的入场动画（问候语与提问依次淡入上浮）。
  late final AnimationController _entranceCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  String? _entranceSessionId;
  static const bool _showReasoning = true;

  /// 是否把持仓快照带进请求（仅由跨页跳转 [AssistantLaunch.attachPortfolio]
  /// 打开；输入栏不再提供手动开关）。
  bool _attachPortfolio = false;
  bool _launchHandled = false;

  late final MarketBriefingService _briefing =
      widget.briefing ?? MarketBriefingService();
  List<String>? _marketSuggestions;
  bool _loadingSuggestions = false;
  DateTime? _suggestionsLoadedAt;

  /// 待发送的图片（data URL）。
  final ImageAttachService _imageAttach = ImageAttachService();
  final List<String> _pendingImages = [];
  final Map<String, Uint8List> _pendingImageBytes = {};
  bool _pickingImage = false;

  /// 已经为哪个会话做过「进入即定位到最新消息」的初始滚动。
  String? _scrolledSessionId;

  /// 右上角「…」的位置：微信式浮层要贴在它下面。
  final GlobalKey _moreKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 输入框有字没字，决定右边是「发送」还是灰着 —— 需要跟着重建。
    _input.addListener(_onInputChanged);
    CompanionVoice.instance.init();
    CompanionVoice.instance.speaking.addListener(_onVoiceChanged);
    // ignore: unawaited_futures
    _loadMarketSuggestions();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {}

  @override
  void dispose() {
    CompanionVoice.instance.speaking.removeListener(_onVoiceChanged);
    CompanionVoice.instance.stop();
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _scroll.removeListener(_onScroll);
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

  /// 滚动到底部。[animate]=false 时用 jumpTo（流式期间用）。
  void _scrollToBottom({bool animate = true}) {
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

  /// 进入 / 切换会话时定位到最新：markdown / 图片会在首帧后继续撑开高度，
  /// 单次 jump 往往偏短，这里首帧 + 延迟各跳一次。
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
    if (text.isEmpty && images.isEmpty) return;
    // 流式输出中不接受新消息：发送按钮此时是「停止」，但键盘回车仍会走到这里。
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
    final chat = context.read<ChatState>();
    final isCompanion = chat.active?.topic == 'companion';
    final companion = isCompanion ? context.read<CompanionState>() : null;
    final prefs = companion?.interests;
    companion?.setMood(AvatarMood.listening);
    await chat.sendMessage(text,
        portfolioContext: ctxJson,
        imageDataUrls: images,
        preferences: prefs,
        companionName: companion?.name,
        companionStyle: companion?.look.style);
    final reply = chat.latestAssistant?.content ?? '';
    companion?.setMood(
      reply.contains('哈哈') || reply.contains('开心') || reply.contains('喜欢')
          ? AvatarMood.happy
          : (reply.contains('害羞') ? AvatarMood.shy : AvatarMood.calm),
    );
    if (companion?.voiceEnabled == true && reply.trim().isNotEmpty) {
      // 她说出来；播放期间头像切到「说话」状态。
      // ignore: unawaited_futures
      CompanionVoice.instance.speak(reply);
    }
    Analytics.instance.track(Analytics.evChatSend, {
      'chars': text.length,
      'images': images.length,
      'with_portfolio': ctxJson != null,
    });
    _scrollToBottom();
  }

  Future<void> _sendSuggestion(String q) => _send(q);

  Future<void> _regenerate(ChatState chat, ChatMessage msg) async {
    if (chat.streaming) return;
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    await chat.regenerate(msg);
    _scrollToBottom();
  }

  /// 选图：底部弹出「拍照 / 从相册选择」。
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined,
                  color: AppColors.amber),
              title: const Text('拍照', style: AppType.body),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppColors.amber),
              title: const Text('从相册选择', style: AppType.body),
              subtitle: const Text('最多 ${ImageAttachService.maxImages} 张',
                  style: AppType.caption),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpace.sm),
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

  /// 「喜点不足 / 扣费失败」弹窗。
  void _showChargeDialog(ChargeIssue issue) {
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
              if (rechargeAvailable) {
                // ignore: unawaited_futures
                showRechargeSheet(context);
              } else {
                showLedgerSheet(context);
              }
            },
            child: Text(rechargeAvailable ? '去充值' : '看明细'),
          ),
        ],
      ),
    );
  }

  /// 标题右边的「…」：换助手 / 新建对话 / 删除这个对话。
  Future<void> _openChatMenu(ChatState chat, Persona persona) async {
    final topic = chat.active?.topic ?? 'money';
    final social = topic == 'social';
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.sm),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(social ? '换一个人' : '换个助手',
                  style: AppType.body),
              subtitle: Text('当前：${persona.displayName}',
                  style: AppType.caption),
              onTap: () => Navigator.pop(ctx, 'persona'),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('发起新的对话', style: AppType.body),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              title: Text('删除这个对话',
                  style: AppType.body.copyWith(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'persona':
        final picked = await showPersonaSheet(context,
            activeId: persona.id, topic: topic);
        if (picked == null || !mounted) return;
        final empty = chat.active?.messages.isEmpty ?? true;
        if (empty) {
          await chat.setPersona(picked);
        } else {
          await chat.newSession(personaId: picked);
        }
        break;
      case 'new':
        await chat.newSession();
        if (mounted) _scrollToBottomInitial();
        break;
      case 'delete':
        final id = chat.activeId;
        if (id == null) return;
        await chat.deleteSession(id);
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final session = chat.active;
    final persona = chat.currentPersona;
    final isCompanion = session?.topic == 'companion';
    final companion = isCompanion ? context.watch<CompanionState>() : null;
    final titleName = companion?.name ?? persona.displayName;
    final companionMood = companion == null
        ? AvatarMood.calm
        : (CompanionVoice.instance.speaking.value
            ? AvatarMood.speaking
            : (chat.streaming ? AvatarMood.thinking : companion.mood));
    final selfName = context.watch<AuthState>().currentUser?.nickname ?? '';

    if (chat.streaming) _scrollToBottom(animate: false);

    if (session != null &&
        session.messages.isNotEmpty &&
        session.id != _scrolledSessionId) {
      _scrolledSessionId = session.id;
      _scrollToBottomInitial();
    }

    final latest = chat.latestAssistant;

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

    // 空会话出现时重放入场动画（冷启动一次，之后每次「新建对话」再来一次）。
    final isEmptySession = session == null || session.messages.isEmpty;
    final entranceKey = isEmptySession ? (session?.id ?? 'new') : null;
    if (entranceKey != null && entranceKey != _entranceSessionId) {
      _entranceSessionId = entranceKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entranceCtl.forward(from: 0);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          titleName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.title.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          Builder(
            key: _moreKey,
            builder: (_) => IconButton(
              key: const ValueKey('chat-menu'),
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz_rounded, size: 24),
              onPressed: () => isCompanion
                  ? _openCompanionMenu(chat, persona)
                  : _openChatMenu(chat, persona),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isEmptySession
                ? _welcomePanel(persona)
                : GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      // ignore: unawaited_futures
                      CompanionVoice.instance.stop();
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                          AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.lg),
                      itemCount: session.messages.length,
                      itemBuilder: (context, i) {
                      final msg = session.messages[i];
                      final prev = i == 0 ? null : session.messages[i - 1];
                      final gap = prev == null
                          ? null
                          : msg.timestamp.difference(prev.timestamp);
                      final showTime = gap == null ||
                          gap.inMinutes.abs() >= 5 ||
                          gap.isNegative;
                      final isLatest = identical(msg, latest);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showTime) WxTimeStamp(wxChatTime(msg.timestamp)),
                          MessageBubble(
                            message: msg,
                            allMessages: session.messages,
                            showReasoning: _showReasoning,
                            isLatest: isLatest,
                            selfName: selfName,
                            assistantName: titleName,
                            showActions: !isCompanion,
                            assistantAvatar: session.topic == 'companion'
                                ? GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => const HerScreen()),
                                    ),
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      child: LiveAvatar(
                                        key: ValueKey(companion!.look.id),
                                        look: companion.look,
                                        mood: companionMood,
                                        width: 40,
                                        height: 40,
                                        radius: 6,
                                        glow: false,
                                      ),
                                    ),
                                  )
                                : null,
                            onSuggestion: isLatest ? _sendSuggestion : null,
                            onRegenerate:
                                isLatest ? () => _regenerate(chat, msg) : null,
                            onFeedback: (r) => chat.setFeedback(msg, r),
                          ),
                        ],
                      );
                      },
                    ),
                  ),
          ),
          _composer(chat),
        ],
      ),
    );
  }

  /// 伴侣版的「…」：微信式深色浮层，贴在右上角。
  Future<void> _openCompanionMenu(ChatState chat, Persona persona) async {
    final auth = context.read<AuthState>();
    final billing = context.read<BillingState>();
    final companion = context.read<CompanionState>();
    final user = auth.currentUser;
    final box = _moreKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: rect,
      color: const Color(0xFF2C2C2C),
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      constraints: const BoxConstraints(minWidth: 184),
      items: [
        _wxMenuItem('look', Icons.swipe_rounded, '遇见'),
        _wxMenuItem('moments', Icons.camera_alt_outlined, '看她'),
        _wxMenuItem('interests', Icons.favorite_border_rounded, '兴趣设置'),
        _wxMenuItem(
          'credits',
          Icons.savings_outlined,
          user == null
              ? '喜点（登录后可见）'
              : '喜点 ${CreditFmt.balance(billing.balance)}',
        ),
        _wxMenuItem(
          'voice',
          CompanionVoice.instance.speaking.value
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          companion.voiceEnabled ? '她的声音：开' : '她的声音：关',
        ),
        _wxMenuItem(
          user == null ? 'login' : 'logout',
          user == null ? Icons.login_rounded : Icons.logout_rounded,
          user == null ? '登录 / 注册' : '退出登录',
        ),
        _wxMenuItem('clear', Icons.delete_sweep_outlined, '清空聊天记录'),
        _wxMenuItem('about', Icons.info_outline_rounded, '关于'),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'look':
        final look = await companion.nextLook();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('现在是 ${look.name} 陪你'),
          duration: const Duration(milliseconds: 1200),
        ));
        break;
      case 'moments':
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const CompanionMomentsScreen()));
        break;
      case 'voice':
        final on = !companion.voiceEnabled;
        await companion.setVoiceEnabled(on);
        if (!on) await CompanionVoice.instance.stop();
        break;
      case 'interests':
        await showInterestsSheet(context);
        break;
      case 'credits':
        if (!auth.isAuthenticated) {
          await requireLogin(context);
        } else if (rechargeAvailable) {
          await showRechargeSheet(context);
        } else {
          showLedgerSheet(context);
        }
        break;
      case 'login':
        await requireLogin(context);
        break;
      case 'logout':
        await auth.logout();
        break;
      case 'clear':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('清空这段对话'),
            content: const Text('她会忘掉这段对话里的内容，但她记得的喜欢还在。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('再想想')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('清空')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        final id = chat.activeId;
        if (id != null) await chat.deleteSession(id);
        await chat.newSession(
            topic: 'companion', personaId: 'xiai', title: companion.name);
        await chat.addLocalMessage(
            '我是${companion.name}。\n陪着你，是长情的告白。');
        break;
      case 'about':
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('关于喜爱'),
            content: const Text(
              '她是 AI 伴侣，不是真人。\n\n'
              '她记得你选过的兴趣，会在你一阵子没说话的时候先开口。'
              '她不替你下单、不承诺收益、不向你索要钱财或隐私。\n\n'
              '陪伴是长情的告白，但真实的生活和关系更值得你花时间。',
              style: TextStyle(fontSize: 14, height: 1.65),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了')),
            ],
          ),
        );
        break;
    }
  }

  PopupMenuItem<String> _wxMenuItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontFamilyFallback: AppType.sansFallback,
              )),
        ],
      ),
    );
  }

  Future<void> _switchLook(CompanionState companion) async {
    final look = await companion.nextLook();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('现在是 ${look.name} 陪你'),
      duration: const Duration(milliseconds: 1200),
    ));
  }

  /// 空会话时的问候：一行白字 + 三条快捷提问（白面行，和微信列表同一套）。
  Widget _welcomePanel(Persona persona) {
    if (context.watch<ChatState>().active?.topic == 'companion') {
      return _companionWelcome(persona);
    }
    final loadedAt = _suggestionsLoadedAt;
    if (loadedAt == null ||
        DateTime.now().difference(loadedAt) > const Duration(minutes: 5)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMarketSuggestions();
      });
    }
    final market = _marketSuggestions;
    final suggestions = (market != null && market.isNotEmpty)
        ? market
        : persona.welcomeSuggestions;

    final nickname = context.watch<AuthState>().currentUser?.nickname ?? '';
    final who = nickname.trim().isEmpty ? '朋友' : nickname.trim();

    var slot = 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            _entrance(
              slot++,
              Row(
                children: [
                  WxAvatar(
                    text: persona.displayName,
                    icon: persona.icon,
                    background: persona.color,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Flexible(
                    child: Text('Hi，$who',
                        style: AppType.title.copyWith(fontSize: 20)),
                  ),
                ],
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
      ),
    );
  }

  /// 伴侣的空会话：她的头像、一句承诺、她记得的喜欢，以及三个开场。
  Widget _companionWelcome(Persona persona) {
    final companion = context.watch<CompanionState>();
    var slot = 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xl, AppSpace.xl, AppSpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _entrance(
              slot++,
              GestureDetector(
                onTap: () => _switchLook(companion),
                child: CompanionAvatar(
                    size: 88, radius: 22, asset: companion.look.asset),
              )),
          const SizedBox(height: AppSpace.lg),
          _entrance(
              slot++,
              Text('我是${companion.name}。',
                  textAlign: TextAlign.center,
                  style: AppType.title.copyWith(fontSize: 22))),
          const SizedBox(height: AppSpace.sm),
          _entrance(
              slot++,
              Text('陪着你，是长情的告白。',
                  textAlign: TextAlign.center,
                  style: AppType.read.copyWith(
                      fontSize: 15, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  /// 拉取「当前时段 + 开/收盘行情」摘要并生成快捷提问；失败保持原建议。
  /// 只有「喜爱钱」这个圈有行情摘要，其它圈直接用助手自带的欢迎提问。
  Future<void> _loadMarketSuggestions() async {
    if (_loadingSuggestions) return;
    _loadingSuggestions = true;
    try {
      final topic = context.read<ChatState>().active?.topic ?? 'money';
      if (topic != 'money') {
        if (mounted) setState(() => _suggestionsLoadedAt = DateTime.now());
        return;
      }
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

  /// 快捷提问：白面行（微信列表的样子），点了直接问。
  Widget _suggestion(String text) => Material(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => _send(text),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(text, style: AppType.body.copyWith(fontSize: 15)),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      );

  /// 入场动画：每个元素按 [slot] 依次淡入并上浮 [from] 像素。
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

  /// 输入栏：微信那条 —— 灰底、一条发丝线、白色圆角输入框、右边绿色发送。
  Widget _composer(ChatState chat) {
    final typed = _input.text.trim().isNotEmpty || _pendingImages.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border(top: BorderSide(color: AppColors.borderDim, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          AppSpace.sm,
          AppSpace.sm,
          AppSpace.sm,
          AppSpace.sm + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pendingImages.isNotEmpty) _pendingImageStrip(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _attachButton(),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    style: AppType.body.copyWith(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '发消息…',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      hintStyle: AppType.body
                          .copyWith(fontSize: 16, color: AppColors.textTertiary),
                    ),
                    onTapOutside: (_) => _focus.unfocus(),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              _sendButton(chat, typed),
            ],
          ),
        ],
      ),
    );
  }

  /// 待发送图片的缩略图条（带右上角删除）。
  Widget _pendingImageStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm, left: AppSpace.xs),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingImages.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
          itemBuilder: (context, i) {
            final url = _pendingImages[i];
            final bytes = _pendingImageBytes[url];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: bytes == null || bytes.isEmpty
                      ? Container(
                          width: 64,
                          height: 64,
                          color: AppColors.bgRaised,
                          child: Icon(Icons.broken_image_outlined,
                              size: 18, color: AppColors.textTertiary),
                        )
                      : Image.memory(bytes,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          gaplessPlayback: true),
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

  /// 输入栏左边的「＋」：拍照 / 相册（一个入口，和微信的 ＋ 同一个位置）。
  Widget _attachButton() {
    final full = _pendingImages.length >= ImageAttachService.maxImages;
    final disabled = full || _pickingImage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        key: const ValueKey('chat-attach'),
        customBorder: const CircleBorder(),
        onTap: disabled ? null : _pickImage,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.add_circle_outline_rounded,
            size: 26,
            color: disabled ? AppColors.textTertiary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 右边：有字（或带了图）就是绿色「发送」，流式中是「停止」。
  Widget _sendButton(ChatState chat, bool typed) {
    if (chat.streaming) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: TextButton(
          onPressed: () => chat.abort(),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.bgSurface,
            foregroundColor: AppColors.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          child: const Text('停止', style: TextStyle(fontSize: 15)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TextButton(
        key: const ValueKey('chat-send'),
        onPressed: typed ? _send : null,
        style: TextButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.bgSurface,
          disabledForegroundColor: AppColors.textTertiary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        child: const Text('发送',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
