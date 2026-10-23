"""重新生成《天亮以前》的中文字体子集。

用法：
    python tools/gen_story_font.py
    # 或指定 Noto Sans SC 源文件
    STORY_FONT_SRC=/path/to/NotoSansSC-VF.ttf python tools/gen_story_font.py

为什么需要它：Flutter Web 的系统字体回退会漏掉少量汉字（例如「煮」「遥」「炖」），
而试用版的文案是固定的。把 Noto Sans SC 裁成只含现有文案的子集，体积约 400KB，
三端渲染一致；改文案后重跑一次即可。

依赖：fonttools（pip install fonttools）
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
STORY_DIR = ROOT / "lib" / "story"
OUT = ROOT / "assets" / "fonts" / "NightSans-subset.ttf"
CHARS = ROOT / ".tools" / "story_font_chars.txt"

DEFAULT_SOURCES = [
    pathlib.Path(r"C:\Windows\Fonts\NotoSansSC-VF.ttf"),
    pathlib.Path("/System/Library/Fonts/NotoSansSC-Regular.otf"),
    pathlib.Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
]


def main() -> int:
    raw = os.environ.get("STORY_FONT_SRC", "").strip()
    source = pathlib.Path(raw).expanduser() if raw else next(
        (p for p in DEFAULT_SOURCES if p.exists()), None
    )
    if source is None or not source.is_file():
        print("找不到 Noto Sans SC 源文件；设置 STORY_FONT_SRC 指向 ttf/otf/ttc。", file=sys.stderr)
        return 1

    chars = set(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    chars.update("，。！？、；：“”‘’（）《》…—·「」『』【】")
    for path in STORY_DIR.rglob("*.dart"):
        chars.update(path.read_text(encoding="utf-8"))
    chars = {c for c in chars if c.isprintable() and c not in "\n\r"}
    CHARS.parent.mkdir(parents=True, exist_ok=True)
    CHARS.write_text("".join(sorted(chars)), encoding="utf-8")

    OUT.parent.mkdir(parents=True, exist_ok=True)

    # Noto Sans SC 的 VF 默认 wght=100；先钉到 400，避免 Flutter 把正文画粗。
    from fontTools.ttLib import TTFont

    if "fvar" in TTFont(source):
        instance = ROOT / ".tools" / "NightSans-400.ttf"
        subprocess.run(
            [
                sys.executable,
                "-m",
                "fontTools.varLib.instancer",
                str(source),
                "wght=400",
                f"--output={instance}",
            ],
            check=True,
        )
        source = instance

    cmd = [
        sys.executable,
        "-m",
        "fontTools.subset",
        str(source),
        f"--text-file={CHARS}",
        f"--output-file={OUT}",
        "--layout-features=*",
        "--no-hinting",
        "--desubroutinize",
    ]
    print(" ".join(cmd))
    subprocess.run(cmd, check=True)

    # 内部 family 也改成 NightSans：不要用「Noto Sans SC」这个系统名，
    # 否则测试环境的 fallback 可能先命中这个子集，漏掉子集外的字。
    from fontTools.ttLib import TTFont

    font = TTFont(OUT)
    for rec in font["name"].names:
        try:
            value = rec.toUnicode()
        except Exception:
            continue
        value = value.replace("Noto Sans SC", "NightSans").replace(
            "NotoSansSC-Thin", "NightSans-Regular"
        )
        rec.string = value
    font.save(OUT)

    print(f"[ok] {OUT} ({OUT.stat().st_size / 1024:.0f} KB, {len(chars)} chars)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
