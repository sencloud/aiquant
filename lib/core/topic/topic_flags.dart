/// 主题相关的编译期开关。
library;

/// 是否开放「喜爱钓鱼」主题（首启选择页、「我的 → 切换主题」、长按标题切换）。
///
/// 关闭时 App 只有喜爱钱、不出现任何主题入口（与主题化之前完全一致）：
///
///   flutter run --dart-define=ENABLE_TOPIC_FISHING=false
const bool kEnableTopicFishing =
    bool.fromEnvironment('ENABLE_TOPIC_FISHING', defaultValue: true);
