import '../../core/config/app_config.dart';
import '../ai_tools.dart';
import '../news_service.dart';
import '../tushare_service.dart';
import 'event_tools.dart';
import 'fundamental_tools.dart';
import 'macro_tools.dart';
import 'quant_tools.dart';
import 'tushare_tools.dart';

/// 把所有工具组装成一个 ToolRegistry。
/// 工具组：
///   1. 基础 Tushare（搜索/行情/对比/行业/大盘/ETF）         × 6
///   2. 量化指标（收益/Sharpe/MaxDD/Corr/Beta/MA/RSI/MACD）   × 8
///   3. 基本面（估值/利润/资负/现金流/股东/分红）             × 6
///   4. 宏观资金面（指数成分/两融/北向/行业资金）             × 4
///   5. 全球事件流（GDELT/中文新闻/航运/地缘/卫星火点）       × 5
ToolRegistry buildAllTools({
  TushareService? tushareService,
  NewsService? newsService,
}) {
  final tCtx = TushareToolsContext(svc: tushareService ?? TushareService());
  final firmsKey = AppConfig.instance.firmsMapKey;

  return ToolRegistry([
    ...buildBaseTushareTools(tCtx),
    ...buildQuantTools(tCtx),
    ...buildFundamentalTools(tCtx),
    ...buildMacroTools(tCtx),
    ...buildEventTools(service: newsService, firmsMapKey: firmsKey),
  ]);
}
