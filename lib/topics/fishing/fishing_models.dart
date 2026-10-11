/// 喜爱钓鱼的数据模型（与后端 internal/fishing 的 JSON 一一对应）。
library;

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
double? _dn(Object? v) => v is num ? v.toDouble() : null;
List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : const [];

/// 出钓指数的一个计分因子。
class ForecastFactor {
  const ForecastFactor({
    required this.key,
    required this.name,
    required this.value,
    required this.score,
    required this.max,
    required this.note,
  });

  factory ForecastFactor.fromJson(Map<String, dynamic> j) => ForecastFactor(
        key: _s(j['key']),
        name: _s(j['name']),
        value: _s(j['value']),
        score: _i(j['score']),
        max: _i(j['max']),
        note: _s(j['note']),
      );

  final String key;
  final String name;
  final String value;
  final int score;
  final int max;
  final String note;
}

class ForecastWindow {
  const ForecastWindow(
      {required this.from, required this.to, required this.label});
  factory ForecastWindow.fromJson(Map<String, dynamic> j) => ForecastWindow(
      from: _s(j['from']), to: _s(j['to']), label: _s(j['label']));
  final String from;
  final String to;
  final String label;
}

/// 某一天的出钓指数。
class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.score,
    required this.level,
    required this.summary,
    required this.factors,
    required this.windows,
    required this.warnings,
    required this.moonPhase,
    required this.sunrise,
    required this.sunset,
    required this.tempMin,
    required this.tempMax,
    required this.precipSum,
    required this.windMax,
  });

  factory ForecastDay.fromJson(Map<String, dynamic> j) => ForecastDay(
        date: _s(j['date']),
        score: _i(j['score']),
        level: _s(j['level']),
        summary: _s(j['summary']),
        factors: _maps(j['factors']).map(ForecastFactor.fromJson).toList(),
        windows: _maps(j['windows']).map(ForecastWindow.fromJson).toList(),
        warnings: (j['warnings'] as List?)?.map((e) => '$e').toList() ??
            const <String>[],
        moonPhase: _s((j['moon'] as Map?)?['phase']),
        sunrise: _s(j['sunrise']),
        sunset: _s(j['sunset']),
        tempMin: _d(j['temp_min']),
        tempMax: _d(j['temp_max']),
        precipSum: _d(j['precip_sum']),
        windMax: _d(j['wind_max']),
      );

  final String date;
  final int score;
  final String level;
  final String summary;
  final List<ForecastFactor> factors;
  final List<ForecastWindow> windows;
  final List<String> warnings;
  final String moonPhase;
  final String sunrise;
  final String sunset;
  final double tempMin;
  final double tempMax;
  final double precipSum;
  final double windMax;
}

/// 出钓指数整体返回。
class FishingForecast {
  const FishingForecast({
    required this.place,
    required this.lat,
    required this.lon,
    required this.days,
    required this.formula,
    required this.disclaimer,
    required this.activeBans,
  });

  factory FishingForecast.fromJson(Map<String, dynamic> j) => FishingForecast(
        place: _s(j['place']),
        lat: _d(j['lat']),
        lon: _d(j['lon']),
        days: _maps(j['days']).map(ForecastDay.fromJson).toList(),
        formula: _s(j['formula']),
        disclaimer: _s(j['disclaimer']),
        activeBans: (j['active_bans'] as List?)?.map((e) => '$e').toList() ??
            const <String>[],
      );

  final String place;
  final double lat;
  final double lon;
  final List<ForecastDay> days;
  final String formula;
  final String disclaimer;
  final List<String> activeBans;
}

/// 全国性禁渔 / 休渔制度。
class FishingRegulation {
  const FishingRegulation({
    required this.id,
    required this.name,
    required this.waters,
    required this.period,
    required this.scope,
    required this.angling,
    required this.source,
    required this.active,
  });

  factory FishingRegulation.fromJson(Map<String, dynamic> j) =>
      FishingRegulation(
        id: _s(j['id']),
        name: _s(j['name']),
        waters: _s(j['waters']),
        period: _s(j['period']),
        scope: _s(j['scope']),
        angling: _s(j['angling']),
        source: _s(j['source']),
        active: j['active'] == true,
      );

  final String id;
  final String name;
  final String waters;
  final String period;
  final String scope;
  final String angling;
  final String source;
  final bool active;
}

class FishingRegulations {
  const FishingRegulations(
      {required this.date, required this.items, required this.disclaimer});
  factory FishingRegulations.fromJson(Map<String, dynamic> j) =>
      FishingRegulations(
        date: _s(j['date']),
        items: _maps(j['regulations']).map(FishingRegulation.fromJson).toList(),
        disclaimer: _s(j['disclaimer']),
      );
  final String date;
  final List<FishingRegulation> items;
  final String disclaimer;

  List<FishingRegulation> get active => items.where((r) => r.active).toList();
}

/// 拍照识鱼的候选。
class FishCandidate {
  const FishCandidate({
    required this.name,
    required this.latin,
    required this.confidence,
    required this.features,
    required this.protected,
    required this.note,
  });

  factory FishCandidate.fromJson(Map<String, dynamic> j) => FishCandidate(
        name: _s(j['name']),
        latin: _s(j['latin']),
        confidence: _d(j['confidence']),
        features: _s(j['features']),
        protected: j['protected'] == true,
        note: _s(j['note']),
      );

  final String name;
  final String latin;
  final double confidence;
  final String features;
  final bool protected;
  final String note;
}

/// 一次识别。
class FishIdentification {
  const FishIdentification({
    required this.requestId,
    required this.status,
    required this.credits,
    required this.refunded,
    required this.candidates,
    required this.tips,
    required this.error,
    required this.disclaimer,
  });

  factory FishIdentification.fromJson(Map<String, dynamic> j) {
    final res = (j['result'] as Map?)?.cast<String, dynamic>();
    return FishIdentification(
      requestId: _s(j['request_id']),
      status: _s(j['status']),
      credits: _i(j['credits']),
      refunded: j['refunded'] == true,
      candidates:
          _maps(res?['candidates']).map(FishCandidate.fromJson).toList(),
      tips: _s(res?['tips']),
      error: _s(j['error']),
      disclaimer: _s(j['disclaimer']),
    );
  }

  final String requestId;
  final String status;
  final int credits;
  final bool refunded;
  final List<FishCandidate> candidates;
  final String tips;
  final String error;
  final String disclaimer;

  bool get ok => status == 'done' && candidates.isNotEmpty;
}

/// 私人钓点。
class FishingSpot {
  const FishingSpot({
    required this.uuid,
    required this.name,
    this.lat,
    this.lon,
    this.waterType = '',
    this.species = '',
    this.note = '',
  });

  factory FishingSpot.fromJson(Map<String, dynamic> j) => FishingSpot(
        uuid: _s(j['uuid']),
        name: _s(j['name']),
        lat: _dn(j['lat']),
        lon: _dn(j['lon']),
        waterType: _s(j['water_type']),
        species: _s(j['species']),
        note: _s(j['note']),
      );

  final String uuid;
  final String name;
  final double? lat;
  final double? lon;
  final String waterType;

  /// 主要鱼种（可选，自由文本，如「鲫鱼、翘嘴」）。
  final String species;
  final String note;

  /// 坐标是 WGS-84（见 map/geo_coord.dart 的约定）。
  bool get hasCoord => lat != null && lon != null;
}

/// 渔获记录。
class FishCatch {
  const FishCatch({
    required this.uuid,
    required this.caughtAt,
    required this.species,
    this.count = 1,
    this.weightG,
    this.lengthCm,
    this.spotName = '',
    this.method = '',
    this.bait = '',
    this.weather = '',
    this.note = '',
    this.released = false,
    this.hasPhoto = false,
  });

  factory FishCatch.fromJson(Map<String, dynamic> j) => FishCatch(
        uuid: _s(j['uuid']),
        caughtAt: DateTime.fromMillisecondsSinceEpoch(_i(j['caught_at'])),
        species: _s(j['species']),
        count: _i(j['count']),
        weightG: j['weight_g'] is num ? (j['weight_g'] as num).toInt() : null,
        lengthCm: _dn(j['length_cm']),
        spotName: _s(j['spot_name']),
        method: _s(j['method']),
        bait: _s(j['bait']),
        weather: _s(j['weather']),
        note: _s(j['note']),
        released: j['released'] == true,
        hasPhoto: j['has_photo'] == true,
      );

  final String uuid;
  final DateTime caughtAt;
  final String species;
  final int count;
  final int? weightG;
  final double? lengthCm;
  final String spotName;
  final String method;
  final String bait;
  final String weather;
  final String note;
  final bool released;
  final bool hasPhoto;
}

class CatchStats {
  const CatchStats(
      {this.trips = 0, this.fish = 0, this.species = 0, this.released = 0});
  factory CatchStats.fromJson(Map<String, dynamic> j) => CatchStats(
      trips: _i(j['trips']),
      fish: _i(j['fish']),
      species: _i(j['species']),
      released: _i(j['released']));
  final int trips;
  final int fish;
  final int species;
  final int released;
}
