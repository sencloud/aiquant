import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api/api_client.dart' show buildNoProxyAdapter;

class NewsItem {
  NewsItem({
    required this.title,
    required this.url,
    required this.source,
    required this.publishedAt,
    this.snippet,
    this.country,
    this.lang,
    this.tone,
  });
  final String title;
  final String url;
  final String source;
  final DateTime publishedAt;
  final String? snippet;
  final String? country;
  final String? lang;
  final double? tone;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'source': source,
        'published_at': publishedAt.toIso8601String(),
        if (snippet != null) 'snippet': snippet,
        if (country != null) 'country': country,
        if (lang != null) 'lang': lang,
        if (tone != null) 'tone': tone,
      };
}

class FireHotspot {
  FireHotspot({
    required this.lat,
    required this.lon,
    required this.brightness,
    required this.confidence,
    required this.acqAt,
    this.satellite,
  });
  final double lat;
  final double lon;
  final double brightness;
  final String confidence;
  final DateTime acqAt;
  final String? satellite;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'brightness': brightness,
        'confidence': confidence,
        'acquired_at': acqAt.toIso8601String(),
        if (satellite != null) 'satellite': satellite,
      };
}

/// 免费数据源聚合：
/// - GDELT DOC 2.0：覆盖全球新闻 + 事件，可按关键词/国家/时间过滤，无需 key
/// - Google News RSS：中文环境随便搜，无需 key
/// - NASA FIRMS：卫星火点（VIIRS/MODIS），需要免费 MAP_KEY
///
/// 全部公开 HTTPS 端点；网络异常一律静默返回空列表，让 AI 在工具结果为空
/// 时也能继续推理（"暂未拉到事件"对模型也是有效信号）。
class NewsService {
  NewsService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 12);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    _dio.httpClientAdapter = buildNoProxyAdapter();
  }
  final Dio _dio;

  // ── GDELT DOC 2.0 ──────────────────────────────────────────────────────
  // https://api.gdeltproject.org/api/v2/doc/doc?query=...&mode=ArtList&format=json
  Future<List<NewsItem>> searchGdelt({
    required String query,
    int maxRecords = 15,
    Duration lookback = const Duration(hours: 24),
    String? country, // ISO 3166-1 alpha-2，例如 CN/US/HK
    String? sourceLang, // 例如 chinese / english
  }) async {
    final qParts = <String>[query];
    if (country != null && country.isNotEmpty) {
      qParts.add('sourcecountry:${country.toUpperCase()}');
    }
    if (sourceLang != null && sourceLang.isNotEmpty) {
      qParts.add('sourcelang:${sourceLang.toLowerCase()}');
    }
    final params = {
      'query': qParts.join(' '),
      'mode': 'ArtList',
      'format': 'json',
      'maxrecords': maxRecords.clamp(1, 50).toString(),
      'sort': 'datedesc',
      'timespan': _gdeltTimespan(lookback),
    };
    Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        'https://api.gdeltproject.org/api/v2/doc/doc',
        queryParameters: params,
        options: Options(responseType: ResponseType.plain),
      );
    } catch (_) {
      return const [];
    }
    final raw = resp.data;
    if (raw is! String || raw.isEmpty || !raw.trim().startsWith('{')) {
      return const [];
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const [];
    }
    final articles = (json['articles'] as List?) ?? const [];
    final out = <NewsItem>[];
    for (final a in articles) {
      if (a is! Map) continue;
      final url = (a['url'] ?? '').toString();
      final title = (a['title'] ?? '').toString().trim();
      if (url.isEmpty || title.isEmpty) continue;
      out.add(NewsItem(
        title: title,
        url: url,
        source: (a['domain'] ?? a['sourcecountry'] ?? '').toString(),
        publishedAt:
            _parseGdeltSeenDate((a['seendate'] ?? '').toString()) ??
                DateTime.now(),
        country: (a['sourcecountry'] ?? '').toString(),
        lang: (a['language'] ?? '').toString(),
        tone: (a['tone'] is num)
            ? (a['tone'] as num).toDouble()
            : double.tryParse((a['tone'] ?? '').toString()),
      ));
    }
    return out;
  }

  // ── Google News RSS ────────────────────────────────────────────────────
  Future<List<NewsItem>> searchGoogleNews({
    required String query,
    int maxItems = 12,
    String hl = 'zh-CN',
    String gl = 'CN',
    String ceid = 'CN:zh-Hans',
  }) async {
    Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        'https://news.google.com/rss/search',
        queryParameters: {'q': query, 'hl': hl, 'gl': gl, 'ceid': ceid},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (_) {
      return const [];
    }
    final raw = resp.data;
    if (raw is! String) return const [];
    return _parseRssItems(raw, fallbackSource: 'Google News')
        .take(maxItems)
        .toList();
  }

  // ── NASA FIRMS（卫星火点）──────────────────────────────────────────────
  // 需要免费 MAP_KEY；https://firms.modaps.eosdis.nasa.gov/api/area/
  Future<List<FireHotspot>> firmsHotspots({
    required double west,
    required double south,
    required double east,
    required double north,
    int dayRange = 1,
    String dataset = 'VIIRS_SNPP_NRT',
    String? mapKey,
  }) async {
    if (mapKey == null || mapKey.trim().isEmpty) return const [];
    final url =
        'https://firms.modaps.eosdis.nasa.gov/api/area/csv/${mapKey.trim()}'
        '/$dataset/$west,$south,$east,$north/$dayRange';
    Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
    } catch (_) {
      return const [];
    }
    final raw = resp.data;
    if (raw is! String) return const [];
    final lines = raw.split('\n');
    if (lines.length < 2) return const [];
    final header = lines.first.split(',');
    final idx = {
      for (var i = 0; i < header.length; i++) header[i].trim(): i,
    };
    final out = <FireHotspot>[];
    for (var i = 1; i < lines.length && out.length < 100; i++) {
      final ln = lines[i].trim();
      if (ln.isEmpty) continue;
      final cols = ln.split(',');
      double? toDouble(String key) {
        final j = idx[key];
        if (j == null || j >= cols.length) return null;
        return double.tryParse(cols[j]);
      }

      final lat = toDouble('latitude');
      final lon = toDouble('longitude');
      final bright = toDouble('bright_ti4') ??
          toDouble('brightness') ??
          toDouble('bright_ti5');
      if (lat == null || lon == null || bright == null) continue;
      final dt = (idx['acq_date'] != null && idx['acq_time'] != null)
          ? _parseFirmsTimestamp(
              cols[idx['acq_date']!], cols[idx['acq_time']!])
          : DateTime.now();
      out.add(FireHotspot(
        lat: lat,
        lon: lon,
        brightness: bright,
        confidence:
            (idx['confidence'] != null && idx['confidence']! < cols.length)
                ? cols[idx['confidence']!]
                : 'n',
        acqAt: dt,
        satellite:
            (idx['satellite'] != null && idx['satellite']! < cols.length)
                ? cols[idx['satellite']!]
                : null,
      ));
    }
    return out;
  }

  // ── helpers ───────────────────────────────────────────────────────────

  String _gdeltTimespan(Duration d) {
    if (d.inDays >= 7) return '${(d.inDays / 7).round().clamp(1, 4)}w';
    if (d.inDays >= 1) return '${d.inDays.clamp(1, 30)}d';
    return '${d.inHours.clamp(1, 168)}h';
  }

  DateTime? _parseGdeltSeenDate(String raw) {
    if (raw.length < 14) return null;
    try {
      return DateTime.utc(
        int.parse(raw.substring(0, 4)),
        int.parse(raw.substring(4, 6)),
        int.parse(raw.substring(6, 8)),
        int.parse(raw.substring(9, 11)),
        int.parse(raw.substring(11, 13)),
        int.parse(raw.substring(13, 15)),
      );
    } catch (_) {
      return null;
    }
  }

  DateTime _parseFirmsTimestamp(String date, String time) {
    final t = time.padLeft(4, '0');
    try {
      return DateTime.utc(
        int.parse(date.substring(0, 4)),
        int.parse(date.substring(5, 7)),
        int.parse(date.substring(8, 10)),
        int.parse(t.substring(0, 2)),
        int.parse(t.substring(2, 4)),
      );
    } catch (_) {
      return DateTime.now().toUtc();
    }
  }

  /// 极简 RSS XML 解析（避免引入 xml 包）：用正则抽 <item> 块。
  Iterable<NewsItem> _parseRssItems(
    String xml, {
    required String fallbackSource,
  }) sync* {
    final itemRe = RegExp(r'<item>([\s\S]*?)</item>', multiLine: true);
    final titleRe =
        RegExp(r'<title(?:\s[^>]*)?>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</title>');
    final linkRe = RegExp(r'<link(?:\s[^>]*)?>([\s\S]*?)</link>');
    final pubRe = RegExp(r'<pubDate>([\s\S]*?)</pubDate>');
    final srcRe = RegExp(
        r'<source(?:\s[^>]*)?>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</source>');

    for (final m in itemRe.allMatches(xml)) {
      final block = m.group(1) ?? '';
      final title = (titleRe.firstMatch(block)?.group(1) ?? '').trim();
      final link = (linkRe.firstMatch(block)?.group(1) ?? '').trim();
      if (title.isEmpty || link.isEmpty) continue;
      final pubText = (pubRe.firstMatch(block)?.group(1) ?? '').trim();
      final source =
          (srcRe.firstMatch(block)?.group(1) ?? fallbackSource).trim();
      yield NewsItem(
        title: title,
        url: link,
        source: source,
        publishedAt: _parseRfc822(pubText) ?? DateTime.now(),
      );
    }
  }

  DateTime? _parseRfc822(String s) {
    if (s.isEmpty) return null;
    try {
      // 例: Wed, 14 May 2026 03:21:00 GMT
      final parts = s.split(' ');
      if (parts.length < 5) return null;
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final day = int.parse(parts[1]);
      final month = months[parts[2]] ?? 1;
      final year = int.parse(parts[3]);
      final time = parts[4].split(':');
      return DateTime.utc(
        year,
        month,
        day,
        int.parse(time[0]),
        int.parse(time[1]),
        time.length > 2 ? int.parse(time[2]) : 0,
      );
    } catch (_) {
      return null;
    }
  }
}
