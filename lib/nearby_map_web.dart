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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'amap_service.dart';

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
    required this.markers,
    this.onTapMarker,
  });

  /// 地图中心（WGS-84）。
  final double centerLat;
  final double centerLon;
  final double zoom;
  final List<NearbyMapMarker> markers;

  /// 点地图上的胶囊标注时回调对应序号。
  final ValueChanged<int>? onTapMarker;

  @override
  State<NearbyDarkMap> createState() => _NearbyDarkMapState();
}

class _NearbyDarkMapState extends State<NearbyDarkMap> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _failed = false;
  String _lastPayload = '';

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

  void _sync() {
    if (!_ready || !mounted) return;
    final payload = _payload();
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    _controller.runJavaScript(payload);
  }

  String _payload() {
    final c = wgsToGcjLocal(widget.centerLat, widget.centerLon);
    return 'setView(${c.$1.toStringAsFixed(6)},'
        '${c.$2.toStringAsFixed(6)},${widget.zoom.toStringAsFixed(2)});'
        'setMarks(${_markersJson()});';
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
