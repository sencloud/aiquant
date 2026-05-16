import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tushare;
  late final TextEditingController _tushareEndpoint;
  late final TextEditingController _deepseek;
  bool _showTushare = false;
  bool _showDeepseek = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsState>();
    _tushare = TextEditingController(
        text: s.hasTushareToken ? s.tushareToken : '');
    _tushareEndpoint =
        TextEditingController(text: s.tushareEndpoint);
    _deepseek = TextEditingController(
        text: s.hasDeepseekKey ? s.deepseekKey : '');
  }

  @override
  void dispose() {
    _tushare.dispose();
    _tushareEndpoint.dispose();
    _deepseek.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('AI 助理（DeepSeek）'),
          _kvRow(
            label: 'API Key',
            child: _masked(_deepseek, _showDeepseek, (v) {
              setState(() => _showDeepseek = v);
            }),
          ),
          _kvRow(
            label: '模型',
            child: DropdownButton<String>(
              value: settings.deepseekModel,
              isExpanded: true,
              dropdownColor: AppColors.bgRaised,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: BuiltInSecrets.defaultDeepseekModel,
                  child: Text('deepseek-v4-flash（默认 · 极速）'),
                ),
                DropdownMenuItem(
                  value: BuiltInSecrets.reasoningDeepseekModel,
                  child: Text('deepseek-reasoner（深度模式 / 推理）'),
                ),
                DropdownMenuItem(
                  value: BuiltInSecrets.chatDeepseekModel,
                  child: Text('deepseek-chat（对话模式）'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                settings.updateDeepseekModel(v);
                settings.updateDeepMode(
                    v == BuiltInSecrets.reasoningDeepseekModel);
              },
            ),
          ),
          SwitchListTile(
            value: settings.deepMode,
            activeThumbColor: AppColors.amber,
            title: const Text('启用“深度模式”',
                style: TextStyle(fontSize: 12)),
            subtitle: Text(
              '切换到 deepseek-reasoner，先生成推理过程再给出最终答案；'
              '关闭则使用默认的 deepseek-v4-flash。',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            onChanged: (v) => settings.updateDeepMode(v),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await settings.updateDeepseekKey(_deepseek.text);
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('DeepSeek API Key 已保存')),
              );
            },
            child: const Text('保存 DeepSeek 设置'),
          ),

          const SizedBox(height: 28),
          _section('行情数据（Tushare Pro）'),
          _kvRow(
            label: 'Token',
            child: _masked(_tushare, _showTushare, (v) {
              setState(() => _showTushare = v);
            }),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await settings.updateTushareToken(_tushare.text);
              await settings.updateTushareEndpoint(_tushareEndpoint.text);
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Tushare 设置已保存')),
              );
            },
            child: const Text('保存 Tushare 设置'),
          ),
          const SizedBox(height: 8),
          Text(
            '提示：默认已内置 Tushare Token，开箱即用。如需替换 Token 或'
            '在 Web (H5) 上绕过 CORS，可在“高级”里改 Endpoint。',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 4),
                  const Text('高级 · Tushare Endpoint',
                      style: TextStyle(
                          color: AppColors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6)),
                ],
              ),
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _tushareEndpoint,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'http://api.tushare.pro',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '默认 http://api.tushare.pro。Web 端浏览器会跨域拦截，'
              '可换成你自己的 HTTPS 反向代理（Cloudflare Worker / Nginx 均可），'
              '后端只需把 POST body 透传到 Tushare 即可。',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textTertiary, height: 1.5),
            ),
          ],

          const SizedBox(height: 28),
          _section('关于'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline, color: AppColors.amber),
            title: Text('Fincept App',
                style: TextStyle(color: AppColors.textPrimary)),
            subtitle: Text('FINCEPT 终端的移动 / Web 简化版',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          t,
          style: const TextStyle(
            color: AppColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      );

  Widget _kvRow({required String label, required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  Widget _masked(TextEditingController c, bool show, ValueChanged<bool> onTap) {
    return TextField(
      controller: c,
      obscureText: !show,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: InputDecoration(
        hintText: '在此粘贴密钥',
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility_off : Icons.visibility,
              size: 18, color: AppColors.textTertiary),
          onPressed: () => onTap(!show),
        ),
      ),
    );
  }
}
