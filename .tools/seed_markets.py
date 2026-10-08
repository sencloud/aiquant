#!/usr/bin/env python3
# 生成鹦鹉螺首发全球盘口的远程建市场脚本(_seed_remote.sh)。
# 金融类走 auto 自动结算(resolve_rule 取实时行情)，天气类 manual 人工结算。
# 运行：python .tools/seed_markets.py  → 产出 .tools/_seed_remote.sh
import json
import os
from datetime import datetime, timedelta, timezone

CST = timezone(timedelta(hours=8))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADMIN_KEY = "Ort5cwvZReXf1QuEoIG0m6Pz2xFLSMC8"
BASE = "http://127.0.0.1:8080"


def ms(dt):
    return int(dt.timestamp() * 1000)


# 各市场对应收盘/判定时点(均为北京时间)。美股 16:00 EDT = 次日 04:00 CST。
AS_C = ms(datetime(2026, 6, 12, 14, 55, tzinfo=CST))   # A股收盘
AS_R = ms(datetime(2026, 6, 12, 15, 10, tzinfo=CST))
HK_C = ms(datetime(2026, 6, 12, 15, 0, tzinfo=CST))    # 港股收盘
HK_R = ms(datetime(2026, 6, 12, 15, 30, tzinfo=CST))
JP_C = ms(datetime(2026, 6, 12, 13, 50, tzinfo=CST))   # 日股收盘
JP_R = ms(datetime(2026, 6, 12, 14, 15, tzinfo=CST))
US_C = ms(datetime(2026, 6, 13, 3, 55, tzinfo=CST))    # 美股周五收盘
US_R = ms(datetime(2026, 6, 13, 4, 15, tzinfo=CST))
FX_C = ms(datetime(2026, 6, 12, 21, 50, tzinfo=CST))   # 外汇欧美盘时点
FX_R = ms(datetime(2026, 6, 12, 22, 10, tzinfo=CST))
WX_C = ms(datetime(2026, 6, 14, 23, 59, tzinfo=CST))   # 天气次日揭晓
WX_R = ms(datetime(2026, 6, 15, 22, 0, tzinfo=CST))


def fin(title, desc, close_at, resolve_at, source, symbol, op, value,
        yes_label, no_label):
    return {
        "category": "finance",
        "title": title,
        "description": desc,
        "close_at": close_at,
        "resolve_at": resolve_at,
        "resolve_kind": "auto",
        "resolve_rule": json.dumps({
            "source": source, "symbol": symbol, "op": op,
            "value": value, "yes_idx": 0, "no_idx": 1,
        }, ensure_ascii=False),
        "rake_bps": 0,
        "options": [yes_label, no_label],
    }


def wx(title, desc, yes_label, no_label):
    return {
        "category": "weather",
        "title": title,
        "description": desc,
        "close_at": WX_C,
        "resolve_at": WX_R,
        "resolve_kind": "manual",
        "resolve_rule": "",
        "rake_bps": 0,
        "options": [yes_label, no_label],
    }


markets = [
    # ── 金融市场（自动结算）──
    fin("纳斯达克100 指数本周五美股收盘能否站上 25500 点？",
        "以纳斯达克综合指数(东财实时)在北京时间 6/13 凌晨美股收盘后的点位自动结算，≥ 25500 则「能」获胜。当前约 25270。",
        US_C, US_R, "global_index", "NDX", "gte", 25500,
        "能（≥ 25500）", "不能（< 25500）"),
    fin("标普500 指数本周五收盘能否突破 7300 点？",
        "以标普500指数(东财实时)美股收盘后点位自动结算，≥ 7300 则「能」获胜。当前约 7293。",
        US_C, US_R, "global_index", "SPX", "gte", 7300,
        "能（≥ 7300）", "不能（< 7300）"),
    fin("道琼斯指数本周五收盘能否站上 50500 点？",
        "以道琼斯工业平均指数(东财实时)美股收盘后点位自动结算，≥ 50500 则「能」获胜。当前约 50132。",
        US_C, US_R, "global_index", "DJIA", "gte", 50500,
        "能（≥ 50500）", "不能（< 50500）"),
    fin("苹果(AAPL) 本周五美股收盘能否突破 295 美元？",
        "以苹果公司股价(东财实时)美股收盘后价格自动结算，≥ 295 则「能」获胜。当前约 291.8。",
        US_C, US_R, "us", "AAPL", "gte", 295,
        "能（≥ $295）", "不能（< $295）"),
    fin("英伟达(NVDA) 本周五收盘能否站上 205 美元？",
        "以英伟达股价(东财实时)美股收盘后价格自动结算，≥ 205 则「能」获胜。当前约 202.3。",
        US_C, US_R, "us", "NVDA", "gte", 205,
        "能（≥ $205）", "不能（< $205）"),
    fin("特斯拉(TSLA) 本周五收盘能否突破 390 美元？",
        "以特斯拉股价(东财实时)美股收盘后价格自动结算，≥ 390 则「能」获胜。当前约 383.3。",
        US_C, US_R, "us", "TSLA", "gte", 390,
        "能（≥ $390）", "不能（< $390）"),
    fin("微软(MSFT) 本周五收盘能否站上 400 美元？",
        "以微软股价(东财实时)美股收盘后价格自动结算，≥ 400 则「能」获胜。当前约 392.8。",
        US_C, US_R, "us", "MSFT", "gte", 400,
        "能（≥ $400）", "不能（< $400）"),
    fin("美元指数本周五能否升破 100.5？",
        "以美元指数(DXY，东财实时)在北京时间 6/12 22:10 的点位自动结算，≥ 100.5 则「能」获胜。当前约 100.1。",
        FX_C, FX_R, "global_index", "UDI", "gte", 100.5,
        "能（≥ 100.5）", "不能（< 100.5）"),
    fin("离岸人民币(USDCNH) 本周五能否升值到 6.75 以内？",
        "以美元兑离岸人民币汇率(东财实时)在北京时间 6/12 22:10 自动结算，汇率 ≤ 6.75（人民币升值）则「能」获胜。当前约 6.78。",
        FX_C, FX_R, "forex", "USDCNH", "lte", 6.75,
        "能（≤ 6.75）", "不能（> 6.75）"),
    fin("欧元美元(EURUSD) 本周五能否站上 1.16？",
        "以欧元兑美元汇率(东财实时)在北京时间 6/12 22:10 自动结算，≥ 1.16 则「能」获胜。当前约 1.153。",
        FX_C, FX_R, "forex", "EURUSD", "gte", 1.16,
        "能（≥ 1.16）", "不能（< 1.16）"),
    fin("美元日元(USDJPY) 本周五能否升破 162？",
        "以美元兑日元汇率(东财实时)在北京时间 6/12 22:10 自动结算，≥ 162 则「能」获胜。当前约 160.5。",
        FX_C, FX_R, "forex", "USDJPY", "gte", 162,
        "能（≥ 162）", "不能（< 162）"),
    fin("恒生指数本周五收盘能否站上 24500 点？",
        "以恒生指数(东财实时)在北京时间 6/12 港股收盘后点位自动结算，≥ 24500 则「能」获胜。当前约 24249。",
        HK_C, HK_R, "global_index", "HSI", "gte", 24500,
        "能（≥ 24500）", "不能（< 24500）"),
    fin("日经225 本周五收盘能否突破 64500 点？",
        "以日经225指数(东财实时)在北京时间 6/12 日股收盘后点位自动结算，≥ 64500 则「能」获胜。当前约 64217。",
        JP_C, JP_R, "global_index", "N225", "gte", 64500,
        "能（≥ 64500）", "不能（< 64500）"),
    fin("创业板指本周五收盘能否站上 3850 点？",
        "以创业板指(399006.SZ，实时行情)在北京时间 6/12 A股收盘后点位自动结算，≥ 3850 则「能」获胜。当前约 3811。",
        AS_C, AS_R, "cn", "399006.SZ", "gte", 3850,
        "能（≥ 3850）", "不能（< 3850）"),
    fin("沪深300 本周五收盘能否突破 4750 点？",
        "以沪深300指数(000300.SH，实时行情)在北京时间 6/12 A股收盘后点位自动结算，≥ 4750 则「能」获胜。当前约 4722。",
        AS_C, AS_R, "cn", "000300.SH", "gte", 4750,
        "能（≥ 4750）", "不能（< 4750）"),

    # ── 全球天气（人工结算）──
    wx("6 月 15 日东京当日最高气温会达到 30℃ 吗？",
       "以日本气象厅发布的东京 6 月 15 日当日最高气温为准，≥ 30.0℃ 则「会」获胜，由运营当晚录入结算。",
       "会（≥ 30℃）", "不会（< 30℃）"),
    wx("6 月 15 日伦敦当日最高气温会达到 25℃ 吗？",
       "以英国气象局(Met Office)发布的伦敦 6 月 15 日当日最高气温为准，≥ 25.0℃ 则「会」获胜，由运营当晚录入结算。",
       "会（≥ 25℃）", "不会（< 25℃）"),
    wx("6 月 15 日纽约当日最高气温会达到 30℃ 吗？",
       "以美国国家气象局(NWS)发布的纽约市 6 月 15 日当日最高气温为准，≥ 30.0℃ 则「会」获胜，由运营当晚录入结算。",
       "会（≥ 30℃）", "不会（< 30℃）"),
    wx("6 月 15 日迪拜当日最高气温会突破 42℃ 吗？",
       "以阿联酋国家气象中心发布的迪拜 6 月 15 日当日最高气温为准，≥ 42.0℃ 则「会」获胜，由运营当晚录入结算。",
       "会（≥ 42℃）", "不会（< 42℃）"),
    wx("6 月 15 日上海当天会下雨吗？",
       "以中国气象局发布的上海(徐家汇)6 月 15 日当日降水实况为准，出现有效降水(日降水量 ≥ 0.1mm)则「会」获胜，由运营当晚录入结算。",
       "会下雨", "不会下雨"),
    wx("6 月 15 日新加坡当天会下雨吗？",
       "以新加坡气象局(MSS)发布的 6 月 15 日当日降水实况为准，出现有效降水则「会」获胜，由运营当晚录入结算。",
       "会下雨", "不会下雨"),
    wx("6 月 15 日巴黎当日最高气温会达到 28℃ 吗？",
       "以法国气象局(Météo-France)发布的巴黎 6 月 15 日当日最高气温为准，≥ 28.0℃ 则「会」获胜，由运营当晚录入结算。",
       "会（≥ 28℃）", "不会（< 28℃）"),
]

lines = [
    "#!/usr/bin/env bash",
    "set -u",
    'KEY="%s"' % ADMIN_KEY,
    'BASE="%s"' % BASE,
    "ok=0; fail=0",
]
for m in markets:
    body = json.dumps(m, ensure_ascii=False)
    # body 内仅含双引号，外层单引号包裹绝对安全。
    lines.append(
        "resp=$(curl -fsS -X POST \"$BASE/v1/admin/nautilus/markets\" "
        "-H \"X-Admin-Key: $KEY\" -H 'Content-Type: application/json' "
        "-d '%s') && { echo \"OK  ${resp:0:70}\"; ok=$((ok+1)); } "
        "|| { echo \"FAIL %s\"; fail=$((fail+1)); }" % (body, m["title"])
    )
lines.append('echo "=== created=$ok failed=$fail ==="')
lines.append('echo "--- current markets ---"')
lines.append('curl -fsS "$BASE/v1/nautilus/markets?limit=100" '
             '| grep -o \'"title":"[^"]*"\' | wc -l')

dst = os.path.join(ROOT, ".tools", "_seed_remote.sh")
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("WROTE", dst, "markets=", len(markets))
