import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'fishing_models.dart';
import 'fishing_state.dart';
import 'regulations_screen.dart';

/// 「出钓」页签：出钓指数（透明计分）+ 推荐时段 + 禁渔提示。
class FishingForecastScreen extends StatefulWidget {
  const FishingForecastScreen({super.key});

  @override
  State<FishingForecastScreen> createState() => _FishingForecastScreenState();
}

class _FishingForecastScreenState extends State<FishingForecastScreen> {
  final _place = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = context.read<FishingState>();
      await s.bootstrap();
      if (mounted && _place.text.isEmpty) _place.text = s.lastPlace;
    });
  }

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  void _search([String? v]) {
    final q = (v ?? _place.text).trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    _place.text = q;
    context.read<FishingState>().loadForecast(place: q);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FishingState>();
    return WkPage(
      title: '出钓',
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([s.reloadForecast(), s.loadRegulations()]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
          children: [
            _searchBar(s),
            const SizedBox(height: AppSpace.md),
            if (s.spots.any((x) => x.hasCoord)) ...[
              _spotChips(s),
              const SizedBox(height: AppSpace.md),
            ],
            if (s.forecastLoading && s.forecast == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (s.forecastError != null && s.forecast == null)
              _errorCard(s)
            else if (s.forecast == null)
              _pickPlace(s)
            else
              ..._forecastBody(s, s.forecast!),
            const SizedBox(height: AppSpace.sm),
            _BanCard(regs: s.regulations),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(FishingState s) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 20, color: AppColors.amber),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: TextField(
              key: const Key('forecast-place'),
              controller: _place,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: const InputDecoration(
                hintText: '输入城市、区县、水库或湖名',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (s.forecastLoading)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              tooltip: '查询',
              icon: Icon(Icons.search_rounded, color: AppColors.amber),
              onPressed: _search,
            ),
        ],
      ),
    );
  }

  Widget _spotChips(FishingState s) {
    final spots = s.spots.where((x) => x.hasCoord).take(6).toList();
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final sp in spots)
          ActionChip(
            avatar: Icon(Icons.bookmark_outline_rounded,
                size: 16, color: AppColors.amber),
            label: Text(sp.name),
            onPressed: () {
              _place.text = sp.name;
              s.loadForecast(place: sp.name, lat: sp.lat, lon: sp.lon);
            },
          ),
      ],
    );
  }

  Widget _pickPlace(FishingState s) {
    return WkGroup(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Text('去哪儿钓？',
            style: AppType.title.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpace.xs),
        Text('输入地名查看未来 3 天的出钓指数：气压、风、气温、降水、月相五项打分，分数怎么来的都写清楚。',
            style: AppType.caption
                .copyWith(color: AppColors.textSecondary, height: 1.6)),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final p in FishingState.quickPlaces)
              ActionChip(label: Text(p), onPressed: () => _search(p)),
          ],
        ),
      ],
    );
  }

  Widget _errorCard(FishingState s) {
    return WkGroup(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Text(s.forecastError!,
            style: AppType.body.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
              onPressed: () => _search(), child: const Text('重试')),
        ),
      ],
    );
  }

  List<Widget> _forecastBody(FishingState s, FishingForecast f) {
    final d = s.day;
    if (d == null) {
      return [
        WkGroup(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [Text('${f.place} 暂无预报数据', style: AppType.body)],
        ),
      ];
    }
    return [
      _DayTabs(days: f.days, selected: s.selectedDay, onSelect: s.selectDay),
      const SizedBox(height: AppSpace.md),
      _ScoreCard(place: f.place, day: d),
      if (d.warnings.isNotEmpty) ...[
        for (final w in d.warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _Banner(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                text: w),
          ),
      ],
      WkGroup(
        header: '分项打分',
        footer: f.disclaimer,
        children: [for (final x in d.factors) _FactorRow(factor: x)],
      ),
      WkGroup(
        header: '推荐时段',
        children: [
          if (d.windows.isEmpty)
            const WkRow(title: '今天没有合适的时段', subtitle: '风雨较大，建议改天')
          else
            for (final w in d.windows)
              WkRow(
                icon: w.label == '清晨'
                    ? Icons.wb_twilight_rounded
                    : Icons.nights_stay_outlined,
                title: '${w.label}  ${w.from}–${w.to}',
                subtitle: w.label == '清晨'
                    ? '日出 ${d.sunrise} 前后，鱼开始觅食'
                    : '日落 ${d.sunset} 前后，鱼口回升',
              ),
          WkRow(
            icon: Icons.thermostat_rounded,
            title: '天气',
            subtitle: '${d.tempMin.round()}–${d.tempMax.round()}℃ · '
                '降水 ${d.precipSum.toStringAsFixed(1)}mm · '
                '最大风速 ${d.windMax.toStringAsFixed(0)}m/s',
          ),
        ],
      ),
      _FormulaTile(formula: f.formula),
    ];
  }
}

class _DayTabs extends StatelessWidget {
  const _DayTabs(
      {required this.days, required this.selected, required this.onSelect});
  final List<ForecastDay> days;
  final int selected;
  final ValueChanged<int> onSelect;

  String _label(int i, String date) {
    if (i == 0) return '今天';
    if (i == 1) return '明天';
    if (i == 2) return '后天';
    return date.length >= 10 ? date.substring(5) : date;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.sm),
          Expanded(
            child: GestureDetector(
              key: Key('forecast-day-$i'),
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                decoration: BoxDecoration(
                  color: i == selected ? AppColors.amber : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    Text(_label(i, days[i].date),
                        style: AppType.caption.copyWith(
                            color: i == selected
                                ? AppColors.onAccent
                                : AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text('${days[i].score}',
                        style: AppType.section.copyWith(
                            color: i == selected
                                ? AppColors.onAccent
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Color levelColor(String level) => switch (level) {
      '很适合' => AppColors.amber,
      '适合' => AppColors.amber.withValues(alpha: 0.8),
      '一般' => AppColors.warning,
      _ => AppColors.textTertiary,
    };

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.place, required this.day});
  final String place;
  final ForecastDay day;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(day.level);
    return WkGroup(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: day.score / 100,
                      strokeWidth: 7,
                      backgroundColor: AppColors.accentSoft,
                      color: c,
                    ),
                  ),
                  Text('${day.score}',
                      key: const Key('forecast-score'),
                      style: AppType.display.copyWith(
                          color: AppColors.textPrimary,
                          fontFamilyFallback: AppType.numericFallback)),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    WkTag(day.level, tone: c, filled: true),
                    const SizedBox(width: AppSpace.sm),
                    Flexible(
                      child: Text(place,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption
                              .copyWith(color: AppColors.textTertiary)),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.sm),
                  Text(day.summary,
                      style: AppType.body
                          .copyWith(color: AppColors.textPrimary, height: 1.5)),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                      '日出 ${day.sunrise} · 日落 ${day.sunset} · ${day.moonPhase}',
                      style: AppType.caption
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor});
  final ForecastFactor factor;

  @override
  Widget build(BuildContext context) {
    final ratio = factor.max == 0 ? 0.0 : factor.score / factor.max;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(factor.name,
                  style: AppType.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(factor.value,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption
                        .copyWith(color: AppColors.textSecondary)),
              ),
              Text('${factor.score}/${factor.max}',
                  style: AppType.body.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamilyFallback: AppType.numericFallback)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.accentSoft,
              color: ratio >= 0.75
                  ? AppColors.amber
                  : ratio >= 0.5
                      ? AppColors.warning
                      : AppColors.danger,
            ),
          ),
          const SizedBox(height: 6),
          Text(factor.note,
              style: AppType.caption
                  .copyWith(color: AppColors.textTertiary, height: 1.5)),
        ],
      ),
    );
  }
}

class _FormulaTile extends StatelessWidget {
  const _FormulaTile({required this.formula});
  final String formula;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: const Key('forecast-formula'),
            leading: Icon(Icons.functions_rounded, color: AppColors.amber),
            title: const Text('计分方式', style: AppType.body),
            childrenPadding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
            children: [
              Text(formula,
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary, height: 1.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(text,
                style: AppType.caption
                    .copyWith(color: AppColors.textPrimary, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// 禁渔提示卡：只列全国性流域制度，固定带「以当地公告为准」。
class _BanCard extends StatelessWidget {
  const _BanCard({required this.regs});
  final FishingRegulations? regs;

  @override
  Widget build(BuildContext context) {
    final active = regs?.active ?? const <FishingRegulation>[];
    return WkGroup(
      header: '禁渔提示',
      footer: '仅列农业农村部公布的全国性流域制度，各地另有禁渔区、禁钓区和钓具钓法规定，以当地公告为准。',
      children: [
        if (regs == null)
          const WkRow(
              icon: Icons.gavel_rounded,
              title: '长江十年禁渔（2021–2030）',
              subtitle: '长江干流、重要支流和鄱阳湖、洞庭湖等重点水域')
        else
          for (final r in active.take(3))
            WkRow(
              icon: Icons.gavel_rounded,
              title: r.name,
              subtitle: '${r.period}\n${r.angling}',
            ),
        WkRow(
          key: const Key('forecast-all-regs'),
          title: '查看全部流域禁渔期',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => RegulationsScreen(regs: regs))),
        ),
      ],
    );
  }
}
