import '../core/api/api_client.dart';

/// 把一条 AI 问答存到服务端，换回一个可公开访问的网页短链。
///
/// 服务端契约：
///   POST /v1/ai/share  { question?, answer }  ->  { id, url }
///   GET  /s/{id}                              ->  渲染好的品牌网页（公开）
class ShareService {
  ShareService({ApiClient? client}) : _api = client ?? ApiClient.instance;

  final ApiClient _api;

  /// 创建分享并返回可分享的 URL。
  Future<String> createShare({String? question, required String answer}) async {
    final r = await _api.dio.post('/v1/ai/share', data: {
      if (question != null && question.trim().isNotEmpty)
        'question': question.trim(),
      'answer': answer,
    });
    final data = r.data as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('服务端未返回分享链接');
    }
    return url;
  }
}
