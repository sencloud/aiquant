import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/storage/hive_setup.dart' show prefsBox;
import '../../theme/app_theme.dart';
import '../../widgets/legal_links.dart';
import '../../widgets/wk_kit.dart';
import '../buddy/work_buddy_catalog.dart';
import '../watch/widgets/market_brand.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({
    super.key,
    required this.onOpenBuddy,
    required this.onOpenCloudBuddy,
    required this.watchPageBuilder,
  });

  final VoidCallback onOpenBuddy;
  final VoidCallback onOpenCloudBuddy;
  final WidgetBuilder watchPageBuilder;

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  String _version = '';
  String _selectedBuddy = workBuddyCharacters.first.name;
  String? _lastMarketName;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _restoreSummary();
  }

  @override
  void didUpdateWidget(covariant MyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restoreSummary();
  }

  void _restoreSummary() {
    try {
      final buddyId = prefsBox.get('buddy.character.v1')?.toString();
      final buddy = workBuddyById(buddyId);
      final raw = prefsBox.get('market_home.selection.v1');
      String? market;
      if (raw is Map) {
        market = raw['name']?.toString();
      } else if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) market = decoded['name']?.toString();
      }
      _selectedBuddy = buddy.name;
      _lastMarketName = market;
    } catch (_) {
      // The page remains useful before Hive has restored local state.
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}');
    } catch (_) {
      // Package metadata is unavailable in some widget-test hosts.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgBase,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            _ProfileHeader(
              lastMarketName: _lastMarketName,
              onTap: _showLocalProfile,
            ),
            const SizedBox(height: 12),
            WkGroup(
              children: [
                WkRow(
                  key: const ValueKey('my-watch-app'),
                  leading: const _AppIcon(
                    icon: Icons.candlestick_chart_rounded,
                    color: Color(0xFF1C49C9),
                  ),
                  title: '看盘',
                  subtitle: '股票 / 期货 · K线 · 支撑阻力 · 喜AI研判',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: widget.watchPageBuilder,
                      ),
                    );
                  },
                ),
              ],
            ),
            WkGroup(
              children: [
                WkRow(
                  leading: const _AppIcon(
                    icon: Icons.face_retouching_natural_rounded,
                    color: Color(0xFFED8D89),
                  ),
                  title: '我的搭子',
                  value: _selectedBuddy,
                  onTap: widget.onOpenBuddy,
                ),
                WkRow(
                  leading: const _AppIcon(
                    icon: Icons.cloud_queue_rounded,
                    color: Color(0xFF7C8FB8),
                  ),
                  title: '云搭子',
                  value: '待建设',
                  onTap: widget.onOpenCloudBuddy,
                ),
              ],
            ),
            WkGroup(
              header: '设置',
              children: [
                const WkRow(
                  leading: _AppIcon(
                    icon: Icons.contrast_rounded,
                    color: Color(0xFF9E8C72),
                  ),
                  title: '外观',
                  value: '浅色',
                ),
                WkRow(
                  leading: const _AppIcon(
                    icon: Icons.storage_rounded,
                    color: Color(0xFF4F86C6),
                  ),
                  title: '本机数据',
                  value: '行情与搭子记忆',
                  onTap: _showLocalProfile,
                ),
                WkRow(
                  leading: const _AppIcon(
                    icon: Icons.info_outline_rounded,
                    color: Color(0xFF7D7D7D),
                  ),
                  title: '关于喜AI',
                  onTap: _showAbout,
                ),
                const LegalLinksRow(),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '喜AI ${_version.isEmpty ? '' : _version} · 行情与搭子都在这里',
                style: AppType.micro.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocalProfile() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('喜AI 本机档案', style: AppType.title),
              const SizedBox(height: 6),
              Text(
                '当前不要求登录。最近查看、自选和搭子的熟悉度都保存在这台设备。',
                style: AppType.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              _InfoLine(
                label: '最近看盘',
                value: _lastMarketName ?? '还没有记录',
              ),
              _InfoLine(label: '当前搭子', value: _selectedBuddy),
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

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于喜AI'),
        content: Text(
          '喜AI 是一个轻量的行情与工作搭子。'
          '你可以在「我的」里打开完整看盘终端，也可以在这里找到陪你上班的搭子。'
          '\n\n行情来自 Tushare 与中国大陆公开行情源；'
          '不提供交易、荐股或收益承诺。',
          style: AppType.body.copyWith(
            fontSize: 15,
            color: AppColors.textSecondary,
            height: 1.65,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.lastMarketName,
    required this.onTap,
  });

  final String? lastMarketName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: const ValueKey('my-profile'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Row(
            children: [
              const MarketBrandMark(size: 62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '喜AI用户',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamilyFallback: AppType.sansFallback,
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      lastMarketName == null
                          ? '本机模式 · 数据保存在这台设备'
                          : '最近在看 · $lastMarketName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.qr_code_2_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 20, color: Colors.white),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: AppType.body),
          const Spacer(),
          Text(
            value,
            style: AppType.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
