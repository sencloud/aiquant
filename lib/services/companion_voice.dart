import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 她的声音：先用系统中文语音（iOS / Android 自带，零成本、无麦克风权限），
/// 音色以后可切到 CosyVoice（服务端代理）。
class CompanionVoice {
  CompanionVoice._();
  static final CompanionVoice instance = CompanionVoice._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.05);
      await _tts.setVolume(1.0);
      _tts.setStartHandler(() => speaking.value = true);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
      _ready = true;
    } catch (_) {
      // 测试 / 不支持 TTS 的平台：静默失败，文字照常。
    }
  }

  Future<void> speak(String text) async {
    final clean = _clean(text);
    if (clean.isEmpty) return;
    await init();
    try {
      await _tts.stop();
      await _tts.speak(clean.length > 400 ? clean.substring(0, 400) : clean);
    } catch (_) {
      speaking.value = false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
  }

  /// 去掉 markdown 标记、链接与列表符号，只留能读的字。
  String _clean(String raw) {
    var t = raw;
    t = t.replaceAll(RegExp(r'```.*?```', dotAll: true), ' ');
    t = t.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
    t = t.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
    t = t.replaceAll(RegExp(r'^[#>*\-+\d.\s]+', multiLine: true), '');
    t = t.replaceAll(RegExp(r'[*_`~]'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
