"""用 alpha-radar 的证伪导出生成 App 内置档案和后端 seed。

数据契约以 alpha-radar 的 docs/falsification-export.md 为准（schema_version 1）：
条目字段、闸门 status/value/threshold、summary 计数都原样保留。这里只做两件事：

  1. 补上 App「方法」页要用、但导出里没有的顶层字段：
     - source（成本口径 / 数据说明）、cost_scales（成本尺），取自当前内置档案；
     - gates[].verdict（闸门的一句话判词，弹层里展示）。
  2. 补兼容字段，让旧客户端 / 旧解析也能读：
     - summary.archive_rejected / archive_pending / archive_insufficient / findings /
       scale_rows / scale_pass / scale_fail；
     - 条目 rerun_pending（= flags 含 rerun_pending）。

同一份输出写到：
  - assets/strategy/falsification.json（App 离线兜底）
  - backend/internal/falsification/seed.json（后端接口兜底，go:embed）

用法：
  # 在 alpha-radar 工程里
  alpharadar falsify-export --out falsify_export.json --include-insufficient
  # 在本工程里
  python tools/strategy-mvp/build_falsification_seed.py path/to/falsify_export.json
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ASSET = ROOT / "assets/strategy/falsification.json"
SEED = ROOT / "backend/internal/falsification/seed.json"


def scale_verdict(ratio):
    return "pass" if ratio < 0.25 else ("marginal" if ratio < 0.40 else "fail")


def main(export_path):
    export = json.loads(pathlib.Path(export_path).read_text(encoding="utf-8"))
    current = json.loads(ASSET.read_text(encoding="utf-8"))

    out = dict(export)
    out["source"] = current.get("source", {})
    scales = current.get("cost_scales", [])
    for r in scales:
        r["verdict"] = scale_verdict(r.get("ratio") or 0)
    out["cost_scales"] = scales

    old_gates = {g["id"]: g for g in current.get("gates", [])}
    out["gates"] = [
        {**g, "verdict": g.get("verdict") or old_gates.get(g["id"], {}).get("verdict", "")}
        for g in export["gates"]
    ]

    arch = out["archive"]
    for e in arch:
        e["rerun_pending"] = "rerun_pending" in (e.get("flags") or [])

    s = dict(out["summary"])
    bv = s.get("by_verdict", {})
    s.update(
        archive_rejected=bv.get("reject", 0),
        archive_pending=bv.get("pending", 0),
        archive_insufficient=bv.get("insufficient", 0),
        findings=bv.get("finding", 0),
        scale_rows=len(scales),
        scale_pass=sum(1 for r in scales if r["verdict"] == "pass"),
        scale_fail=sum(1 for r in scales if r["verdict"] == "fail"),
    )
    out["summary"] = s

    text = json.dumps(out, ensure_ascii=False, indent=2) + "\n"
    ASSET.write_text(text, encoding="utf-8")
    SEED.write_text(text, encoding="utf-8")
    print("archive", len(arch), "threshold", out.get("threshold_version"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
