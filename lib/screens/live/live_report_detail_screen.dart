import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/live.dart';
import '../../state/live_state.dart';
import '../../theme/app_theme.dart';

/// 单份报告详情：WebView 渲染后端生成的完整 HTML（含内联 CSS）。
///
/// HTML 已经是"片段（含一个 <style> + 一组 div）"，我们包一层
/// `<html><head><meta viewport/></head><body>...HTML...</body></html>`
/// 让 WKWebView 正确按屏宽渲染。
class LiveReportDetailScreen extends StatefulWidget {
  const LiveReportDetailScreen({super.key, required this.reportId});
  final int reportId;

  @override
  State<LiveReportDetailScreen> createState() => _LiveReportDetailScreenState();
}

class _LiveReportDetailScreenState extends State<LiveReportDetailScreen> {
  WebViewController? _ctrl;
  LiveReportFull? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFF15171b));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<LiveState>().loadReport(widget.reportId);
      if (r == null) {
        setState(() {
          _loading = false;
          _error = '未找到报告';
        });
        return;
      }
      await _ctrl!.loadHtmlString(_wrapHtml(r.htmlBody));
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _wrapHtml(String fragment) {
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
</head>
<body>$fragment</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15171b),
      appBar: AppBar(
        title: Text(
          _report == null
              ? '分析师报告'
              : '${_report!.personaName} · ${_report!.symbolName}',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? _errorView()
              : WebViewWidget(controller: _ctrl!),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.amber, size: 48),
              const SizedBox(height: 12),
              Text(
                '加载报告失败',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: Colors.white),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
}
