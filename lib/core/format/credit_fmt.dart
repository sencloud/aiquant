/// 喜点显示格式化。
///
/// 业务策略：后端账本（credit_ledger / SKU / user.credit_balance / SSE balance）
/// 与面向用户的展示**口径统一为同一个整数**（大数口径），不再 ÷10。
///
/// 这样一来全链路一致：
///   - 充 ¥6 进账 60 → 显示 "+60 喜点"，与 Apple 内购弹窗一致
///   - 一次回答扣 6 → 显示 "-6 喜点"
///   - SKU "60 喜点 / ¥6" → 展示 "60 喜点 / ¥6"
///
/// 不要在 UI 里直接 toString() 拼接 credit 数字，统一走这里。
library;

class CreditFmt {
  /// 展示倍数：用户看到的就是后端原始整数（大数口径，不缩放）。
  static const int unit = 1;

  /// 把后端整数 credit 转成展示字符串（整数，无小数）。
  static String amount(num value) {
    final v = (value / unit).round();
    return v.toString();
  }

  /// 带 "喜点" 后缀。
  static String label(num value) => '${amount(value)} 喜点';

  /// 余额/正数展示（整数）。
  static String balance(num value) => amount(value);

  /// 流水里的 "+60" / "-6"。
  static String delta(num value) {
    final s = amount(value.abs());
    if (value > 0) return '+$s';
    if (value == 0) return '0';
    return '-$s';
  }

  /// "¥0.10/喜点" 之类，price 单位为元。
  static String unitPrice(double priceYuan, num credits) {
    final c = credits / unit;
    if (c <= 0) return '—';
    final price = priceYuan / c;
    return '¥${price.toStringAsFixed(price < 1 ? 2 : 3)}/喜点';
  }
}
