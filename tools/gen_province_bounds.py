#!/usr/bin/env python3
"""生成 backend/internal/fishing/data/provinces.json：简化后的省级边界，
只用于「坐标 → 省份」判断（出钓指数只提示该省所在流域的禁渔期），不用于展示地图。

数据源：阿里云 DataV.GeoAtlas 省级边界
  https://geo.datav.aliyun.com/areas_v3/bound/100000_full.json
（坐标为 GCJ-02，与 WGS-84 相差约几百米，对判断省份影响可以忽略。）

用法：python3 tools/gen_province_bounds.py [下载好的 100000_full.json]
只用标准库：Douglas-Peucker 简化（容差 0.02°≈2 km），去掉 <1 km² 的小岛，坐标保留 3 位小数。
"""
import json, sys, urllib.request

SRC = 'https://geo.datav.aliyun.com/areas_v3/bound/100000_full.json'
OUT = 'backend/internal/fishing/data/provinces.json'
TOL = 0.02
MIN_AREA = 1e-4  # 度²，约 1 km²：更小的岛礁不影响判断，丢掉


def dp(pts, tol):
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]; bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        nn = dx * dx + dy * dy
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if nn == 0:
                d = (px - ax) ** 2 + (py - ay) ** 2
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / nn))
                d = (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2
            if d > best:
                best, bi = d, i
        if bi > 0 and best > tol * tol:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [p for p, k in zip(pts, keep) if k]


def main():
    if len(sys.argv) > 1:
        d = json.load(open(sys.argv[1], encoding='utf-8'))
    else:
        d = json.load(urllib.request.urlopen(SRC, timeout=60))
    out = []
    for f in d['features']:
        name = f['properties'].get('name') or ''
        g = f.get('geometry')
        if not name or not g:
            continue  # 九段线等非省级要素
        polys = g['coordinates'] if g['type'] == 'MultiPolygon' else [g['coordinates']]
        rings = []
        for poly in polys:
            for ring in poly:
                r = dp([(round(x, 4), round(y, 4)) for x, y in ring], TOL)
                area = abs(sum(r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1] for i in range(len(r) - 1))) / 2
                if len(r) >= 4 and area >= MIN_AREA:
                    rings.append([[round(x, 3), round(y, 3)] for x, y in r])
        out.append({'name': name, 'adcode': f['properties'].get('adcode'), 'rings': rings})
    with open(OUT, 'w', encoding='utf-8', newline='\n') as fp:
        json.dump({'source': SRC, 'note': '简化省界（DP 0.02°），仅用于坐标→省份判断，不用于展示',
                   'provinces': out}, fp, ensure_ascii=False, separators=(',', ':'))
        fp.write('\n')
    print(OUT, sum(len(r) for p in out for r in p['rings']), 'points')


if __name__ == '__main__':
    main()
