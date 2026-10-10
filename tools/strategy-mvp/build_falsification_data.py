"""离线生成「证伪台」用的数据资产。

数据来源是本机的 alpha-radar 工程（策略证伪器）：直接读它的 data_cache
（Tushare 缓存的期货主力连续 5 分钟线 / 日线、A 股日线），用它的 universe.py
里的成本模型，算出每个「品种 × 周期」的**往返成本 ÷ 平均振幅**，也就是
alpha-radar 判定序列里的第一道闸门（尺度闸门，阈值 25%）。

不做任何网络请求，也不做参数搜索：这里的每个数字都能用
`alpha-radar` 仓库里的同一份缓存复现。

用法：
    python tools/strategy-mvp/build_falsification_data.py \
        --alpha-radar D:/GitHub/alpha-radar \
        --out assets/strategy/falsification.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
import pathlib
import sys

import numpy as np
import pandas as pd

# 15/30/60 分钟由缓存的 5 分钟线重采样（桶 = 向上取整到周期倍数，与行情软件一致）
DERIVED_FREQS = {"15min": 3, "30min": 6, "60min": 12}
BASE_FREQ = "5min"

# 尺度闸门阈值：往返成本 ÷ 平均振幅。alpha-radar 的实战结论是 25% 以上不做，
# 这里再拆一档「勉强」，方便 UI 用三档呈现而不是二值。
SCALE_PASS = 0.25
SCALE_MARGINAL = 0.40

# alpha-radar 的 universe.py 只给常用品种起了中文名，缓存里还有它没登记的代码；
# 这里补上，免得 UI 上出现一串裸代码。
NAME_OVERRIDE = {"000002.SZ": "万科A"}


def load_instruments(repo: pathlib.Path):
    """按文件路径直接加载 universe.py，绕开包 __init__（它有自己的依赖）。"""
    spec = importlib.util.spec_from_file_location(
        "alpharadar_universe", repo / "alpharadar" / "universe.py"
    )
    mod = importlib.util.module_from_spec(spec)
    # dataclass 解析注解时要回查 sys.modules，必须先注册再执行。
    sys.modules["alpharadar_universe"] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def read_mapping(cache: pathlib.Path, symbol: str) -> pd.DataFrame:
    m = pd.read_csv(cache / f"{symbol}_mapping.csv", dtype={"trade_date": str})
    return m.sort_values("trade_date").reset_index(drop=True)


def segments(mapping: pd.DataFrame) -> list[tuple[str, str, str]]:
    segs: list[list[str]] = []
    for code, d in zip(mapping["mapping_ts_code"], mapping["trade_date"]):
        if segs and segs[-1][0] == code:
            segs[-1][2] = d
        else:
            segs.append([code, d, d])
    return [(c, s, e) for c, s, e in segs]


def main_continuous_5min(cache: pathlib.Path, symbol: str,
                         mapping: pd.DataFrame) -> pd.DataFrame:
    """把逐合约的 5 分钟线拼成主力连续，夜盘归下一个交易日。"""
    cal = np.array(sorted(set(mapping["trade_date"])))
    frames = []
    for code, start, end in segments(mapping):
        f = cache / f"{code}_ft_mins_5min.csv"
        if not f.exists():
            continue
        df = pd.read_csv(f, parse_dates=["trade_time"])
        day = df["trade_time"].dt.strftime("%Y%m%d")
        night = df["trade_time"].dt.hour >= 20
        idx = np.searchsorted(cal, day.to_numpy(), side="right")
        nxt = np.where(idx < len(cal), cal[np.minimum(idx, len(cal) - 1)],
                       day.to_numpy())
        df["sdate"] = np.where(night, nxt, day.to_numpy())
        df = df[(df["sdate"] >= start) & (df["sdate"] <= end)]
        if not df.empty:
            frames.append(df[["trade_time", "sdate", "open", "high", "low",
                              "close", "vol"]])
    if not frames:
        return pd.DataFrame()
    out = pd.concat(frames, ignore_index=True)
    out = out.drop_duplicates(subset="trade_time").sort_values("trade_time")
    return out.reset_index(drop=True)


def main_continuous_daily(cache: pathlib.Path, mapping: pd.DataFrame) -> pd.DataFrame:
    frames = []
    for code, start, end in segments(mapping):
        f = cache / f"{code}_fut_daily.csv"
        if not f.exists():
            continue
        df = pd.read_csv(f, dtype={"trade_date": str})
        df = df[(df["trade_date"] >= start) & (df["trade_date"] <= end)]
        frames.append(df[["trade_date", "open", "high", "low", "close"]])
    if not frames:
        return pd.DataFrame()
    out = pd.concat(frames, ignore_index=True).drop_duplicates("trade_date")
    return out.sort_values("trade_date").reset_index(drop=True)


def resample(df: pd.DataFrame, step: int) -> pd.DataFrame:
    """把 [step] 根 5 分钟线合成一根更大周期的线（成交量为求和）。

    [step] 是「每根合成线包含几根 5 分钟线」，不是分钟数：桶按每个交易日
    内的第几根 5 分钟线切，而不是按钟表分钟取整 —— 钟表取整在周期不是 5 的
    整数倍时会把同一根 5 分钟线拆进不同桶。
    """
    if step <= 1:
        return df
    d = df.copy()
    d["_b"] = d.groupby("sdate", sort=False).cumcount() // step
    g = d.groupby(["sdate", "_b"], sort=False)
    out = g.agg(high=("high", "max"), low=("low", "min"),
                close=("close", "last"), vol=("vol", "sum"))
    return out.reset_index().sort_values(["sdate", "_b"]).reset_index(drop=True)


def span_years(df: pd.DataFrame) -> float:
    """样本跨了多少年（按实际日期跨度，不按根数折算）。"""
    col = "trade_date" if "trade_date" in df.columns else "sdate"
    d = df[col].astype(str)
    if d.empty:
        return 0.0
    lo = pd.to_datetime(d.min(), format="%Y%m%d")
    hi = pd.to_datetime(d.max(), format="%Y%m%d")
    return round(max((hi - lo).days, 0) / 365.25, 1)


def scale_row(inst, freq: str, df: pd.DataFrame, *, is_daily: bool,
              years: float | None = None, source: str = "computed") -> dict:
    """算一行尺度闸门：往返成本（点）÷ 平均振幅（点）。"""
    hi, lo = df["high"].astype(float), df["low"].astype(float)
    cl = df["close"].astype(float)
    amp = float((hi - lo).mean())          # 平均振幅，单位 = 报价点
    px = float(cl.mean())

    if inst.market == "futures":
        # 每边 1 跳滑点 + 单边手续费（元/手 → 报价点：fee / 乘数）
        slip = 2 * inst.tick
        fee_pts = 2 * inst.fee_per_lot / max(inst.mult, 1e-9)
        cost = slip + fee_pts
        cost_pct = 0.0
        basis = f"{freq} 平均振幅 {amp:,.1f} 点"
    else:
        # A 股：佣金双边 2.5bp + 卖出印花税 5bp + 每边 1 跳滑点
        slip = 2 * inst.tick
        fee = px * (inst.fee_rate * 2 + inst.fee_rate_sell)
        cost = slip + fee
        cost_pct = cost / px
        basis = f"{freq} 平均振幅 {amp:,.2f} 元"

    ratio = cost / amp if amp > 0 else float("inf")
    verdict = ("pass" if ratio < SCALE_PASS
               else "marginal" if ratio < SCALE_MARGINAL else "fail")
    # 往返成本折算成「元/手」（股票为元/百股），和点数一起给，方便理解量级
    per_unit = cost * inst.mult * inst.lot
    return {
        "symbol": inst.ts_code,
        "name": NAME_OVERRIDE.get(inst.ts_code, inst.name),
        "market": inst.market,
        "freq": freq,
        "bars": int(len(df)),
        "years": years if years is not None else span_years(df),
        "source": source,
        "amplitude": round(amp, 2),
        "cost": round(cost, 3),
        "cost_pct": round(cost_pct, 5),
        "per_lot_yuan": round(per_unit, 1),
        "ratio": round(ratio, 4),
        "verdict": verdict,
        "note": basis,
    }


def build_cost_scales(cache: pathlib.Path, universe) -> list[dict]:
    rows: list[dict] = []
    for symbol in ("P.DCE", "Y.DCE"):
        mapping = read_mapping(cache, symbol)
        inst = universe.PRESETS[symbol]
        base = main_continuous_5min(cache, symbol, mapping)
        if not base.empty:
            rows.append(scale_row(inst, BASE_FREQ, base, is_daily=False))
            for name, tf in DERIVED_FREQS.items():
                rows.append(scale_row(inst, name, resample(base, tf),
                                      is_daily=False))
        daily = main_continuous_daily(cache, mapping)
        if not daily.empty:
            rows.append(scale_row(inst, "1d", daily, is_daily=True))

    for symbol in ("000001.SZ", "000002.SZ", "600519.SH", "510300.SH"):
        code = symbol.split(".")[0]
        f = cache / (f"{symbol}_fund_daily.csv" if code.startswith("5")
                     else f"{symbol}_daily.csv")
        if not f.exists():
            continue
        df = pd.read_csv(f, dtype={"trade_date": str})
        df = df.dropna(subset=["high", "low", "close"])
        rows.append(scale_row(universe.resolve(symbol), "1d", df, is_daily=True))

    order = {"5min": 0, "15min": 1, "30min": 2, "60min": 3, "1d": 4}
    rows.sort(key=lambda r: (r["market"] != "futures", order.get(r["freq"], 9),
                             r["ratio"]))
    # 1 分钟这一行是本机没有缓存的部分（缓存只到 5 分钟），数字取自
    # alpha-radar 的 docs/findings.md，标注来源以免和实测行混淆。
    palm = universe.PRESETS["P.DCE"]
    rows.insert(0, {
        "symbol": palm.ts_code,
        "name": palm.name,
        "market": palm.market,
        "freq": "1min",
        "bars": 0,
        "years": 4.8,
        "source": "recorded",
        "amplitude": 7.8,
        "cost": 4.5,
        "cost_pct": 0.0,
        "per_lot_yuan": 45.0,
        "ratio": 0.577,
        "verdict": "fail",
        "note": "1min 平均振幅 7.8 点（alpha-radar findings 记录，本机未缓存 1 分钟线）",
    })
    return rows


# ── 证伪档案：逐条来自 alpha-radar 的 docs/findings.md（数字原样搬过来） ──
ARCHIVE = [
    {
        "id": "utbot-5min",
        "strategy": "UT Bot",
        "family": "趋势跟随",
        "source": "TradingView @QuantNomad",
        "symbol": "P.DCE",
        "freq": "5min",
        "verdict": "reject",
        "headline": "千笔样本里唯一 PF > 1，但利润全在 2022 一年",
        "metrics": {"trades": 1060, "win": 0.427, "pf": 1.05, "avg_points": 1.06,
                    "max_dd_pct": -0.185, "pnl_dd": 0.45, "positive_years": 2,
                    "years": 5},
        "few": "1060 笔 / 胜率 42.7% / PF 1.05 / 每手 +1.06 点",
        "yearly": [["2022", 23554], ["2023", 5915], ["2024", -2666],
                   ["2025", -3885], ["2026", -11691]],
        "mechanism": "全部利润来自 2022 年（印尼出口禁令年）。最近三年连亏，"
                     "收益回撤比 0.45。它证明了 5 分钟尺度上「宽跟踪止损 + 趋势"
                     "跟随」这个结构本身有微弱优势，值得继续挖 —— 但这条参数"
                     "不能实盘。",
        "command": "alpharadar run --symbol P.DCE --strategy utbot --freq 5min --start 20220101",
    },
    {
        "id": "utbot-regime",
        "strategy": "UT Bot + ER 体制闸门",
        "family": "趋势跟随 + 体制过滤",
        "source": "TradingView @QuantNomad + 原创闸门",
        "symbol": "P.DCE",
        "freq": "5min",
        "verdict": "pending",
        "headline": "目前最好的一档：PF 1.578、正年数 4/5，但只剩 55 笔",
        "metrics": {"trades": 55, "win": 0.0, "pf": 1.578, "avg_points": 13.75,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 4,
                    "years": 5},
        "few": "55 笔 / PF 1.578 / 每手 +13.75 点 / 正年数 4/5",
        "yearly": [],
        "mechanism": "加一个 ER（效率系数）闸门把体制不对的时段整段跳过，PF 从 "
                     "1.043 抬到 1.578、正年数从 2/5 抬到 4/5 —— 比两轮入场调优"
                     "加起来都有效。代价是样本只剩 55 笔（约 12 笔/年），统计上"
                     "太薄。下一步是跨品种验证体制闸门，不是继续调阈值。",
        "command": "alpharadar run --symbol P.DCE --strategy utbot --freq 5min "
                   "--start 20220101 --set use_regime=1 --set er_min=0.25 "
                   "--set atr_ratio_min=0",
    },
    {
        "id": "orb-5min",
        "strategy": "开盘区间突破 ORB",
        "family": "日内突破",
        "source": "TradingView @LuxAlgo（CC BY-NC-SA 4.0）",
        "symbol": "P.DCE",
        "freq": "5min",
        "verdict": "reject",
        "headline": "全场最高胜率 49.3%，依然是负期望",
        "metrics": {"trades": 1223, "win": 0.493, "pf": 0.889, "avg_points": 0.0,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 0,
                    "years": 5},
        "few": "1223 笔 / 胜率 49.3% / PF 0.889 / 0/5 年为正",
        "yearly": [],
        "mechanism": "赔率结构不成立：突破后回撤到对侧止损太常见，而赢的行程"
                     "常在一倍区间高度之前就衰竭。**高胜率掩盖不了负期望** —— "
                     "这条是胜率和赚钱无关的最干净证据。",
        "command": "alpharadar run --symbol P.DCE --strategy orb --freq 5min --start 20220101",
    },
    {
        "id": "false-breakout-1min",
        "strategy": "假突破反向",
        "family": "反转",
        "source": "TradingView @Zeiierman（CC BY-NC-SA 4.0）",
        "symbol": "P.DCE",
        "freq": "1min",
        "verdict": "reject",
        "headline": "1931 笔、0/5 年为正：突破确实偏假，但假完是延续不是回头",
        "metrics": {"trades": 1931, "win": 0.0, "pf": 0.692, "avg_points": -4.31,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 0,
                    "years": 5},
        "few": "1min 1931 笔 / PF 0.692 / 每手 −4.31 点；5min 462 笔 / PF 0.849",
        "yearly": [],
        "mechanism": "信号在价格已经收回之后才触发，等于在反方向的「最大不利"
                     "偏移」处入场。棕榈油的突破确实偏假，但假完之后沿原方向"
                     "延续，不是回头。",
        "command": "alpharadar run --symbol P.DCE --strategy false_breakout --freq 1min --start 20220101",
    },
    {
        "id": "vreversal-1min",
        "strategy": "冰点反转（原创）",
        "family": "反转",
        "source": "原创（形态来自沪银 1 分钟图）",
        "symbol": "P.DCE",
        "freq": "1min",
        "verdict": "reject",
        "headline": "形态边际比成本小一个数量级，1 分钟尺度没有边际",
        "metrics": {"trades": 1718, "win": 0.0, "pf": 0.746, "avg_points": -3.72,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 0,
                    "years": 5},
        "few": "1min 1718 笔 / PF 0.746 / 每手 −3.72 点",
        "yearly": [],
        "mechanism": "事件研究：冰点事件前向收益最大 +0.30 点（5 根），突破入场 "
                     "−1.02 点，而往返成本 4.5 点 —— 形态的边际比成本小一个"
                     "数量级。回踩再入能把盈亏比从 0.81 修到 1.29，但胜率跌破"
                     "平衡线，PF 反而降。**盈亏比倒挂是症状，病根是这个形态在 "
                     "1 分钟尺度没有边际。**",
        "command": "alpharadar run --symbol P.DCE --strategy vreversal --freq 1min --start 20220101",
    },
    {
        "id": "atr-sweep",
        "strategy": "ATR 止损倍数敏感性",
        "family": "参数稳健性检验",
        "source": "参数扫描（3 变体 × 3 周期 × 5 倍数 = 45 组）",
        "symbol": "P.DCE",
        "freq": "5min",
        "verdict": "finding",
        "headline": "宽止损 > 紧止损，单调改善，没有例外",
        "metrics": {"trades": 45, "win": 0.0, "pf": 0.0, "avg_points": 0.0,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 0,
                    "years": 0},
        "few": "45 组参数：倍数 1.0/1.5 一律惨败（PF 0.55~0.88），2.0 勉强，3.0 顶点",
        "yearly": [],
        "mechanism": "紧止损是成本绞肉机：止损越紧，被噪声打掉的次数越多，"
                     "而每次被打掉都要付一遍往返成本。这条结论在参数邻域上是"
                     "单调的，所以它才可信 —— 孤点最优才是过拟合的信号。",
        "command": "alpharadar matrix --symbols P.DCE --strategies utbot "
                   "--freqs 5min --set stop_atr=1.0,1.5,2.0,3.0",
    },
    {
        "id": "partial-tp",
        "strategy": "分批止盈",
        "family": "离场结构",
        "source": "参数对照",
        "symbol": "P.DCE",
        "freq": "5min",
        "verdict": "finding",
        "headline": "负贡献：PF 0.905 → 0.852",
        "metrics": {"trades": 0, "win": 0.0, "pf": 0.852, "avg_points": 0.0,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 0,
                    "years": 0},
        "few": "TP1/TP2/TP3 各平 1/3（1/2/3 ×ATR）：PF 0.905 → 0.852",
        "yearly": [],
        "mechanism": "盈利单被提前砍掉，亏损单照吃满止损。分批只在「少数单子"
                     "能走很远」的分布下才划算，本形态不具备。",
        "command": "alpharadar run --symbol P.DCE --strategy utbot --freq 5min "
                   "--set partial_tps=1,2,3",
    },
    {
        "id": "breakeven-stop",
        "strategy": "保本止损",
        "family": "离场结构",
        "source": "参数对照",
        "symbol": "P.DCE",
        "freq": "5min",
        "verdict": "finding",
        "headline": "重灾：胜率 47.8% → 31.2%，PF 0.75 → 0.65",
        "metrics": {"trades": 0, "win": 0.312, "pf": 0.65, "avg_points": 0.0,
                    "max_dd_pct": 0.0, "pnl_dd": 0.0, "positive_years": 0,
                    "years": 0},
        "few": "浮盈 8 点推平：胜率 47.8% → 31.2%，PF 0.75 → 0.65",
        "yearly": [],
        "mechanism": "推平止损把还没走出来的单子提前判死。与工程内 5 分钟 BOLL "
                     "策略的历史记录完全一致（当时胜率掉到 1%）—— 同一个坑踩两次，"
                     "所以它进了「已知无效」清单。",
        "command": "alpharadar run --symbol P.DCE --strategy utbot --freq 5min "
                   "--set breakeven_points=8",
    },
]

GATES = [
    {
        "id": "scale",
        "name": "尺度闸门",
        "rule": "往返成本 ÷ 该周期平均振幅 < 25%",
        "why": "成本是第一道闸门。棕榈油 1 分钟占比 58%，五个策略家族全负 —— "
               "在成本吃掉一半以上振幅的尺度上，再好的信号也是给交易所打工。",
        "verdict": "先卡这一条，能省掉后面所有工作。",
    },
    {
        "id": "sample",
        "name": "样本闸门",
        "rule": "≥ 200 笔，且跨越 ≥ 3 年",
        "why": "少于 30 笔的「高 PF」是噪声；55 笔那一档再漂亮也不敢实盘。",
        "verdict": "样本不够就只写「方向对、样本不足」，不许当结论用。",
    },
    {
        "id": "yearly",
        "name": "分年闸门",
        "rule": "正年数 ≥ 4/5，或最近三年不亏",
        "why": "只报总收益的策略一律不算数：本工程的「有效」几乎全部来自单一"
               "年份（2022 印尼出口禁令年）。",
        "verdict": "利润集中在一年 = 那不是策略，是那年的事件。",
    },
    {
        "id": "drawdown",
        "name": "收益回撤比",
        "rule": "总盈亏 ÷ 最大回撤 ≥ 1.0",
        "why": "决定这套参数值不值得占用资金。千笔样本那一档只有 0.45。",
        "verdict": "PF 好看但回撤吃掉全部利润，等于白做。",
    },
    {
        "id": "robust",
        "name": "参数稳健性",
        "rule": "最优参数的邻域不能塌方（单调或平台，不能是孤点）",
        "why": "搜索越广，样本内最优值的乐观偏差越大。孤点最优就是过拟合。",
        "verdict": "参数一旦被用来挑结果，它就是样本内参数。",
    },
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--alpha-radar", default="D:/GitHub/alpha-radar")
    ap.add_argument("--out", default="assets/strategy/falsification.json")
    args = ap.parse_args()

    repo = pathlib.Path(args.alpha_radar)
    cache = repo / "data_cache"
    if not cache.exists():
        print(f"[err] 找不到 alpha-radar 行情缓存：{cache}", file=sys.stderr)
        return 1

    universe = load_instruments(repo)
    scales = build_cost_scales(cache, universe)

    rejected = sum(1 for a in ARCHIVE if a["verdict"] == "reject")
    pending = sum(1 for a in ARCHIVE if a["verdict"] == "pending")
    payload = {
        "generated_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "source": {
            "project": "alpha-radar · 策略雷达",
            "what": "持续从 TradingView 采集开源策略，在 A 股 / 期货上做"
                    "含成本回测，把「什么不行、为什么不行」沉淀成可复现记录。",
            "not": "它不是策略生成器，是策略证伪器。量化研究里 90% 的工作量在"
                   "否定，而不是在发现。",
            "data": "本机 alpha-radar 仓库的 data_cache（Tushare 主力连续 5 分钟"
                    "线 / 日线、A 股日线）；15/30/60 分钟由 5 分钟重采样。",
            "cost_model": "期货：每边 1 跳滑点 + 单边手续费折点；A 股：佣金 "
                          "2.5bp 双边 + 卖出印花税 5bp + 每边 1 跳滑点。",
        },
        "gates": GATES,
        "cost_scales": scales,
        "archive": ARCHIVE,
        "summary": {
            "archive_total": len(ARCHIVE),
            "archive_rejected": rejected,
            "archive_pending": pending,
            "tradable": 0,
            "scale_rows": len(scales),
            "scale_fail": sum(1 for r in scales if r["verdict"] == "fail"),
            "scale_pass": sum(1 for r in scales if r["verdict"] == "pass"),
        },
    }

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                   encoding="utf-8")

    print(f"[ok] {out}  ({out.stat().st_size / 1024:.1f} KB)")
    print("尺度闸门（往返成本 / 平均振幅）：")
    for r in scales:
        print(f"  {r['name']:<10} {r['freq']:>6}  "
              f"振幅 {r['amplitude']:>9,.2f}  成本 {r['cost']:>7,.2f}  "
              f"占比 {r['ratio'] * 100:>6.1f}%  {r['verdict']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
