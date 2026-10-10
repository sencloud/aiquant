"""查一下这次 push 触发的 Actions 跑得怎么样（公开仓库不需要 token）。"""

import requests

API = "https://api.github.com/repos/sencloud/aiquant/actions/runs"


def main() -> int:
    r = requests.get(API, params={"per_page": 4}, timeout=20,
                     headers={"User-Agent": "xiai-ci-check"})
    print("http", r.status_code)
    if r.status_code != 200:
        print(r.text[:300])
        return 1
    for w in r.json().get("workflow_runs", [])[:4]:
        print(f"{w['name'][:26]:<26} {w['status']:<12} "
              f"{str(w['conclusion']):<10} {w['head_sha'][:7]}  {w['html_url']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
