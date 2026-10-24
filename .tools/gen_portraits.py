"""用阿里云百炼（DashScope）生广场居民的写真头像。

key 从 %TEMP%\\dashscope.key 读（不入库、不打进 App）。产物落在
assets/portraits/<id>.jpg，固定 768x1024，给广场卡片 / 资料页 / 朋友圈用。

用法：
    python .tools/gen_portraits.py            # 只补缺的
    python .tools/gen_portraits.py --force    # 全部重生成
    python .tools/gen_portraits.py --model wanx2.1-t2i-plus
"""

from __future__ import annotations

import io
import os
import pathlib
import sys
import time

import requests
from PIL import Image

BASE = "https://dashscope.aliyuncs.com/api/v1"
OUT = pathlib.Path("assets/portraits")
OUT_MOMENTS = pathlib.Path("assets/moments")

STYLE = (
    "photorealistic editorial portrait photograph, 35mm film look, "
    "soft natural window light, muted cinematic color grade, real skin texture, "
    "adult Chinese person in their late twenties, calm confident expression, "
    "looking at the camera, tasteful casual clothing, shallow depth of field, "
    "no text, no watermark, no logo, vertical portrait framing"
)

PEOPLE = {
    "xiai": "anime illustration, 2D cel-shaded, adult Chinese woman, long soft dark "
    "hair, warm knowing eyes, slight smile, cream knit sweater, sitting by a window "
    "at dawn, soft golden light, clean lineart, cozy intimate mood, no text",
    "xiai_qinghe": "anime illustration, 2D cel-shaded, adult Chinese woman, short "
    "black bob, cool calm eyes, white shirt, rainy window at dusk, cool blue light, "
    "clean lineart, quiet composed mood, no text",
    "xiai_lulu": "anime illustration, 2D cel-shaded, adult Chinese woman, long wavy "
    "brown hair, bright playful smile, soft pink cardigan, warm afternoon sunlight, "
    "cheerful mood, clean lineart, no text",
    "xiai_atang": "anime illustration, 2D cel-shaded, adult Chinese woman, "
    "shoulder-length black hair, elegant confident look, black blazer, city night "
    "lights, warm amber rim light, composed expression, clean lineart, no text",
    "xiai_xiaoman": "anime illustration, 2D cel-shaded, adult Chinese woman, low "
    "ponytail, gentle eyes, beige linen, quiet warm library corner, soft window "
    "light, peaceful mood, clean lineart, no text",
    "moment_xiai": "anime illustration, 2D cel-shaded, a cozy room at dawn, warm "
    "lamp, a cup of coffee on a wooden table, lace curtain, soft golden light, "
    "no people, clean lineart, no text",
    "moment_qinghe": "anime illustration, 2D cel-shaded, rain on a window at night, "
    "city lights blurred outside, a book and a mug on the sill, blue cool tones, "
    "no people, clean lineart, no text",
    "moment_lulu": "anime illustration, 2D cel-shaded, a small livehouse stage with "
    "pink and purple lights, a microphone, empty room, joyful mood, no people, "
    "clean lineart, no text",
    "moment_atang": "anime illustration, 2D cel-shaded, a city rooftop at night, "
    "warm string lights, skyline glow, confident mood, no people, clean lineart, "
    "no text",
    "moment_xiaoman": "anime illustration, 2D cel-shaded, a quiet mountain trail "
    "in soft morning mist, pine trees, a wooden signpost, peaceful mood, no people, "
    "clean lineart, no text",
    "room": "anime illustration, 2D cel-shaded, a cozy small living room at dusk, "
    "warm floor lamp, big window with soft city lights, low sofa, bookshelf, "
    "plants, a cup on the table, empty room, no people, clean lineart, no text",
    "linxia": "a 27-year-old Chinese woman photographer with long dark hair, "
    "wearing a beige knit sweater, standing by a rain-streaked window at dusk, "
    "warm terracotta light, a film camera on a strap over her shoulder",
    "suyu": "a 29-year-old Chinese woman brand strategist with a chin-length dark bob, "
    "wearing a black turtleneck, standing outside a convenience store at night, "
    "cool blue light, faint knowing smile",
    "anke": "a 24-year-old Chinese woman independent musician with voluminous curly "
    "brown hair, headphones around her neck, backstage of a small livehouse, "
    "magenta and purple stage light",
    "zhoumu": "a 30-year-old Chinese man product manager with short black hair, "
    "wearing a plain unbranded dark green running jacket, no logos, no text on "
    "clothing, after a night run on a city street, soft streetlights behind him",
    "chenye": "a 28-year-old Chinese man documentary filmmaker with a buzz cut, "
    "wearing a grey wool coat, standing on an empty subway platform, "
    "quiet gaze, cool fluorescent light",
    "luyao": "a 31-year-old Chinese man architect with wavy hair, wearing a linen "
    "shirt and a work apron in a wooden workshop, warm afternoon light, "
    "relaxed half-smile",
}

SCENE_STYLE = (
    "photorealistic cinematic film still, 35mm, shallow depth of field, "
    "muted color grade, no people, no text, no watermark, no logo"
)

SCENES = {
    "linxia-1": "a rainy city street at night in Hangzhou, wet asphalt reflecting "
    "warm streetlights, empty street, quiet mood",
    "suyu-1": "the front of a late-night Chinese convenience store, glowing glass "
    "windows, empty sidewalk, cool blue night",
    "anke-1": "a small livehouse stage at night, magenta and purple stage lights, "
    "a microphone stand, empty room",
    "zhoumu-1": "half a watermelon on a kitchen counter at night, warm lamp light, "
    "minimal still life",
    "chenye-1": "an empty subway car interior at night in Beijing, cool fluorescent "
    "light, long carriage",
    "luyao-1": "a wooden workbench in an architect's workshop, hand tools and timber, "
    "warm afternoon light",
}


def key() -> str:
    env = os.environ.get("DASHSCOPE_API_KEY")
    if env:
        return env.strip()
    p = pathlib.Path(os.environ.get("TEMP", ".")) / "dashscope.key"
    return p.read_text(encoding="utf-8").strip()


def submit(session: requests.Session, token: str, model: str, prompt: str) -> str:
    for attempt in range(8):
        r = session.post(
            f"{BASE}/services/aigc/text2image/image-synthesis",
            headers={
                "Authorization": f"Bearer {token}",
                "X-DashScope-Async": "enable",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "input": {"prompt": prompt},
                "parameters": {"size": "768*1024", "n": 1, "prompt_extend": True},
            },
            timeout=30,
        )
        data = r.json()
        if r.status_code == 429:
            wait_s = 12 + attempt * 8
            print(f"429 throttled, retry in {wait_s}s", flush=True)
            time.sleep(wait_s)
            continue
        if r.status_code != 200 or "output" not in data:
            raise RuntimeError(f"{r.status_code}: {str(data)[:300]}")
        return data["output"]["task_id"]
    raise RuntimeError("still throttled after retries")


def wait(session: requests.Session, token: str, task: str) -> str:
    for _ in range(120):
        r = session.get(
            f"{BASE}/tasks/{task}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=30,
        )
        out = r.json().get("output", {})
        status = out.get("task_status")
        if status == "SUCCEEDED":
            return out["results"][0]["url"]
        if status in {"FAILED", "CANCELED", "UNKNOWN"}:
            raise RuntimeError(f"task {status}: {str(out)[:300]}")
        time.sleep(4)
    raise RuntimeError("timeout")


def save(url: str, path: pathlib.Path, aspect: float = 3 / 4) -> None:
    raw = requests.get(url, timeout=60).content
    im = Image.open(io.BytesIO(raw)).convert("RGB")
    # 居中裁成 3:4，再缩到 768x1024
    w, h = im.size
    target = aspect
    if w / h > target:
        nw = int(h * target)
        im = im.crop(((w - nw) // 2, 0, (w + nw) // 2, h))
    else:
        nh = int(w / target)
        im = im.crop((0, 0, w, nh))
    if aspect > 1:
        im = im.resize((1024, int(1024 / aspect)), Image.LANCZOS)
    else:
        im = im.resize((768, 1024), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "JPEG", quality=86, optimize=True)


def main() -> int:
    force = "--force" in sys.argv
    scenes = "--scenes" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
    model = "wanx2.1-t2i-turbo"
    if "--model" in sys.argv:
        model = sys.argv[sys.argv.index("--model") + 1]

    token = key()
    source = SCENES if scenes else PEOPLE
    out_dir = OUT_MOMENTS if scenes else OUT
    todo = {
        k: v
        for k, v in source.items()
        if (only is None or k == only)
        and (force or not (out_dir / f"{k}.jpg").exists())
    }
    if not todo:
        print("nothing to do")
        return 0

    # 逐个来：账号的并发额度很小，一把提交会被 429 打断。
    with requests.Session() as s:
        for rid, desc in todo.items():
            prompt = (
                f"{SCENE_STYLE}. Scene: {desc}."
                if scenes
                else f"{STYLE}. Subject: {desc}."
            )
            task = submit(s, token, model, prompt)
            print(f"submitted {rid} -> {task}", flush=True)
            url = wait(s, token, task)
            save(url, out_dir / f"{rid}.jpg", aspect=16 / 10 if scenes else 3 / 4)
            print(f"saved {out_dir / (rid + '.jpg')}", flush=True)
            time.sleep(3)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
