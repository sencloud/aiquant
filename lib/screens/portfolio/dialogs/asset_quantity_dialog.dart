import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/china_market.dart';
import '../../../models/instrument.dart';
import '../../../services/tushare_service.dart';
import '../../../theme/app_theme.dart';
import 'asset_lot.dart';

/// Status of the auto-prefill of the "均价" field, per instrument.
enum _PriceStatus { loading, loaded, failed }

class AssetQuantityDialog extends StatefulWidget {
  const AssetQuantityDialog({super.key, required this.instruments});

  final List<Instrument> instruments;

  @override
  State<AssetQuantityDialog> createState() => _AssetQuantityDialogState();
}

class _AssetQuantityDialogState extends State<AssetQuantityDialog> {
  late final Map<String, TextEditingController> _qtyCtrls;
  late final Map<String, TextEditingController> _priceCtrls;
  late final Map<String, _PriceStatus> _status;
  // Track whether the user has manually touched the price so we never
  // clobber their input with the auto-fetched close.
  late final Map<String, bool> _userEditedPrice;
  final TushareService _tushare = TushareService();

  @override
  void initState() {
    super.initState();
    _qtyCtrls = {
      for (final ins in widget.instruments)
        ins.tsCode: TextEditingController(text: _defaultQty(ins)),
    };
    _priceCtrls = {
      for (final ins in widget.instruments)
        ins.tsCode: TextEditingController(),
    };
    _userEditedPrice = {
      for (final ins in widget.instruments) ins.tsCode: false,
    };
    _status = {
      for (final ins in widget.instruments) ins.tsCode: _PriceStatus.loading,
    };
    for (final entry in _priceCtrls.entries) {
      entry.value.addListener(() {
        // Only flip the flag for input that didn't originate from our
        // auto-prefill (i.e. real keystrokes from the user). We detect this
        // by setting the text via [_setPrefill] which temporarily disables
        // the listener.
        _userEditedPrice[entry.key] = true;
      });
    }
    _fetchPrices();
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchPrices() async {
    await Future.wait([
      for (final ins in widget.instruments) _fetchOne(ins),
    ]);
  }

  Future<void> _fetchOne(Instrument ins) async {
    try {
      final candles = await _tushare.historyFor(
        ins.tsCode,
        start: DateTime.now().subtract(const Duration(days: 14)),
        end: DateTime.now(),
      );
      if (!mounted) return;
      if (candles.isEmpty) {
        setState(() => _status[ins.tsCode] = _PriceStatus.failed);
        return;
      }
      final close = candles.last.close;
      // Don't overwrite anything the user has already typed.
      if (!(_userEditedPrice[ins.tsCode] ?? false)) {
        _setPrefill(ins.tsCode, _formatPrice(close, ins));
      }
      setState(() => _status[ins.tsCode] = _PriceStatus.loaded);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status[ins.tsCode] = _PriceStatus.failed);
    }
  }

  void _setPrefill(String code, String value) {
    final ctrl = _priceCtrls[code];
    if (ctrl == null) return;
    final wasEdited = _userEditedPrice[code] ?? false;
    ctrl.text = value;
    // Setting text fires the listener — restore the original "user-edited"
    // flag so this programmatic write doesn't look like a keystroke.
    _userEditedPrice[code] = wasEdited;
  }

  String _formatPrice(double v, Instrument ins) {
    // Stocks/ETFs/indices → 2~3 decimals; futures often need more precision
    // depending on the contract — 2 is a safe default for display.
    final decimals = ins.assetClass == 'ETF' ? 3 : 2;
    return v.toStringAsFixed(decimals);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSurface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 600),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('填写数量与买入均价',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
            ),
            Divider(height: 1, color: AppColors.borderDim),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                itemCount: widget.instruments.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.borderDim),
                itemBuilder: (_, i) {
                  final ins = widget.instruments[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ins.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(ins.tsCode,
                                  style: const TextStyle(
                                      color: AppColors.amber,
                                      fontSize: 11,
                                      fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _qtyCtrls[ins.tsCode],
                            keyboardType: TextInputType.numberWithOptions(
                                decimal: ins.assetClass == '期货'
                                    ? false
                                    : false),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText:
                                  '数量(${ChinaMarket.quantityUnit(ins.assetClass)})',
                              isDense: true,
                              helperText: _qtyHint(ins),
                              helperStyle: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 9),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _priceCtrls[ins.tsCode],
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                            ],
                            decoration: InputDecoration(
                              labelText: '均价',
                              isDense: true,
                              hintText: _hintFor(ins.tsCode),
                              suffixIcon: _statusIcon(ins.tsCode),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: AppColors.borderDim),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('均价默认是最新收盘价，可自行修改',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.add_task, size: 14),
                    label: const Text('确认添加'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _hintFor(String code) {
    switch (_status[code]) {
      case _PriceStatus.loading:
        return '加载中…';
      case _PriceStatus.failed:
        return '收盘价获取失败';
      case _PriceStatus.loaded:
      case null:
        return null;
    }
  }

  Widget? _statusIcon(String code) {
    switch (_status[code]) {
      case _PriceStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.amber),
          ),
        );
      case _PriceStatus.loaded:
        return const Icon(Icons.check, size: 16, color: AppColors.positive);
      case _PriceStatus.failed:
        return const Icon(Icons.error_outline,
            size: 16, color: AppColors.warning);
      case null:
        return null;
    }
  }

  void _confirm() {
    final out = <String, AssetLot>{};
    final problems = <String>[];
    for (final ins in widget.instruments) {
      final raw = _qtyCtrls[ins.tsCode]?.text ?? '';
      final qty = double.tryParse(raw) ?? 0;
      final price = double.tryParse(_priceCtrls[ins.tsCode]?.text ?? '') ?? 0;
      if (qty <= 0) continue;
      // 中国市场业务校验：A 股 / ETF 必须 100 整数倍；期货必须整数手。
      final lot = ChinaMarket.lotSize(ins.assetClass);
      if (lot > 1 && (qty % lot) != 0) {
        problems.add('${ins.name}：${ChinaMarket.quantityUnit(ins.assetClass)}'
            '数需为 $lot 的整数倍');
        continue;
      }
      if (ins.assetClass == '期货' && qty != qty.roundToDouble()) {
        problems.add('${ins.name}：手数请输入整数');
        continue;
      }
      out[ins.tsCode] = AssetLot(qty, price);
    }
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(problems.join(' ; ')),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    Navigator.pop(context, out);
  }

  String _defaultQty(Instrument ins) {
    switch (ins.assetClass) {
      case '股票':
      case 'ETF':
      case 'LOF':
        return '100';
      case '期货':
        return '1';
      default:
        return '1';
    }
  }

  String _qtyHint(Instrument ins) {
    switch (ins.assetClass) {
      case '股票':
        return '至少 100 股，且按 100 的整数倍输入';
      case 'ETF':
      case 'LOF':
        return '至少 100 份，且按 100 的整数倍输入';
      case '期货':
        final mult = ChinaMarket.contractMultiplier(ins.tsCode, ins.assetClass);
        if (mult > 1) {
          return '1 手 = ${mult.toStringAsFixed(0)} 个标的单位';
        }
        return '请按手数输入（整数）';
      default:
        return '';
    }
  }
}
