import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_models.dart';
import '../core/storage/hive_setup.dart' show prefsBox;
import '../models/trade_review.dart';

typedef TradeReviewCloudLoader = Future<List<TradeReviewReport>> Function(
  String account,
);

class TradeReviewStore extends ChangeNotifier {
  TradeReviewStore._({TradeReviewCloudLoader? cloudLoader})
      : _cloudLoader = cloudLoader;

  static final TradeReviewStore instance = TradeReviewStore._();
  static const _legacyStorageKey = 'trade_reviews.v1';
  static const _guestAccount = 'guest';
  static const _storagePrefix = 'trade_reviews.v2.';
  static const _tombstonePrefix = 'trade_reviews.v2.deleted.';
  static const _pendingUploadPrefix = 'trade_reviews.v2.pending.';
  static const _legacyMigrationOwnerKey = 'trade_reviews.v2.legacy_owner';
  static const _maxReports = 20;

  List<TradeReviewReport>? _reports;
  String? _accountId;
  bool _binding = false;
  bool _loading = false;
  bool _syncing = false;
  String? _syncError;
  int _accountEpoch = 0;
  Completer<bool>? _bindCompleter;
  final TradeReviewCloudLoader? _cloudLoader;

  @visibleForTesting
  factory TradeReviewStore.forTesting({
    TradeReviewCloudLoader? cloudLoader,
  }) {
    return TradeReviewStore._(cloudLoader: cloudLoader);
  }

  List<TradeReviewReport> get reports => List.unmodifiable(_load());

  TradeReviewReport? get latest => reports.isEmpty ? null : reports.first;
  bool get loading => _loading;
  bool get syncing => _syncing;
  String? get syncError => _syncError;
  bool get isAccountBound => _accountId != null && _accountId != _guestAccount;

  String get _storageKey => _storageKeyFor(_accountId ?? _guestAccount);
  String get _tombstoneKey => _tombstoneKeyFor(_accountId ?? _guestAccount);
  String get _pendingUploadKey =>
      _pendingUploadKeyFor(_accountId ?? _guestAccount);

  String _storageKeyFor(String account) => '$_storagePrefix$account';
  String _tombstoneKeyFor(String account) => '$_tombstonePrefix$account';
  String _pendingUploadKeyFor(String account) =>
      '$_pendingUploadPrefix$account';

  TradeReviewReport? byId(String id) {
    for (final report in _load()) {
      if (report.id == id) return report;
    }
    return null;
  }

  /// 登录账号变化时切换本地视图，并以云端记录为准。
  ///
  /// 冷启动时 AuthState 可能先恢复本地缓存、稍后再刷新 profile。同一个 uuid
  /// 的重复调用会被合并，避免重复请求。
  Future<bool> bindAccount(String? userUuid) async {
    final target = (userUuid == null || userUuid.trim().isEmpty)
        ? _guestAccount
        : userUuid.trim();
    if (_binding && _accountId == target) {
      return _bindCompleter?.future ?? false;
    }
    if (!_binding && _accountId == target && _reports != null) {
      if (target == _guestAccount) return true;
      return refresh();
    }
    final epoch = ++_accountEpoch;
    final completer = Completer<bool>();
    _bindCompleter = completer;
    _binding = true;
    _accountId = target;
    _reports = null;
    _loading = target != _guestAccount;
    _syncing = false;
    _syncError = null;
    notifyListeners();
    var success = false;
    try {
      _load();
      if (target != _guestAccount) {
        await _migrateLegacyIfNeeded(target);
        if (!_isCurrent(target, epoch)) return false;
        final cloud = await _fetchCloudFor(target);
        if (!_isCurrent(target, epoch)) return false;
        _reports = _mergeCloudWithPending(cloud, target);
        await _persistLocal(target, epoch);
      }
      success = _isCurrent(target, epoch);
    } on ApiException catch (error) {
      if (_isCurrent(target, epoch)) _syncError = error.message;
    } catch (_) {
      if (_isCurrent(target, epoch)) {
        _syncError = '读取账号复盘失败，请稍后重试。';
      }
    } finally {
      if (_isCurrent(target, epoch)) {
        _binding = false;
        _loading = false;
        if (!completer.isCompleted) completer.complete(success);
        if (identical(_bindCompleter, completer)) _bindCompleter = null;
        notifyListeners();
      } else if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    return success && _isCurrent(target, epoch);
  }

  Future<bool> refresh() async {
    if (!isAccountBound || _binding) return false;
    final account = _accountId!;
    final epoch = _accountEpoch;
    _loading = true;
    _syncError = null;
    notifyListeners();
    var success = false;
    try {
      final cloud = await _fetchCloudFor(account);
      if (!_isCurrent(account, epoch)) return false;
      _reports = _mergeCloudWithPending(cloud, account);
      await _persistLocal(account, epoch);
      success = _isCurrent(account, epoch);
    } on ApiException catch (error) {
      if (_isCurrent(account, epoch)) _syncError = error.message;
    } finally {
      if (_isCurrent(account, epoch)) {
        _loading = false;
        notifyListeners();
      }
    }
    return success;
  }

  /// 把当前账号的本地复盘和待删除墓碑推到云端，再拉取最新列表。
  ///
  /// 上传和删除会尽量逐份重试；任何一项失败时仍保留其它成功结果和本地
  /// 文件，最后用一个 [ApiException] 告知调用方“还有内容待同步”。
  Future<void> syncNow() async {
    final account = _accountId;
    if (account == null || account == _guestAccount) {
      throw ApiException(
        code: 'AUTH.REQUIRED',
        message: '登录后才能同步复盘。',
        statusCode: 401,
      );
    }
    if (_syncing) return;
    final epoch = _accountEpoch;
    _syncing = true;
    _syncError = null;
    notifyListeners();

    String? firstFailure;
    try {
      for (final report in List<TradeReviewReport>.of(_load())) {
        if (!_isCurrent(account, epoch)) return;
        try {
          await _uploadReport(report);
          if (!_isCurrent(account, epoch)) return;
          _removePendingUpload(report.id, account, epoch);
          await _persistPendingUploads(account, epoch);
        } on ApiException catch (error) {
          if (!_isCurrent(account, epoch)) return;
          firstFailure ??= error.message;
          _addPendingUpload(report.id, account, epoch);
          await _persistPendingUploads(account, epoch);
        }
      }

      for (final id in _loadTombstones().toList()) {
        if (!_isCurrent(account, epoch)) return;
        try {
          await _deleteRemote(id);
          if (!_isCurrent(account, epoch)) return;
          _removeTombstone(id, account, epoch);
          await _persistTombstones(account, epoch);
        } on ApiException catch (error) {
          if (!_isCurrent(account, epoch)) return;
          firstFailure ??= error.message;
        }
      }

      final cloud = await _fetchCloudFor(account);
      if (!_isCurrent(account, epoch)) return;
      _reports = _mergeCloudWithPending(cloud, account);
      await _persistLocal(account, epoch);
      _syncError = firstFailure;
      if (firstFailure != null) {
        throw ApiException(
          code: 'TRADE_REVIEW.SYNC_FAILED',
          message: firstFailure,
          statusCode: 0,
        );
      }
    } on ApiException catch (error) {
      if (!_isCurrent(account, epoch)) rethrow;
      _syncError ??= error.message;
      rethrow;
    } finally {
      if (_isCurrent(account, epoch)) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  Future<TradeReviewReport> analyze({
    required List<ParsedTrade> trades,
    required String brokerHint,
    required String currency,
    required List<String> warnings,
  }) async {
    final account = _accountId;
    final epoch = _accountEpoch;
    if (account == null || account == _guestAccount) {
      throw ApiException(
        code: 'AUTH.REQUIRED',
        message: '登录后才能分析并同步复盘。',
        statusCode: 401,
      );
    }
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/v1/trade-reviews/analyze',
        data: {
          'trades': trades.map((trade) => trade.toJson()).toList(),
          'broker_hint': brokerHint,
          'currency': currency,
          'warnings': warnings,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final raw = response.data?['report'];
      if (raw is! Map) {
        throw const FormatException('missing report');
      }
      if (!_isCurrent(account, epoch)) {
        throw ApiException(
          code: 'AUTH.ACCOUNT_CHANGED',
          message: '登录账号已切换，请重新生成复盘。',
          statusCode: 409,
        );
      }
      return TradeReviewReport.fromJson(Map<String, dynamic>.from(raw));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      final apiError = error.error;
      if (apiError is ApiException) throw apiError;
      throw ApiException(
        code: 'TRADE_REVIEW.ANALYZE_FAILED',
        message: '分析服务暂时不可用，请稍后重试。',
        statusCode: 0,
      );
    }
  }

  Future<TradeReviewReport> analyzeAndSave({
    required List<ParsedTrade> trades,
    required String brokerHint,
    required String currency,
    required List<String> warnings,
  }) async {
    final account = _accountId;
    final epoch = _accountEpoch;
    final report = await analyze(
      trades: trades,
      brokerHint: brokerHint,
      currency: currency,
      warnings: warnings,
    );
    if (account == null || !_isCurrent(account, epoch)) {
      throw ApiException(
        code: 'AUTH.ACCOUNT_CHANGED',
        message: '登录账号已切换，请重新生成复盘。',
        statusCode: 409,
      );
    }
    await _saveForAccount(report, account, epoch);
    return report;
  }

  Future<void> save(TradeReviewReport report) async {
    final account = _accountId ?? _guestAccount;
    final epoch = _accountEpoch;
    await _saveForAccount(report, account, epoch);
  }

  Future<void> _saveForAccount(
    TradeReviewReport report,
    String account,
    int epoch,
  ) async {
    if (!_isCurrent(account, epoch)) {
      throw ApiException(
        code: 'AUTH.ACCOUNT_CHANGED',
        message: '登录账号已切换，报告没有保存。',
        statusCode: 409,
      );
    }
    final rows = _load().where((item) => item.id != report.id).toList()
      ..insert(0, report);
    _reports = rows.take(_maxReports).toList(growable: false);
    _removeTombstone(report.id, account, epoch);
    await _persistLocal(account, epoch);
    if (!_isCurrent(account, epoch)) return;
    notifyListeners();

    if (account == _guestAccount) return;
    _syncing = true;
    _syncError = null;
    notifyListeners();
    try {
      await _uploadReport(report);
      if (!_isCurrent(account, epoch)) return;
      _removePendingUpload(report.id, account, epoch);
      await _persistPendingUploads(account, epoch);
      _syncError = null;
    } on ApiException catch (error) {
      if (!_isCurrent(account, epoch)) return;
      _addPendingUpload(report.id, account, epoch);
      await _persistPendingUploads(account, epoch);
      _syncError = error.message;
      throw ApiException(
        code: 'TRADE_REVIEW.SYNC_FAILED',
        message: '复盘已保存在本机，但还没有同步到账号。$_syncError',
        statusCode: 0,
      );
    } finally {
      if (_isCurrent(account, epoch)) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> delete(String id) async {
    final account = _accountId ?? _guestAccount;
    final epoch = _accountEpoch;
    if (!_isCurrent(account, epoch)) return;
    _reports = _load().where((item) => item.id != id).toList(growable: false);
    _addTombstone(id, account, epoch);
    await _persistLocal(account, epoch);
    if (!_isCurrent(account, epoch)) return;
    notifyListeners();

    if (account == _guestAccount) return;
    _syncing = true;
    _syncError = null;
    notifyListeners();
    try {
      await _deleteRemote(id);
      if (!_isCurrent(account, epoch)) return;
      _removeTombstone(id, account, epoch);
      await _persistTombstones(account, epoch);
      _syncError = null;
    } on ApiException catch (error) {
      if (!_isCurrent(account, epoch)) return;
      _syncError = error.message;
      throw ApiException(
        code: 'TRADE_REVIEW.DELETE_SYNC_FAILED',
        message: '复盘已从本机移除，但账号云端删除失败。$_syncError',
        statusCode: 0,
      );
    } finally {
      if (_isCurrent(account, epoch)) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> clear() async {
    _reports = const [];
    await prefsBox.delete(_storageKey);
    await prefsBox.delete(_tombstoneKey);
    await prefsBox.delete(_pendingUploadKey);
    notifyListeners();
  }

  Future<List<TradeReviewReport>> _fetchCloudFor(String account) async {
    final cloudLoader = _cloudLoader;
    if (cloudLoader != null) return cloudLoader(account);
    final deleted = _loadTombstonesFor(account);
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/v1/trade-reviews',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final cloud = <TradeReviewReport>[];
      for (final row in (response.data?['reports'] as List? ?? const [])) {
        if (row is! Map) continue;
        try {
          final report = TradeReviewReport.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (!deleted.contains(report.id)) cloud.add(report);
        } catch (_) {
          // 单份历史格式损坏时不阻断其它记录。
        }
      }
      cloud.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return cloud.take(_maxReports).toList(growable: false);
    } on DioException catch (error) {
      final api = error.error;
      if (api is ApiException) rethrow;
      throw ApiException(
        code: 'TRADE_REVIEW.SYNC_FAILED',
        message: _messageFor(error),
        statusCode: 0,
      );
    }
  }

  List<TradeReviewReport> _mergeCloudWithPending(
    List<TradeReviewReport> cloud,
    String account,
  ) {
    final pending = _loadPendingUploadsFor(account);
    final deleted = _loadTombstonesFor(account);
    final ids = {for (final report in cloud) report.id};
    final local = _decodeReports(
      prefsBox.get(_storageKeyFor(account))?.toString() ?? '',
    );
    final merged = <TradeReviewReport>[
      for (final report in cloud)
        if (!deleted.contains(report.id)) report,
      for (final report in local)
        if (pending.contains(report.id) &&
            !deleted.contains(report.id) &&
            !ids.contains(report.id))
          report,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged.take(_maxReports).toList(growable: false);
  }

  Future<void> _uploadReport(TradeReviewReport report) async {
    try {
      await ApiClient.instance.dio.put<void>(
        '/v1/trade-reviews/${Uri.encodeComponent(report.id)}',
        data: {'report': report.toJson()},
      );
    } on DioException catch (error) {
      final api = error.error;
      if (api is ApiException) rethrow;
      throw ApiException(
        code: 'TRADE_REVIEW.SYNC_FAILED',
        message: _messageFor(error),
        statusCode: 0,
      );
    }
  }

  Future<void> _deleteRemote(String id) async {
    try {
      await ApiClient.instance.dio.delete<void>(
        '/v1/trade-reviews/${Uri.encodeComponent(id)}',
      );
    } on DioException catch (error) {
      final api = error.error;
      if (api is ApiException && api.statusCode == 404) return;
      if (api is ApiException) rethrow;
      throw ApiException(
        code: 'TRADE_REVIEW.DELETE_SYNC_FAILED',
        message: _messageFor(error),
        statusCode: 0,
      );
    }
  }

  Future<void> _migrateLegacyIfNeeded(String account) async {
    final owner = prefsBox.get(_legacyMigrationOwnerKey);
    if (owner is String && owner.isNotEmpty) return;
    final raw = prefsBox.get(_legacyStorageKey);
    if (raw is! String || raw.trim().isEmpty) return;
    final legacy = _decodeReports(raw);
    if (legacy.isEmpty) return;

    for (final report in legacy.take(_maxReports)) {
      try {
        await ApiClient.instance.dio.put<void>(
          '/v1/trade-reviews/${Uri.encodeComponent(report.id)}',
          data: {'report': report.toJson()},
        );
      } catch (_) {
        // 单份迁移失败时保留旧数据，下次启动仍可重试。
        return;
      }
    }
    await prefsBox.put(_legacyMigrationOwnerKey, account);
  }

  bool _isCurrent(String account, int epoch) {
    return epoch == _accountEpoch &&
        (_accountId ?? _guestAccount) == account;
  }

  Future<void> _persistLocal(String account, int epoch) async {
    if (!_isCurrent(account, epoch) || _reports == null) return;
    await prefsBox.put(
      _storageKeyFor(account),
      jsonEncode(_reports!.map((item) => item.toJson()).toList()),
    );
    if (!_isCurrent(account, epoch)) return;
    _pruneAccountKeys(account);
  }

  /// v2 每个账号最多一份缓存；不过多账号来回切换会累积键，这里只保留
  /// 最近使用的 5 个账号，避免本地键无限增长。
  void _pruneAccountKeys(String currentAccount) {
    final keys = prefsBox.keys
        .whereType<String>()
        .where((key) =>
            key.startsWith(_storagePrefix) &&
            !key.startsWith(_tombstonePrefix) &&
            !key.startsWith(_pendingUploadPrefix))
        .toList();
    if (keys.length <= 5) return;
    final currentIndex = keys.indexOf(_storageKeyFor(currentAccount));
    if (currentIndex > 0) keys.removeAt(currentIndex);
    for (final key in keys.take(keys.length - 5)) {
      prefsBox.delete(key);
    }
  }

  List<TradeReviewReport> _load() {
    if (_reports != null) return _reports!;
    try {
      final raw = prefsBox.get(_storageKey);
      if (raw is String && raw.trim().isNotEmpty) {
        _reports = _decodeReports(raw);
        return _reports!;
      }
      if (_accountId == null || _accountId == _guestAccount) {
        final legacy = prefsBox.get(_legacyStorageKey);
        if (legacy is String && legacy.trim().isNotEmpty) {
          _reports = _decodeReports(legacy);
          return _reports!;
        }
      }
    } catch (_) {
      // Corrupt local history should not make the review surface unusable.
    }
    _reports = const [];
    return _reports!;
  }

  List<TradeReviewReport> _decodeReports(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final row in decoded)
          if (row is Map)
            TradeReviewReport.fromJson(Map<String, dynamic>.from(row)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Set<String> _loadTombstones() {
    return _loadTombstonesFor(_accountId ?? _guestAccount);
  }

  Set<String> _loadTombstonesFor(String account) {
    try {
      final raw = prefsBox.get(_tombstoneKeyFor(account));
      if (raw is! String || raw.trim().isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return {for (final value in decoded) value.toString()};
      }
    } catch (_) {
      // Ignore corrupt tombstones; the next remote refresh remains usable.
    }
    return <String>{};
  }

  void _addTombstone(String id, String account, int epoch) {
    if (!_isCurrent(account, epoch)) return;
    final ids = _loadTombstonesFor(account)..add(id);
    prefsBox.put(_tombstoneKeyFor(account), jsonEncode(ids.toList()));
  }

  void _removeTombstone(String id, String account, int epoch) {
    if (!_isCurrent(account, epoch)) return;
    final ids = _loadTombstonesFor(account)..remove(id);
    _writeTombstones(ids, account, epoch);
  }

  Future<void> _persistTombstones(String account, int epoch) async {
    if (!_isCurrent(account, epoch)) return;
    _writeTombstones(_loadTombstonesFor(account), account, epoch);
  }

  Set<String> _loadPendingUploadsFor(String account) {
    try {
      final raw = prefsBox.get(_pendingUploadKeyFor(account));
      if (raw is! String || raw.trim().isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return {for (final value in decoded) value.toString()};
      }
    } catch (_) {
      // A corrupt queue should not make the account history unusable.
    }
    return <String>{};
  }

  void _addPendingUpload(String id, String account, int epoch) {
    if (!_isCurrent(account, epoch)) return;
    final ids = _loadPendingUploadsFor(account)..add(id);
    prefsBox.put(_pendingUploadKeyFor(account), jsonEncode(ids.toList()));
  }

  void _removePendingUpload(String id, String account, int epoch) {
    if (!_isCurrent(account, epoch)) return;
    final ids = _loadPendingUploadsFor(account)..remove(id);
    _writePendingUploads(ids, account, epoch);
  }

  Future<void> _persistPendingUploads(String account, int epoch) async {
    if (!_isCurrent(account, epoch)) return;
    _writePendingUploads(_loadPendingUploadsFor(account), account, epoch);
  }

  void _writePendingUploads(Set<String> ids, String account, int epoch) {
    if (!_isCurrent(account, epoch)) return;
    if (ids.isEmpty) {
      prefsBox.delete(_pendingUploadKeyFor(account));
    } else {
      prefsBox.put(_pendingUploadKeyFor(account), jsonEncode(ids.toList()));
    }
  }

  void _writeTombstones(Set<String> ids, String account, int epoch) {
    if (!_isCurrent(account, epoch)) return;
    if (ids.isEmpty) {
      prefsBox.delete(_tombstoneKeyFor(account));
    } else {
      prefsBox.put(_tombstoneKeyFor(account), jsonEncode(ids.toList()));
    }
  }

  String _messageFor(DioException error) {
    final api = error.error;
    if (api is ApiException) return api.message;
    if (error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionTimeout) {
      return '连接超时，请稍后重试。';
    }
    return '网络连接失败，请检查网络后重试。';
  }
}
