/// 小应用（对话生成的发现页小工具）的数据模型。字段与后端 /v1/miniapps/* 一致。
library;

import 'expr/xel.dart' show normalize;

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

int _int(dynamic v) => v is num ? v.toInt() : 0;

/// 用户自己的小应用。
class MiniApp {
  MiniApp({
    required this.uuid,
    required this.topic,
    required this.title,
    required this.icon,
    required this.summary,
    required this.status,
    required this.version,
    required this.mounted,
    required this.position,
    required this.cardSize,
    required this.sessionId,
    required this.spec,
    this.templateId,
    this.inputs = const {},
    this.state = const {},
    this.updatedAt = 0,
  });

  final String uuid;
  final String topic;
  final String title;
  final String icon;
  final String summary;
  final String status;
  final int version;
  final bool mounted;
  final int position;
  final String cardSize;
  final String sessionId;
  final String? templateId;
  final Map<String, dynamic> spec;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> state;
  final int updatedAt;

  factory MiniApp.fromJson(Map<String, dynamic> j) => MiniApp(
        uuid: j['uuid'] as String? ?? '',
        topic: j['topic'] as String? ?? 'money',
        title: j['title'] as String? ?? '',
        icon: j['icon'] as String? ?? 'apps',
        summary: j['summary'] as String? ?? '',
        status: j['status'] as String? ?? 'draft',
        version: _int(j['version']),
        mounted: j['mounted'] == true,
        position: _int(j['position']),
        cardSize: j['card_size'] as String? ?? 'medium',
        sessionId: j['session_id'] as String? ?? '',
        templateId: j['template_id'] as String?,
        spec: normalize(_map(j['spec'])) as Map<String, dynamic>,
        inputs: normalize(_map(j['inputs'])) as Map<String, dynamic>,
        state: normalize(_map(j['state'])) as Map<String, dynamic>,
        updatedAt: _int(j['updated_at']),
      );
}

/// 官方模板（未登录也能浏览）。
class MiniAppTemplate {
  MiniAppTemplate({
    required this.id,
    required this.topic,
    required this.title,
    required this.summary,
    required this.icon,
    required this.spec,
    this.privateData = false,
  });

  final String id;
  final String topic;
  final String title;
  final String summary;
  final String icon;
  final Map<String, dynamic> spec;
  final bool privateData;

  String get cardSize =>
      (spec['meta'] is Map ? spec['meta']['card_size'] as String? : null) ??
      'medium';

  factory MiniAppTemplate.fromJson(Map<String, dynamic> j) => MiniAppTemplate(
        id: j['id'] as String? ?? '',
        topic: j['topic'] as String? ?? 'money',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        icon: j['icon'] as String? ?? 'apps',
        spec: normalize(_map(j['spec'])) as Map<String, dynamic>,
        privateData: j['private_data'] == true,
      );
}

/// 澄清问题。
class GenQuestion {
  GenQuestion(this.q, this.options);
  final String q;
  final List<String> options;

  factory GenQuestion.fromJson(Map<String, dynamic> j) => GenQuestion(
        j['q'] as String? ?? '',
        [for (final o in (j['options'] as List? ?? const [])) '$o'],
      );
}

/// 一次生成（一轮工坊对话）。
class MiniAppGen {
  MiniAppGen({
    required this.requestId,
    required this.sessionId,
    required this.topic,
    required this.kind,
    required this.status,
    required this.stage,
    required this.outcome,
    required this.message,
    required this.credits,
    required this.refunded,
    this.resultMessage,
    this.questions = const [],
    this.appUuid,
    this.version,
    this.summary,
    this.warnings = const [],
    this.error,
  });

  final String requestId;
  final String sessionId;
  final String topic;
  final String kind; // create / iterate
  final String status; // pending / done / failed
  final String stage; // thinking / validating / repairing / dry_run
  final String outcome; // ask / spec / refuse / fail
  final String message; // 用户这一轮说的话
  final int credits;
  final bool refunded;
  final String? resultMessage;
  final List<GenQuestion> questions;
  final String? appUuid;
  final int? version;
  final String? summary;
  final List<String> warnings;
  final String? error;

  bool get pending => status == 'pending';

  factory MiniAppGen.fromJson(Map<String, dynamic> j) {
    final r = _map(j['result']);
    return MiniAppGen(
      requestId: j['request_id'] as String? ?? '',
      sessionId: j['session_id'] as String? ?? '',
      topic: j['topic'] as String? ?? '',
      kind: j['kind'] as String? ?? 'create',
      status: j['status'] as String? ?? 'pending',
      stage: j['stage'] as String? ?? '',
      outcome: j['outcome'] as String? ?? '',
      message: j['message'] as String? ?? '',
      credits: _int(j['credits']),
      refunded: j['refunded'] == true,
      resultMessage: r['message'] as String?,
      questions: [
        for (final q in (r['questions'] as List? ?? const []))
          if (q is Map) GenQuestion.fromJson(q.cast<String, dynamic>())
      ],
      appUuid: r['app_uuid'] as String?,
      version: r['version'] == null ? null : _int(r['version']),
      summary: r['summary'] as String?,
      warnings: [for (final w in (r['warnings'] as List? ?? const [])) '$w'],
      error: j['error'] as String?,
    );
  }
}

/// 一次取数结果。
class MiniAppRun {
  MiniAppRun({
    required this.inputs,
    required this.data,
    required this.errors,
    required this.fetchedAt,
  });

  final Map<String, dynamic> inputs;
  final Map<String, dynamic> data;
  final Map<String, String> errors;
  final int fetchedAt;

  static final empty =
      MiniAppRun(inputs: const {}, data: const {}, errors: const {}, fetchedAt: 0);

  factory MiniAppRun.fromJson(Map<String, dynamic> j) => MiniAppRun(
        inputs: normalize(_map(j['inputs'])) as Map<String, dynamic>,
        data: normalize(_map(j['data'])) as Map<String, dynamic>,
        errors: {
          for (final e in _map(j['errors']).entries) e.key: '${e.value}'
        },
        fetchedAt: _int(j['fetched_at']),
      );
}

/// 目录：价格、限额、是否可生成。
class MiniAppCatalog {
  MiniAppCatalog({
    this.createCredits = 5,
    this.iterateCredits = 2,
    this.maxApps = 20,
    this.maxMounted = 12,
    this.maxMessage = 500,
    this.generation = true,
    this.disclaimer = '',
    this.rendererVersion = 1,
  });

  final int createCredits;
  final int iterateCredits;
  final int maxApps;
  final int maxMounted;
  final int maxMessage;
  final bool generation;
  final String disclaimer;
  final int rendererVersion;

  factory MiniAppCatalog.fromJson(Map<String, dynamic> j) {
    final p = _map(j['prices']);
    final l = _map(j['limits']);
    return MiniAppCatalog(
      createCredits: _int(p['create'] ?? 5),
      iterateCredits: _int(p['iterate'] ?? 2),
      maxApps: _int(l['apps'] ?? 20),
      maxMounted: _int(l['mounted'] ?? 12),
      maxMessage: _int(l['message_runes'] ?? 500),
      generation: j['generation'] != false,
      disclaimer: j['disclaimer'] as String? ?? '',
      rendererVersion: _int(j['renderer_version'] ?? 1),
    );
  }
}
