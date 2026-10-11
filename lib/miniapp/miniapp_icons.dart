import 'package:flutter/material.dart';

/// meta.icon → Material 图标（与后端 catalog.go 的 Icons 一一对应；未知回落 apps）。
const Map<String, IconData> kMiniAppIcons = {
  'apps': Icons.apps_rounded,
  'insights': Icons.insights_rounded,
  'show_chart': Icons.show_chart_rounded,
  'candlestick': Icons.candlestick_chart_rounded,
  'bar_chart': Icons.bar_chart_rounded,
  'pie_chart': Icons.pie_chart_rounded,
  'calculate': Icons.calculate_rounded,
  'savings': Icons.savings_rounded,
  'account_balance': Icons.account_balance_rounded,
  'currency_exchange': Icons.currency_exchange_rounded,
  'oil_barrel': Icons.oil_barrel_rounded,
  'agriculture': Icons.agriculture_rounded,
  'grain': Icons.grain_rounded,
  'newspaper': Icons.newspaper_rounded,
  'notifications': Icons.notifications_rounded,
  'cloud': Icons.cloud_rounded,
  'water_drop': Icons.water_drop_rounded,
  'thermostat': Icons.thermostat_rounded,
  'air': Icons.air_rounded,
  'sunny': Icons.wb_sunny_rounded,
  'phishing': Icons.phishing_rounded,
  'set_meal': Icons.set_meal_rounded,
  'water': Icons.water_rounded,
  'place': Icons.place_rounded,
  'map': Icons.map_rounded,
  'event': Icons.event_rounded,
  'timer': Icons.timer_rounded,
  'scale': Icons.scale_rounded,
  'science': Icons.science_rounded,
  'inventory': Icons.inventory_2_rounded,
  'checklist': Icons.checklist_rounded,
  'star': Icons.star_rounded,
};

IconData miniAppIcon(String name) => kMiniAppIcons[name] ?? Icons.apps_rounded;
