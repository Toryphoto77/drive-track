/// 附近的赛道：深色交互底图（高德 JS API）。
///
/// 为什么不沿用高德静态图：`v3/staticmap` 没有任何深色样式参数（只有
/// key/location/zoom/size/scale/markers/labels/paths/traffic），做不出
/// 参考图那种「近黑背景 + 细路网 + 纯黑水面 + 无 POI」的观感。
/// 高德官方的暗色样式 `amap://styles/dark` 只在 JS API / 原生 SDK 里
/// 开放，这里用 WebView 承载 JS API，换取 1:1 的深色矢量底图。
///
/// 配置（构建时 --dart-define 注入，缺省即不可用 → 页面回落旧版静态图）：
/// - AMAP_JS_KEY：高德控制台「Web端(JS API)」类型的 Key，与现有
///   AMAP_KEY（Web 服务）不是同一种，不能混用；
/// - AMAP_JS_SECURITY_CODE：与该 Key 成对的安全密钥（2021-12 之后
///   新建的 JS Key 必须带，否则接口返回 INVALID_USER_SCODE）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'amap_service.dart';
import 'models.dart';

/// 高德「Web端(JS API)」Key。
const String amapJsKey = String.fromEnvironment('AMAP_JS_KEY', defaultValue: '');

/// 高德 JS API 2.0 安全密钥（与 [amapJsKey] 成对）。
const String amapJsSecurityCode =
    String.fromEnvironment('AMAP_JS_SECURITY_CODE', defaultValue: '');

/// 底图是否可用（Key 未注入时整页回落旧版静态图，不展示空 WebView）。
bool get nearbyMapAvailable => amapJsKey.isNotEmpty;

/// 暗色样式名；`amap://styles/dark` 最接近参考图，改这里可换
/// darkblue / grey 等官方样式。
const String kNearbyMapStyle =
    String.fromEnvironment('AMAP_MAP_STYLE', defaultValue: 'amap://styles/dark');

/// 地图上的一个赛道标注（坐标为 WGS-84，内部统一转 GCJ-02）。
class NearbyMapMarker {
  const NearbyMapMarker({
    required this.index,
    required this.name,
    required this.lat,
    required this.lon,
    this.selected = false,
  });

  final int index;
  final String name;
  final double lat;
  final double lon;
  final bool selected;
}

class NearbyDarkMap extends StatefulWidget {
  const NearbyDarkMap({
    super.key,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    this.markers = const [],
    this.onTapMarker,
    this.recordingTrail = const [],
    this.vehicleLat,
    this.vehicleLon,
    this.vehicleHeadingDeg = 0,
    this.follow = false,
    this.headingUp = false,
  });

  /// 地图中心（WGS-84）。
  final double centerLat;
  final double centerLon;
  final double zoom;
  final List<NearbyMapMarker> markers;

  /// 点地图上的胶囊标注时回调对应序号。
  final ValueChanged<int>? onTapMarker;

  // ---- 记录模式（可选）----
  // 带上这三个参数即进入“记录中”形态：已跑轨迹 + 车标 + 跟随，
  // 底图仍是附近赛道那套深色路网，不再额外维护第二套地图观感。

  /// 已跑轨迹（WGS-84，直接传记录器的点，避免每次重建都整表拷贝）。
  final List<TrackPoint> recordingTrail;

  /// 车辆当前位置（WGS-84）；为空时只按 [centerLat]/[centerLon] 定位。
  final double? vehicleLat;
  final double? vehicleLon;

  /// 车头朝向（度，0 = 正北，顺时针）。只转车标，不依赖底图旋转。
  final double vehicleHeadingDeg;

  /// 是否让车辆保持在地图中心（记录中为 true）。
  final bool follow;

  /// 车头朝上：尝试旋转底图；JS API 在部分版本/模式下不支持旋转，
  /// JS 侧已 try/catch 兜底，失败时退回北朝上，不影响使用。
  final bool headingUp;

  @override
  State<NearbyDarkMap> createState() => _NearbyDarkMapState();
}

class _NearbyDarkMapState extends State<NearbyDarkMap> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _failed = false;
  String _lastPayload = '';
  String _lastMarks = '';
  String _lastTrailKey = '';

  /// 记录模式下轨迹点 25 Hz 刷新，WebView 重绘跟不上；统一压到
  /// 500 ms 一次（2 Hz），肉眼仍连续，低端机也不会卡顿。
  static const int _kSyncIntervalMs = 500;
  int _lastPushMs = 0;
  Timer? _pushTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0C))
      ..addJavaScriptChannel(
        'dtMap',
        onMessageReceived: (msg) {
          final n = int.tryParse(msg.message);
          if (n != null) widget.onTapMarker?.call(n);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _ready = true);
            _lastPayload = '';
            _lastMarks = '';
            _lastTrailKey = '';
            _sync();
          },
          onWebResourceError: (err) {
            // 只有主文档失败才认为地图挂了；子资源（瓦片/图标）失败
            // 不影响框架渲染，交给高德自己降级。
            if (err.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() => _failed = true);
          },
        ),
      )
      ..loadHtmlString(_buildHtml(), baseUrl: 'https://webapi.amap.com');
  }

  @override
  void didUpdateWidget(covariant NearbyDarkMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    super.dispose();
  }

  void _sync() {
    if (!_ready || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final wait = _kSyncIntervalMs - (now - _lastPushMs);
    if (wait > 0) {
      _pushTimer ??= Timer(Duration(milliseconds: wait), () {
        _pushTimer = null;
        _push();
      });
      return;
    }
    _push();
  }

  void _push() {
    if (!_ready || !mounted) return;
    _lastPushMs = DateTime.now().millisecondsSinceEpoch;
    final payload = _payload();
    if (payload.isEmpty || payload == _lastPayload) return;
    _lastPayload = payload;
    _controller.runJavaScript(payload);
  }

  String _payload() {
    final parts = <String>[];
    final marks = _markersJson();
    if (marks != _lastMarks) {
      _lastMarks = marks;
      parts.add('setMarks($marks);');
    }
    final vLat = widget.vehicleLat;
    final vLon = widget.vehicleLon;
    if (vLat != null && vLon != null) {
      final v = wgsToGcjLocal(vLat, vLon);
      parts.add('setVehicle(${v.$1.toStringAsFixed(6)},'
          '${v.$2.toStringAsFixed(6)},'
          '${widget.vehicleHeadingDeg.toStringAsFixed(1)},'
          '${widget.follow},${widget.headingUp},'
          '${widget.zoom.toStringAsFixed(2)});');
    } else {
      final c = wgsToGcjLocal(widget.centerLat, widget.centerLon);
      parts.add('setView(${c.$1.toStringAsFixed(6)},'
          '${c.$2.toStringAsFixed(6)},${widget.zoom.toStringAsFixed(2)});');
    }
    final trail = _trailJson();
    if (trail != null) parts.add('setTrail($trail);');
    return parts.join('');
  }

  /// 轨迹按屏幕精度抽稀到 ≤600 点再下发：25 Hz 原始点整段重发会
  /// 让 WebView 每次同步都解析十几万字符；抽稀后视觉几乎无差别。
  String? _trailJson() {
    final pts = widget.recordingTrail;
    if (pts.isEmpty) {
      if (_lastTrailKey.isEmpty) return null;
      _lastTrailKey = '';
      return '[]';
    }
    final step = (pts.length / 600).ceil();
    final buf = <String>[];
    for (var i = 0; i < pts.length; i += step) {
      final g = wgsToGcjLocal(pts[i].lat, pts[i].lon);
      buf.add('[${g.$2.toStringAsFixed(6)},${g.$1.toStringAsFixed(6)}]');
    }
    if ((pts.length - 1) % step != 0) {
      final g = wgsToGcjLocal(pts.last.lat, pts.last.lon);
      buf.add('[${g.$2.toStringAsFixed(6)},${g.$1.toStringAsFixed(6)}]');
    }
    final key = '${pts.length}:${buf.length}:${buf.last}';
    if (key == _lastTrailKey) return null;
    _lastTrailKey = key;
    return '[${buf.join(',')}]';
  }

  String _markersJson() {
    final list = <Map<String, Object>>[];
    for (final m in widget.markers) {
      final g = wgsToGcjLocal(m.lat, m.lon);
      list.add({
        'n': m.index,
        'name': m.name,
        'lat': g.$1,
        'lon': g.$2,
        'sel': m.selected,
      });
    }
    return jsonEncode(list);
  }

  String _buildHtml() {
    final c = wgsToGcjLocal(widget.centerLat, widget.centerLon);
    final sec = amapJsSecurityCode.isEmpty
        ? '{}'
        : jsonEncode({'securityJsCode': amapJsSecurityCode});
    final style = jsonEncode(kNearbyMapStyle);
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
  html,body{margin:0;padding:0;width:100%;height:100%;background:#0b0b0c;overflow:hidden}
  #map{width:100%;height:100%}
  .pin{display:flex;align-items:center;gap:6px;background:#fff;color:#111;
       border-radius:14px;padding:4px 10px 4px 4px;box-shadow:0 2px 8px rgba(0,0,0,.6);
       font:600 12px/1.15 -apple-system,"PingFang SC","Noto Sans CJK SC",sans-serif;
       white-space:nowrap;max-width:190px;overflow:hidden}
  .pin .nm{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .pin .n{flex:0 0 auto;width:17px;height:17px;border-radius:5px;background:#111;color:#fff;
          display:flex;align-items:center;justify-content:center;font-size:10px}
  .pin.sel{background:#111;color:#fff}
  .pin.sel .n{background:#fff;color:#111}
  .car{width:24px;height:24px;border-radius:50%;background:#E10600;
       border:2.5px solid #fff;box-shadow:0 0 10px rgba(225,6,0,.85);
       display:flex;align-items:center;justify-content:center;box-sizing:border-box}
  .car .arw{width:0;height:0;border-left:5px solid transparent;
             border-right:5px solid transparent;border-bottom:9px solid #fff;
             transform-origin:50% 50%;transition:transform .18s linear}
</style>
<script>window._AMapSecurityConfig = { securityJsCode: $sec };</script>
<script src="https://webapi.amap.com/maps?v=2.0&key=$amapJsKey"></script>
</head>
<body>
<div id="map"></div>
<script>
  var map = new AMap.Map('map', {
    zoom: ${widget.zoom.toStringAsFixed(2)},
    center: [${c.$2.toStringAsFixed(6)}, ${c.$1.toStringAsFixed(6)}],
    mapStyle: $style,
    viewMode: '2D',
    // 只要背景 / 道路 / 建筑：去掉 'point' 就没有 POI 点，配合
    // showLabel:false 再把地名注记一并关掉，只剩路网和水域。
    features: ['bg', 'road', 'building'],
    showLabel: false,
    resizeEnable: true,
    zooms: [4, 18]
  });
  var marks = [];
  function setMarks(list) {
    if (marks.length) { map.remove(marks); marks = []; }
    list.forEach(function(m) {
      var d = document.createElement('div');
      d.className = 'pin' + (m.sel ? ' sel' : '');
      var n = document.createElement('span');
      n.className = 'n';
      n.textContent = m.n;
      var t = document.createElement('span');
      t.className = 'nm';
      t.textContent = m.name;
      d.appendChild(n);
      d.appendChild(t);
      var mk = new AMap.Marker({
        position: [m.lon, m.lat],
        content: d,
        anchor: 'center',
        zIndex: 100 + m.n
      });
      mk.on('click', function() { dtMap.postMessage(String(m.n)); });
      mk.setMap(map);
      marks.push(mk);
    });
  }
  function setView(lat, lon, z) { map.setZoomAndCenter(z, [lon, lat]); }

  // ---- 记录中：已跑轨迹 ----
  var rideLine = null;
  function setTrail(list) {
    if (!list || !list.length) {
      if (rideLine) { rideLine.setPath([]); }
      return;
    }
    if (!rideLine) {
      rideLine = new AMap.Polyline({
        path: list,
        strokeColor: '#FF3B30',
        strokeWeight: 5,
        strokeOpacity: 0.95,
        lineJoin: 'round',
        lineCap: 'round',
        showDir: false,
        zIndex: 90
      });
      rideLine.setMap(map);
    } else {
      rideLine.setPath(list);
    }
  }

  // ---- 记录中：车标 + 跟随 + 车头朝上 ----
  var carMarker = null;
  var carArrow = null;
  function setVehicle(lat, lon, heading, follow, headingUp, z) {
    if (!carMarker) {
      carArrow = document.createElement('div');
      carArrow.className = 'arw';
      var body = document.createElement('div');
      body.className = 'car';
      body.appendChild(carArrow);
      carMarker = new AMap.Marker({
        position: [lon, lat],
        content: body,
        anchor: 'center',
        zIndex: 200
      });
      carMarker.setMap(map);
    }
    carMarker.setPosition([lon, lat]);
    carArrow.style.transform = 'rotate(' + heading + 'deg)';
    if (follow) map.setZoomAndCenter(z, [lon, lat]);
    // 底图旋转在 2D / 部分版本不支持，失败时保持北朝上即可。
    try {
      if (map.setRotation) map.setRotation(headingUp ? -heading : 0);
    } catch (e) {}
  }
  setMarks(${_markersJson()});
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: const Color(0xFF0B0B0C),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Text(
          '地图加载失败：检查网络后重新进入本页',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    return WebViewWidget(controller: _controller);
  }
}
