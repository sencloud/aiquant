/// Billing 相关 DTO —— 与 backend `internal/billing` 字段一一对齐。
library;

import '../format/credit_fmt.dart';

class CreditSku {
  CreditSku({
    required this.code,
    required this.appleProductId,
    required this.baseCredits,
    required this.bonusCredits,
    required this.totalCredits,
    required this.priceCentsCny,
    required this.priceYuan,
    required this.sort,
  });

  final String code;
  final String appleProductId;
  final int baseCredits;
  final int bonusCredits;
  final int totalCredits;
  final int priceCentsCny;
  final double priceYuan;
  final int sort;

  factory CreditSku.fromJson(Map<String, dynamic> j) => CreditSku(
        code: j['code'] as String,
        appleProductId: j['apple_product_id'] as String,
        baseCredits: (j['base_credits'] as num).toInt(),
        bonusCredits: (j['bonus_credits'] as num).toInt(),
        totalCredits: (j['total_credits'] as num).toInt(),
        priceCentsCny: (j['price_cents_cny'] as num).toInt(),
        priceYuan: (j['price_yuan'] as num).toDouble(),
        sort: (j['sort'] as num).toInt(),
      );

  /// 给 UI 展示用的"原价 / 总额 / 红利"标签。
  /// 注意：后端 credits 仍按整数计量，前端统一 ÷10 显示给用户。
  String get titleLabel => CreditFmt.label(totalCredits);
  String get baseLabel => CreditFmt.label(baseCredits);
  String get bonusLabel => bonusCredits > 0 ? '送 ${CreditFmt.amount(bonusCredits)}' : '';
  String get priceLabel => '¥${priceYuan.toStringAsFixed(priceYuan == priceYuan.roundToDouble() ? 0 : 2)}';
  String get unitPriceLabel => CreditFmt.unitPrice(priceYuan, totalCredits);
}

class CreditOrder {
  CreditOrder({
    required this.orderNo,
    required this.skuCode,
    required this.credits,
    required this.amountCents,
    required this.channel,
    required this.status,
    this.paidAt,
    this.creditedAt,
    this.refundedAt,
    this.clientRequestId,
    required this.createdAt,
  });

  final String orderNo;
  final String skuCode;
  final int credits;
  final int amountCents;
  final String channel;
  final String status;
  final int? paidAt;
  final int? creditedAt;
  final int? refundedAt;
  final String? clientRequestId;
  final int createdAt;

  factory CreditOrder.fromJson(Map<String, dynamic> j) => CreditOrder(
        orderNo: j['order_no'] as String,
        skuCode: j['sku_code'] as String,
        credits: (j['credits'] as num).toInt(),
        amountCents: (j['amount_cents'] as num).toInt(),
        channel: j['channel'] as String,
        status: j['status'] as String,
        paidAt: (j['paid_at'] as num?)?.toInt(),
        creditedAt: (j['credited_at'] as num?)?.toInt(),
        refundedAt: (j['refunded_at'] as num?)?.toInt(),
        clientRequestId: j['client_request_id'] as String?,
        createdAt: (j['created_at'] as num).toInt(),
      );

  bool get isCredited => status == 'credited';
  bool get isPending => status == 'pending';
}

class CreditLedgerItem {
  CreditLedgerItem({
    required this.id,
    required this.delta,
    required this.balanceAfter,
    required this.reason,
    this.refType,
    this.refId,
    this.remark,
    required this.createdAt,
  });

  final int id;
  final int delta;
  final int balanceAfter;
  final String reason;
  final String? refType;
  final String? refId;
  final String? remark;
  final int createdAt;

  factory CreditLedgerItem.fromJson(Map<String, dynamic> j) => CreditLedgerItem(
        id: (j['id'] as num).toInt(),
        delta: (j['delta'] as num).toInt(),
        balanceAfter: (j['balance_after'] as num).toInt(),
        reason: j['reason'] as String,
        refType: j['ref_type'] as String?,
        refId: j['ref_id'] as String?,
        remark: j['remark'] as String?,
        createdAt: (j['created_at'] as num).toInt(),
      );

  /// 中文描述。
  String get reasonLabel {
    switch (reason) {
      case 'topup':
        return '充值';
      case 'refund':
        return '退款';
      case 'admin_adjust':
        return '后台调整';
      case 'signup_gift':
        return '注册赠送';
      case 'consume_ai':
        return '助理消费';
      case 'consume_ding':
        return 'DING 任务';
      case 'dev_topup':
        return '内部充值';
      default:
        return reason;
    }
  }

  /// "+5.0" / "-0.6"
  String get deltaLabel => CreditFmt.delta(delta);

  /// "余 6.0"
  String get balanceLabel => CreditFmt.balance(balanceAfter);
}
