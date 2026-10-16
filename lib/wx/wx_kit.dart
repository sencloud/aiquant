/// 微信式的构件箱。
///
/// 这一套只放「微信里长这样、别处不长这样」的零件：方头像、未读角标、
/// 搜索框、带小尖角的聊天气泡、彩色方块图标。通用的分组卡 / 行 / 空状态
/// 还在 `lib/widgets/wk_kit.dart` 里 —— 那些构件的形状本来就来自微信，
/// 这次只是把材质（灰底、白面、发丝线、绿）换掉了。
library;

import 'package:flutter/material.dart';

import '../core/app_profile.dart';
import '../theme/app_theme.dart';

/// 微信式头像：圆角方块（不是圆形），底色 + 单字，可选右下角未读点。
/// 页签页的顶栏：灰底、居中标题、右（或左）一个动作。高 44，与微信一致。
class WxTopBar extends StatelessWidget {
  const WxTopBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgBase,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: Stack(
            children: [
              Center(child: Text(title, style: AppType.title)),
              if (leading != null)
                Positioned(left: AppSpace.xs, top: 0, bottom: 0, child: leading!),
              if (actions.isNotEmpty)
                Positioned(
                  right: AppSpace.xs,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WxAvatar extends StatelessWidget {
  const WxAvatar({
    super.key,
    required this.text,
    this.size = 48,
    this.background,
    this.icon,
    this.badge = 0,
    this.dot = false,
  });

  /// 头像里的字（一个字最好看，两个字也行）。
  final String text;

  final double size;
  final Color? background;

  /// 用图标代替字（AI 助手的几个固定位）。
  final IconData? icon;

  /// 右上角未读数，0 表示不显示。
  final int badge;

  /// 只显示一个小红点（不显示数字）。
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? AppColors.amber;
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.52, color: Colors.white)
          : Text(
              text.isEmpty ? kBrandMark : text.characters.first,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w500,
                height: 1.0,
                fontFamilyFallback: AppType.sansFallback,
              ),
            ),
    );
    if (badge <= 0 && !dot) return tile;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          right: -6,
          top: -6,
          child: badge > 0 ? WxBadge(count: badge) : const WxDot(),
        ),
      ],
    );
  }
}

/// 红色未读数角标（微信那个：红底白字、圆角胶囊、带一圈白边）。
class WxBadge extends StatelessWidget {
  const WxBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.bgSurface, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          height: 1.25,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: AppType.sansFallback,
        ),
      ),
    );
  }
}

/// 小红点（只有「有新的」这一个意思，不带数字）。
class WxDot extends StatelessWidget {
  const WxDot({super.key, this.borderColor});

  /// 压在头像 / 图标上时给一圈底色描边，避免糊在一起。
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.danger,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? AppColors.bgSurface,
          width: 1.5,
        ),
      ),
    );
  }
}

/// 微信式搜索框：白底、圆角 6、居中一个放大镜与「搜索」。
///
/// 不展开成真的输入框 —— 微信里它点开是另一个页面；我们这边点开就是
/// 一个「筛选当前列表」的输入框，所以直接做成可聚焦的输入框，样式照抄。
class WxSearchBar extends StatelessWidget {
  const WxSearchBar({
    super.key,
    this.hint = '搜索',
    this.controller,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpace.sm),
          Icon(Icons.search_rounded,
              size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              readOnly: readOnly,
              onTap: onTap,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: AppType.body.copyWith(fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle:
                    AppType.body.copyWith(fontSize: 15, color: AppColors.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
    );
  }
}

/// 聊天气泡：绿的是自己说的，白的是对方说的，左上/右上带一个小尖角。
class WxBubble extends StatelessWidget {
  const WxBubble({
    super.key,
    required this.child,
    required this.isSelf,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.maxWidth,
  });

  final Widget child;
  final bool isSelf;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final bg = isSelf ? AppColors.bubbleSelf : AppColors.bubbleOther;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? MediaQuery.of(context).size.width * 0.72,
      ),
      child: CustomPaint(
        painter: _BubbleTailPainter(color: bg, isSelf: isSelf),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 气泡的小尖角：一个 6×10 的三角，贴在气泡的上缘、靠头像那一侧。
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.isSelf});

  final Color color;
  final bool isSelf;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const w = 6.0;
    const h = 9.0;
    final path = Path();
    if (isSelf) {
      path
        ..moveTo(size.width - w, 12)
        ..lineTo(size.width, 12 + h)
        ..lineTo(size.width - w, 12 + h);
    } else {
      path
        ..moveTo(w, 12)
        ..lineTo(0, 12 + h)
        ..lineTo(w, 12 + h);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.color != color || old.isSelf != isSelf;
}

/// 聊天里的时间戳：居中、灰字、小号，只在「隔了一会儿」的时候出现。
class WxTimeStamp extends StatelessWidget {
  const WxTimeStamp(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      child: Center(
        child: Text(
          text,
          style: AppType.micro.copyWith(color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

/// 聊天里的时间写法，照微信：
///   今天 → 「上午 9:20」；昨天 → 「昨天 上午 9:20」；
///   一周内 → 「星期二 上午 9:20」；更早 → 「2026年10月13日 上午 9:20」。
String wxChatTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final that = DateTime(t.year, t.month, t.day);
  final diff = today.difference(that).inDays;
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final clock = '${t.hour < 12 ? '上午' : '下午'} $hour12:'
      '${t.minute.toString().padLeft(2, '0')}';
  if (diff <= 0) return clock;
  if (diff == 1) return '昨天 $clock';
  if (diff < 7) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return '星期${names[t.weekday - 1]} $clock';
  }
  return '${t.year}年${t.month}月${t.day}日 $clock';
}

/// 彩色方块图标：微信「发现」那一排的样子（32 方块 + 白色图标）。
class WxIconTile extends StatelessWidget {
  const WxIconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 28,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? AppColors.amber,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: size * 0.62, color: Colors.white),
    );
  }
}
