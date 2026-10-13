import 'package:flutter/foundation.dart';

/// 兴趣圈外壳的状态：现在站在首页（兴趣圈），还是已经进了某个圈。
///
/// 首页是 App 的首屏，所以 [insideCircle] **不持久化**：每次冷启动都落在首页。
/// 圈本身的选择由 TopicState 持久化（它是身份与配色），两者各管一件事。
class HubState extends ChangeNotifier {
  bool _insideCircle = false;
  int? _pendingTab;

  bool get insideCircle => _insideCircle;

  /// 进圈时希望落在哪个页签（首页的「记烘焙日」直接进记录页）。
  /// 由圈内的外壳取走一次后清空。
  int? takePendingTab() {
    final t = _pendingTab;
    _pendingTab = null;
    return t;
  }

  /// 进圈。[tab] 是要落到的页签下标（默认 0）。
  void enter({int? tab}) {
    _pendingTab = tab;
    if (_insideCircle) return;
    _insideCircle = true;
    notifyListeners();
  }

  /// 回到首页。
  void leave() {
    if (!_insideCircle) return;
    _insideCircle = false;
    _pendingTab = null;
    notifyListeners();
  }
}
