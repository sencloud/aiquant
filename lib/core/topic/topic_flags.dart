/// 主题相关的编译期开关。
library;

/// 是否开放「喜爱钓鱼」主题（首启选择页、「我的 → 切换主题」、长按标题切换）。
///
/// 关闭时 App 只有喜爱钱、不出现任何主题入口（与主题化之前完全一致）：
///
///   flutter run --dart-define=ENABLE_TOPIC_FISHING=false
const bool kEnableTopicFishing =
    bool.fromEnvironment('ENABLE_TOPIC_FISHING', defaultValue: true);

/// 是否开放方案五新开的四个兴趣圈（喜爱养猫 / 喜爱咖啡 / 喜爱露营 / 喜爱汉服）。
///
/// 关掉时 App 只剩喜爱钱与喜爱钓鱼，与这两条上线之前完全一致：
///
///   flutter run --dart-define=ENABLE_TOPIC_CIRCLES=false
const bool kEnableTopicCircles =
    bool.fromEnvironment('ENABLE_TOPIC_CIRCLES', defaultValue: true);
