import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../models/trade_review.dart';
import 'trade_screenshot_parser.dart';

class PickedTradeFile {
  const PickedTradeFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

class TradeFilePicker {
  Future<PickedTradeFile?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      allowMultiple: false,
      withData: true,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return null;
    final file = files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        '文件内容为空或无法读取，请重新选择。',
      );
    }
    return PickedTradeFile(name: file.name, bytes: bytes);
  }
}

class TradeFileParser {
  const TradeFileParser();

  static const _nameHeaders = ['证券名称', '股票名称', '名称'];
  static const _symbolHeaders = ['证券代码', '股票代码', '代码'];
  static const _dateHeaders = ['成交日期', '交易日期', '日期'];
  static const _timeHeaders = ['成交时间', '交易时间', '时间'];
  static const _sideHeaders = ['买卖方向', '交易方向', '方向', '操作'];
  static const _quantityHeaders = ['成交数量', '成交股数', '数量', '股数'];
  static const _priceHeaders = ['成交价格', '成交均价', '价格', '单价'];
  static const _feeHeaders = ['手续费', '佣金', '费用', '手续费合计'];

  ParsedTradesResult parse(
    PickedTradeFile file, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final extension = file.extension;
    final rows = switch (extension) {
      'csv' => _csvRows(file.bytes),
      'xlsx' => _excelRows(file.bytes),
      _ => throw const TradeParseException(
          TradeParseFailureKind.invalidRequest,
          '只支持 CSV 或 Excel (.xlsx) 文件。',
        ),
    };
    final header = _findHeader(rows);
    if (header == null) {
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        '没有找到成交表头。请确认文件包含证券名称、成交日期、买卖方向、成交数量、成交价格。',
      );
    }

    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final end = DateTime(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
      23,
      59,
      59,
      999,
    );
    final parsed = <ParsedTrade>[];
    var rawCount = 0;
    var invalidCount = 0;
    var dateFilteredCount = 0;

    for (var index = header.rowIndex + 1; index < rows.length; index++) {
      final row = rows[index];
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      rawCount++;
      final trade = _parseRow(row, header.columns, index - header.rowIndex);
      if (trade == null) {
        invalidCount++;
        continue;
      }
      if (trade.occurredAt.isBefore(start) ||
          trade.occurredAt.isAfter(end)) {
        dateFilteredCount++;
        continue;
      }
      parsed.add(trade);
    }

    final validCount = rawCount - invalidCount;
    if (rawCount == 0) {
      throw const TradeParseException(
        TradeParseFailureKind.noTrades,
        '文件里没有成交数据行。',
      );
    }
    final warnings = <String>[
      if (invalidCount > 0) '$invalidCount 行字段不完整或格式无效，已跳过。',
      if (dateFilteredCount > 0)
        '$dateFilteredCount 行不在所选时间段内，已过滤。',
      if (parsed.isEmpty) '所选时间段内没有有效成交，请调整日期后重新导入。',
    ];
    if (parsed.isEmpty) {
      throw TradeParseException(
        TradeParseFailureKind.noTrades,
        '所选时间段内没有有效成交。文件中有 $validCount 行有效记录，'
            '其中 $dateFilteredCount 行不在所选时间段。',
      );
    }
    parsed.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return ParsedTradesResult(
      brokerHint: file.name,
      currency: 'CNY',
      trades: parsed,
      warnings: warnings,
      screenshotCount: 0,
      successfulScreenshotCount: 0,
      rawTradeCount: rawCount,
      validTradeCount: validCount,
      invalidRowCount: invalidCount,
      dateFilteredOutTradeCount: dateFilteredCount,
      importSource: extension == 'xlsx' ? 'Excel' : 'CSV',
      periodStart: start,
      periodEnd: end,
    );
  }

  List<List<String>> _csvRows(Uint8List bytes) {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        '暂不支持 GBK/GB18030 编码的 CSV，请另存为 UTF-8 后重试。',
      );
    }
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final values = Csv(autoDetect: true, dynamicTyping: false).decode(text);
    return [
      for (final row in values)
        [for (final value in row) value?.toString().trim() ?? ''],
    ];
  }

  List<List<String>> _excelRows(Uint8List bytes) {
    late final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        'Excel 文件无法读取，请确认它是有效的 .xlsx 文件。',
      );
    }
    List<List<String>> best = const [];
    for (final tableName in workbook.tables.keys) {
      final rows = [
        for (final row in workbook.tables[tableName]!.rows)
          [for (final cell in row) _excelCellText(cell?.value)],
      ];
      if (_findHeader(rows) != null && rows.length >= best.length) best = rows;
    }
    if (best.isEmpty) {
      throw const TradeParseException(
        TradeParseFailureKind.invalidRequest,
        'Excel 中没有任何工作表可读取。',
      );
    }
    return best;
  }

  String _excelCellText(Object? value) {
    if (value == null) return '';
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is num || value is String || value is bool) {
      return value.toString().trim();
    }
    try {
      final dynamic wrapped = value;
      final inner = wrapped.value;
      if (inner != null && !identical(inner, value)) {
        return _excelCellText(inner);
      }
    } catch (_) {
      // 新版本 excel 的某些单元格值没有 .value；退回 toString。
    }
    return value.toString().trim();
  }

  _Header? _findHeader(List<List<String>> rows) {
    for (var i = 0; i < rows.length; i++) {
      final columns = <String, int>{};
      for (var j = 0; j < rows[i].length; j++) {
        final value = rows[i][j].replaceAll(RegExp(r'\s+'), '');
        columns[value] = j;
      }
      int? find(List<String> aliases) {
        for (final alias in aliases) {
          final index = columns[alias];
          if (index != null) return index;
        }
        return null;
      }

      final name = find(_nameHeaders);
      final symbol = find(_symbolHeaders);
      final date = find(_dateHeaders);
      final side = find(_sideHeaders);
      final quantity = find(_quantityHeaders);
      final price = find(_priceHeaders);
      if ((name != null || symbol != null) &&
          date != null &&
          side != null &&
          quantity != null &&
          price != null) {
        return _Header(i, {
          'name': name,
          'symbol': symbol,
          'date': date,
          'time': find(_timeHeaders),
          'side': side,
          'quantity': quantity,
          'price': price,
          'fee': find(_feeHeaders),
        });
      }
    }
    return null;
  }

  ParsedTrade? _parseRow(
    List<String> row,
    Map<String, int?> columns,
    int sourceIndex,
  ) {
    String cell(String key) {
      final index = columns[key];
      if (index == null || index < 0 || index >= row.length) return '';
      return row[index].trim();
    }

    final name = cell('name');
    final symbol = cell('symbol');
    if (name.isEmpty && symbol.isEmpty) return null;
    final side = _parseSide(cell('side'));
    if (side == null) return null;
    final date = _parseDate(cell('date'), cell('time'));
    if (date == null) return null;
    final quantity = _parseNumber(cell('quantity'));
    final price = _parseNumber(cell('price'));
    final fee = _parseNumber(cell('fee')) ?? 0;
    if (quantity == null || quantity <= 0 || price == null || price <= 0) {
      return null;
    }
    return ParsedTrade(
      occurredAt: date,
      symbol: symbol,
      name: name,
      side: side,
      quantity: quantity,
      price: price,
      fee: fee < 0 ? 0 : fee,
      sourceIndex: sourceIndex,
    );
  }

  TradeSide? _parseSide(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized.contains('买') ||
        normalized == 'buy' ||
        normalized == 'b') {
      return TradeSide.buy;
    }
    if (normalized.contains('卖') ||
        normalized == 'sell' ||
        normalized == 's') {
      return TradeSide.sell;
    }
    return null;
  }

  DateTime? _parseDate(String dateText, String timeText) {
    final text = dateText
        .trim()
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .replaceAll('.', '-');
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T\s]+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
    ).firstMatch(text);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    var hour = int.tryParse(match.group(4) ?? '') ?? 0;
    var minute = int.tryParse(match.group(5) ?? '') ?? 0;
    var second = int.tryParse(match.group(6) ?? '') ?? 0;
    final time = RegExp(
      r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?',
    ).firstMatch(timeText.trim());
    if (time != null) {
      hour = int.tryParse(time.group(1)!) ?? hour;
      minute = int.tryParse(time.group(2)!) ?? minute;
      second = int.tryParse(time.group(3) ?? '') ?? second;
    }
    try {
      final value = DateTime(year, month, day, hour, minute, second);
      if (value.year != year ||
          value.month != month ||
          value.day != day ||
          hour > 23 ||
          minute > 59 ||
          second > 59) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  double? _parseNumber(String value) {
    final cleaned = value
        .replaceAll(',', '')
        .replaceAll('，', '')
        .replaceAll(RegExp(r'[¥￥$]'), '')
        .replaceAll(RegExp(r'(股|份|元|手)$'), '')
        .trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}

class _Header {
  const _Header(this.rowIndex, this.columns);

  final int rowIndex;
  final Map<String, int?> columns;
}

