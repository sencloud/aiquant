import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_models.dart';

/// 调用 Finme Backend 鉴权接口的薄封装。AuthState 持有这个 service。
class AuthService {
  AuthService({ApiClient? client}) : _api = client ?? ApiClient.instance;

  final ApiClient _api;

  Future<void> sendSMS(String phone) async {
    await _api.dio.post(
      '/v1/auth/sms/send',
      data: {'phone': phone},
      options: _noAuth(),
    );
  }

  Future<({TokenPair tokens, UserPublic user})> verifySMS({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    final r = await _api.dio.post(
      '/v1/auth/sms/verify',
      data: {'phone': phone, 'code': code, 'device_id': deviceId},
      options: _noAuth(),
    );
    return _parseLoginResponse(r);
  }

  Future<void> sendEmailCode(String email) async {
    await _api.dio.post(
      '/v1/auth/email/send',
      data: {'email': email},
      options: _noAuth(),
    );
  }

  Future<({TokenPair tokens, UserPublic user})> verifyEmail({
    required String email,
    required String code,
    required String deviceId,
  }) async {
    final r = await _api.dio.post(
      '/v1/auth/email/verify',
      data: {'email': email, 'code': code, 'device_id': deviceId},
      options: _noAuth(),
    );
    return _parseLoginResponse(r);
  }

  Future<({TokenPair tokens, UserPublic user})> appleLogin({
    required String identityToken,
    String nickname = '',
    required String deviceId,
  }) async {
    final r = await _api.dio.post(
      '/v1/auth/apple',
      data: {
        'identity_token': identityToken,
        'nickname': nickname,
        'device_id': deviceId,
      },
      options: _noAuth(),
    );
    return _parseLoginResponse(r);
  }

  Future<UserPublic> me() async {
    final r = await _api.dio.get('/v1/me');
    return UserPublic.fromJson(r.data as Map<String, dynamic>);
  }

  Future<UserPublic> updateNickname(String nickname) async {
    final r = await _api.dio.patch(
      '/v1/me',
      data: {'nickname': nickname},
    );
    return UserPublic.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> upsertDevice({
    required String deviceId,
    required String platform,
    String? pushToken,
    required String appVersion,
  }) async {
    await _api.dio.post('/v1/devices', data: {
      'device_id': deviceId,
      'platform': platform,
      if (pushToken != null && pushToken.isNotEmpty) 'push_token': pushToken,
      'app_version': appVersion,
    });
  }

  Future<void> logout() async {
    try {
      await _api.dio.post('/v1/auth/logout');
    } catch (_) {
      // 服务端登出失败也照样清本地
    }
    await _api.notifyLogout();
  }

  Future<void> deleteAccount() async {
    await _api.dio.delete('/v1/me');
    await _api.notifyLogout();
  }

  ({TokenPair tokens, UserPublic user}) _parseLoginResponse(Response r) {
    final body = r.data as Map<String, dynamic>;
    final tokens = TokenPair.fromJson(body['tokens'] as Map<String, dynamic>);
    final user = UserPublic.fromJson(body['user'] as Map<String, dynamic>);
    return (tokens: tokens, user: user);
  }

  Options _noAuth() => Options(extra: {'__skip_auth__': true});
}
