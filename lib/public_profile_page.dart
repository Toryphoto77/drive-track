import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'card_style.dart';
import 'cloud_service.dart';
import 'models.dart';

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}年${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  if (m < 60) return '$m 分钟';
  return '${m ~/ 60} 小时 ${m % 60} 分钟';
}

/// 他人公开资料页：只展示对方公开的昵称 / 简介 / 头像与公开行程。
///
/// 不展示、不请求对方的私有行程（云端只返回 is_public = true 的行，
/// 私有行在 RLS 层就被挡掉）。没有关注、点赞、评论——云端没有
/// 对应表与接口，不做。
/// 打开方式：云端页 → 公开资料区，输入对方云端用户 ID；
/// 自己的公开资料页同样从云端页打开，用于自查公开后别人看到的样子。
class PublicProfilePage extends StatefulWidget {
  final String userId;
  const PublicProfilePage({super.key, required this.userId});

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  late final Future<PublicProfile?> _profileFuture;
  late final Future<List<CloudTripRow>> _tripsFuture;
  Future<Uint8List?>? _avatarFuture;

  @override
  void initState() {
    super.initState();
    final svc = CloudService.instance;
    _profileFuture = svc.fetchPublicProfile(widget.userId);
    _tripsFuture = svc.listPublicTrips(widget.userId);
  }

  String get _shortUserId {
    final id = widget.userId;
    return id.length <= 12 ? id : '${id.substring(0, 8)}…';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: const Text('公开资料')),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<PublicProfile?>(
              future: _profileFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const DriveTrackCard(
                    child: Row(children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('正在加载公开资料…'),
                    ]),
                  );
                }
                final profile = snap.data;
                if (profile == null) {
                  return DriveTrackCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('对方还没有设置公开资料',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('用户 ID · $_shortUserId',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        const Text('没设置过昵称、简介不代表没有公开行程，下方照常列出。',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  );
                }
                _avatarFuture ??= CloudService.instance
                    .downloadAvatar(profile);
                return DriveTrackCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // v1.5.2：与我的页资料卡同款个人主页式头行——头像 +
                      // 名字/ID 居中对齐，简介与扩展字段移到头行下方通栏。
                      Row(children: [
                        _avatar(profile, accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.nickname.isEmpty
                                    ? '未设置昵称'
                                    : profile.nickname,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text('用户 ID · $_shortUserId',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                        profile.bio.isEmpty ? '暂无简介' : profile.bio,
                        style: TextStyle(
                            color: profile.bio.isEmpty
                                ? Colors.white38
                                : Colors.white70,
                            fontSize: 13),
                      ),
                      // v1.5.1：公开资料扩展字段（只显示已填的，空的不占位）。
                      if (profile.gender.isNotEmpty ||
                          profile.birthday.isNotEmpty ||
                          profile.industry.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (profile.gender.isNotEmpty) profile.gender,
                            if (profile.birthday.isNotEmpty)
                              profile.birthday,
                            if (profile.industry.isNotEmpty)
                              profile.industry,
                          ].join(' · '),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                      if (profile.vehicleBrand.isNotEmpty ||
                          profile.vehicleModel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '座驾：${[
                            profile.vehicleBrand,
                            profile.vehicleModel
                          ].where((s) => s.isNotEmpty).join(' ')}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            const DriveTrackCard(
              child: Text(
                '公开说明：这里只显示对方设为公开的行程；对方的私有行程不会出现。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CloudTripRow>>(
              future: _tripsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows = snap.data ?? [];
                if (rows.isEmpty) {
                  return const DriveTrackCard(
                    child: Text('对方暂无公开行程',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 13)),
                  );
                }
                return Column(
                  children: [
                    for (final r in rows) ...[
                      DriveTrackCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PublicTripDetailPage(row: r),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Row(children: [
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${TripModeLabel.fromKey(r.mode).label}行程 · ${_fmtDate(r.startedAtMs)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${(r.distanceM / 1000).toStringAsFixed(1)} km · ${_fmtDuration(r.durationS)} · 评分 ${r.score} · ${r.source == 'device' ? '外接设备' : '手机'}',
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white38),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(PublicProfile profile, Color accent) {
    final fut = _avatarFuture;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 2),
      ),
      child: ClipOval(
        child: fut == null
            ? Container(
                color: Colors.black54,
                child: Icon(Icons.person, size: 32, color: accent),
              )
            : FutureBuilder<Uint8List?>(
                future: fut,
                builder: (context, snap) {
                  final bytes = snap.data;
                  if (bytes == null || bytes.isEmpty) {
                    return Container(
                      color: Colors.black54,
                      child:
                          Icon(Icons.person, size: 32, color: accent),
                    );
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
      ),
    );
  }
}

/// 公开行程查看页（只读）：对方公开行程的摘要与轨迹线。
///
/// 轨迹文件从公开桶下载；下载失败时只显示摘要与失败原因，不闪退。
/// 一种已知失败：对方在公开功能上线前上传的行程，文件还在私有桶里，
/// 他人读不到——页面会说明“对方重新上传后可见”，不要当成自己没网。
class PublicTripDetailPage extends StatefulWidget {
  final CloudTripRow row;
  const PublicTripDetailPage({super.key, required this.row});

  @override
  State<PublicTripDetailPage> createState() => _PublicTripDetailPageState();
}

class _PublicTripDetailPageState extends State<PublicTripDetailPage> {
  late final Future<Trip?> _tripFuture;

  @override
  void initState() {
    super.initState();
    _tripFuture = _loadTrip();
  }

  Future<Trip?> _loadTrip() async {
    final bytes =
        await CloudService.instance.downloadTripFile(widget.row);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return Trip.fromJson(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  void _retry() {
    setState(() {
      _tripFuture = _loadTrip();
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: const Text('公开行程')),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DriveTrackCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${TripModeLabel.fromKey(r.mode).label}行程',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('开始：${_fmtDate(r.startedAtMs)}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  Text('结束：${_fmtDate(r.endedAtMs)}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    '${(r.distanceM / 1000).toStringAsFixed(1)} km · ${_fmtDuration(r.durationS)} · 评分 ${r.score} · 最高 ${(r.maxSpeedKmh).toStringAsFixed(0)} km/h · ${r.source == 'device' ? '外接设备' : '手机'}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Trip?>(
              future: _tripFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final trip = snap.data;
                if (trip == null) {
                  return DriveTrackCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('轨迹文件打不开',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                          '摘要不受影响。这条行程可能是对方在公开功能上线前上传的，轨迹文件还在私有桶里，对方重新上传后可见；也可能是网络问题。',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                final points = trip.points;
                return DriveTrackCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('轨迹 · ${points.length} 个点',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      if (trip.startPlace.isNotEmpty ||
                          trip.endPlace.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          trip.startPlace.isNotEmpty &&
                                  trip.endPlace.isNotEmpty
                              ? '${trip.startPlace} → ${trip.endPlace}'
                              : (trip.startPlace.isNotEmpty
                                  ? '起点：${trip.startPlace}'
                                  : '终点：${trip.endPlace}'),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (points.length < 2)
                        const Text('轨迹点太少，画不出轨迹线。',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 12))
                      else
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: CustomPaint(
                            painter: _TripPolylinePainter(points),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 轨迹折线：经纬度等比缩放到画布内画线（示意轨迹形状，不加载地图瓦片）。
class _TripPolylinePainter extends CustomPainter {
  final List<TrackPoint> points;
  _TripPolylinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLon = points.first.lon;
    var maxLon = points.first.lon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final latSpan = (maxLat - minLat).abs();
    final lonSpan = (maxLon - minLon).abs();
    if (latSpan == 0 && lonSpan == 0) return;
    const pad = 12.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final scale = math.min(
      w / (lonSpan == 0 ? 1 : lonSpan),
      h / (latSpan == 0 ? 1 : latSpan),
    );
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = pad + (points[i].lon - minLon) * scale;
      // 纬度越大越靠上：y 翻转。
      final y = pad + (maxLat - points[i].lat) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = const Color(0xFFE10600)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
    // 起点绿点、终点红点。
    canvas.drawCircle(
        Offset(pad + (points.first.lon - minLon) * scale,
            pad + (maxLat - points.first.lat) * scale),
        5,
        Paint()..color = Colors.greenAccent);
    canvas.drawCircle(
        Offset(pad + (points.last.lon - minLon) * scale,
            pad + (maxLat - points.last.lat) * scale),
        5,
        Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(covariant _TripPolylinePainter oldDelegate) =>
      oldDelegate.points != points;
}
