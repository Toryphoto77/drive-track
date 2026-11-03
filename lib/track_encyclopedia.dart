import 'package:flutter/material.dart';

import 'track_catalog.dart';
import 'card_style.dart';
import 'track_guide.dart';
import 'track_widgets.dart';

/// 赛道图鉴（v1.0.2：第 9 项，由赛道目录扩充而来）。
///
/// 口径（防编造）：
/// - 现有目录 14 条：长度 / 弯道数 / 轮廓一律复用 track_catalog.dart
///   的已核实数据与重绘轮廓（本文件不复制轮廓点列，图鉴页用
///   [TrackSchematicDiagram] 按 catalogId 查目录画图）；位置只写
///   目录 region 与赛道名已含的城市，城市未核实的写“待核”；
///   建成 / 启用年份与举办赛事未在本轮核实的，一律写“待核”，
///   不把推测写成事实。
/// - 新增 7 条：长度 / 弯道数 / 位置 / 历史 / 赛事均为本轮公开资料
///   核实值（来源见各条 [source]）；轮廓尚未按公开布局重绘，
///   一律标“轮廓待补”，绝不编造轮廓点列；金港弯道数因公开资料
///   有 12 与 16 两种说法，弯道数标待核，不二选一。
/// - 长度一律按“约”理解：不同年份、不同布局的公布值会有出入，
///   界面必须显示“约 X km”，不得当成官方精确测绘值。
/// - 本页不接入计时：图鉴只做资料浏览；选为本次赛道仍走原有
///   赛道选择器（目录 14 条），新增 7 条在接入赛道模式前不设
///   选赛道按钮，总协调接入时再按 catalogId 补。

/// 一条图鉴条目。
class EncyclopediaTrack {
  /// 稳定 id；目录 14 条与 TrackInfo.id 一致，新增 7 条为新 id。
  final String id;
  final String nameCn;
  final String nameEn;

  /// 国家 / 地区（筛选维度）：中国 / 德国 / 比利时 / 英国 /
  /// 意大利 / 日本 / 美国 / 摩纳哥 / 法国 / 马来西亚 / 澳大利亚。
  final String region;

  /// 详细位置（城市 / 园区）；未核实部分写“待核”。
  final String location;

  /// 目录条目的 id；非 null 时长度 / 弯道数 / 轮廓取目录值。
  final String? catalogId;

  /// 仅新增条目用：长度（km，约数）；目录条目留 null，走目录值。
  final double? lengthKm;

  /// 仅新增条目用：弯道总数；null 表示待核。
  final int? totalCorners;

  /// 历史：建成 / 启用年份等能核实的事实；不确定的写“待核”。
  final String history;

  /// 举办赛事：能核实的赛事名；不确定的写“待核”。
  final String events;

  /// 赛事筛选标签：F1 / WEC / MotoGP / 国内赛事 / 其他赛事 / 待核。
  final List<String> eventTags;

  /// 资料来源（网站名即可）。
  final String source;

  const EncyclopediaTrack({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.region,
    required this.location,
    this.catalogId,
    this.lengthKm,
    this.totalCorners,
    required this.history,
    required this.events,
    required this.eventTags,
    required this.source,
  });

  /// 关联的目录条目（新增条目为 null）。
  TrackInfo? get catalog => catalogId == null ? null : trackById(catalogId);

  /// 是否已有重绘轮廓：仅目录 14 条有；新增条目轮廓待补。
  bool get hasOutline => catalog != null && catalog!.outline.length >= 3;

  /// 长度（km）：目录条目取目录值，新增条目取本条值。
  double? get resolvedLengthKm => catalog?.lengthKm ?? lengthKm;

  String get lengthLabel => resolvedLengthKm == null
      ? '约？/待核'
      : '约 $resolvedLengthKm km';

  /// 弯道总数：目录条目取目录值（0 表示待核），新增条目取本条值。
  int? get resolvedCorners {
    if (catalog != null) {
      return catalog!.totalCorners > 0 ? catalog!.totalCorners : null;
    }
    return totalCorners;
  }

  String get cornerLabel =>
      resolvedCorners == null ? '弯道数：待核' : '共 $resolvedCorners 弯';
}

/// 目录 14 条的图鉴补充信息（长度 / 弯道 / 轮廓走目录，不复制）。
const List<EncyclopediaTrack> _catalogEntries = [
  EncyclopediaTrack(
    id: 'shanghai',
    nameCn: '上海国际赛车场',
    nameEn: 'Shanghai International Circuit',
    region: '中国',
    location: '中国·上海',
    catalogId: 'shanghai',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'formula1.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'zhuhai',
    nameCn: '珠海国际赛车场',
    nameEn: 'Zhuhai International Circuit',
    region: '中国',
    location: '中国·广东珠海',
    catalogId: 'zhuhai',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'Wikipedia（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'ningbo',
    nameCn: '宁波国际赛车场',
    nameEn: 'Ningbo International Circuit',
    region: '中国',
    location: '中国·浙江宁波',
    catalogId: 'ningbo',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'sohu.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'zhejiang',
    nameCn: '浙江国际赛车场',
    nameEn: 'Zhejiang International Circuit',
    region: '中国',
    location: '中国·浙江（具体城市待核）',
    catalogId: 'zhejiang',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'racetrackworld.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'tianma',
    nameCn: '上海天马山赛车场',
    nameEn: 'Shanghai Tianma Circuit',
    region: '中国',
    location: '中国·上海',
    catalogId: 'tianma',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'Wikipedia（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'ordos',
    nameCn: '鄂尔多斯国际赛车场',
    nameEn: 'Ordos International Circuit',
    region: '中国',
    location: '中国·内蒙古鄂尔多斯',
    catalogId: 'ordos',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'Wikipedia（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'nordschleife',
    nameCn: '纽博格林北环',
    nameEn: 'Nürburgring Nordschleife',
    region: '德国',
    location: '德国·纽博格林',
    catalogId: 'nordschleife',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'nuerburgring.de（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'spa',
    nameCn: '斯帕',
    nameEn: 'Circuit de Spa-Francorchamps',
    region: '比利时',
    location: '比利时·斯帕-弗朗科尚',
    catalogId: 'spa',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'sportmonks.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'silverstone',
    nameCn: '银石',
    nameEn: 'Silverstone Circuit',
    region: '英国',
    location: '英国·银石',
    catalogId: 'silverstone',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'sportmonks.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'monza',
    nameCn: '蒙扎',
    nameEn: 'Autodromo Nazionale Monza',
    region: '意大利',
    location: '意大利·蒙扎',
    catalogId: 'monza',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'sportmonks.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'suzuka',
    nameCn: '铃鹿',
    nameEn: 'Suzuka Circuit',
    region: '日本',
    location: '日本·铃鹿',
    catalogId: 'suzuka',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'formula1.com（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'laguna_seca',
    nameCn: '拉古纳塞卡',
    nameEn: 'WeatherTech Raceway Laguna Seca',
    region: '美国',
    location: '美国·加利福尼亚拉古纳塞卡',
    catalogId: 'laguna_seca',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'Wikipedia（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'cota',
    nameCn: '美洲赛道',
    nameEn: 'Circuit of the Americas',
    region: '美国',
    location: '美国·得克萨斯奥斯汀',
    catalogId: 'cota',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'FIA 赛道执照表（目录长度来源）',
  ),
  EncyclopediaTrack(
    id: 'fuji',
    nameCn: '富士 Speedway',
    nameEn: 'Fuji Speedway',
    region: '日本',
    location: '日本·富士',
    catalogId: 'fuji',
    history: '建成/启用年份：待核',
    events: '举办赛事：待核',
    eventTags: ['待核'],
    source: 'racefans.net（目录长度来源）',
  ),
];

/// 新增 7 条（本轮公开资料核实；轮廓一律待补，不编轮廓）。
const List<EncyclopediaTrack> _newEntries = [
  EncyclopediaTrack(
    id: 'chengdu_tianfu',
    nameCn: '成都天府国际赛车场',
    nameEn: 'Chengdu Tianfu International Circuit',
    region: '中国',
    location: '中国·四川成都东部新区简州新城',
    lengthKm: 3.265,
    totalCorners: 19,
    history: '2023 年 12 月 1 日开放；一期西赛道按 FIA 二级标准建设，'
        '12 左弯 + 7 右弯，落差约 20 米。',
    events: 'FIA F4 方程式中国锦标赛、CEC 中国汽车耐力锦标赛、'
        'TCR 世界巡回赛成都站。',
    eventTags: ['国内赛事', '其他赛事'],
    source: 'Wikipedia / racetrackworld.com',
  ),
  EncyclopediaTrack(
    id: 'goldenport',
    nameCn: '北京金港国际赛车场',
    nameEn: 'Goldenport Park Circuit',
    region: '中国',
    location: '中国·北京朝阳金盏',
    lengthKm: 2.39,
    // 弯道数待核：英文资料作 12 弯，国内资料作 16 弯，本条不二选一。
    totalCorners: null,
    history: '2001 年 12 月开放；由澳大利亚设计师设计，'
        '中低速技术型赛道，路面最窄 12 米、最宽 20 米。',
    events: '全国汽车场地锦标赛、亚洲赛车节（中国站）等国内赛事。',
    eventTags: ['国内赛事'],
    source: 'Wikipedia / racingcircuits.info（弯道数来源冲突，标待核）',
  ),
  EncyclopediaTrack(
    id: 'guangdong_gic',
    nameCn: '广东国际赛车场',
    nameEn: 'Guangdong International Circuit',
    region: '中国',
    location: '中国·广东肇庆四会大旺',
    lengthKm: 2.82,
    totalCorners: 13,
    history: '2009 年 12 月正式开始运营；按 FIA F3 级别设计建造，'
        '5 左弯 + 8 右弯，顺时针。',
    events: '中国房车锦标赛（CTCC）2009、2010 年总决赛等国内赛事。',
    eventTags: ['国内赛事'],
    source: 'Wikipedia / racetrackworld.com',
  ),
  EncyclopediaTrack(
    id: 'monaco',
    nameCn: '摩纳哥赛道',
    nameEn: 'Circuit de Monaco',
    region: '摩纳哥',
    location: '摩纳哥·蒙特卡洛',
    lengthKm: 3.337,
    totalCorners: 19,
    history: '首届摩纳哥大奖赛 1929 年；1950 年起成为 F1 世锦赛分站；'
        '城市街道赛，顺时针。',
    events: 'F1 摩纳哥大奖赛。',
    eventTags: ['F1'],
    source: 'racetrackworld.com / mercedesamgf1.com',
  ),
  EncyclopediaTrack(
    id: 'le_mans',
    nameCn: '勒芒萨尔特赛道',
    nameEn: 'Circuit de la Sarthe',
    region: '法国',
    location: '法国·勒芒',
    lengthKm: 13.626,
    totalCorners: 38,
    history: '1923 年 5 月 26 日开放；永久赛道 + 封闭公共道路混合布局，'
        '现布局自 2018 年起使用。',
    events: 'FIA WEC 勒芒 24 小时耐力赛。',
    eventTags: ['WEC'],
    source: 'Wikipedia / racetrackworld.com',
  ),
  EncyclopediaTrack(
    id: 'sepang',
    nameCn: '雪邦国际赛车场',
    nameEn: 'Sepang International Circuit',
    region: '马来西亚',
    location: '马来西亚·雪邦（吉隆坡附近）',
    lengthKm: 5.543,
    totalCorners: 15,
    history: '1999 年 3 月开放；由 Hermann Tilke 设计，顺时针；'
        '首届 F1 马来西亚大奖赛同年 10 月举行。',
    events: 'F1 马来西亚大奖赛（1999–2017）、MotoGP 马来西亚大奖赛。',
    eventTags: ['F1', 'MotoGP'],
    source: 'racetrackworld.com',
  ),
  EncyclopediaTrack(
    id: 'bathurst',
    nameCn: '巴瑟斯特全景山赛道',
    nameEn: 'Mount Panorama Circuit',
    region: '澳大利亚',
    location: '澳大利亚·新南威尔士巴瑟斯特',
    lengthKm: 6.213,
    totalCorners: 23,
    history: '1938 年首办赛事；原为环山观光道路，逆时针，'
        '爬升落差约 174 米。',
    events: '巴瑟斯特 1000、巴瑟斯特 12 小时耐力赛。',
    eventTags: ['其他赛事'],
    source: 'racetrackworld.com',
  ),
];

/// 全部图鉴条目：目录 14 条在前，新增 7 条在后，共 21 条。
const List<EncyclopediaTrack> encyclopediaTracks = [
  ..._catalogEntries,
  ..._newEntries,
];

/// 赛事筛选档位（图鉴页筛选条用，不做复杂筛选）。
const List<String> encyclopediaEventFilters = [
  '全部',
  'F1',
  'WEC',
  'MotoGP',
  '国内赛事',
  '其他赛事',
  '待核',
];

EncyclopediaTrack? encyclopediaTrackById(String? id) {
  if (id == null) return null;
  for (final t in encyclopediaTracks) {
    if (t.id == id) return t;
  }
  return null;
}

/// 赛道图鉴页 Widget（总协调接线见文末）。
///
/// [onSelectCatalogTrack]：仅目录 14 条可用，点“选为本次赛道”时
/// 回传对应的 [TrackInfo]，由总协调复用原有赛道选择流程；
/// 新增 7 条未接入赛道模式时不显示该按钮。不传时不显示按钮。
class TrackEncyclopediaPage extends StatefulWidget {
  final ValueChanged<TrackInfo>? onSelectCatalogTrack;

  const TrackEncyclopediaPage({
    super.key,
    this.onSelectCatalogTrack,
  });

  @override
  State<TrackEncyclopediaPage> createState() => _TrackEncyclopediaPageState();
}

class _TrackEncyclopediaPageState extends State<TrackEncyclopediaPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _region = '全部';
  String _event = '全部';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _regions {
    final seen = <String>{};
    final out = <String>['全部'];
    for (final t in encyclopediaTracks) {
      if (seen.add(t.region)) out.add(t.region);
    }
    return out;
  }

  List<EncyclopediaTrack> get _filtered {
    final q = _query.trim().toLowerCase();
    return encyclopediaTracks.where((t) {
      if (_region != '全部' && t.region != _region) return false;
      if (_event != '全部' && !t.eventTags.contains(_event)) return false;
      if (q.isEmpty) return true;
      return t.nameCn.toLowerCase().contains(q) ||
          t.nameEn.toLowerCase().contains(q) ||
          t.location.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('赛道图鉴'),
        backgroundColor: const Color(0xFF121212),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '搜索赛道名 / 位置',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('国家/地区',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _region,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      for (final r in _regions)
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: (v) => setState(() => _region = v ?? '全部'),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final e in encyclopediaEventFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e),
                      selected: _event == e,
                      selectedColor: accent.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: _event == e ? accent : Colors.white70,
                      ),
                      onSelected: (_) => setState(() => _event = e),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${encyclopediaTracks.length} 条，当前显示 ${list.length} 条',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: list.length,
              itemBuilder: (_, i) => _card(list[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(EncyclopediaTrack t) {
    final osm = trackOsmOutlines[t.id];
    final catalog = t.catalog;
    if (osm != null) {
      return SizedBox(
        width: 88,
        height: 60,
        child: OutlineDiagram(outline: osm, height: 60),
      );
    }
    if (catalog != null && t.hasOutline) {
      return SizedBox(
        width: 88,
        height: 60,
        child: TrackSchematicDiagram(
          track: catalog,
          height: 60,
          showCaption: false,
        ),
      );
    }
    return Container(
      width: 88,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: const Center(
        child: Text('轮廓待补',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ),
    );
  }

  Widget _card(EncyclopediaTrack t) {
    return DriveTrackCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrackDetailPage(
              track: t,
              onSelectCatalogTrack: widget.onSelectCatalogTrack,
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumbnail(t),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.nameCn,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(t.nameEn,
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _miniChip(t.location),
                    _miniChip(t.lengthLabel),
                    _miniChip(t.cornerLabel),
                  ],
                ),
                if (t.eventTags.isNotEmpty && t.eventTags.first != '待核')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      t.eventTags.join(' · '),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ],
      ),
    );
  }

  Widget _miniChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}

// ---------- 总协调接线（不执行，仅供参考） ----------
// 1) 抽屉菜单（main.dart，禁止本工人改）：旧文案 '赛道目录' +
//    旧回调 _openTrackCatalogSheet 改为推 TrackEncyclopediaPage(
//      onSelectCatalogTrack: (track) { 复用原有选赛道流程； })；
//    旧文案 '收藏' 改为连接的设备管理（设备中心入口，另见设备工人）。
// 2) 主题设置接线（main.dart 的 _openThemeSettings）：
//      ThemeSettingsPage(initial: 当前 ThemeChoice,
//        onAccentChanged: 存主题色,
//        vehicleMarkerInitial: appPrefs.vehicleSelection,
//        onVehicleMarkerChanged: (sel) => appPrefs.setVehicleSelection(sel))
//    并删除 SettingsHomePage 的 onOpenVehicle 接线（本轮设置首页
//    入口已删，入参由主协调收尾删除）。
// 3) 3D 记录页（recording_3d_map.dart，禁止本工人改）：见回执钩子，
//    用 markerPainterFor / markerFor 替换场景中心旧三角形车体。
// 4) 地图层（refined_map.dart）当前位置标：已在用 markerFor 时自动
//    获得新版俯视 3D 车标，无需改调用签名；未用 markerFor 的旧
//    固定圆点由主协调统一替换。
