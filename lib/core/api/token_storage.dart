import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

/// 双 token 持久化。Keychain (iOS) / Keystore (Android) 加密存储。
///
/// - 单进程访问，不需要做并发互斥。
/// - 序列化用 JSON；解析失败一律视为"未登录"，由上层重新登录。
class TokenStorage {
  TokenStorage._({required FlutterSecureStorage storage}) : _storage = storage;

  factory TokenStorage() {
    return TokenStorage._(
      storage: const FlutterSecureStorage(
        // Android: secure_storage 10+ 自动用自定义 cipher，不需要 EncryptedSharedPreferences。
        aOptions: AndroidOptions(),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      ),
    );
  }

  static const _kTokens = 'finme_tokens_v1';
  static const _kUser = 'finme_user_v1';
  static const _kDeviceId = 'finme_device_id_v1';

  final FlutterSecureStorage _storage;

  Future<void> saveTokens(TokenPair p) async {
    await _storage.write(key: _kTokens, value: jsonEncode(p.toJson()));
  }

  Future<TokenPair?> loadTokens() async {
    final raw = await _storage.read(key: _kTokens);
    if (raw == null || raw.isEmpty) return null;
    try {
      return TokenPair.fromStored(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _kTokens);
      return null;
    }
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _kTokens);
  }

  Future<void> saveUser(UserPublic u) async {
    await _storage.write(key: _kUser, value: jsonEncode(u.toJson()));
  }

  Future<UserPublic?> loadUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserPublic.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _kUser);
      return null;
    }
  }

  Future<void> clearUser() async {
    await _storage.delete(key: _kUser);
  }

  /// 设备 id 由客户端首次启动时生成，之后保持稳定（卸载重装会换新）。
  Future<String?> readDeviceId() => _storage.read(key: _kDeviceId);
  Future<void> writeDeviceId(String id) =>
      _storage.write(key: _kDeviceId, value: id);

  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _kTokens),
      _storage.delete(key: _kUser),
    ]);
  }
}
