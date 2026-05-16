import 'dart:convert';

import '../ai_tools.dart';
import '../news_service.dart';

class EventToolsContext {
  EventToolsContext({required this.svc, this.firmsKey});
  final NewsService svc;
  final String? firmsKey;
}

Duration _parseLookback(String? s, Duration fallback) {
  if (s == null || s.isEmpty) return fallback;
  final m = RegExp(r'^(\d+)\s*([hdw])$', caseSensitive: false).firstMatch(s);
  if (m == null) return fallback;
  final n = int.parse(m.group(1)!);
  switch (m.group(2)!.toLowerCase()) {
    case 'h':
      return Duration(hours: n);
    case 'd':
      return Duration(days: n);
    case 'w':
      return Duration(days: n * 7);
  }
  return fallback;
}

/// 19. 搜全球事件 / 国际新闻（GDELT DOC API）
class SearchGlobalEventsTool extends AiTool {
  SearchGlobalEventsTool(this._ctx);
  final EventToolsContext _ctx;

  @override
  String get name => 'search_global_events';
  @override
  String get description =>
      '在 GDELT 全球新闻数据库（覆盖 100+ 国家、65 种语言）里按关键词搜索最近一段'
      '时间的国际事件、地缘政治、宏观新闻、大宗商品等。返回包含标题、来源、时间、'
      '基调（tone）的新闻列表。'
      '\n例如：航运中断 / OPEC 减产 / 红海袭击 / 美联储加息 / 台海 / 中东冲突 / '
      'AI 监管 / 气候峰会 等关键词都可以查。'
      '\n基调（tone）越负面表示新闻情绪越负面，可作为情绪指标。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'query': {
            'type': 'string',
            'description': '关键词，可以是中英文（GDELT 同时索引中英文新闻）',
          },
          'lookback': {
            'type': 'string',
            'description': '回看时长，格式如 6h / 24h / 3d / 7d / 2w（默认 24h）',
          },
          'country': {
            'type': 'string',
            'description': '只看某国来源（ISO-2 代码：CN/US/JP/HK/IN…）',
          },
          'lang': {
            'type': 'string',
            'description': '只看某语言（chinese / english / japanese 等）',
          },
          'limit': {
            'type': 'integer',
            'description': '返回前 N 条（默认 12，最大 50）',
          },
        },
        required: ['query'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final q = (args['query'] as String? ?? '').trim();
    if (q.isEmpty) return jsonEncode({'error': 'query 必填'});
    final lookback = _parseLookback(
        args['lookback'] as String?, const Duration(hours: 24));
    final limit = ((args['limit'] as num?)?.toInt() ?? 12).clamp(1, 50);
    final country = (args['country'] as String?)?.trim();
    final lang = (args['lang'] as String?)?.trim();
    final items = await _ctx.svc.searchGdelt(
      query: q,
      maxRecords: limit,
      lookback: lookback,
      country: country,
      sourceLang: lang,
    );
    return jsonEncode({
      'query': q,
      'lookback': lookback.inHours >= 24
          ? '${lookback.inDays}d'
          : '${lookback.inHours}h',
      'count': items.length,
      'articles': [for (final n in items) n.toJson()],
      if (items.isNotEmpty)
        'avg_tone': double.parse(
            (items
                        .where((n) => n.tone != null)
                        .fold<double>(0, (s, n) => s + n.tone!) /
                    (items.where((n) => n.tone != null).length.clamp(1, 999)))
                .toStringAsFixed(3)),
    });
  }
}

/// 20. 搜中文新闻（Google News RSS，中文环境）
class SearchChineseNewsTool extends AiTool {
  SearchChineseNewsTool(this._ctx);
  final EventToolsContext _ctx;

  @override
  String get name => 'search_chinese_news';
  @override
  String get description =>
      '搜索 Google News 中文环境下与关键词匹配的最新新闻（中文媒体为主）。'
      '与 search_global_events 互补：GDELT 偏全球宏观/事件，本工具偏中文媒体直接报道。'
      '\n适合查具体公司、A 股板块、政策发布、行业动态等中文媒体覆盖更全的话题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'query': {
            'type': 'string',
            'description': '关键词（建议中文，例如"贵州茅台 业绩"、"光伏 装机"）',
          },
          'limit': {
            'type': 'integer',
            'description': '返回前 N 条（默认 10，最大 25）',
          },
        },
        required: ['query'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final q = (args['query'] as String? ?? '').trim();
    if (q.isEmpty) return jsonEncode({'error': 'query 必填'});
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 25);
    final items = await _ctx.svc.searchGoogleNews(query: q, maxItems: limit);
    return jsonEncode({
      'query': q,
      'count': items.length,
      'articles': [for (final n in items) n.toJson()],
    });
  }
}

/// 21. 全球航运/海事事件（GDELT 主题预设）
class SearchShippingEventsTool extends AiTool {
  SearchShippingEventsTool(this._ctx);
  final EventToolsContext _ctx;

  @override
  String get name => 'search_shipping_events';
  @override
  String get description =>
      '搜索全球航运 / 港口 / 海事 / 海运中断相关事件（关键词预设：'
      'shipping OR port OR maritime OR strait OR canal OR vessel）。'
      '红海危机、苏伊士运河、巴拿马运河水位、马六甲、台湾海峡等突发事件会通过这里抓到。'
      '常用于分析航运 ETF / 集运指数期货 / 油运板块 / 大宗商品物流的影响。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'lookback': {
            'type': 'string',
            'description': '回看时长（默认 7d，最长 4w）',
          },
          'limit': {'type': 'integer', 'description': '默认 15，最大 50'},
          'extra_keyword': {
            'type': 'string',
            'description': '可选：在航运主题里再加一个限定词（例如"red sea"、"hormuz"）',
          },
        },
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final lookback =
        _parseLookback(args['lookback'] as String?, const Duration(days: 7));
    final limit = ((args['limit'] as num?)?.toInt() ?? 15).clamp(1, 50);
    final extra = (args['extra_keyword'] as String?)?.trim() ?? '';
    const base =
        '(shipping OR port OR maritime OR vessel OR strait OR canal OR "sea route")';
    final query = extra.isEmpty ? base : '$base AND ($extra)';
    final items = await _ctx.svc.searchGdelt(
      query: query,
      maxRecords: limit,
      lookback: lookback,
    );
    return jsonEncode({
      'theme': 'global_shipping',
      'query': query,
      'lookback':
          lookback.inDays >= 1 ? '${lookback.inDays}d' : '${lookback.inHours}h',
      'count': items.length,
      'articles': [for (final n in items) n.toJson()],
    });
  }
}

/// 22. 地缘政治 / 武装冲突事件
class SearchGeopoliticsEventsTool extends AiTool {
  SearchGeopoliticsEventsTool(this._ctx);
  final EventToolsContext _ctx;

  @override
  String get name => 'search_geopolitics_events';
  @override
  String get description =>
      '搜索全球地缘政治 / 武装冲突 / 制裁 / 外交摩擦类事件，'
      '关键词预设包含 conflict / sanction / sanction / military / war / treaty / summit。'
      '常用于分析军工、能源、避险资产（黄金/美债）等板块。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'lookback': {'type': 'string', 'description': '默认 3d'},
          'region': {
            'type': 'string',
            'description':
                '可选：限定地理关键词（如 "middle east"、"taiwan strait"、"ukraine"、"south china sea"）',
          },
          'limit': {'type': 'integer', 'description': '默认 15，最大 50'},
        },
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final lookback =
        _parseLookback(args['lookback'] as String?, const Duration(days: 3));
    final limit = ((args['limit'] as num?)?.toInt() ?? 15).clamp(1, 50);
    final region = (args['region'] as String?)?.trim() ?? '';
    const base =
        '(conflict OR sanction OR military OR war OR treaty OR summit OR diplomatic)';
    final query = region.isEmpty ? base : '$base AND ("$region")';
    final items = await _ctx.svc.searchGdelt(
      query: query,
      maxRecords: limit,
      lookback: lookback,
    );
    return jsonEncode({
      'theme': 'geopolitics',
      'query': query,
      'lookback':
          lookback.inDays >= 1 ? '${lookback.inDays}d' : '${lookback.inHours}h',
      'count': items.length,
      'articles': [for (final n in items) n.toJson()],
    });
  }
}

/// 23. NASA FIRMS 卫星火点（VIIRS/MODIS）
/// 主要用途：识别森林火灾 / 工业事故 / 钻井平台燃烧等热源，
/// 对棕榈油、橡胶、木材、油气库存等大宗商品有传导效应。
class GetFireHotspotsTool extends AiTool {
  GetFireHotspotsTool(this._ctx);
  final EventToolsContext _ctx;

  @override
  String get name => 'get_satellite_fire_hotspots';
  @override
  String get description =>
      '通过 NASA FIRMS 拉取最近 N 天卫星观测到的火点（热源）数据，'
      '可指定经纬度范围（默认全球热点区域）。需要在 .env 配置 FIRMS_MAP_KEY '
      '才会有数据返回。'
      '常见用法：东南亚棕榈油产区火点（→ 棕榈油价格）、加拿大林火（→ 木材/纸浆）、'
      '俄乌石油设施袭击热点（→ 原油）。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'west': {'type': 'number', 'description': '经度西界 (-180~180)'},
          'south': {'type': 'number', 'description': '纬度南界 (-90~90)'},
          'east': {'type': 'number', 'description': '经度东界'},
          'north': {'type': 'number', 'description': '纬度北界'},
          'day_range': {'type': 'integer', 'description': '回看天数（1~10，默认 1）'},
          'dataset': {
            'type': 'string',
            'enum': [
              'VIIRS_SNPP_NRT',
              'VIIRS_NOAA20_NRT',
              'MODIS_NRT',
            ],
            'description': '默认 VIIRS_SNPP_NRT',
          },
        },
        required: ['west', 'south', 'east', 'north'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    if (_ctx.firmsKey == null || _ctx.firmsKey!.trim().isEmpty) {
      return jsonEncode({
        'error':
            '未配置 FIRMS_MAP_KEY；请去 https://firms.modaps.eosdis.nasa.gov/api/ 申请免费 key 后写入 .env',
      });
    }
    final w = (args['west'] as num?)?.toDouble();
    final s = (args['south'] as num?)?.toDouble();
    final e = (args['east'] as num?)?.toDouble();
    final n = (args['north'] as num?)?.toDouble();
    if (w == null || s == null || e == null || n == null) {
      return jsonEncode({'error': '需要 west/south/east/north 四个边界'});
    }
    final dayRange = ((args['day_range'] as num?)?.toInt() ?? 1).clamp(1, 10);
    final dataset = (args['dataset'] as String?) ?? 'VIIRS_SNPP_NRT';
    final pts = await _ctx.svc.firmsHotspots(
      west: w,
      south: s,
      east: e,
      north: n,
      dayRange: dayRange,
      dataset: dataset,
      mapKey: _ctx.firmsKey,
    );
    return jsonEncode({
      'bbox': {'west': w, 'south': s, 'east': e, 'north': n},
      'dataset': dataset,
      'day_range': dayRange,
      'count': pts.length,
      'hotspots': [for (final p in pts.take(50)) p.toJson()],
    });
  }
}

/// 工厂：构建事件流工具组
List<AiTool> buildEventTools({
  NewsService? service,
  String? firmsMapKey,
}) {
  final ctx = EventToolsContext(svc: service ?? NewsService(), firmsKey: firmsMapKey);
  return [
    SearchGlobalEventsTool(ctx),
    SearchChineseNewsTool(ctx),
    SearchShippingEventsTool(ctx),
    SearchGeopoliticsEventsTool(ctx),
    GetFireHotspotsTool(ctx),
  ];
}
