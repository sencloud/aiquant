import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class SectorDonut extends StatelessWidget {
  const SectorDonut({super.key, required this.weights});

  /// sector → percent (0-100)
  final Map<String, double> weights;

  @override
  Widget build(BuildContext context) {
    if (weights.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text('暂无行业数据',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        ),
      );
    }
    final entries = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visible = entries.take(8).toList();
    if (visible.length < entries.length) {
      final rest = entries.skip(8).fold<double>(0, (s, e) => s + e.value);
      visible.add(MapEntry('其它', rest));
    }
    final singleSegment = visible.length == 1;

    return SizedBox(
      height: 200,
      child: ClipRect(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide;
                  final outerRadius = (side / 2) - 8;
                  final ringRadius = (outerRadius * 0.34).clamp(8.0, 28.0);
                  final centerHole = (outerRadius - ringRadius).clamp(20.0, 60.0);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 1,
                          centerSpaceRadius: centerHole,
                          startDegreeOffset: -90,
                          sections: [
                            for (int i = 0; i < visible.length; i++)
                              PieChartSectionData(
                                value: visible[i].value,
                                color: sectorColorFor(visible[i].key),
                                radius: ringRadius,
                                showTitle: !singleSegment &&
                                    visible[i].value >= 8,
                                title: '${visible[i].value.toStringAsFixed(1)}%',
                                titleStyle: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black),
                                titlePositionPercentageOffset: 0.55,
                              ),
                          ],
                        ),
                      ),
                      if (singleSegment)
                        Text(
                          '${visible.first.value.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 4),
                child: Column(
                  children: [
                    for (final e in visible) _legend(e.key, e.value),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, double percent) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: sectorColorFor(label)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textPrimary)),
            ),
            Text('${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace')),
          ],
        ),
      );
}
