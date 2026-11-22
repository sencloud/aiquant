import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart' show prefsBox;
import '../models/trade_review.dart';

class TradeReviewStore extends ChangeNotifier {
  TradeReviewStore._();

  static final TradeReviewStore instance = TradeReviewStore._();
  static const _storageKey = 'trade_reviews.v1';
  static const _maxReports = 20;

  List<TradeReviewReport>? _reports;

  List<TradeReviewReport> get reports => List.unmodifiable(_load());

  TradeReviewReport? get latest => reports.isEmpty ? null : reports.first;

  TradeReviewReport? byId(String id) {
    for (final report in _load()) {
      if (report.id == id) return report;
    }
    return null;
  }

  Future<void> save(TradeReviewReport report) async {
    final rows = _load().where((item) => item.id != report.id).toList()
      ..insert(0, report);
    _reports = rows.take(_maxReports).toList(growable: false);
    await prefsBox.put(
      _storageKey,
      jsonEncode(_reports!.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _reports = _load().where((item) => item.id != id).toList(growable: false);
    await prefsBox.put(
      _storageKey,
      jsonEncode(_reports!.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> clear() async {
    _reports = const [];
    await prefsBox.delete(_storageKey);
    notifyListeners();
  }

  List<TradeReviewReport> _load() {
    if (_reports != null) return _reports!;
    try {
      final raw = prefsBox.get(_storageKey);
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _reports = [
            for (final row in decoded)
              if (row is Map)
                TradeReviewReport.fromJson(
                  Map<String, dynamic>.from(row),
                ),
          ];
          return _reports!;
        }
      }
    } catch (_) {
      // Corrupt local history should not make the review surface unusable.
    }
    _reports = const [];
    return _reports!;
  }
}
