import '../core/storage/hive_setup.dart';

/// 故事存档。抽出来是为了测试能注入内存实现，不让 Hive 把单测拖死。
abstract class StoryStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class HiveStoryStore implements StoryStore {
  static const _key = 'story.save.v1';

  @override
  Future<String?> read() async {
    try {
      if (!prefsBox.isOpen) return null;
      return prefsBox.get(_key) as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      if (!prefsBox.isOpen) return;
      await prefsBox.put(_key, value);
    } catch (_) {
      // 存不进去也不能让故事停住：内存里还有一份。
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (!prefsBox.isOpen) return;
      await prefsBox.delete(_key);
    } catch (_) {}
  }
}

class MemoryStoryStore implements StoryStore {
  MemoryStoryStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}
