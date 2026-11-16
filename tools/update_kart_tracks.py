#!/usr/bin/env python3
"""浙江卡丁车赛道包更新（数据源仅 OSM）。

把 data/packages/kart_osm_*.json 里浙江境内的赛道，按 OSM 最新 way
重算中心线、长度、起终点，并在内容确有变化时升包版本、升 manifest
dataVersion。默认只打印差异，加 --apply 才写回。

用法：
  python3 tools/update_kart_tracks.py                  # 联网抓取，预览差异
  python3 tools/update_kart_tracks.py --apply          # 联网抓取并写回
  python3 tools/update_kart_tracks.py --from-dir DIR   # 用本地导出的 way JSON
  python3 tools/update_kart_tracks.py --ids 1189857783,1453469821

--from-dir 目录下文件名是 way id，例如 1189857783.json，内容为
https://api.openstreetmap.org/api/0.6/way/<id>/full.json 的原始回包。

红线：只读 OSM；名称缺失时绝不编造，沿用原占位名并继续标 pending。
"""
import argparse
import copy
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.request

UA = 'DriveTrack-track-update/1.0 (+https://github.com/Toryphoto77/drive-track)'
API = 'https://api.openstreetmap.org/api/0.6/way/{}/full.json'

# 浙江地市名，用于从库里筛出浙江条目
ZJ_TOKENS = ('杭州', '宁波', '温州', '绍兴', '金华', '台州',
             '湖州', '嘉兴', '衢州', '丽水', '舟山')

# 已知的浙江卡丁车包（OSM 上无名称，nameCn 是占位名；只靠 token 会漏，
# 因此固定列出）
DEFAULT_WAY_IDS = (1453469821, 1421514205, 1315459879,
                   1189857783, 1474437369)


def haversine(a, b):
    r = 6371000.0
    la1, lo1 = math.radians(a['lat']), math.radians(a['lon'])
    la2, lo2 = math.radians(b['lat']), math.radians(b['lon'])
    d = (math.sin((la2 - la1) / 2) ** 2
         + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(d))


def line_length(pts):
    return sum(haversine(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def max_gap(pts):
    return max((haversine(pts[i], pts[i + 1]) for i in range(len(pts) - 1)),
               default=0.0)


def nearest_m(pt, pts):
    return min((haversine(pt, q) for q in pts), default=float('inf'))


def fetch_way(way_id, from_dir=None, timeout=30):
    if from_dir:
        path = os.path.join(from_dir, '%d.json' % way_id)
        if not os.path.exists(path):
            raise RuntimeError('缺少本地文件：%s' % path)
        with open(path, encoding='utf-8') as f:
            return json.load(f)

    url = API.format(way_id)
    last = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (429, 500, 502, 503, 504) and attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            raise
        except Exception as e:  # 网络被墙 / TLS 失败
            last = e
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            raise
    raise RuntimeError('抓取失败：%s' % last)


def parse_way(doc, way_id):
    way = None
    nodes = {}
    for el in doc.get('elements', []):
        if el.get('type') == 'way' and el.get('id') == way_id:
            way = el
        elif el.get('type') == 'node':
            nodes[el['id']] = el
    if way is None:
        raise RuntimeError('回包里没有 way %d' % way_id)

    pts = []
    for nid in way.get('nodes', []):
        n = nodes.get(nid)
        if n is None:
            raise RuntimeError('way %d 引用了回包里不存在的节点 %s'
                               % (way_id, nid))
        pt = {'lat': round(float(n['lat']), 6),
              'lon': round(float(n['lon']), 6)}
        # 去掉连续重复点（OSM 偶有零长度段）
        if pts and hav(pts[-1], pt) < 0.5:
            continue
        pts.append(pt)

    tags = way.get('tags', {}) or {}
    return {
        'version': way.get('version'),
        'timestamp': way.get('timestamp'),
        'tags': tags,
        'points': pts,
    }


def hav(a, b):
    return haversine(a, b)


def osm_name(tags):
    for key in ('name:zh', 'name:zh-Hans', 'name'):
        v = (tags.get(key) or '').strip()
        if v:
            return v
    return None


def note_text(way_id, info, name, length, gap, closed, closed_note):
    ts = (info.get('timestamp') or '').replace('T', ' ').replace('Z', '')
    head = 'OSM way %d v%s（%s）复核：' % (way_id, info['version'], ts)
    if not closed:
        return head + closed_note + '；本次未替换几何'
    return (head
            + ('有名称' if name else 'OSM 无名称，沿用占位名')
            + '；闭合中心线；%d 点；几何重算 %d m；最大节点间距 %.1f m；'
              '公开长度未公布，长度待核；起终点为临时计时线，待现场核对'
            % (len(info['points']), round(length), gap))


def update_one(pkg, way_id, info):
    """返回 (new_pkg, changes, warnings)。"""
    changes, warnings = [], []
    new = copy.deepcopy(pkg)
    tags = info['tags']
    pts = info['points']

    closed = len(pts) > 1 and hav(pts[0], pts[-1]) < 1.0
    closed_note = ''
    if not closed:
        closed_note = '未闭合（首尾相距 %.0f m）' % (hav(pts[0], pts[-1]) if pts else 0)
        warnings.append(closed_note)
    if len(pts) < 30:
        warnings.append('点数仅 %d，低于 30' % len(pts))
        if not closed_note:
            closed_note = '点数不足 30'
        closed = False

    length = line_length(pts)
    gap = max_gap(pts)

    if closed:
        if new.get('centerline') != pts:
            new['centerline'] = pts
            changes.append('中心线')
        if round(length) != new.get('lengthM'):
            changes.append('长度 %s→%d m' % (new.get('lengthM'), round(length)))
            new['lengthM'] = round(length)
        # 几何变了，原临时起终点可能不在新线上
        for key in ('start', 'finish'):
            old = new.get(key)
            if old and nearest_m(old, pts) > 5.0:
                new[key] = dict(pts[0])
                changes.append('%s 重取首点' % key)

    name = osm_name(tags)
    if name and name != new.get('nameCn'):
        changes.append('名称 %s→%s' % (new.get('nameCn'), name))
        new['nameCn'] = name
    if tags.get('name:en') and tags['name:en'] != new.get('nameEn'):
        new['nameEn'] = tags['name:en']
        changes.append('英文名')

    new['sourceDetail'] = (
        'OSM way %d v%s（%s，highway=raceway，sport=karting）（'
        '© OpenStreetMap contributors，ODbL）'
        % (way_id, info['version'], info['timestamp']))
    new['verificationNote'] = note_text(way_id, info, name, length, gap,
                                        closed, closed_note)

    content_changed = bool(changes)
    if content_changed:
        new['version'] = int(pkg.get('version', 1)) + 1
    return new, changes, warnings, content_changed


def bump_data_version(v):
    m = re.fullmatch(r'V(\d+)\.(\d+)\.(\d+)', v or '')
    if not m:
        return v
    a, b, c = map(int, m.groups())
    return 'V%d.%d.%d' % (a, b, c + 1)


def write_json(path, obj):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=4)
        f.write('\n')


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description='更新浙江卡丁车赛道包（OSM 源）')
    ap.add_argument('--apply', action='store_true', help='写回文件（默认只预览）')
    ap.add_argument('--from-dir', help='从本地目录读 <wayid>.json，不联网')
    ap.add_argument('--ids', help='逗号分隔的 way id，指定后忽略自动筛选')
    ap.add_argument('--data-dir', default=os.path.join(root, 'data'),
                    help='data 目录（默认仓库 data/）')
    args = ap.parse_args()

    manifest_path = os.path.join(args.data_dir, 'tracks-manifest.json')
    pkg_dir = os.path.join(args.data_dir, 'packages')
    with open(manifest_path, encoding='utf-8') as f:
        manifest = json.load(f)

    # 选包
    if args.ids:
        want = {int(x) for x in re.split(r'[,\s]+', args.ids.strip()) if x}
    else:
        want = set(DEFAULT_WAY_IDS)
        for e in manifest.get('packages', []):
            pid = e.get('id', '')
            if not pid.startswith('kart_osm_'):
                continue
            if any(t in (e.get('nameCn') or '') for t in ZJ_TOKENS):
                want.add(int(pid.rsplit('_', 1)[1]))

    targets = []
    for e in manifest.get('packages', []):
        pid = e.get('id', '')
        if not pid.startswith('kart_osm_'):
            continue
        if int(pid.rsplit('_', 1)[1]) in want:
            targets.append(e)

    if not targets:
        print('没有匹配到浙江卡丁车包。')
        return 1

    print('目标 %d 条：' % len(targets))
    for e in targets:
        print('  %s  %s' % (e['id'], e.get('nameCn')))
    print()

    ok, failed, bumped = 0, 0, 0
    for entry in targets:
        pid = entry['id']
        way_id = int(pid.rsplit('_', 1)[1])
        path = os.path.join(pkg_dir, pid + '.json')
        try:
            with open(path, encoding='utf-8') as f:
                pkg = json.load(f)
            if pkg.get('userModified') or pkg.get('isUserTrack'):
                print('[跳过] %s 用户改过/自建' % pid)
                continue

            info = parse_way(fetch_way(way_id, args.from_dir), way_id)
            new, changes, warnings, changed = update_one(pkg, way_id, info)
            ok += 1

            label = new.get('nameCn') or pid
            if changed:
                bumped += 1
                print('[更新] %-24s v%s→v%s  %s' % (
                    label[:24], pkg.get('version'), new.get('version'),
                    '，'.join(changes)))
            else:
                print('[无变化] %-24s OSM v%s，几何/名称均未变' % (
                    label[:24], info['version']))
            for w in warnings:
                print('        ! %s' % w)

            if args.apply and changed:
                write_json(path, new)
                entry.update({
                    'nameCn': new['nameCn'],
                    'version': new['version'],
                    'verification': new['verification'],
                })
        except Exception as e:
            failed += 1
            print('[失败] %s：%s' % (pid, e))

    print('\n成功 %d，失败 %d，升版 %d' % (ok, failed, bumped))

    if args.apply and bumped:
        old_v = manifest.get('dataVersion')
        manifest['dataVersion'] = bump_data_version(old_v)
        manifest['updatedAt'] = time.strftime('%Y-%m-%d')
        write_json(manifest_path, manifest)
        print('manifest dataVersion %s → %s，updatedAt %s' % (
            old_v, manifest['dataVersion'], manifest['updatedAt']))
    elif args.apply:
        print('没有内容变化，manifest 未改动。')
    else:
        print('预览模式，未写回（确认无误后加 --apply）。')

    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
