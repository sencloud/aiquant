// 小应用图表 Y 轴刻度文字：同一单位、同一位小数，相邻刻度不重名。
import 'package:fincept_app/miniapp/render/charts.dart';
import 'package:flutter_test/flutter_test.dart';

List<double> _ticks(double lo, double hi) =>
    [for (var i = 0; i <= 3; i++) lo + (hi - lo) * i / 3];

void main() {
  test('1 万上下的价格（棕榈油 K 线）不再出现两个「1万」', () {
    final l = axisLabels(_ticks(9466, 10148));
    expect(l, ['9466', '9693', '9921', '10148']);
    expect(l.toSet().length, l.length);
  });

  test('≥10 万统一换成「万」，小数位按间距取且不重名', () {
    expect(axisLabels(_ticks(580000, 600000)), ['58.0万', '58.7万', '59.3万', '60.0万']);
    final l = axisLabels(_ticks(100000, 100300));
    expect(l.toSet().length, 4);
    expect(l.every((t) => t.endsWith('万')), isTrue);
  });

  test('亿', () {
    expect(axisLabels(_ticks(1.2e8, 3.0e8)), ['1.2亿', '1.8亿', '2.4亿', '3.0亿']);
  });

  test('负数价差、小数、跨零', () {
    expect(axisLabels(_ticks(-1399, -544)), ['-1399', '-1114', '-829', '-544']);
    expect(axisLabels(_ticks(0, 6.8)), ['0.0', '2.3', '4.5', '6.8']);
    expect(axisLabels(_ticks(-0.3, 0.3)), ['-0.3', '-0.1', '0.1', '0.3']);
    expect(axisLabels([-0.0001, 0.0, 0.0001]).toSet().length, 3);
  });

  test('退化情况', () {
    expect(axisLabels(const []), isEmpty);
    expect(axisLabels(const [5, 5, 5]), ['5.0', '5.0', '5.0']);
  });
}
