/// Lightweight port of `services::markets::ChinaMarket` from the Qt project.
///
/// Centralises symbol normalisation rules (SH/SZ/BJ for stocks, the various
/// futures exchange suffixes used by Tushare) and a tiny seed catalogue used
/// for offline display names. Live data still comes from Tushare.
class ChinaMarket {
  static String normalizeSymbol(String input) {
    final s = input.trim().toUpperCase().replaceAll(' ', '');
    if (s.isEmpty) return '';

    // Already qualified — fix the futures-exchange suffix differences.
    if (s.contains('.')) {
      if (s.endsWith('.CZCE')) return s.substring(0, s.length - 1); // CZCE → CZC
      if (s.endsWith('.SHFE')) return '${s.substring(0, s.length - 5)}.SHF';
      if (s.endsWith('.GFEX')) return '${s.substring(0, s.length - 5)}.GFE';
      if (s.endsWith('.CFFEX')) return '${s.substring(0, s.length - 6)}.CFE';
      return s;
    }

    // Pure 6-digit numeric → infer SSE/SZSE/BSE.
    final sixDigit = RegExp(r'^\d{6}$');
    if (sixDigit.hasMatch(s)) {
      if (s.startsWith('6') || s.startsWith('900')) return '$s.SH';
      if (s.startsWith('0') || s.startsWith('3') || s.startsWith('200')) {
        return '$s.SZ';
      }
      if (s.startsWith('4') || s.startsWith('8') || s.startsWith('920')) {
        return '$s.BJ';
      }
    }

    return s;
  }

  static const _futureSuffixes = {
    '.CZC', '.CZCE',
    '.DCE',
    '.SHF', '.SHFE',
    '.INE',
    '.GFE', '.GFEX',
    '.CFE', '.CFFEX',
  };

  static bool isFuture(String symbol) {
    final s = symbol.toUpperCase();
    return _futureSuffixes.any(s.endsWith);
  }

  static bool isIndex(String symbol) {
    final s = symbol.toUpperCase();
    if (s.startsWith('000') && s.endsWith('.SH')) return true;
    if (s.startsWith('399') && s.endsWith('.SZ')) return true;
    return false;
  }

  static bool isStock(String symbol) {
    final s = symbol.toUpperCase();
    return s.endsWith('.SH') || s.endsWith('.SZ') || s.endsWith('.BJ');
  }

  static String exchangeOf(String symbol) {
    final s = symbol.toUpperCase();
    if (s.endsWith('.SH')) return 'SSE';
    if (s.endsWith('.SZ')) return 'SZSE';
    if (s.endsWith('.BJ')) return 'BSE';
    if (s.endsWith('.CZC') || s.endsWith('.CZCE')) return '郑商所';
    if (s.endsWith('.DCE')) return '大商所';
    if (s.endsWith('.SHF') || s.endsWith('.SHFE')) return '上期所';
    if (s.endsWith('.INE')) return '上海能源';
    if (s.endsWith('.GFE') || s.endsWith('.GFEX')) return '广期所';
    if (s.endsWith('.CFE') || s.endsWith('.CFFEX')) return '中金所';
    return '';
  }

  static String assetClassOf(String symbol) {
    if (isFuture(symbol)) return '期货';
    if (isIndex(symbol)) return '指数';
    if (isStock(symbol)) return '股票';
    return '其它';
  }
}
