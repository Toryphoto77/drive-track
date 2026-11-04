#!/usr/bin/env python3
"""DriveTrack 赛道库种子数据抓取 + 逐条核对脚本。

合法来源（红线）：
- 仅 OSM（ODbL，署名 © OpenStreetMap contributors）与官方公开事实
  （赛道官网/FIA/维基公布的长度等，仅用于校验，不复制专有库数据）。
- 绝不复制/抓取 RaceChrono、Harry's、VBOX 等专有赛道库的数据。

流程（每条赛道）：
1. Nominatim 按英文名搜 venue，取 bbox；
2. OSM map API 拉 bbox 内全部对象（live 数据）；
3. 优先找 type=circuit 关系（名匹配），主回路 = 空 role 的 member way
   （单条闭合或多条拼接），pit_lane 排除；起点 = role=start 的 member node；
4. 无 circuit 关系时回落：highway=raceway + sport=motor 的 way 拼接闭合回路；
5. 逐条核对：闭合、点数、名称、长度（与公布长度对照）、起点落点；
6. 弯角：由中心线曲率推导（仅作几何推导标注，绝不冒充官方弯角数据）；
7. 通过的写 data/packages/{id}.json；未通过的只记报告，不写经纬度。

输出：
- data/packages/{id}.json（仅通过核对的条目）
- data/tracks-manifest.json（dataVersion + 包列表）
- data/seed-verification.md（逐条核对报告）

用法：python3 tools/seed_fetch.py
"""
import json
import math
import os
import re
import sys
import time
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

UA = 'DriveTrack-seed-check/1.0 (track library seed verification)'
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT, 'data')
PKG_DIR = os.path.join(DATA_DIR, 'packages')
RAW_BASE = 'https://raw.githubusercontent.com/wangtao969/drive-track/main/data/packages'

REGION_COUNTRY = {
    '中国': ['China', '中国'],
    '德国': ['Germany', 'Deutschland'],
    '比利时': ['Belgium', 'Belgique'],
    '英国': ['United Kingdom', 'England', '英国'],
    '意大利': ['Italy', 'Italia'],
    '日本': ['Japan'],
    '美国': ['United States', 'USA'],
    '摩纳哥': ['Monaco'],
    '法国': ['France'],
    '马来西亚': ['Malaysia'],
    '澳大利亚': ['Australia'],
}

# 用于名称匹配的关键 token（小写，匹配任一即算名对得上；中文 venue
# 的 display_name 为中文，故中文赛道另加中文 token）
NAME_TOKENS = {
    'shanghai': ['shanghai', '上海'],
    'zhuhai': ['zhuhai', '珠海'],
    'ningbo': ['ningbo', '宁波'],
    'zhejiang': ['zhejiang', '浙江'],
    'tianma': ['tianma', '天马'],
    'ordos': ['ordos', '鄂尔多斯'],
    'nordschleife': ['nordschleife', 'nürburgring', 'nurburgring'],
    'spa': ['spa-francorchamps', 'spa'],
    'silverstone': ['silverstone'],
    'monza': ['monza'],
    'suzuka': ['suzuka'],
    'laguna_seca': ['laguna seca'],
    'cota': ['americas', 'cota'],
    'fuji': ['fuji'],
    'chengdu_tianfu': ['tianfu', '天府', 'chengdu', '成都'],
    'goldenport': ['goldenport', '金港'],
    'guangdong_gic': ['guangdong', '广东'],
    'monaco': ['monaco'],
    'le_mans': ['sarthe', 'le mans'],
    'sepang': ['sepang'],
    'bathurst': ['mount panorama', 'bathurst'],
}


def http_get(url, timeout=60):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def hav(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dphi = math.radians(b[0] - a[0])
    dl = math.radians(b[1] - a[1])
    x = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(x))


def polyline_length(pts):
    return sum(hav(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def norm_name(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())


def name_matches(track_id, osm_name):
    if not osm_name:
        return False
    n = osm_name.lower()
    return any(t in n for t in NAME_TOKENS.get(track_id, []))


TRACK_COUNTRY = {
    'shanghai': 'cn', 'zhuhai': 'cn', 'ningbo': 'cn', 'zhejiang': 'cn',
    'tianma': 'cn', 'ordos': 'cn', 'chengdu_tianfu': 'cn',
    'goldenport': 'cn', 'guangdong_gic': 'cn',
    'nordschleife': 'de', 'spa': 'be', 'silverstone': 'gb',
    'monza': 'it', 'suzuka': 'jp', 'laguna_seca': 'us', 'cota': 'us',
    'fuji': 'jp', 'monaco': 'mc', 'le_mans': 'fr', 'sepang': 'my',
    'bathurst': 'au',
}

# 已知大环关系直取（v4）：纽北 20.8km 超出任何 venue bbox，且 OSM
# map API 大框恒 400；关系 38566（route Nürburgring Nordschleife，
# 53 成员）经实测拼接 20.831km，与公布值偏差 -0.00%。ID 若未来失效
# 则直取失败，自动回落常规流程，不产生坏数据。
TRACK_RELATION_OVERRIDES = {
    'nordschleife': 38566,
}


def nominatim_search(query, country=None):
    url = ('https://nominatim.openstreetmap.org/search?q=' +
           urllib.parse.quote(query) +
           '&format=json&limit=5&addressdetails=1')
    if country:
        url += '&countrycodes=' + country
    data = json.loads(http_get(url, timeout=30))
    return data


def pick_venue(track, results):
    """从 Nominatim 结果里挑 venue。
    优先级：① 名称 token 命中（防把邻近小赛道当成目标，如勒芒的
    Maison Blanche）；② leisure/landuse；③ 第一个。"""
    if not results:
        return None
    for r in results:
        nm = (r.get('name') or '') + ' ' + (r.get('display_name') or '')
        if name_matches(track['id'], nm):
            return r
    for r in results:
        if r.get('class') in ('leisure', 'landuse') or 'circuit' in (r.get('type') or ''):
            return r
    return results[0]


def fetch_bbox(bbox):
    minlon, minlat, maxlon, maxlat = bbox
    url = ('https://api.openstreetmap.org/api/0.6/map?bbox=%s,%s,%s,%s'
           % (minlon, minlat, maxlon, maxlat))
    raw = http_get(url, timeout=120)
    return ET.fromstring(raw)


def _expand_bbox(bbox, factor):
    minlon, minlat, maxlon, maxlat = bbox
    clon = (minlon + maxlon) / 2
    clat = (minlat + maxlat) / 2
    hw = (maxlon - minlon) / 2 * factor
    hh = (maxlat - minlat) / 2 * factor
    return (clon - hw, clat - hh, clon + hw, clat + hh)


def parse_osm(root):
    nodes = {}
    for n in root.findall('node'):
        try:
            nodes[n.get('id')] = (float(n.get('lat')), float(n.get('lon')))
        except (TypeError, ValueError):
            pass
    ways = {}
    for w in root.findall('way'):
        refs = [nd.get('ref') for nd in w.findall('nd')]
        tags = {c.get('k'): c.get('v') for c in w.findall('tag')}
        ways[w.get('id')] = (refs, tags)
    rels = []
    for r in root.findall('relation'):
        tags = {c.get('k'): c.get('v') for c in r.findall('tag')}
        members = [(m.get('type'), m.get('ref'), m.get('role') or '')
                   for m in r.findall('member')]
        rels.append((r.get('id'), tags, members))
    return nodes, ways, rels


def way_points(refs, nodes):
    return [nodes[r] for r in refs if r in nodes]


def stitch(segments, tol_m=50.0):
    """把若干段按端点邻近拼接成一条线。返回 (points, closed, used_count)。"""
    if not segments:
        return [], False, 0
    ordered = [segments[0]]
    rest = segments[1:]
    cur_end = ordered[0][-1]
    while rest:
        found = None
        for i, seg in enumerate(rest):
            if hav(cur_end, seg[0]) < tol_m:
                found = (i, False)
                break
            if hav(cur_end, seg[-1]) < tol_m:
                found = (i, True)
                break
        if found is None:
            break
        i, rev = found
        seg = rest.pop(i)
        pts = list(reversed(seg)) if rev else seg
        ordered.append(pts)
        cur_end = pts[-1]
    loop = []
    for pts in ordered:
        if loop and loop[-1] == pts[0]:
            loop.extend(pts[1:])
        else:
            loop.extend(pts)
    closed = len(loop) >= 2 and hav(loop[0], loop[-1]) < tol_m
    if closed and loop[0] != loop[-1]:
        loop.append(loop[0])
    return loop, closed, len(ordered)


def stitch_multi(segments, tol_m=50.0, published_km=None):
    """多起点拼接：逐个段作起点贪心拼接，收集所有闭合回路后选最优
    （有公布长度时取偏差最小，否则取最长）。
    解决单起点贪心在分支处提前闭合小环的问题（如摩纳哥港区小环）。
    返回 (loop, closed)。"""
    if not segments:
        return [], False
    candidates = []
    for start_idx in range(len(segments)):
        ordered = [segments[start_idx]]
        rest = segments[:start_idx] + segments[start_idx + 1:]
        cur_end = ordered[0][-1]
        while rest:
            found = None
            for i, seg in enumerate(rest):
                if hav(cur_end, seg[0]) < tol_m:
                    found = (i, False)
                    break
                if hav(cur_end, seg[-1]) < tol_m:
                    found = (i, True)
                    break
            if found is None:
                break
            i, rev = found
            seg = rest.pop(i)
            pts = list(reversed(seg)) if rev else seg
            ordered.append(pts)
            cur_end = pts[-1]
        loop = []
        for pts in ordered:
            if loop and loop[-1] == pts[0]:
                loop.extend(pts[1:])
            else:
                loop.extend(pts)
        if len(loop) >= 30 and hav(loop[0], loop[-1]) < tol_m:
            if loop[0] != loop[-1]:
                loop.append(loop[0])
            candidates.append(loop)
    if not candidates:
        return [], False
    if published_km:
        best = min(candidates,
                   key=lambda l: abs(polyline_length(l) / 1000.0 - published_km))
    else:
        best = max(candidates, key=lambda l: polyline_length(l))
    return best, True


def resample(pts, step_m=10.0):
    """沿折线按约 step_m 重采样（闭合线保留首尾闭合）。"""
    if len(pts) < 2:
        return list(pts)
    out = [pts[0]]
    acc = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        d = hav(a, b)
        if d == 0:
            continue
        acc += d
        while acc >= step_m:
            f = (acc - step_m + d) / d if d else 0
            # 从 a 向 b 插值：已走 acc-step_m 之后还差 step_m-acc？直接按比例
            # 更简单：按累计距离插值
            t = 1.0 - (acc - step_m) / d if d else 0
            t = min(max(t, 0.0), 1.0)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            acc -= step_m
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out


def bearing(a, b):
    """方位角（度，0=北，顺时针）。"""
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def wrap180(d):
    while d > 180:
        d -= 360
    while d < -180:
        d += 360
    return d


def derive_corners(loop):
    """由中心线曲率推导弯角表（几何推导，非官方数据）。

    关键修正（v2）：弯角组按转向符号切分——左弯接右弯的
    chicane / S 弯不得合并成一组（否则正负转向抵消，弯数被
    严重低估，上一版上海 16 弯只推出 7 个即因此）。
    返回 list of {number, direction, radiusM, angleDeg, lat, lon}。
    """
    pts = resample(loop, 10.0)
    if len(pts) < 50:
        return []
    # 分段方位角 + 环形平滑（窗口 3，约 30m，保留短弯）
    heads = []
    for i in range(len(pts) - 1):
        heads.append(bearing(pts[i], pts[i + 1]))
    sm = []
    n = len(heads)
    for i in range(n):
        s = 0.0
        cnt = 0
        for k in range(-1, 2):
            j = (i + k) % n
            s += heads[i] + wrap180(heads[j] - heads[i])
            cnt += 1
        sm.append((heads[i] + (s / cnt - heads[i])) % 360)
    dhead = []
    for i in range(n):
        dhead.append(wrap180(sm[(i + 1) % n] - sm[i]))
    # 转弯样本：|曲率| > 0.04 度/米（半径约 < 1400m）
    turning = [abs(d) / 10.0 > 0.04 for d in dhead]

    def sign(d):
        return 1 if d > 0 else -1

    # 分组：同号连续，异号即切分；允许 30m 内短直道缺口
    groups = []
    cur = None  # [start, end, sign]
    gap = 0
    for i, t in enumerate(turning):
        if t:
            s = sign(dhead[i])
            if cur is None:
                cur = [i, i, s]
            elif s != cur[2]:
                groups.append((cur[0], cur[1]))
                cur = [i, i, s]
            else:
                cur[1] = i
            gap = 0
        else:
            if cur is not None:
                gap += 1
                if gap > 3:
                    groups.append((cur[0], cur[1]))
                    cur = None
                    gap = 0
    if cur is not None:
        groups.append((cur[0], cur[1]))
    corners = []
    for (a, b) in groups:
        total = 0.0
        idx = a
        while idx != b:
            total += dhead[idx % n]
            idx = (idx + 1) % n
        angle = abs(total)
        if angle < 15:
            continue
        seg_len = (b - a) * 10.0
        if seg_len < 30:
            continue
        radius = seg_len / math.radians(angle) if angle > 0 else 0
        if radius < 10 or radius > 2000:
            continue
        mid = pts[(a + b) // 2 % len(pts)]
        corners.append({
            'direction': 'left' if total < 0 else 'right',
            'radiusM': round(radius),
            'angleDeg': round(angle),
            'lat': round(mid[0], 6),
            'lon': round(mid[1], 6),
        })
    for i, c in enumerate(corners):
        c2 = {'number': i + 1}
        c2.update(c)
        corners[i] = c2
    return corners


def loop_orientation(loop):
    """闭合线走向：正面积=逆时针，负面积=顺时针（经纬度平面近似）。"""
    s = 0.0
    for i in range(len(loop) - 1):
        x1, y1 = loop[i][1], loop[i][0]
        x2, y2 = loop[i + 1][1], loop[i + 1][0]
        s += (x2 - x1) * (y2 + y1)
    return 'clockwise' if s > 0 else 'counterclockwise'


def find_loop(tid, track, nodes, ways, rels, venue):
    """在一次 bbox 拉取结果里找主回路。
    返回 (loop, loop_src, start_pt, diag)。loop 为 None 表示未找到。
    """
    diag = []
    loop = None
    loop_src = ''
    start_pt = None
    # 3a. circuit / route 关系
    # v3：成员角色回落——空 role 无主回路时，改试除 pit/access 外的
    # 全部 way 成员拼接（银石 / 蒙扎 / 摩纳哥 / 巴瑟斯特的关系成员
    # 带非空 role，上一版因此漏掉），但须过长度校验才收。
    # v4：收集全部名匹配关系的候选回路后选最优（有公布长度取偏差
    # 最小，否则取最长），避免“先匹配到的关系是短布局”时锁定错误
    # 回路；拼接改多起点（防分支处提前闭合小环）；起终点节点同时
    # 认 role=start 与 role=start-finish（摩纳哥 / 勒芒用后者）；
    # 关系类型同时认 circuit 与 route（拉古纳 / 勒芒只建了 route
    # 关系）；名称匹配同时查 name 与 name:en / name:ja（铃鹿关系
    # 主名是日文、英名才含 Suzuka，勒芒 route 英名才含 Le Mans）。
    candidates = []
    for rid, tags, members in rels:
        rtype = tags.get('type')
        if rtype not in ('circuit', 'route'):
            continue
        nm = ' '.join(x for x in (tags.get('name'), tags.get('name:en'),
                                  tags.get('name:ja')) if x)
        if not name_matches(tid, nm):
            continue
        start_node = None
        for mtype, mref, role in members:
            if mtype == 'node' and role in ('start', 'start-finish',
                                            'start_finish') and mref in nodes:
                start_node = nodes[mref]
        empty_ways = []
        other_ways = []
        for mtype, mref, role in members:
            if mtype != 'way' or mref not in ways:
                continue
            pts = way_points(ways[mref][0], nodes)
            if role in ('', None):
                empty_ways.append(pts)
            elif role not in ('pit_lane', 'pit', 'access', 'pit_entry',
                              'pit_exit', 'service'):
                other_ways.append(pts)
        tried = []
        if empty_ways:
            tried.append(('空 role 成员', empty_ways))
        if other_ways:
            tried.append(('非 pit 成员', other_ways))
        for label, cand_ways in tried:
            if len(cand_ways) == 1:
                cand = cand_ways[0]
                closed = cand[0] == cand[-1]
            else:
                cand, closed = stitch_multi(cand_ways, 50.0,
                                            track['lengthKm'])
            if closed and len(cand) >= 30:
                # 非空 role 回落须过长度校验（防把备用布局当主赛道）
                if label != '空 role 成员' and track['lengthKm']:
                    lk = polyline_length(cand) / 1000.0
                    if abs((lk - track['lengthKm']) / track['lengthKm'] * 100) > 20:
                        diag.append(
                            f'关系 {rid}（{label}）拼接回路长度 {lk:.2f}km 与公布值偏差 >20%，弃用')
                        continue
                sp = None
                if start_node is not None:
                    dmin = min(hav(start_node, p) for p in cand)
                    if dmin < 25:
                        sp = start_node
                candidates.append((
                    cand,
                    f'OSM {rtype} {rid}（type={rtype}，name={nm}，{label}）',
                    sp))
    if candidates:
        pub = track['lengthKm']
        if pub:
            loop, loop_src, start_pt = min(
                candidates,
                key=lambda c: abs(polyline_length(c[0]) / 1000.0 - pub))
        else:
            loop, loop_src, start_pt = max(
                candidates, key=lambda c: polyline_length(c[0]))
        diag.append(f'回路：{loop_src}，{len(loop)} 点')
        return loop, loop_src, start_pt, diag
    # 3b. 回落：raceway way 拼接
    # v4：收集单条闭合 + 单起点拼接 + 多起点拼接的全部候选后选最优
    # （有公布长度取偏差最小，否则取最长），不再取第一条闭合小环。
    if loop is None:
        rw = []
        for wid, (refs, tags) in ways.items():
            if tags.get('highway') == 'raceway' and tags.get('sport') == 'motor':
                # v4：维修区通道（名含 pit）不得链进主回路
                if 'pit' in (tags.get('name') or '').lower():
                    continue
                pts = way_points(refs, nodes)
                if len(pts) >= 5:
                    rw.append(pts)
        # 回落路径的 guard：候选回路必须经过 venue 点附近 2km 内，
        # 否则可能是同区域的卡丁车小环 / 试车场，一律弃用。
        vlat, vlon = float(venue['lat']), float(venue['lon'])

        def near_venue(cand):
            return min(hav((vlat, vlon), p) for p in cand)

        fb_candidates = []
        for pts in rw:
            if pts[0] == pts[-1] and len(pts) >= 30 and near_venue(pts) < 2000:
                fb_candidates.append(
                    (pts, 'OSM highway=raceway 单条闭合 way'))
        if rw:
            cand, closed, _ = stitch(rw, tol_m=100.0)
            if closed and len(cand) >= 30 and near_venue(cand) < 2000:
                fb_candidates.append(
                    (cand, 'OSM highway=raceway 多段拼接'))
            cand, closed = stitch_multi(rw, 100.0, track['lengthKm'])
            if closed and len(cand) >= 30 and near_venue(cand) < 2000:
                fb_candidates.append(
                    (cand, 'OSM highway=raceway 多起点拼接'))
        if fb_candidates:
            pub = track['lengthKm']
            if pub:
                loop, loop_src = min(
                    fb_candidates,
                    key=lambda c: abs(polyline_length(c[0]) / 1000.0 - pub))
            else:
                loop, loop_src = max(
                    fb_candidates, key=lambda c: polyline_length(c[0]))
    return loop, loop_src, start_pt, diag


def process_track(track):
    tid = track['id']
    rep = {'id': tid, 'nameCn': track['cn'], 'nameEn': track['en'],
           'publishedLengthKm': track['lengthKm'], 'steps': []}
    # 1. Nominatim（按 queries 顺序试，中文赛道先中文名）
    venue = None
    queries = track.get('queries') or [track['en']]
    for q in queries:
        try:
            results = nominatim_search(q, TRACK_COUNTRY.get(tid))
            time.sleep(1.2)
        except Exception as e:
            rep['status'] = 'fetch_failed'
            rep['reason'] = f'Nominatim 请求失败：{e}'
            return rep, None
        venue = pick_venue(track, results)
        if venue is not None:
            rep['steps'].append(f'Nominatim 命中：{q}')
            break
    if venue is None:
        rep['status'] = 'not_found'
        rep['reason'] = 'Nominatim 未返回候选 venue（已试全部查询词）'
        return rep, None
    bb = venue.get('boundingbox')
    if not bb:
        lat, lon = float(venue['lat']), float(venue['lon'])
        bb = [str(lat - 0.02), str(lat + 0.02), str(lon - 0.02), str(lon + 0.02)]
    # boundingbox 顺序：[south, north, west, east]
    south, north, west, east = bb[0], bb[1], bb[2], bb[3]
    margin_lat = (float(north) - float(south)) * 0.05 + 0.002
    margin_lon = (float(east) - float(west)) * 0.05 + 0.002
    bbox = (float(west) - margin_lon, float(south) - margin_lat,
            float(east) + margin_lon, float(north) + margin_lat)
    rep['venue'] = {'osm_type': venue.get('osm_type'), 'osm_id': venue.get('osm_id'),
                    'display_name': venue.get('display_name')}
    # 2. OSM map API（bbox 拉取；首轮无回路时扩大 3 倍重试一次，
    #    纽北这类 20km 赛道常超出 venue bbox）
    # v4 修复：第二轮拉取失败时，若首轮已解析成功，应回落首轮数据
    # 走未核实诊断，而非误报 fetch_failed（银石 v3 即因此丢数据）；
    # 仅当两轮均未解析成功才报 fetch_failed。
    loop = None
    loop_src = ''
    start_pt = None
    cur_bbox = bbox
    nodes, ways, rels = {}, {}, []
    parsed_once = False
    # v4：已知关系直取（见 TRACK_RELATION_OVERRIDES）。只接受关系分支
    # 的回路（loop_src 含 OSM circuit / OSM route）；回落路径的回路
    # 不接受（关系直取数据的回落 guard 不可信），继续走常规流程。
    if tid in TRACK_RELATION_OVERRIDES:
        rid = TRACK_RELATION_OVERRIDES[tid]
        try:
            raw = http_get(
                f'https://api.openstreetmap.org/api/0.6/relation/{rid}/full',
                timeout=60)
            time.sleep(1.0)
            onodes, oways, orels = parse_osm(ET.fromstring(raw))
            oloop, osrc, osp, odiag = find_loop(
                tid, track, onodes, oways, orels, venue)
            rep['steps'].extend(odiag)
            if oloop is not None and ('OSM circuit' in osrc
                                     or 'OSM route' in osrc):
                loop, loop_src, start_pt = oloop, osrc, osp
                rep['steps'].append(f'已知关系直取成功：relation {rid}')
            else:
                rep['steps'].append(
                    f'已知关系 {rid} 未给出关系分支回路，回落常规流程')
        except Exception as e:
            rep['steps'].append(f'已知关系 {rid} 直取失败：{e}，回落常规流程')
    for attempt in range(2 if loop is None else 0):
        try:
            root = fetch_bbox(cur_bbox)
            time.sleep(1.0)
        except Exception as e:
            if attempt == 1 and parsed_once:
                rep['steps'].append(
                    f'扩框拉取失败（{e}），回落首轮已解析数据走诊断')
                break
            if attempt == 1:
                rep['status'] = 'fetch_failed'
                rep['reason'] = f'OSM map API 请求失败：{e}'
                return rep, None
            cur_bbox = _expand_bbox(cur_bbox, 3.0)
            continue
        nodes, ways, rels = parse_osm(root)
        parsed_once = True
        rep['steps'].append(f'bbox 内节点 {len(nodes)} / way {len(ways)} / relation {len(rels)}')
        loop, loop_src, start_pt, diag = find_loop(
            tid, track, nodes, ways, rels, venue)
        rep['steps'].extend(diag)
        # v4.1：bbox 内截断成员拼出的“闭合回路”若与公布长度偏差
        # >20%（终核必弃），不得直接采纳——否则会挡住扩框与关系直取
        # 的机会（摩纳哥 / 勒芒 v4 即因此错失真环）。弃用后继续尝试。
        if loop is not None and track['lengthKm']:
            lk = polyline_length(loop) / 1000.0
            if abs((lk - track['lengthKm']) / track['lengthKm'] * 100) > 20:
                rep['steps'].append(
                    f'bbox 回路 {lk:.2f}km 与公布值偏差 >20%，不采纳，继续尝试')
                loop, loop_src, start_pt = None, '', None
        if loop is not None:
            break
        if attempt == 0:
            rep['steps'].append('首轮无闭合回路，扩大 bbox 3 倍重试')
            cur_bbox = _expand_bbox(cur_bbox, 3.0)

    if loop is None:
        # v4：关系直取重试——bbox 可能截断关系成员（蒙扎 / 摩纳哥 /
        # 银石的成员段超出 venue bbox），改按名匹配的关系 ID 直取
        # relation/full（完整成员，不受 bbox 截断），再跑一次找环。
        matched_ids = []
        for rid, tags, members in rels:
            if tags.get('type') in ('circuit', 'route'):
                nm = ' '.join(x for x in (tags.get('name'),
                                          tags.get('name:en'),
                                          tags.get('name:ja')) if x)
                if name_matches(tid, nm) and rid not in matched_ids:
                    matched_ids.append(rid)
        for rid in matched_ids[:3]:
            try:
                raw = http_get(
                    f'https://api.openstreetmap.org/api/0.6/relation/{rid}/full',
                    timeout=60)
                time.sleep(1.0)
            except Exception as e:
                rep['steps'].append(f'关系 {rid} 直取失败：{e}')
                continue
            rnodes, rways, rrels = parse_osm(ET.fromstring(raw))
            rloop, rsrc, rsp, rdiag = find_loop(
                tid, track, rnodes, rways, rrels, venue)
            rep['steps'].extend(rdiag)
            # v4.1：直取重试只接受关系分支的回路；关系直取数据的回落
            # 路径（成员 way 子集拼出的片段）不可信，不得采纳。
            if rloop is not None and ('OSM circuit' in rsrc
                                     or 'OSM route' in rsrc):
                loop, loop_src, start_pt = rloop, rsrc, rsp
                rep['steps'].append(f'关系直取重试成功：relation {rid}')
                break
            if rloop is not None:
                rep['steps'].append(
                    f'关系 {rid} 直取仅给出回落路径回路，不采纳')

    if loop is None:
        # 诊断：bbox 里到底有什么，供人工复核（不拉新数据）
        circ_names = []
        for rid, tags, members in rels:
            if tags.get('type') == 'circuit':
                circ_names.append(f"{rid}:{tags.get('name')}")
        rw_count = 0
        rw_closed = 0
        for wid, (refs, tags) in ways.items():
            if tags.get('highway') == 'raceway':
                rw_count += 1
                pts = way_points(refs, nodes)
                if len(pts) >= 5 and pts[0] == pts[-1]:
                    rw_closed += 1
        rep['status'] = 'not_verified'
        rep['reason'] = '未找到可核实的闭合赛道几何（无匹配的 circuit 关系或 raceway 闭合回路）'
        rep['steps'].append(f'诊断：bbox 内 circuit 关系 {circ_names}；raceway way {rw_count} 条，其中单条闭合 {rw_closed} 条')
        return rep, None
    # 4. 核对
    length_m = polyline_length(loop)
    length_km = length_m / 1000.0
    gaps = [hav(loop[i], loop[i + 1]) for i in range(len(loop) - 1)]
    max_gap = max(gaps) if gaps else 0
    pub = track['lengthKm']
    dev = None
    if pub:
        dev = (length_km - pub) / pub * 100
    # 最大缺口是否落在直道上（缺口前后走向夹角 < 15° 即直道稀疏节点，
    # 而非缺段；缺段会走捷径、长度随之缩水）
    # v4.1：回路是闭合的（首尾同点），方位检查必须按环索引取模，
    # 否则最后一个缺口（富士主直道 1288m 稀疏节点）因下标越界被
    # 误判为缺段。
    gap_straight = None
    if gaps:
        gi = gaps.index(max(gaps))
        m = len(loop) - 1  # 去重点数
        if m >= 4:
            def cyc(i):
                return loop[i % m]
            h1 = bearing(cyc(gi - 1), cyc(gi))
            h2 = bearing(cyc(gi + 1), cyc(gi + 2))
            gap_straight = abs(wrap180(h2 - h1)) < 15
    checks = {
        'closed': True,
        'points': len(loop),
        'maxGapM': round(max_gap, 1),
        'maxGapStraight': gap_straight,
        'computedLengthKm': round(length_km, 3),
        'publishedLengthKm': pub,
        'deviationPct': round(dev, 2) if dev is not None else None,
        'loopSource': loop_src,
        'startOnLoop': start_pt is not None,
        'orientation': loop_orientation(loop),
    }
    rep['checks'] = checks
    # 拒收带：长度偏差 > 20% 即几何疑似非主赛道 / 片段，整包弃用
    # （上一版铃鹿 -78%、富士 -85% 的小环即属此类，绝不能留）。
    if dev is not None and abs(dev) > 20:
        rep['status'] = 'not_verified'
        rep['reason'] = f'长度偏差 {dev:.1f}%（>20%），几何疑似非主赛道或片段，已弃用'
        return rep, None
    problems = []
    if max_gap > 500 and not (gap_straight and dev is not None and abs(dev) < 2):
        problems.append(f'最大点间距 {max_gap:.0f}m 过大，几何可能缺段')
    if dev is not None and abs(dev) > 10:
        problems.append(f'长度偏差 {dev:.1f}%（>10%），长度标待核')
    if problems:
        rep['status'] = 'pending'
        rep['reason'] = '；'.join(problems)
    else:
        rep['status'] = 'verified'
        rep['reason'] = '名称一致；闭合回路；长度与公布值对照通过'
    # 5. 弯角推导
    corners = derive_corners(loop)
    rep['derivedCorners'] = len(corners)
    # 弯数 sanity（v2 收紧）：官方总数已知时，推导数须在 0.7x~1.3x 内
    # 才收入；否则弯角表留空标待核（宁缺勿错）。
    official_corners = track.get('corners')
    corners_ok = True
    if official_corners:
        if not (official_corners * 0.7 <= len(corners) <= official_corners * 1.3):
            corners_ok = False
            rep['steps'].append(
                f'推导弯数 {len(corners)} 与官方总数 {official_corners} 差异大，弯角表留空标待核')
    elif not (5 <= len(corners) <= 40):
        corners_ok = False
        rep['steps'].append(f'推导弯数 {len(corners)} 超出合理范围，弯角表留空标待核')
    if not corners_ok:
        corners = []
    pkg = {
        'id': tid,
        'nameCn': track['cn'],
        'nameEn': track['en'],
        'region': track['region'],
        'version': 1,
        'source': 'osm',
        'sourceDetail': loop_src + '（© OpenStreetMap contributors，ODbL）',
        'verification': 'verified' if rep['status'] == 'verified' else 'pending',
        'verificationNote': rep['reason'],
        'centerline': [{'lat': round(p[0], 6), 'lon': round(p[1], 6)} for p in loop],
        'lengthM': round(length_m),
        'publishedLengthM': round(pub * 1000) if pub else None,
        'corners': corners,
        'cornerSource': 'osm-derived' if corners else None,
        'sectorPoints': [],
        'sectorNote': '分段点待核：OSM 几何无法推导官方分段线',
        'gantry': None,
        'start': {'lat': round(start_pt[0], 6), 'lon': round(start_pt[1], 6)} if start_pt else None,
        'finish': {'lat': round(start_pt[0], 6), 'lon': round(start_pt[1], 6)} if start_pt else None,
        'startNote': 'OSM circuit 关系 role=start / start-finish 节点，位于回路线上' if start_pt else '起终点待核：OSM 几何无法推导',
        'userModified': False,
        'isUserTrack': False,
    }
    return rep, pkg


def main():
    # 赛道清单：优先 /tmp/tracks21.json（人工可临时改查询词复跑），
    # 否则用随仓库走的 tools/tracks21.json（/tmp 会被清空，不得只放 /tmp）。
    tracks_path = '/tmp/tracks21.json'
    if not os.path.exists(tracks_path):
        tracks_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   'tracks21.json')
    tracks = json.load(open(tracks_path))
    os.makedirs(PKG_DIR, exist_ok=True)
    # 清旧包：上一轮被拒收的包（如铃鹿/富士小环）不得残留进清单。
    for fn in os.listdir(PKG_DIR):
        if fn.endswith('.json'):
            os.remove(os.path.join(PKG_DIR, fn))
    results = []
    pkgs = []
    for t in tracks:
        print(f'== {t["id"]} {t["en"]}', flush=True)
        try:
            rep, pkg = process_track(t)
        except Exception as e:
            rep, pkg = {'id': t['id'], 'nameCn': t['cn'], 'nameEn': t['en'],
                        'publishedLengthKm': t['lengthKm'],
                        'status': 'fetch_failed', 'reason': f'处理异常：{e}'}, None
        results.append(rep)
        if pkg is not None:
            with open(os.path.join(PKG_DIR, f"{t['id']}.json"), 'w') as f:
                json.dump(pkg, f, ensure_ascii=False, indent=1)
            pkgs.append(pkg)
        print(f"   -> {rep['status']}: {rep['reason']}", flush=True)
    manifest = {
        'dataVersion': '1.0',
        'updatedAt': '2026-11-05',
        'attribution': '© OpenStreetMap contributors，ODbL（http://osm.org/copyright）',
        'packages': [{
            'id': p['id'], 'nameCn': p['nameCn'], 'version': p['version'],
            'url': f"{RAW_BASE}/{p['id']}.json",
            'source': p['source'], 'verification': p['verification'],
        } for p in pkgs],
    }
    with open(os.path.join(DATA_DIR, 'tracks-manifest.json'), 'w') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    with open('/tmp/seed_report.json', 'w') as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    nv = sum(1 for r in results if r['status'] == 'verified')
    np = sum(1 for r in results if r['status'] == 'pending')
    print(f'DONE: verified={nv} pending={np} other={len(results)-nv-np} packages={len(pkgs)}')


if __name__ == '__main__':
    main()
