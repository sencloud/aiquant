import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../trade_review/trade_review_widgets.dart';

/// 微信式设置页。
///
/// 隐私、协议和产品信息都收在这一层，避免“我的”首屏变成入口清单。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.reportCount,
    this.lastSavedAt,
  });

  final int reportCount;
  final DateTime? lastSavedAt;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}');
    } catch (_) {
      // Package metadata is unavailable in some widget-test hosts.
    }
  }

  Future<void> _openLegal(String url) async {
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WkPage(
      title: '设置',
      child: ListView(
        key: const ValueKey('settings-page'),
        padding: const EdgeInsets.only(top: AppSpace.md),
        children: [
          WkGroup(
            children: [
              WkRow(
                key: const ValueKey('settings-data-privacy'),
                title: '数据与隐私',
                value: '账号同步',
                onTap: _showPrivacy,
              ),
              WkRow(
                key: const ValueKey('settings-terms'),
                title: '用户协议',
                onTap: () => _openLegal(AppConfig.instance.termsUrl),
              ),
              WkRow(
                key: const ValueKey('settings-privacy-policy'),
                title: '隐私政策',
                onTap: () => _openLegal(AppConfig.instance.privacyUrl),
              ),
            ],
          ),
          WkGroup(
            children: [
              WkRow(
                key: const ValueKey('settings-about'),
                title: '关于喜爱',
                value: _version.isEmpty ? null : _version,
                onTap: _showAbout,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Text(
              '截图只用于当次识别，原图不保存。核对后的成交字段与复盘报告'
              '保存在喜爱账号，并可在手机和电脑之间同步。',
              style: AppType.caption.copyWith(
                color: AppColors.textTertiary,
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacy() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('数据与隐私', style: AppType.title),
              const SizedBox(height: AppSpace.md),
              Text(
                '截图只用于当次识别，不保存原图。日期、方向、数量、价格、'
                '手续费和复盘报告会保存到你的喜爱账号，最多保留 20 份，'
                '可随时逐份删除。电脑端生成的复盘也会同步到同一账号，'
                '登录后即可在手机查看。',
                style: AppType.read.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.75,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _InfoLine(label: '账号复盘', value: '${widget.reportCount} 份'),
              _InfoLine(
                label: '最近保存',
                value: widget.lastSavedAt == null
                    ? '暂无'
                    : formatTradeDate(widget.lastSavedAt!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('关于喜爱', style: AppType.title),
              const SizedBox(height: AppSpace.md),
              Text(
                '喜爱读取你的成交记录，按先进先出还原已平仓交易，'
                '再用可以验证的数据说明交易逻辑、问题与改进措施。'
                '\n\n它不判断账户总资金，不推测截图中没有出现的仓位、'
                '止损金额、消息来源或临场情绪，也不提供交易指令或收益承诺。',
                style: AppType.read.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.75,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _InfoLine(
                label: '应用版本',
                value: _version.isEmpty ? '读取中' : _version,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          Text(label, style: AppType.body),
          const Spacer(),
          Text(
            value,
            textAlign: TextAlign.right,
            style: AppType.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
