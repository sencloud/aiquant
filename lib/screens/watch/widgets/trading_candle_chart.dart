import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/instrument.dart';
import '../../../models/market_period.dart';
import '../../../services/market_levels.dart';
import '../market_theme.dart';
import 'chart_indicators.dart';

class ChartCrosshair {
  const ChartCrosshair({required this.index, required this.candle});

  final int index;
  final CandlePoint candle;
}

double chartBarCenterX({
  required int index,
  required double windowStart,
  required double visibleBars,
  required double plotWidth,
}) =>
    (index - windowStart + 0.5) / visibleBars * plotWidth;

/// TradingView 式交互 K 线：
/// - 单指拖动看历史，双指捏合缩放
/// - 长按/鼠标悬停显示十字光标
/// - 双击恢复最新一段
/// - 滚轮以鼠标位置为中心缩放
class TradingCandleChart extends StatefulWidget {
  const TradingCandleChart({
    super.key,
    required this.candles,
    required this.period,
    required this.levels,
    required this.watermark,
    this.showMovingAverages = true,
    this.showVolume = true,
    this.replayIndex,
    this.onCrosshair,
  });

  final List<CandlePoint> candles;
  final MarketPeriod period;
  final SupportResistance levels;
  final String watermark;
  final bool showMovingAverages;
  final bool showVolume;
  final int? replayIndex;
  final ValueChanged<ChartCrosshair?>? onCrosshair;

  @override
  State<TradingCandleChart> createState() => _TradingCandleChartState();
}

class _TradingCandleChartState extends State<TradingCandleChart> {
  static const _priceAxisWidth = 88.0;

  double _visibleBars = 100;
  double _visibleEnd = 0;
  double _plotWidth = 0;
  double _scaleAnchorBars = 100;
  double _scaleAnchorEnd = 0;
  double _scaleAnchorFocal = 0;
  int? _crosshairIndex;
  double? _crosshairY;

  @override
  void initState() {
    super.initState();
    _fitData();
  }

  @override
  void didUpdateWidget(covariant TradingCandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles) ||
        oldWidget.period != widget.period) {
      _crosshairIndex = null;
      _crosshairY = null;
      _fitData();
    }
    if (oldWidget.replayIndex == null && widget.replayIndex != null) {
      _crosshairIndex = null;
      _crosshairY = null;
    }
  }

  void _fitData() {
    final length = widget.candles.length;
    if (length == 0) {
      _visibleBars = 1;
      _visibleEnd = 0;
      return;
    }
    final preferred = widget.period.preferredVisibleBars;
    _visibleBars = math.min(length, preferred).toDouble();
    _visibleEnd = length.toDouble();
  }

  int get _startIndex {
    final start = (_visibleEnd - _visibleBars).floor();
    return start.clamp(0, math.max(0, widget.candles.length - 1));
  }

  int get _endIndex =>
      _visibleEnd.ceil().clamp(0, widget.candles.length).toInt();

  void _clampViewport(double bars, double end) {
    final length = widget.candles.length;
    if (length == 0) return;
    final maxBars = math.min(360, length).toDouble();
    final minBars = math.min(18, maxBars);
    final nextBars = bars.clamp(minBars, maxBars).toDouble();
    _visibleBars = nextBars;
    _visibleEnd = end
        .clamp(
          math.min(nextBars, length.toDouble()),
          length.toDouble(),
        )
        .toDouble();
  }

  void _zoomTo(double focalX, double factor) {
    if (_plotWidth <= 0 || widget.candles.isEmpty) return;
    final ratio = (focalX / _plotWidth).clamp(0.0, 1.0);
    final focalIndex = _visibleEnd - _visibleBars * (1 - ratio);
    final nextBars = _visibleBars * factor;
    final nextEnd = focalIndex + nextBars * (1 - ratio);
    setState(() {
      _clampViewport(nextBars, nextEnd);
      _updateCrosshairAt(Offset(focalX, _crosshairY ?? 0));
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleAnchorBars = _visibleBars;
    _scaleAnchorEnd = _visibleEnd;
    _scaleAnchorFocal = details.localFocalPoint.dx;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.candles.isEmpty || _plotWidth <= 0) return;
    if (details.pointerCount > 1) {
      final ratio = (_scaleAnchorFocal / _plotWidth).clamp(0.0, 1.0);
      final focalIndex = _scaleAnchorEnd - _scaleAnchorBars * (1 - ratio);
      final nextBars = _scaleAnchorBars / math.max(0.08, details.scale);
      final nextEnd = focalIndex + nextBars * (1 - ratio);
      setState(() => _clampViewport(nextBars, nextEnd));
      return;
    }
    final barWidth = _plotWidth / _visibleBars;
    if (barWidth <= 0) return;
    setState(() {
      _visibleEnd += -details.focalPointDelta.dx / barWidth;
      _clampViewport(_visibleBars, _visibleEnd);
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = math.exp(event.scrollDelta.dy * 0.0013);
    _zoomTo(event.localPosition.dx, factor);
  }

  void _updateCrosshairAt(Offset position) {
    final length = widget.candles.length;
    if (length == 0 || _plotWidth <= 0) return;
    final x = position.dx.clamp(0.0, _plotWidth);
    final windowStart = _visibleEnd - _visibleBars;
    final index = (windowStart + x / _plotWidth * _visibleBars)
        .floor()
        .clamp(0, length - 1);
    if (index == _crosshairIndex && position.dy == _crosshairY) return;
    setState(() {
      _crosshairIndex = index;
      _crosshairY = position.dy;
    });
    widget.onCrosshair?.call(
      ChartCrosshair(index: index, candle: widget.candles[index]),
    );
  }

  void _clearCrosshair() {
    if (_crosshairIndex == null) return;
    setState(() {
      _crosshairIndex = null;
      _crosshairY = null;
    });
    widget.onCrosshair?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _plotWidth = math.max(
          1,
          constraints.maxWidth - _priceAxisWidth,
        );
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (event) => _updateCrosshairAt(event.localPosition),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onDoubleTap: () {
                setState(_fitData);
                _clearCrosshair();
              },
              onTapUp: (details) => _updateCrosshairAt(details.localPosition),
              onLongPressStart: (details) =>
                  _updateCrosshairAt(details.localPosition),
              onLongPressMoveUpdate: (details) =>
                  _updateCrosshairAt(details.localPosition),
              child: CustomPaint(
                painter: _TradingChartPainter(
                  candles: widget.candles,
                  period: widget.period,
                  levels: widget.levels,
                  watermark: widget.watermark,
                  startIndex: _startIndex,
                  endIndex: _endIndex,
                  windowStart: _visibleEnd - _visibleBars,
                  visibleBars: _visibleBars,
                  showMovingAverages: widget.showMovingAverages,
                  showVolume: widget.showVolume,
                  replayIndex: widget.replayIndex,
                  crosshairIndex: _crosshairIndex,
                  crosshairY: _crosshairY,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TradingChartPainter extends CustomPainter {
  _TradingChartPainter({
    required this.candles,
    required this.period,
    required this.levels,
    required this.watermark,
    required this.startIndex,
    required this.endIndex,
    required this.windowStart,
    required this.visibleBars,
    required this.showMovingAverages,
    required this.showVolume,
    required this.replayIndex,
    required this.crosshairIndex,
    required this.crosshairY,
  });

  final List<CandlePoint> candles;
  final MarketPeriod period;
  final SupportResistance levels;
  final String watermark;
  final int startIndex;
  final int endIndex;
  final double windowStart;
  final double visibleBars;
  final bool showMovingAverages;
  final bool showVolume;
  final int? replayIndex;
  final int? crosshairIndex;
  final double? crosshairY;

  static const _axisWidth = 88.0;
  static const _timeHeight = 24.0;
  static const _top = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || endIndex <= startIndex) {
      _paintEmpty(canvas, size);
      return;
    }
    final plotW = math.max(1.0, size.width - _axisWidth);
    final volumeH = showVolume ? (size.height * 0.19).clamp(48.0, 92.0) : 0.0;
    final gap = showVolume ? 8.0 : 0.0;
    final priceBottom =
        math.max(_top + 1, size.height - _timeHeight - volumeH - gap);
    final priceRect = Rect.fromLTRB(0, _top, plotW, priceBottom);
    final bars = candles.sublist(startIndex, endIndex);
    if (bars.isEmpty) return;

    var rawMin = bars.first.low ?? bars.first.close;
    var rawMax = bars.first.high ?? bars.first.close;
    for (final bar in bars) {
      rawMin = math.min(rawMin, bar.low ?? bar.close);
      rawMax = math.max(rawMax, bar.high ?? bar.close);
    }
    if (rawMin == rawMax) {
      rawMin -= rawMax.abs() * 0.002 + 0.01;
      rawMax += rawMax.abs() * 0.002 + 0.01;
    }
    final rawSpan = rawMax - rawMin;
    for (final zone in [...levels.supports, ...levels.resistances]) {
      if (zone.high >= rawMin - rawSpan * 0.08 &&
          zone.low <= rawMax + rawSpan * 0.08) {
        rawMin = math.min(rawMin, zone.low);
        rawMax = math.max(rawMax, zone.high);
      }
    }

    final ma5 =
        showMovingAverages ? ChartIndicators.smaSeries(candles, 5) : null;
    final ma10 =
        showMovingAverages ? ChartIndicators.smaSeries(candles, 10) : null;
    final ma20 =
        showMovingAverages ? ChartIndicators.smaSeries(candles, 20) : null;
    for (final series in [ma5, ma10, ma20]) {
      if (series == null) continue;
      for (var i = startIndex; i < endIndex; i++) {
        final value = series[i];
        if (value == null) continue;
        rawMin = math.min(rawMin, value);
        rawMax = math.max(rawMax, value);
      }
    }
    final pad = math.max((rawMax - rawMin) * 0.08, rawMax * 0.0005);
    final minPrice = rawMin - pad;
    final maxPrice = rawMax + pad;
    final priceSpan = maxPrice - minPrice;

    double xAt(int index) {
      return chartBarCenterX(
        index: index,
        windowStart: windowStart,
        visibleBars: visibleBars,
        plotWidth: plotW,
      );
    }

    double yAt(double price) =>
        priceRect.top + (maxPrice - price) / priceSpan * priceRect.height;

    final axisPaint = Paint()
      ..color = MarketColors.border
      ..strokeWidth = 1;
    final dashedPaint = Paint()
      ..color = MarketColors.grid
      ..strokeWidth = 0.7;

    const horizontalGrid = 6;
    for (var i = 0; i <= horizontalGrid; i++) {
      final y = priceRect.top + priceRect.height * i / horizontalGrid;
      _drawDashed(
        canvas,
        Offset(0, y),
        Offset(plotW, y),
        dashedPaint,
        dash: 2,
        gap: 4,
      );
      final price = maxPrice - (maxPrice - minPrice) * i / horizontalGrid;
      _paintText(
        canvas,
        _formatPrice(price),
        Offset(plotW + 8, y - 7),
        const TextStyle(
          color: MarketColors.textMuted,
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
    }
    canvas.drawLine(
      Offset(plotW, 0),
      Offset(plotW, size.height),
      axisPaint,
    );

    _paintWatermark(canvas, priceRect);
    _paintLevels(canvas, plotW, priceRect, minPrice, maxPrice, yAt);
    _paintCandles(canvas, bars, plotW, yAt, replayIndex);
    _paintMovingAverages(
      canvas,
      ma5,
      ma10,
      ma20,
      xAt,
      yAt,
    );

    if (showVolume) {
      final volumeTop = priceBottom + gap;
      final volumeRect = Rect.fromLTRB(
        0,
        volumeTop,
        plotW,
        size.height - _timeHeight,
      );
      _paintVolume(canvas, bars, volumeRect, plotW, replayIndex);
      canvas.drawLine(
        Offset(0, volumeTop),
        Offset(plotW, volumeTop),
        dashedPaint,
      );
    }

    _paintTimeAxis(canvas, size, plotW, bars);
    _paintLatestPrice(canvas, plotW, priceRect, yAt);
    _paintReplayMarker(canvas, plotW, priceRect);
    _paintCrosshair(
      canvas,
      size,
      plotW,
      priceRect,
      minPrice,
      maxPrice,
    );
    _paintMovingAverageLegend(canvas, ma5, ma10, ma20);
  }

  void _paintCandles(
    Canvas canvas,
    List<CandlePoint> bars,
    double plotW,
    double Function(double) yAt,
    int? replayIndex,
  ) {
    final barWidth = plotW / visibleBars;
    final bodyWidth = (barWidth * 0.68).clamp(1.0, 14.0);
    final wickWidth = math.max(1.0, bodyWidth * 0.13);
    for (var local = 0; local < bars.length; local++) {
      final index = startIndex + local;
      final candle = bars[local];
      final open = candle.open ?? candle.close;
      final high = candle.high ?? math.max(open, candle.close);
      final low = candle.low ?? math.min(open, candle.close);
      final future = replayIndex != null && index > replayIndex;
      final up = candle.close >= open;
      final color = future
          ? MarketColors.futureBar
          : up
              ? MarketColors.up
              : MarketColors.down;
      final x = chartBarCenterX(
        index: index,
        windowStart: windowStart,
        visibleBars: visibleBars,
        plotWidth: plotW,
      );
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = wickWidth;
      canvas.drawLine(
        Offset(x, yAt(high)),
        Offset(x, yAt(low)),
        wickPaint,
      );
      final top = yAt(math.max(open, candle.close));
      final bottom = yAt(math.min(open, candle.close));
      final body = Rect.fromLTWH(
        x - bodyWidth / 2,
        top,
        bodyWidth,
        math.max(1, bottom - top),
      );
      canvas.drawRect(
        body,
        Paint()..color = future ? color.withValues(alpha: 0.72) : color,
      );
    }
  }

  void _paintMovingAverages(
    Canvas canvas,
    List<double?>? ma5,
    List<double?>? ma10,
    List<double?>? ma20,
    double Function(int) xAt,
    double Function(double) yAt,
  ) {
    void line(List<double?>? series, Color color) {
      if (series == null) return;
      final path = Path();
      var started = false;
      final seriesEnd = replayIndex == null ? endIndex : replayIndex! + 1;
      for (var i = startIndex; i < math.min(endIndex, seriesEnd); i++) {
        final value = series[i];
        if (value == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(xAt(i), yAt(value));
          started = true;
        } else {
          path.lineTo(xAt(i), yAt(value));
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..isAntiAlias = true,
      );
    }

    line(ma5, MarketColors.ma5);
    line(ma10, MarketColors.ma10);
    line(ma20, MarketColors.ma20);
  }

  void _paintMovingAverageLegend(
    Canvas canvas,
    List<double?>? ma5,
    List<double?>? ma10,
    List<double?>? ma20,
  ) {
    if (!showMovingAverages) return;
    var x = 8.0;
    void label(String text, Color color, double? value) {
      if (value == null) return;
      final painter = _textPainter(
        '$text ${_formatPrice(value)}',
        TextStyle(
          color: color,
          fontSize: 10,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      painter.paint(canvas, Offset(x, 8));
      x += painter.width + 10;
    }

    final displayIndex = replayIndex ?? endIndex - 1;
    label('MA5', MarketColors.ma5, ma5?[displayIndex]);
    label('MA10', MarketColors.ma10, ma10?[displayIndex]);
    label('MA20', MarketColors.ma20, ma20?[displayIndex]);
  }

  void _paintVolume(
    Canvas canvas,
    List<CandlePoint> bars,
    Rect rect,
    double plotW,
    int? replayIndex,
  ) {
    var maxVolume = 0.0;
    for (final bar in bars) {
      maxVolume = math.max(maxVolume, bar.vol ?? 0);
    }
    _paintText(
      canvas,
      '成交量',
      Offset(8, rect.top + 5),
      const TextStyle(color: MarketColors.textMuted, fontSize: 10),
    );
    if (maxVolume <= 0) return;
    final barWidth = plotW / visibleBars;
    final bodyWidth = (barWidth * 0.68).clamp(1.0, 14.0);
    for (var local = 0; local < bars.length; local++) {
      final bar = bars[local];
      final volume = bar.vol ?? 0;
      if (volume <= 0) continue;
      final open = bar.open ?? bar.close;
      final future = replayIndex != null && startIndex + local > replayIndex;
      final color = future
          ? MarketColors.futureBar
          : bar.close >= open
              ? MarketColors.up
              : MarketColors.down;
      final height = volume / maxVolume * (rect.height - 7);
      final center = chartBarCenterX(
        index: startIndex + local,
        windowStart: windowStart,
        visibleBars: visibleBars,
        plotWidth: plotW,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          center - bodyWidth / 2,
          rect.bottom - height,
          bodyWidth,
          height,
        ),
        Paint()..color = color.withValues(alpha: future ? 0.34 : 0.55),
      );
    }
  }

  void _paintLevels(
    Canvas canvas,
    double plotW,
    Rect priceRect,
    double minPrice,
    double maxPrice,
    double Function(double) yAt,
  ) {
    final placedLabels = <double>[];

    void draw(MarketPriceZone zone, int rank) {
      if (zone.high < minPrice || zone.low > maxPrice) return;
      final top = yAt(math.min(zone.high, maxPrice))
          .clamp(priceRect.top, priceRect.bottom);
      final bottom = yAt(math.max(zone.low, minPrice))
          .clamp(priceRect.top, priceRect.bottom);
      if (bottom <= top) return;
      final color = zone.kind == MarketLevelKind.support
          ? MarketColors.support
          : MarketColors.resistance;
      canvas.drawRect(
        Rect.fromLTRB(0, top, plotW, bottom),
        Paint()..color = color.withValues(alpha: 0.105),
      );
      for (final y in [top, bottom]) {
        _drawDashed(
          canvas,
          Offset(0, y),
          Offset(plotW, y),
          Paint()
            ..color = color.withValues(alpha: 0.74)
            ..strokeWidth = 0.9,
          dash: 5,
          gap: 4,
        );
      }
      final centerY = (top + bottom) / 2;
      _drawDashed(
        canvas,
        Offset(0, centerY),
        Offset(plotW, centerY),
        Paint()
          ..color = color.withValues(alpha: 0.34)
          ..strokeWidth = 0.7,
        dash: 2,
        gap: 4,
      );

      final label = zone.kind == MarketLevelKind.support ? 'S$rank' : 'R$rank';
      final rangeText = '${_formatPrice(zone.low)}–${_formatPrice(zone.high)}';
      _paintText(
        canvas,
        label,
        Offset(7, centerY - 6),
        TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      );
      final painter = _textPainter(
        rangeText,
        TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      var labelY =
          (centerY - painter.height / 2 - 2).clamp(0.0, priceRect.bottom - 14);
      var direction = labelY + 18 <= priceRect.bottom - 14 ? 18.0 : -18.0;
      var attempts = 0;
      while (placedLabels.any((y) => (y - labelY).abs() < 17) && attempts < 5) {
        labelY =
            (labelY + direction).clamp(0.0, priceRect.bottom - 14).toDouble();
        direction = -direction;
        attempts++;
      }
      placedLabels.add(labelY);
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          plotW + 4,
          labelY,
          _axisWidth - 8,
          painter.height + 4,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        labelRect,
        Paint()..color = color.withValues(alpha: 0.12),
      );
      painter.paint(
        canvas,
        Offset(plotW + 7, labelY + 2),
      );
    }

    for (var i = 0; i < levels.resistances.length; i++) {
      draw(levels.resistances[i], i + 1);
    }
    for (var i = 0; i < levels.supports.length; i++) {
      draw(levels.supports[i], i + 1);
    }
  }

  void _paintLatestPrice(
    Canvas canvas,
    double plotW,
    Rect priceRect,
    double Function(double) yAt,
  ) {
    final index = replayIndex ?? candles.length - 1;
    final latest = candles[index];
    final previous = index > 0 ? candles[index - 1] : null;
    final up = previous == null || latest.close >= previous.close;
    final y = yAt(latest.close).clamp(priceRect.top, priceRect.bottom);
    final color = up ? MarketColors.up : MarketColors.down;
    _drawDashed(
      canvas,
      Offset(0, y),
      Offset(plotW, y),
      Paint()
        ..color = color.withValues(alpha: 0.65)
        ..strokeWidth = 0.8,
      dash: 3,
      gap: 3,
    );
    final painter = _textPainter(
      _formatPrice(latest.close),
      const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    final rect = Rect.fromLTWH(
      plotW + 1,
      (y - 9).clamp(0, priceRect.bottom - 18),
      _axisWidth - 1,
      18,
    );
    canvas.drawRect(rect, Paint()..color = color);
    painter.paint(
      canvas,
      Offset(rect.left + 7, rect.top + (18 - painter.height) / 2),
    );
  }

  void _paintReplayMarker(Canvas canvas, double plotW, Rect priceRect) {
    final index = replayIndex;
    if (index == null || index < startIndex || index >= endIndex) return;
    final x = chartBarCenterX(
      index: index,
      windowStart: windowStart,
      visibleBars: visibleBars,
      plotWidth: plotW,
    );
    _drawDashed(
      canvas,
      Offset(x, 0),
      Offset(x, priceRect.bottom),
      Paint()
        ..color = MarketColors.accent.withValues(alpha: 0.72)
        ..strokeWidth = 1,
      dash: 3,
      gap: 3,
    );
    final triangle = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 6)
      ..close();
    canvas.drawPath(triangle, Paint()..color = MarketColors.accent);
  }

  void _paintTimeAxis(
    Canvas canvas,
    Size size,
    double plotW,
    List<CandlePoint> bars,
  ) {
    final tickCount = (plotW / 90).floor().clamp(2, 6);
    final step = math.max(1, (bars.length / tickCount).ceil());
    for (var local = 0; local < bars.length; local += step) {
      final candle = bars[local];
      final index = startIndex + local;
      final x = chartBarCenterX(
        index: index,
        windowStart: windowStart,
        visibleBars: visibleBars,
        plotWidth: plotW,
      );
      if (x < 18 || x > plotW - 22) continue;
      final label = _formatAxisTime(candle.date, period);
      final painter = _textPainter(
        label,
        const TextStyle(
          color: MarketColors.textMuted,
          fontSize: 9,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
      painter.paint(
        canvas,
        Offset(x - painter.width / 2, size.height - _timeHeight + 6),
      );
    }
  }

  void _paintCrosshair(
    Canvas canvas,
    Size size,
    double plotW,
    Rect priceRect,
    double minPrice,
    double maxPrice,
  ) {
    final index = crosshairIndex;
    if (index == null || index < startIndex || index >= endIndex) return;
    final x = chartBarCenterX(
      index: index,
      windowStart: windowStart,
      visibleBars: visibleBars,
      plotWidth: plotW,
    );
    final y = (crosshairY ?? priceRect.top + priceRect.height / 2)
        .clamp(priceRect.top, priceRect.bottom);
    final paint = Paint()
      ..color = MarketColors.textMuted
      ..strokeWidth = 0.8;
    _drawDashed(
      canvas,
      Offset(x, 0),
      Offset(x, size.height - _timeHeight),
      paint,
      dash: 3,
      gap: 3,
    );
    _drawDashed(
      canvas,
      Offset(0, y),
      Offset(plotW, y),
      paint,
      dash: 3,
      gap: 3,
    );

    final candle = candles[index];
    final time = _formatCrosshairTime(candle.date);
    final timePainter = _textPainter(
      time,
      const TextStyle(color: Colors.white, fontSize: 9),
    );
    final timeRect = Rect.fromLTWH(
      (x - timePainter.width / 2 - 6).clamp(0, plotW - timePainter.width - 12),
      size.height - _timeHeight,
      timePainter.width + 12,
      _timeHeight,
    );
    canvas.drawRect(timeRect, Paint()..color = const Color(0xFF363A45));
    timePainter.paint(
      canvas,
      Offset(timeRect.left + 6, timeRect.top + 6),
    );

    final price = _priceAtY(
      y,
      priceRect,
      minPrice,
      maxPrice,
    );
    final pricePainter = _textPainter(
      _formatPrice(price),
      const TextStyle(color: Colors.white, fontSize: 10),
    );
    final priceRectLabel = Rect.fromLTWH(
      plotW + 1,
      y - 9,
      _axisWidth - 1,
      18,
    );
    canvas.drawRect(
      priceRectLabel,
      Paint()..color = const Color(0xFF363A45),
    );
    pricePainter.paint(
      canvas,
      Offset(
        priceRectLabel.left + 7,
        priceRectLabel.top + (18 - pricePainter.height) / 2,
      ),
    );
  }

  double _priceAtY(
    double y,
    Rect rect,
    double minPrice,
    double maxPrice,
  ) {
    final ratio = ((y - rect.top) / rect.height).clamp(0.0, 1.0);
    return maxPrice - (maxPrice - minPrice) * ratio;
  }

  void _paintWatermark(Canvas canvas, Rect rect) {
    if (watermark.isEmpty) return;
    final painter = _textPainter(
      watermark,
      TextStyle(
        color: MarketColors.textPrimary.withValues(alpha: 0.035),
        fontSize: 34,
        fontWeight: FontWeight.w700,
      ),
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  void _paintEmpty(Canvas canvas, Size size) {
    final painter = _textPainter(
      '正在等待行情数据',
      const TextStyle(color: MarketColors.textMuted, fontSize: 12),
    );
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  static void _drawDashed(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 4,
    double gap = 4,
  }) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance <= 0) return;
    final direction = delta / distance;
    var progress = 0.0;
    while (progress < distance) {
      final end = math.min(progress + dash, distance);
      canvas.drawLine(
        from + direction * progress,
        from + direction * end,
        paint,
      );
      progress += dash + gap;
    }
  }

  static TextPainter _textPainter(String text, TextStyle style) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  static void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
  ) {
    _textPainter(text, style).paint(canvas, offset);
  }

  static String _formatPrice(double value) {
    final abs = value.abs();
    if (abs >= 100000) return value.toStringAsFixed(0);
    if (abs >= 1000) return value.toStringAsFixed(1);
    if (abs >= 100) return value.toStringAsFixed(2);
    return value.toStringAsFixed(3);
  }

  static String _formatAxisTime(DateTime date, MarketPeriod period) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    if (period.isIntraday) {
      return '$month/$day '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }
    if (period == MarketPeriod.oneDay) return '$month/$day';
    return '${date.year.toString().substring(2)}/$month';
  }

  static String _formatCrosshairTime(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _TradingChartPainter old) =>
      old.candles != candles ||
      old.period != period ||
      old.levels != levels ||
      old.startIndex != startIndex ||
      old.endIndex != endIndex ||
      old.windowStart != windowStart ||
      old.visibleBars != visibleBars ||
      old.showMovingAverages != showMovingAverages ||
      old.showVolume != showVolume ||
      old.replayIndex != replayIndex ||
      old.crosshairIndex != crosshairIndex ||
      old.crosshairY != crosshairY ||
      old.watermark != watermark;
}
