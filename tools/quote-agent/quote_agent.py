#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本机行情采集端（RPA 中转）——把生产服务器拿不到的行情推给喜宽后端。

为什么需要它
------------
运营服务器（阿里云）出口访问不了内盘期货实时行情：东财 push2/push2delay 在
TLS 握手后直接 EOF，新浪 hq.sinajs.cn 对数据中心 IP 返回 403，腾讯 / 雪球 /
金十都不提供内盘期货。而我们自己的机器可以直连新浪拿到**主力连续合约**的实时价
（实测螺纹/铁矿/豆粕/铜/黄金/玉米/股指/PTA/甲醇/白糖/苹果/原油 12 个品种全部可用）。

做法是标准的采集-推送：本机定时取数 → POST 给后端 `/v1/ingest/quotes`
→ 后端缓存并落库 → AI 工具优先读它。**不需要本机开放任何端口**（出站即可），
也不需要公网 IP。

用法
----
    python quote_agent.py --print          # 只取数并打印，不推送（自检用）
    python quote_agent.py --once           # 推一次就退出
    python quote_agent.py                  # 常驻，每 15 秒推一次

后端地址与密钥从环境变量读，避免写进仓库：
    QUOTE_AGENT_URL      默认 https://api.singzquant.com
    QUOTE_AGENT_KEY      必填，对应服务端 config.toml 的 ingest.key
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request

SINA = "https://hq.sinajs.cn/list="
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36",
    "Referer": "https://finance.sina.com.cn/",
}

# 新浪代码 → (Tushare 主力连续代码, 中文名)
# 用"主力连续"而不是具体月份：模型手里的具体合约会由后端自动折算到连续合约。
PRODUCTS = {
    "nf_RB0": ("RB.SHF", "螺纹钢"),
    "nf_HC0": ("HC.SHF", "热卷"),
    "nf_I0": ("I.DCE", "铁矿石"),
    "nf_J0": ("J.DCE", "焦炭"),
    "nf_JM0": ("JM.DCE", "焦煤"),
    "nf_M0": ("M.DCE", "豆粕"),
    "nf_Y0": ("Y.DCE", "豆油"),
    "nf_P0": ("P.DCE", "棕榈油"),
    "nf_C0": ("C.DCE", "玉米"),
    "nf_A0": ("A.DCE", "豆一"),
    "nf_CU0": ("CU.SHF", "沪铜"),
    "nf_AL0": ("AL.SHF", "沪铝"),
    "nf_ZN0": ("ZN.SHF", "沪锌"),
    "nf_AU0": ("AU.SHF", "沪金"),
    "nf_AG0": ("AG.SHF", "沪银"),
    "nf_TA0": ("TA.CZC", "PTA"),
    "nf_MA0": ("MA.CZC", "甲醇"),
    "nf_FG0": ("FG.CZC", "玻璃"),
    "nf_SA0": ("SA.CZC", "纯碱"),
    "nf_SR0": ("SR.CZC", "白糖"),
    "nf_CF0": ("CF.CZC", "棉花"),
    "nf_AP0": ("AP.CZC", "苹果"),
    "nf_SC0": ("SC.INE", "原油"),
    "nf_IF0": ("IF.CFX", "沪深300"),
    "nf_IH0": ("IH.CFX", "上证50"),
    "nf_IC0": ("IC.CFX", "中证500"),
    "nf_IM0": ("IM.CFX", "中证1000"),
    "nf_T0": ("T.CFX", "十债"),
    "nf_TF0": ("TF.CFX", "五债"),
}


def _num(s: str) -> float:
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0


def fetch_sina(codes: list[str]) -> str:
    req = urllib.request.Request(SINA + ",".join(codes), headers=HEADERS)
    with urllib.request.urlopen(req, timeout=12) as resp:
        return resp.read().decode("gbk", errors="replace")


def parse(text: str) -> list[dict]:
    """新浪 nf_ 字段位：0 名称 1 时间 2 开 3 高 4 低 6 买 7 卖 8 最新 10 昨结 13 持仓 14 成交。"""
    out: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("var hq_str_"):
            continue
        try:
            code = line.split("=")[0].replace("var hq_str_", "")
            body = line.split('="', 1)[1].rstrip('";')
        except IndexError:
            continue
        if not body:
            continue
        f = body.split(",")
        if len(f) < 15:
            continue
        mapped = PRODUCTS.get(code)
        if not mapped:
            continue
        ts_code, name = mapped
        last, pre = _num(f[8]), _num(f[10])
        out.append({
            "symbol": ts_code,
            "name": f[0] or name,
            "last": last,
            "change": round(last - pre, 3) if pre else 0.0,
            "pct_chg": round((last / pre - 1) * 100, 3) if pre else 0.0,
            "open": _num(f[2]),
            "high": _num(f[3]),
            "low": _num(f[4]),
            "pre_close": pre,
            "volume": _num(f[14]),
            "oi": _num(f[13]),
            "ts": int(time.time() * 1000),
        })
    return out


def push(base_url: str, key: str, quotes: list[dict]) -> str:
    body = json.dumps({"source": "local_quote_agent", "quotes": quotes}).encode()
    req = urllib.request.Request(
        base_url.rstrip("/") + "/v1/ingest/quotes",
        data=body,
        headers={"Content-Type": "application/json", "X-Ingest-Key": key},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode()


def main() -> int:
    ap = argparse.ArgumentParser(description="喜宽本机行情采集端")
    ap.add_argument("--url", default=os.environ.get("QUOTE_AGENT_URL", "https://api.singzquant.com"))
    ap.add_argument("--key", default=os.environ.get("QUOTE_AGENT_KEY", ""))
    ap.add_argument("--interval", type=float, default=15.0, help="推送间隔秒数")
    ap.add_argument("--once", action="store_true", help="推一次就退出")
    ap.add_argument("--print", dest="dry", action="store_true", help="只取数打印，不推送")
    args = ap.parse_args()

    if not args.dry and not args.key:
        print("缺少采集密钥：请设置环境变量 QUOTE_AGENT_KEY（对应服务端 ingest.key）", file=sys.stderr)
        return 2

    codes = list(PRODUCTS.keys())
    while True:
        try:
            quotes = parse(fetch_sina(codes))
            if args.dry:
                for q in quotes[:6]:
                    print(f"{q['symbol']:<10} {q['name']:<8} 最新 {q['last']:<10} "
                          f"涨跌 {q['pct_chg']:+.2f}%  持仓 {q['oi']:.0f}")
                print(f"... 共 {len(quotes)} 个品种")
            else:
                print(f"[{time.strftime('%H:%M:%S')}] 取到 {len(quotes)} 个品种 → 推送中", flush=True)
                print("   " + push(args.url, args.key, quotes), flush=True)
        except Exception as exc:  # 采集端不该因为一次失败退出
            print(f"[{time.strftime('%H:%M:%S')}] 失败：{exc}", file=sys.stderr, flush=True)
        if args.once or args.dry:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
