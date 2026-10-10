/// 编译期功能开关。
///
/// MVP 付费闭环只保留「对话 + 证伪」主线：AI 直播、鹦鹉螺预测默认隐藏。
/// 代码与后端路由都保留，需要时用 dart-define 打开：
///
///   flutter run --dart-define=ENABLE_LIVE=true --dart-define=ENABLE_NAUTILUS=true
library;

/// 「发现」里的 AI 直播入口。
const bool kEnableLive = bool.fromEnvironment('ENABLE_LIVE', defaultValue: false);

/// 「发现」里的鹦鹉螺预测入口（含螺壳钱包、螺壳邀请页）。
/// 关闭时不再刷新螺壳钱包；邀请改走 /v1/invite（喜点）。
const bool kEnableNautilus =
    bool.fromEnvironment('ENABLE_NAUTILUS', defaultValue: false);
