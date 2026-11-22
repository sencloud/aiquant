import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/trade_review.dart';
import '../../services/trade_desktop_server.dart';
import '../../services/trade_review_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_report_screen.dart';
import 'trade_review_widgets.dart';

class TradeDesktopConnectScreen extends StatefulWidget {
  const TradeDesktopConnectScreen({
    super.key,
    this.server,
    this.store,
  });

  final TradeDesktopServer? server;
  final TradeReviewStore? store;

  @override
  State<TradeDesktopConnectScreen> createState() =>
      _TradeDesktopConnectScreenState();
}

class _TradeDesktopConnectScreenState extends State<TradeDesktopConnectScreen> {
  late final TradeDesktopServer _server = widget.server ?? TradeDesktopServer();
  late final TradeReviewStore _store =
      widget.store ?? TradeReviewStore.instance;
  bool _starting = true;
  String? _error;
  String? _knownReviewId;

  @override
  void initState() {
    super.initState();
    _knownReviewId = _store.latest?.id;
    _store.addListener(_onStoreChanged);
    _start();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _server.stop();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _server.start();
      if (!mounted) return;
      setState(() => _starting = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '无法开启本机接收。请确认这个网络允许设备互相访问，然后再试一次。';
      });
    }
  }

  void _onStoreChanged() {
    final latest = _store.latest;
    if (latest == null || latest.id == _knownReviewId) return;
    _knownReviewId = latest.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('电脑端成交记录已收到，复盘已保存到本机。')),
        );
      _openReport(latest);
    });
  }

  void _openReport(TradeReviewReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TradeReportScreen(report: report),
      ),
    );
  }

  void _rotateCode() {
    _server.rotatePairCode();
    setState(() {});
  }

  Future<void> _copyEndpoint() async {
    final endpoint = _server.endpoint;
    if (endpoint == null) return;
    await Clipboard.setData(ClipboardData(text: endpoint));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('电脑连接地址已复制。')),
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _server.pairCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('六位配对码已复制。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('电脑端连接')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpace.xl),
          children: [
            _intro(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                  0,
                ),
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4F2),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 19,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppType.caption.copyWith(height: 1.6),
                        ),
                      ),
                      TextButton(
                        onPressed: _starting ? null : _start,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            const TradeSectionTitle(
              title: '电脑上填写这两项',
              caption: '地址和配对码只在你打开这个页面时有效，离开后会停止接收。',
            ),
            _connectionCard(),
            const TradeSectionTitle(
              title: '怎么连接',
              caption: '电脑端会调用你配置的识图模型读取截图，只把核对后的结构化成交行发送到这台手机。',
            ),
            _steps(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: WkNote(
                title: '连接条件',
                text: '电脑和手机需要连接同一个 Wi-Fi。若公司或公共网络禁止设备互访，'
                    '可以改用手机热点。配对码错误、手机页面关闭或地址不一致时，'
                    '电脑端都不会发送成功。',
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: WkNote(
                title: '隐私',
                text: '电脑端截图会发送给所配置的识图模型做当次识别；手机只接收日期、方向、'
                    '数量、价格与手续费等成交字段。复盘结果保存在本机，不保存接收的截图。',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(
              Icons.devices_rounded,
              color: AppColors.amber,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '让电脑把交易记录交给手机',
                  style: AppType.title.copyWith(fontSize: 18),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '在电脑端识别成交截图、核对成交行，再一键发送到「嘻，AI」生成同样的复盘报告。',
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionCard() {
    final endpoint = _server.endpoint;
    final hasAddress = _server.isRunning && endpoint != null;
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_starting)
            const SizedBox(
              height: 132,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!hasAddress)
            SizedBox(
              height: 132,
              child: WkEmpty(
                icon: Icons.wifi_off_rounded,
                title: '连接没有开启',
                hint: '点下方按钮重新开启接收。',
                action: TextButton(
                  onPressed: _start,
                  child: const Text('重新开启'),
                ),
              ),
            )
          else ...[
            Text(
              '手机地址',
              style: AppType.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.md,
                AppSpace.xs,
                AppSpace.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.bgRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      endpoint,
                      key: const ValueKey('trade-desktop-endpoint'),
                      style: AppType.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontFamilyFallback: AppType.numericFallback,
                        height: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制地址',
                    onPressed: _copyEndpoint,
                    icon: const Icon(Icons.copy_rounded, size: 19),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '六位配对码',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        _server.pairCode,
                        key: const ValueKey('trade-desktop-pair-code'),
                        style: AppType.display.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 5,
                          fontFamilyFallback: AppType.numericFallback,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('复制'),
                ),
                IconButton(
                  tooltip: '刷新配对码',
                  onPressed: _rotateCode,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '每次离开本页再进入都会生成新的地址端口和配对码。',
              style: AppType.micro.copyWith(
                color: AppColors.textTertiary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _steps() {
    const steps = [
      '在电脑端打开「交易复盘」，选择同一张成交记录截图。',
      '核对识别出的日期、方向、数量和价格。',
      '填写本页地址与配对码，发送后手机会自动打开报告。',
    ];
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: AppType.micro.copyWith(
                        color: AppColors.amberDim,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: AppType.body.copyWith(
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
