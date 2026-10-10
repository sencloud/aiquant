"""把 assets/strategy/falsification.json 升级到 v2 schema（MVP 付费闭环）。

v2 在原有字段上只做加法（客户端对旧 schema 仍然兼容）：
  - 顶层：threshold_version；gates 按新判定顺序（样本 → 尺度 → 分年 → 收益回撤比 → 稳健性）
    并写入机器可判定的阈值；summary 增加 archive_insufficient / findings。
  - 每条档案：failed_gate、gates{id:{status,value,threshold}}、updated_at、asset_class、
    license、curated、threshold_version、rerun_pending。

这 8 条是手写的精选档案（curated=true），结论来自 alpha-radar docs/findings.md；
ORB、假突破反向的原始实现是 CC BY-NC-SA，按决策做 clean-room 重写后重判，
在重判完成前标 rerun_pending=true。

同一份输出同时写到：
  - assets/strategy/falsification.json（App 离线兜底）
  - backend/internal/falsification/seed.json（后端接口兜底，go:embed）

用法：python tools/strategy-mvp/upgrade_falsification_v2.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
ASSET = ROOT / "assets/strategy/falsification.json"
SEED = ROOT / "backend/internal/falsification/seed.json"
VERSION = "manual-2026-10"

GATES = [
    ("sample", "样本闸门", "≥ 200 笔，且跨越 ≥ 3 年；不足记「样本不足」，不算淘汰",
     None),
    ("scale", "尺度闸门", "往返成本 ÷ 该周期平均振幅：< 25% 通过，25%–40% 勉强，≥ 40% 淘汰",
     None),
    ("yearly", "分年闸门", "正年数 ÷ 年数 ≥ 0.8，或最近三个完整年度都不为负", None),
    ("drawdown", "收益回撤比", "总盈亏 ÷ |最大回撤| ≥ 1.0，且总盈亏 > 0", None),
    ("robust", "参数稳健性", "最优参数的邻域不能塌方（单调或平台，不能是孤点）；MVP 阶段人工复核，记「待复核」",
     None),
]

# 手写档案的人工判定（与 findings.md 一致）。
MANUAL = {
    "utbot-5min": dict(verdict="reject", failed_gate="yearly"),
    "utbot-regime": dict(verdict="insufficient", failed_gate="sample"),
    "orb-5min": dict(verdict="reject", failed_gate="yearly", rerun_pending=True,
                     source="原创实现（clean-room 重写中）· 思路来源：开盘区间突破（ORB）",
                     license="原创实现"),
    "false-breakout-1min": dict(verdict="reject", failed_gate="scale", rerun_pending=True,
                                source="原创实现（clean-room 重写中）· 思路来源：假突破反向",
                                license="原创实现"),
    "vreversal-1min": dict(verdict="reject", failed_gate="scale"),
    "atr-sweep": dict(verdict="finding", failed_gate=""),
    "partial-tp": dict(verdict="finding", failed_gate=""),
    "breakeven-stop": dict(verdict="finding", failed_gate=""),
}


def scale_ratio(data, symbol, freq):
    for r in data.get("cost_scales", []):
        if r.get("symbol") == symbol and r.get("freq") == freq:
            return r.get("ratio")
    return None


def gate_results(data, e):
    m = e.get("metrics", {})
    trades, years, pos = m.get("trades", 0), m.get("years", 0), m.get("positive_years", 0)
    if e.get("verdict") == "finding" or e["id"] in ("atr-sweep", "partial-tp", "breakeven-stop"):
        return {}
    g = {}
    ok = trades >= 200 and years >= 3
    g["sample"] = dict(status="pass" if ok else "fail",
                       value=f"{trades} 笔 / {years} 年", threshold="≥ 200 笔且 ≥ 3 年")
    ratio = scale_ratio(data, e.get("symbol"), e.get("freq"))
    if ratio is None:
        g["scale"] = dict(status="skip", value="", threshold="< 25%（25%–40% 勉强）")
    else:
        st = "pass" if ratio < 0.25 else ("marginal" if ratio < 0.40 else "fail")
        g["scale"] = dict(status=st, value=f"{ratio * 100:.1f}%", threshold="< 25%（25%–40% 勉强）")
    if years:
        st = "pass" if pos / years >= 0.8 else "fail"
        g["yearly"] = dict(status=st, value=f"{pos}/{years}", threshold="≥ 0.8 或近三年不亏")
    pnl_dd = m.get("pnl_dd", 0)
    g["drawdown"] = dict(status=("pass" if pnl_dd >= 1 else "fail") if pnl_dd else "skip",
                         value=f"{pnl_dd:.2f}" if pnl_dd else "", threshold="≥ 1.0 且盈利")
    g["robust"] = dict(status="pending", value="", threshold="人工复核")
    # 第一道失败之后的闸门不再判定。
    seen_fail = False
    for gid in ["sample", "scale", "yearly", "drawdown", "robust"]:
        if gid not in g:
            continue
        if seen_fail:
            g[gid]["status"] = "skip"
        elif g[gid]["status"] == "fail":
            seen_fail = True
    return g


def main():
    data = json.loads(ASSET.read_text(encoding="utf-8"))
    old_gates = {g["id"]: g for g in data.get("gates", [])}
    data["threshold_version"] = VERSION
    data["gates"] = [
        dict(id=gid, name=name, rule=rule,
             why=old_gates.get(gid, {}).get("why", ""),
             verdict=old_gates.get(gid, {}).get("verdict", ""))
        for gid, name, rule, _ in GATES
    ]
    for r in data.get("cost_scales", []):
        ratio = r.get("ratio", 0)
        r["verdict"] = "pass" if ratio < 0.25 else ("marginal" if ratio < 0.40 else "fail")
    updated = data.get("generated_at", "")
    for e in data["archive"]:
        man = MANUAL.get(e["id"], {})
        e.update({k: v for k, v in man.items()})
        e.setdefault("license", "")
        e["curated"] = True
        e["asset_class"] = "futures"
        e["threshold_version"] = VERSION
        e["updated_at"] = updated
        e.setdefault("rerun_pending", False)
        e["gates"] = gate_results(data, e)
    arch = data["archive"]
    cnt = lambda v: sum(1 for e in arch if e["verdict"] == v)
    data["summary"].update(
        archive_total=len(arch),
        archive_rejected=cnt("reject"),
        archive_pending=cnt("pending"),
        archive_insufficient=cnt("insufficient"),
        findings=cnt("finding"),
        tradable=cnt("tradable"),
        scale_fail=sum(1 for r in data.get("cost_scales", []) if r["verdict"] == "fail"),
        scale_pass=sum(1 for r in data.get("cost_scales", []) if r["verdict"] == "pass"),
    )
    out = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    ASSET.write_text(out, encoding="utf-8")
    SEED.write_text(out, encoding="utf-8")
    print("archive", len(arch), "summary", data["summary"])


if __name__ == "__main__":
    main()
