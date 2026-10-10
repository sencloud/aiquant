/// 「纸上墨金」的基础构件。
///
/// 微信的结构语法：页面是纸，内容是白面分组卡，卡内是行；行与行之间一条
/// 发丝线，靠右是值或箭头。所有页面都从这几个构件拼，不要各写各的 Card
/// 圆角和阴影。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 页面骨架：纸底 + 居中标题导航栏。
///
/// 微信的导航栏和页面同色，不浮起来、不投影，只有一条发丝线收边。标题居中。
class WkPage extends StatelessWidget {
  const WkPage({
    super.key,
    this.title,
    required this.child,
    this.actions = const [],
    this.leading,
    this.showNavBar = true,
    this.bottomNav,
  });

  final String? title;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final bool showNavBar;
  final Widget? bottomNav;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: showNavBar
          ? AppBar(
              title: title == null ? null : Text(title!),
              centerTitle: true,
              leading: leading,
              actions: actions,
              // 页签页没什么可退，二级页必须有返回箭头 —— 交给 Flutter 按
              // 「这个路由能不能 pop」自己判断（只在没有自定义 leading 时）。
              automaticallyImplyLeading: leading == null,
            )
          : null,
      body: SafeArea(top: !showNavBar, bottom: false, child: child),
      bottomNavigationBar: bottomNav,
    );
  }
}

/// 白面分组卡。圆角 + 白面，不用描边、不用宽阴影。
class WkGroup extends StatelessWidget {
  const WkGroup({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.padding,
    this.margin = const EdgeInsets.only(bottom: AppSpace.md),
  });

  final List<Widget> children;

  /// 分组头（浅色小字，左对齐，如微信设置页的分组名）。
  final String? header;

  /// 分组尾注（口径、说明）。
  final String? footer;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpace.xs, bottom: AppSpace.sm, top: AppSpace.xs),
            child: Text(header!,
                style: AppType.section.copyWith(color: AppColors.textSecondary)),
          ),
        Container(
          margin: margin,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withDividers(children),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpace.xs, right: AppSpace.xs, bottom: AppSpace.md),
            child: Text(footer!,
                style: AppType.caption.copyWith(
                    color: AppColors.textTertiary, height: 1.5)),
          ),
      ],
    );
  }

  /// 行与行之间插发丝线，最后一行不加。
  List<Widget> _withDividers(List<Widget> items) {
    if (items.length < 2) return items;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) {
        out.add(Divider(height: 0.5, thickness: 0.5, color: AppColors.borderDim));
      }
    }
    return out;
  }
}

/// 分组内的一行：左图标 / 主文 + 副文 / 右值或箭头。
///
/// 微信列表行高：单行 52，双行自适应。箭头一定是最右那个，值在箭头左边。
class WkRow extends StatelessWidget {
  const WkRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.minHeight = 52,
    this.titleColor,
    this.padding =
        const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 12),
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final double minHeight;
  final Color? titleColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? AppColors.danger : AppColors.textPrimary;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 20,
                  color: destructive ? AppColors.danger : AppColors.amber),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: AppType.body.copyWith(color: titleColor ?? fg)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!,
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: AppSpace.sm),
              Text(value!,
                  style: AppType.body.copyWith(color: AppColors.textSecondary)),
            ],
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.sm),
              trailing!,
            ],
            if (onTap != null) ...[
              const SizedBox(width: AppSpace.xs),
              // textTertiary 是运行时字段，不能进 const 构造。
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textTertiary),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// 大按钮：主色实心，圆角 12，高度 48。全 App 的主行动都用它。
class WkPrimaryButton extends StatelessWidget {
  const WkPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.borderMed,
          disabledForegroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: AppSpace.sm),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// 小标签：默认描边灰底；[tone] 指定语义色时描边走该色。
class WkTag extends StatelessWidget {
  const WkTag(this.text, {super.key, this.tone, this.filled = false});

  final String text;
  final Color? tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: filled ? Colors.transparent : c.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: AppType.micro.copyWith(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 数字 + 单位 + 标签的一格。数字用等宽字形，避免多格并排时跳动。
class WkStat extends StatelessWidget {
  const WkStat({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.color,
    this.align = CrossAxisAlignment.start,
  });

  final String value;
  final String label;
  final String? unit;
  final Color? color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: AppType.display.copyWith(
              color: color ?? AppColors.textPrimary,
              fontFamilyFallback: AppType.numericFallback,
            ),
            children: [
              TextSpan(text: value),
              if (unit != null)
                TextSpan(
                  text: unit,
                  style: AppType.caption.copyWith(
                    color: color ?? AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: AppType.caption.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}

/// 口径 / 免责声明块：纸色内嵌、行高 1.75，读起来是「小字说明」而不是噪声。
class WkNote extends StatelessWidget {
  const WkNote({super.key, required this.text, this.title});

  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!,
                style: AppType.section
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.xs),
          ],
          Text(text,
              style: AppType.caption.copyWith(
                  color: AppColors.textSecondary, height: 1.7)),
        ],
      ),
    );
  }
}

/// 页面级空状态：一句话说清「为什么空」和「下一步做什么」。
class WkEmpty extends StatelessWidget {
  const WkEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textTertiary),
            const SizedBox(height: AppSpace.md),
            Text(title,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: AppColors.textSecondary)),
            if (hint != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: AppType.caption
                      .copyWith(color: AppColors.textTertiary, height: 1.6)),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
