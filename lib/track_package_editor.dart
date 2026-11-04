/// 赛道包地图编辑器（canvas 点选，不引入需联网瓦片的新依赖）。
///
/// - 画布用与详情轮廓同一投影（等距圆柱近似，保长宽比），点选后
///   显示经纬度读数；点选落起点 / 终点 / 龙门架 / 分段点 / 轮廓点。
/// - 轮廓闭合时（首尾同点），新轮廓点插在末点之前，保持闭合。
/// - 无中心线时画布无参照系，改走下方手动坐标落点（或先回库页
///   从行程导入轮廓）。
/// - 保存即本地生效（调用方持久化为用户改动，远端更新永不覆盖）；
///   编辑后核对状态一律回落为待核；弯角表本版编辑器暂不改动。

import 'package:flutter/material.dart';

import 'track_library.dart';
import 'track_timing.dart';

enum _EditTool { start, finish, gantry, sector, outline }

extension _EditToolLabel on _EditTool {
  String get label => switch (this) {
        _EditTool.start => '起点',
        _EditTool.finish => '终点',
        _EditTool.gantry => '龙门架',
        _EditTool.sector => '分段点',
        _EditTool.outline => '轮廓点',
      };
}

/// 赛道包编辑器。
class TrackPackageEditorPage extends StatefulWidget {
  final TrackPackage package;
  final ValueChanged<TrackPackage> onSave;

  const TrackPackageEditorPage({
    super.key,
    required this.package,
    required this.onSave,
  });

  @override
  State<TrackPackageEditorPage> createState() =>
      _TrackPackageEditorPageState();
}

class _TrackPackageEditorPageState extends State<TrackPackageEditorPage> {
  late List<GeoPoint> _centerline;
  late GeoPoint? _start;
  late GeoPoint? _finish;
  late GeoPoint? _gantry;
  late List<GeoPoint> _sectors;
  _EditTool _tool = _EditTool.start;
  GeoPoint? _lastTap;
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  _EditTool _manualTarget = _EditTool.start;

  @override
  void initState() {
    super.initState();
    _centerline = List.of(widget.package.centerline);
    _start = widget.package.start;
    _finish = widget.package.finish;
    _gantry = widget.package.gantry;
    _sectors = List.of(widget.package.sectorPoints);
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  List<GeoPoint> get _framePoints {
    if (_centerline.isNotEmpty) return _centerline;
    return [
      if (_start != null) _start!,
      if (_finish != null) _finish!,
      if (_gantry != null) _gantry!,
      ..._sectors,
    ];
  }

  void _onCanvasTap(Offset pos, Size size) {
    final frame = _framePoints;
    if (frame.isEmpty) return;
    final proj = LatLonProjection(frame);
    final p = proj.unproject(pos.dx, pos.dy, size.width, size.height);
    if (p.lat < -90 || p.lat > 90 || p.lon < -180 || p.lon > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('落点超出经纬度范围，请点在赛道区域内')),
      );
      return;
    }
    setState(() {
      _lastTap = p;
      switch (_tool) {
        case _EditTool.start:
          _start = p;
        case _EditTool.finish:
          _finish = p;
        case _EditTool.gantry:
          _gantry = p;
        case _EditTool.sector:
          _sectors.add(p);
        case _EditTool.outline:
          if (_centerline.length >= 2 &&
              _centerline.first.lat == _centerline.last.lat &&
              _centerline.first.lon == _centerline.last.lon) {
            // 闭合回路：新点插在末点之前，保持首尾重合。
            _centerline.insert(_centerline.length - 1, p);
          } else {
            _centerline.add(p);
          }
      }
    });
  }

  void _manualDrop() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null || lon == null || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('经纬度格式不对（纬度 -90~90，经度 -180~180）')),
      );
      return;
    }
    setState(() {
      _lastTap = GeoPoint(lat, lon);
      switch (_manualTarget) {
        case _EditTool.start:
          _start = GeoPoint(lat, lon);
        case _EditTool.finish:
          _finish = GeoPoint(lat, lon);
        case _EditTool.gantry:
          _gantry = GeoPoint(lat, lon);
        case _EditTool.sector:
          _sectors.add(GeoPoint(lat, lon));
        case _EditTool.outline:
          _centerline.add(GeoPoint(lat, lon));
      }
    });
  }

  void _save() {
    final lengthM = _centerline.length >= 2
        ? polylineLengthM(_centerline).round()
        : widget.package.lengthM;
    final updated = widget.package.copyWith(
      centerline: _centerline,
      start: _start,
      finish: _finish,
      gantry: _gantry,
      sectorPoints: _sectors,
      lengthM: lengthM,
      verification: TrackPackageVerification.pending,
      verificationNote: '用户编辑，待核对',
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _framePoints;
    final lengthLabel = _centerline.length >= 2
        ? '${(polylineLengthM(_centerline) / 1000).toStringAsFixed(3)} km'
        : widget.package.lengthLabel;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text('编辑：${widget.package.nameCn}'),
        backgroundColor: const Color(0xFF121212),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '先选工具，再点画布落点。保存后本地生效；编辑后核对状态回落为待核；弯角表本版编辑器暂不改动。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _EditTool.values.map((t) {
                final selected = _tool == t;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _tool = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (frame.isEmpty)
              Container(
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '暂无坐标：请先在库页从行程导入轮廓，或在下方手动输入坐标落点。',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, 320);
                  return GestureDetector(
                    onTapUp: (d) => _onCanvasTap(d.localPosition, size),
                    child: CustomPaint(
                      size: size,
                      painter: _EditorPainter(
                        centerline: _centerline,
                        start: _start,
                        finish: _finish,
                        gantry: _gantry,
                        sectors: _sectors,
                        lastTap: _lastTap,
                        frame: frame,
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
            Text(
              '轮廓 ${_centerline.length} 点 · 分段 ${_sectors.length} 点 · 当前长度 $lengthLabel',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (_lastTap != null)
              Text(
                '上次落点：${_lastTap!.lat.toStringAsFixed(5)}, ${_lastTap!.lon.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _centerline.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (_centerline.length >= 2 &&
                                _centerline.first.lat ==
                                        _centerline.last.lat &&
                                _centerline.first.lon ==
                                        _centerline.last.lon &&
                                _centerline.length > 2) {
                              _centerline.removeAt(_centerline.length - 2);
                            } else {
                              _centerline.removeLast();
                            }
                          });
                        },
                  child: const Text('删除轮廓末点'),
                ),
                OutlinedButton(
                  onPressed: _sectors.isEmpty
                      ? null
                      : () => setState(() => _sectors.removeLast()),
                  child: const Text('删除末分段点'),
                ),
                OutlinedButton(
                  onPressed: _centerline.isEmpty
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清空轮廓？'),
                              content: const Text(
                                '轮廓点列将全部删除（起点 / 终点 / 分段点不受影响），保存后生效。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('清空'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            setState(() => _centerline.clear());
                          }
                        },
                  child: const Text('清空轮廓'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '手动输入坐标落点',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                DropdownButton<_EditTool>(
                  value: _manualTarget,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white),
                  items: _EditTool.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.label),
                          ))
                      .toList(),
                  onChanged: (t) {
                    if (t != null) setState(() => _manualTarget = t);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '纬度',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lonCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '经度',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _manualDrop,
                  child: const Text('落点'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;
  final GeoPoint? gantry;
  final List<GeoPoint> sectors;
  final GeoPoint? lastTap;
  final List<GeoPoint> frame;

  _EditorPainter({
    required this.centerline,
    required this.start,
    required this.finish,
    required this.gantry,
    required this.sectors,
    required this.lastTap,
    required this.frame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0A0A0A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(12),
      ),
      bg,
    );
    final proj = LatLonProjection(frame);
    Offset pt(GeoPoint p) {
      final (x, y) = proj.project(p, size.width, size.height);
      return Offset(x, y);
    }

    if (centerline.length >= 2) {
      final path = Path()..moveTo(pt(centerline.first).dx, pt(centerline.first).dy);
      for (var i = 1; i < centerline.length; i++) {
        final o = pt(centerline[i]);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFE10600)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }
    void dot(GeoPoint p, Color color, String label) {
      final o = pt(p);
      canvas.drawCircle(o, 9, Paint()..color = color);
      canvas.drawCircle(
        o,
        9,
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }

    for (var i = 0; i < sectors.length; i++) {
      dot(sectors[i], Colors.blue, 'S${i + 1}');
    }
    if (gantry != null) dot(gantry!, Colors.orange, '门');
    if (finish != null) dot(finish!, Colors.black, '终');
    if (start != null) dot(start!, Colors.green, '起');
    if (lastTap != null) {
      final o = pt(lastTap!);
      canvas.drawCircle(
        o,
        5,
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) =>
      old.centerline != centerline ||
      old.start != start ||
      old.finish != finish ||
      old.gantry != gantry ||
      old.sectors != sectors ||
      old.lastTap != lastTap;
}
