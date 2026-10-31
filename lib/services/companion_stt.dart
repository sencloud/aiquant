import 'package:speech_to_text/speech_to_text.dart';

/// 你的声音：系统中文语音识别（iOS / Android 自带，不上传第三方服务）。
///
/// 点击麦克风开始，识别到一句完整的话就停；再说一次再点。
class CompanionStt {
  CompanionStt._();
  static final CompanionStt instance = CompanionStt._();

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize();
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  Future<bool> start({
    required void Function(String text) onText,
    void Function()? onDone,
  }) async {
    if (!await init()) return false;
    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'zh_CN',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
        onResult: (r) {
          if (!r.finalResult) return;
          final text = r.recognizedWords.trim();
          if (text.isNotEmpty) onText(text);
          onDone?.call();
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
