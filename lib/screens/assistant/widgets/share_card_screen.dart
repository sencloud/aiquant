import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../theme/app_theme.dart';

/// 下载落地页前缀（带邀请码可做拉新归因）。
String _downloadUrl(String inviteCode, String channel) {
  const base = 'https://www.singzquant.com/d/';
  if (inviteCode.isEmpty) return '$base?utm_source=$channel';
  return '$base?ref=$inviteCode&utm_source=$channel';
}

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
    this.question,
    this.inviteCode = '',
  });

  /// 触发回答的用户提问（可空）。非空时长图顶部会渲染一个"问题"气泡。
  final String? question;

  /// 要分享的助理回答正文（Markdown）。
  final String text;

  /// 消息时间（卡片右上角小字）。
  final DateTime timestamp;

  /// 当前用户邀请码（可空）；用于卡片底部二维码做拉新归因。
  final String inviteCode;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  // 0 = 微信长图（浅色长卡）, 1 = 小红书竖版（封面式竖图）
  int _template = 0;
  String get _channel => _template == 0 ? 'wxlong' : 'xhs';

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePng();
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/xikuan_${_channel}_$stamp.png');
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

  Widget _templateToggle() {
    Widget chip(int i, String label, IconData icon) {
      final active = _template == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _template = i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.amber : AppColors.bgRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? AppColors.amber : AppColors.borderDim),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: active ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
      child: Row(
        children: [
          chip(0, '微信长图', Icons.wechat),
          chip(1, '小红书竖版', Icons.photo_size_select_actual_outlined),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('分享卡片')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
            child: Column(
              children: [
                _templateToggle(),
                RepaintBoundary(
                  key: _boundaryKey,
                  child: _template == 0
                      ? _ShareCard(
                          question: widget.question,
                          text: widget.text,
                          timestamp: widget.timestamp,
                          inviteCode: widget.inviteCode,
                          channel: _channel,
                        )
                      : _XhsCard(
                          question: widget.question,
                          text: widget.text,
                          timestamp: widget.timestamp,
                          inviteCode: widget.inviteCode,
                          channel: _channel,
                        ),
                ),
              ],
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
            label: Text(_template == 0 ? '生成长图并分享到微信' : '生成竖版图并分享到小红书'),
            onPressed: _busy ? null : _share,
          ),
        ),
      ),
    );
  }
}

/// 实际要被截图的浅色卡片：品牌头部 + 用户提问 + Markdown 回答 + 底部水印。
///
/// 颜色与 App 主题解耦（始终浅色），保证发到微信里观感稳定。
class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.text,
    required this.timestamp,
    required this.inviteCode,
    required this.channel,
    this.question,
  });

  final String? question;
  final String text;
  final DateTime timestamp;
  final String inviteCode;
  final String channel;

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
          if (question != null && question!.isNotEmpty) _questionBlock(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              (question != null && question!.isNotEmpty) ? 6 : 18,
              20,
              12,
            ),
            child: _answerHeader(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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

  Widget _questionBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.person, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 6),
              const Text(
                '我的提问',
                style: TextStyle(
                  color: _fgSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _bgSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Text(
              question!,
              style: const TextStyle(
                color: _fgPrimary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerHeader() {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(4),
          ),
          child:
              const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
        ),
        const SizedBox(width: 6),
        const Text(
          'AI 回答',
          style: TextStyle(
            color: _fgSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
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
    return _BrandQrFooter(inviteCode: inviteCode, channel: channel);
  }
}

/// 卡片底部的「品牌 + 下载二维码 + 邀请码」页脚，微信长图与小红书竖版共用。
///
/// 二维码指向下载落地页(带邀请码)，扫码下载后填码双方得螺壳，
/// 把分享流量沉淀为带归因的拉新。
class _BrandQrFooter extends StatelessWidget {
  const _BrandQrFooter({required this.inviteCode, required this.channel});

  final String inviteCode;
  final String channel;

  static const _accent = Color(0xFFD97706);
  static const _fgPrimary = Color(0xFF1A1A1A);
  static const _fgSecondary = Color(0xFF5A5A5A);
  static const _fgTertiary = Color(0xFF999999);
  static const _bgSoft = Color(0xFFFAF5EC);
  static const _border = Color(0xFFE6E1D5);

  @override
  Widget build(BuildContext context) {
    final hasCode = inviteCode.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        color: _bgSoft,
        border: Border(top: BorderSide(color: _border, width: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: QrImageView(
              data: _downloadUrl(inviteCode, channel),
              version: QrVersions.auto,
              size: 56,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: _fgPrimary),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: _fgPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '扫码下载「喜宽」AI 投研助理',
                  style: TextStyle(
                      color: _fgPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                if (hasCode)
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          color: _fgSecondary, fontSize: 10.5, height: 1.4),
                      children: [
                        const TextSpan(text: '邀请码 '),
                        TextSpan(
                          text: inviteCode,
                          style: const TextStyle(
                              color: _accent, fontWeight: FontWeight.w900),
                        ),
                        const TextSpan(text: ' · 填码双方各得螺壳'),
                      ],
                    ),
                  )
                else
                  const Text(
                    '聊行情、管组合、做日报 · 仅供参考',
                    style: TextStyle(color: _fgSecondary, fontSize: 10.5),
                  ),
                const SizedBox(height: 2),
                const Text(
                  'singzquant.com',
                  style: TextStyle(
                      color: _fgTertiary,
                      fontSize: 9.5,
                      letterSpacing: 0.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小红书竖版图文卡：封面式标题块 + 正文 + 二维码页脚。
///
/// 与微信长图的区别：固定较窄宽度 + 醒目封面头，更贴近小红书竖版笔记封面观感。
class _XhsCard extends StatelessWidget {
  const _XhsCard({
    required this.text,
    required this.timestamp,
    required this.inviteCode,
    required this.channel,
    this.question,
  });

  final String? question;
  final String text;
  final DateTime timestamp;
  final String inviteCode;
  final String channel;

  static const _accent = Color(0xFFD97706);
  static const _fgPrimary = Color(0xFF1A1A1A);
  static const _fgSecondary = Color(0xFF5A5A5A);
  static const _bgSoft = Color(0xFFFAF5EC);
  static const _border = Color(0xFFE6E1D5);

  @override
  Widget build(BuildContext context) {
    final headline =
        (question != null && question!.trim().isNotEmpty) ? question!.trim() : 'AI 投研助理怎么说？';
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cover(headline),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: MarkdownBody(
              data: text.isEmpty ? '…' : text,
              selectable: false,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                    color: _fgPrimary, fontSize: 13, height: 1.65),
                strong: const TextStyle(
                    color: _accent, fontWeight: FontWeight.w800),
                listBullet:
                    const TextStyle(color: _fgPrimary, fontSize: 13),
                h1: const TextStyle(
                    color: _fgPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18),
                h2: const TextStyle(
                    color: _fgPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
                h3: const TextStyle(
                    color: _fgPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
                blockquoteDecoration: const BoxDecoration(
                  color: _bgSoft,
                  border: Border(left: BorderSide(color: _accent, width: 3)),
                ),
                blockquote:
                    const TextStyle(color: _fgSecondary, fontSize: 12.5),
              ),
            ),
          ),
          _BrandQrFooter(inviteCode: inviteCode, channel: channel),
        ],
      ),
    );
  }

  /// 封面式头部：大字钩子标题 + 品牌标识，营造"竖版笔记封面"观感。
  Widget _cover(String headline) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFB35B05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '喜宽 · AI 投研助理',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            headline,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '滑到底部扫码免费体验 →',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
