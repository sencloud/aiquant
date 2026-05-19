/// 喜点显示格式化。
///
/// 业务策略：后端账本（credit_ledger / SKU / user.credit_balance / SSE balance）
/// 仍按整数计量；面向用户的所有数字统一 ÷10，保留 1 位小数。
///
/// 这样一来：
///   - 充 ¥6 进账 60 内部单位 → 显示 "+6.0 喜点"
///   - 一次回答内部扣 6 单位 → 显示 "-0.6 喜点"
///   - SKU "60 喜点 / ¥6" → 展示 "6.0 喜点 / ¥6"
///
/// 不要在 UI 里直接 toString() 拼接 credit 数字，统一走这里。
library;

class CreditFmt {
  /// 显示喜点单价倍数：用户看到的是后端值 ÷ [unit]。
  static const int unit = 10;

  /// 把后端的整数 credit 转成 "0.6" 之类的展示字符串（默认 1 位小数，去掉无意义尾零）。
  static String amount(num value, {int fractionDigits = 1, bool stripTrailingZero = true}) {
    final v = value / unit;
    var s = v.toStringAsFixed(fractionDigits);
    if (stripTrailingZero && s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// 带 "喜点" 后缀。
  static String label(num value, {int fractionDigits = 1}) =>
      '${amount(value, fractionDigits: fractionDigits)} 喜点';

  /// 余额/正数展示：保留 1 位小数（"6.0"），让 UI 重数字看起来稳定。
  static String balance(num value) => amount(value, fractionDigits: 1, stripTrailingZero: false);

  /// 流水里的 "+6.0" / "-0.6"。
  static String delta(num value) {
    final s = amount(value, fractionDigits: 1, stripTrailingZero: false);
    if (value > 0) return '+$s';
    if (value == 0) return '0.0';
    // value 已经带负号了
    return s;
  }

  /// "¥0.10/喜点" 之类，price 单位为元。
  static String unitPrice(double priceYuan, num credits) {
    if (credits <= 0) return '—';
    final price = priceYuan / (credits / unit);
    return '¥${price.toStringAsFixed(price < 1 ? 2 : 3)}/喜点';
  }
}
