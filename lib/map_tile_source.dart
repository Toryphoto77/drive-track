/// 地图源共用模块（v1.8.3）：用户可选「高德（国内，默认，GCJ-02）/
/// 谷歌（WGS-84）」。
///
/// 抽出枚举 + URL 构造 + 本机持久化，供 refined_map / recording_map_page
/// / 分析页卫星 / 3D 回放 / 设置页共用，不再各处硬编码高德。
///
/// 持久化不新增 pub 依赖：沿用仓库既有的 Native.getFilesDir() + JSON
/// 文件模式（见 track_settings_page.dart 的 TrackSettingsStore），
/// 存 Native 文件目录下的 map_tile_source.json。SharedPreferences 不在
/// 本仓依赖中（pubspec.yaml 未声明），故不引入。
///
/// 坐标口径：
/// - 高德国内栅格 / 卫星瓦片是 GCJ-02：叠加层（轨迹 / 中心线 / 车标）
///   必须先经 WGS-84 → GCJ-02 转换（见 amap_service.wgsToGcjLocal），
///   否则会与道路错位数百米；
/// - 谷歌瓦片是 WGS-84：直接用原始坐标，不做 GCJ 转换。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native.dart';

/// 用户可选的底图源。
enum MapTileSource { amap, google }

extension MapTileSourceLabel on MapTileSource {
  String get label => switch (this) {
        MapTileSource.amap => '高德',
        MapTileSource.google => '谷歌',
      };

  String get attribution => switch (this) {
        MapTileSource.amap => '© 高德地图',
        MapTileSource.google => '© Google',
      };

  /// 该源瓦片所用坐标系：高德国内瓦片为 GCJ-02，谷歌为 WGS-84。
  bool get usesGcj => this == MapTileSource.amap;
}

/// 路网瓦片 URL（街道记录 / RefinedMap 底图用）。
///
/// - 高德：深色影像路网 style=8，webrd01~04 主机按瓦片坐标轮转（与
///   amap_service.amapTileUrl 同口径，国内免 Key 公开栅格）；
/// - 谷歌：标准路网 lyrs=m，mt0~mt3 子域轮转。国内可能不可达，调用方
///   失败时须回落高德 / 占位，不崩。
String roadTileUrl(MapTileSource src, int z, int x, int y) {
  switch (src) {
    case MapTileSource.amap:
      final host = 'webrd0${(x + y) % 4 + 1}.is.autonavi.com';
      return 'https://$host/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=$x&y=$y&z=$z';
    case MapTileSource.google:
      final s = (x + y) & 3;
      return 'https://mt$s.google.com/vt/lyrs=m&x=$x&y=$y&z=$z';
  }
}

/// 卫星瓦片 URL（分析页 / 3D 回放底图用）。
///
/// - 高德：style=6 卫星影像，webst01~04 子域轮转（GCJ-02，z ≤ 17）；
/// - 谷歌：lyrs=s 卫星影像，mt0~mt3 子域轮转（WGS-84）。
String satelliteTileUrlFor(MapTileSource src, int z, int x, int y) {
  switch (src) {
    case MapTileSource.amap:
      final host = 1 + (x + y) % 4;
      return 'https://webst0$host.is.autonavi.com/appmaptile?style=6&x=$x&y=$y&z=$z';
    case MapTileSource.google:
      final s = (x + y) & 3;
      return 'https://mt$s.google.com/vt/lyrs=s&x=$x&y=$y&z=$z';
  }
}

/// 谷歌瓦片署名。
const String googleTileAttribution = '© Google';

/// 谷歌路网 / 卫星瓦片可用缩放范围（slippy-map 公开瓦片常规范围）。
const int googleTileMinZoom = 2;
const int googleTileMaxZoom = 19;

/// 高德卫星最大可用缩放（再高回落到旧图 / 空图），由 satellite_tiles.dart
/// 的 amapSatelliteMaxZoom 定义；这里给分析页 / 回放一个统一上限。
const int mapTileMaxZoom = 19;

/// 地图源持久化：Native.getFilesDir()/map_tile_source.json。
///
/// 单例 [mapTileSourceStore] 供各处读取与监听；设置页调用 [setSource]
/// 写入并广播，消费方（地图组件）在 initState 里 [load] + 监听即可，
/// 无需修改 main.dart 传参。
class MapTileSourceStore extends ChangeNotifier {
  static const String _fileName = 'map_tile_source.json';

  MapTileSource _source = MapTileSource.amap;
  bool _loaded = false;

  /// 当前生效的地图源（默认高德）。
  MapTileSource get source => _source;

  /// 是否已从本机读出过（首次读出后恒真）。
  bool get loaded => _loaded;

  /// 从本机读取用户选择；已读过则直接返回。读盘失败回落默认高德。
  Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/$_fileName');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final v = j['source'] as String?;
        _source =
            v == MapTileSource.google.name ? MapTileSource.google : MapTileSource.amap;
      }
    } catch (_) {
      _source = MapTileSource.amap;
    }
    _loaded = true;
    notifyListeners();
  }

  /// 设置并写入本机；立即广播，消费方随之切换底图。
  Future<void> setSource(MapTileSource s) async {
    if (_source == s && _loaded) {
      notifyListeners();
      return;
    }
    _source = s;
    _loaded = true;
    notifyListeners();
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/$_fileName')
          .writeAsString(jsonEncode({'source': s.name}));
    } catch (_) {
      // 写盘失败不阻塞界面；本次会话内选择仍生效。
    }
  }

  /// 测试用：重置到默认高德并清除加载态（不删文件，避免跨用例污染
  /// 由 setUp 的临时目录隔离保证）。
  void resetForTest() {
    _source = MapTileSource.amap;
    _loaded = false;
  }
}

/// 全局单例：设置页写、地图组件读。
final MapTileSourceStore mapTileSourceStore = MapTileSourceStore();
