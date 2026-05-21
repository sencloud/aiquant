import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../theme/app_theme.dart';

/// 把助理消息渲染成「长图卡片」并通过系统分享面板分享。
///
/// - 卡片走浅色主题（白底 + 深色文字 + 金黄品牌色），在微信里看比深色截图更耐看；
/// - 用 `RepaintBoundary` 包裹卡片整体，分享时 `toImage(pixelRatio: 3)` 输出
///   高清 PNG 到临时目录，再走 `Share.shareXFiles` → iOS 系统分享面板（用户
///   从里面选「微信 / 朋友圈」即可）。
class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({
    super.key,
    required this.text,
    required this.timestamp,
  });

  /// 要分享的消息正文（Markdown）。
  final String text;

  /// 消息时间（卡片右上角小字）。
  final DateTime timestamp;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePng();
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/xikuan_assistant_$stamp.png');
      await file.writeAsBytes(bytes, flush: true);

      Rect? origin;
      if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          origin = box.localToGlobal(Offset.zero) & box.size;
        }
      }
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'xikuan_assistant.png')],
        subject: '来自喜宽 AI 助理',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成长图失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _capturePng() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('toByteData returned null');
    }
    return data.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('分享长图')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            child: Center(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: _ShareCard(
                  text: widget.text,
                  timestamp: widget.timestamp,
                ),
              ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.amber),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('生成长图并分享到微信'),
            onPressed: _busy ? null : _share,
          ),
        ),
      ),
    );
  }
}

/// 实际要被截图的浅色卡片：品牌头部 + Markdown 正文 + 底部水印。
///
/// 颜色与 App 主题解耦（始终浅色），保证发到微信里观感稳定。
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.text, required this.timestamp});

  final String text;
  final DateTime timestamp;

  static const _bg = Color(0xFFFFFFFF);
  static const _accent = Color(0xFFD97706);
  static const _fgPrimary = Color(0xFF1A1A1A);
  static const _fgSecondary = Color(0xFF5A5A5A);
  static const _fgTertiary = Color(0xFF999999);
  static const _bgSoft = Color(0xFFFAF5EC);
  static const _border = Color(0xFFE6E1D5);

  @override
  Widget build(BuildContext context) {
    // 固定宽度 → 让长图无论手机宽度多少都输出统一尺寸，避免分享出去字号忽大忽小。
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: MarkdownBody(
              data: text.isEmpty ? '…' : text,
              selectable: false,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: _fgPrimary,
                  fontSize: 13,
                  height: 1.6,
                ),
                strong: const TextStyle(
                    color: _fgPrimary, fontWeight: FontWeight.w800),
                listBullet: const TextStyle(color: _fgPrimary, fontSize: 13),
                h1: const TextStyle(
                  color: _fgPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  height: 1.35,
                ),
                h2: const TextStyle(
                  color: _fgPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.35,
                ),
                h3: const TextStyle(
                  color: _fgPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1.35,
                ),
                code: const TextStyle(
                  backgroundColor: _bgSoft,
                  color: _accent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                codeblockDecoration: BoxDecoration(
                  color: _bgSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _border),
                ),
                blockquoteDecoration: const BoxDecoration(
                  color: _bgSoft,
                  border: Border(
                    left: BorderSide(color: _accent, width: 3),
                  ),
                ),
                blockquote: const TextStyle(color: _fgSecondary, fontSize: 13),
                tableHead: const TextStyle(
                    color: _fgPrimary, fontWeight: FontWeight.w800),
                tableBorder: TableBorder.all(color: _border, width: 0.6),
                tableCellsPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    final ts = DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFCE7B5), Color(0xFFFFF4D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '喜宽 · AI 投资助理',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '由喜宽生成的对话内容 · 仅供参考',
                  style: TextStyle(
                    color: _fgSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            ts,
            style: const TextStyle(
              color: _fgTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: _bgSoft,
        border: Border(
          top: BorderSide(color: _border, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.copyright_outlined, size: 11, color: _fgTertiary),
          const SizedBox(width: 4),
          const Text(
            '喜宽 AI 助理 · 长按识别图中文字可复制',
            style: TextStyle(color: _fgTertiary, fontSize: 10),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'xikuan.ai',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
