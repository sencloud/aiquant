/// 编译期功能开关。
///
/// 喜爱钱目前只保留「对话」主线：AI 直播、鹦鹉螺预测、策略（证伪档案）、
/// 组合管理、我的自选默认下线。代码与后端路由、定时任务都保留，需要时用
/// dart-define 打开：
///
///   flutter run --dart-define=ENABLE_LIVE=true --dart-define=ENABLE_NAUTILUS=true
///   flutter run --dart-define=ENABLE_STRATEGY_TAB=true \
///     --dart-define=ENABLE_PORTFOLIO=true --dart-define=ENABLE_WATCHLIST=true
library;

/// 喜爱钱的「策略」页签（证伪档案 / 证伪台）。下线：不出现在页签里，
/// 也没有其它入口可以进去。
const bool kEnableStrategyTab =
    bool.fromEnvironment('ENABLE_STRATEGY_TAB', defaultValue: false);

/// 「发现」里的「组合管理」（含策略模拟组合）。下线时 PortfolioState 也不再
/// 启动拉行情；服务端每天的模拟组合任务照常跑（数据不丢，重新开放即可见）。
const bool kEnablePortfolio =
    bool.fromEnvironment('ENABLE_PORTFOLIO', defaultValue: false);

/// 「我的 → 随身工具」里的「我的自选」。下线时自选列表（本机 Hive）保留，
/// 不再启动拉行情。
const bool kEnableWatchlist =
    bool.fromEnvironment('ENABLE_WATCHLIST', defaultValue: false);

/// 「发现」里的 AI 直播入口。
const bool kEnableLive = bool.fromEnvironment('ENABLE_LIVE', defaultValue: false);

/// 「发现」里的鹦鹉螺预测入口（含螺壳钱包、螺壳邀请页）。
/// 关闭时不再刷新螺壳钱包；邀请改走 /v1/invite（喜点）。
const bool kEnableNautilus =
    bool.fromEnvironment('ENABLE_NAUTILUS', defaultValue: false);

/// 喜爱钓鱼的「拍照识鱼」。下线：「渔获」页、「我的」工具、计费说明里都不再出现；
/// 服务端接口默认也关闭（FINME_FISHING_IDENTIFY=1 才放行）。识鱼页面代码保留。
const bool kEnableFishIdentify =
    bool.fromEnvironment('ENABLE_FISH_IDENTIFY', defaultValue: false);
