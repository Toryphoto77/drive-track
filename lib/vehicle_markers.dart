import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'models.dart';
import 'perspective_projection.dart';

/// 地图车标选择与自绘模型（v0.1.4 外壳 UI 分工；v1.0.2 重画）。
///
/// v1.0.2 重画说明：三类车标一律改为俯视 3D 画法——车头朝上
/// （headingDeg = 0 时朝北），先画偏移投影阴影，再画车体，
/// 最后画车身高光条与前后灯；透视感来自车头收窄 + 阴影偏移，
/// 不是贴图。全部仍为自绘矢量路径，不用任何图片资源、
/// 不用 AI 生成图、不画品牌 Logo；摩托品牌名仍仅作风格区分。
/// v1.2.0 立体化：双层地面阴影（宽淡投影 + 紧贴的深色接触影，
/// 地面贴合感，类似导航开始后的车标）+ 车体下移暗色挤出层
/// （侧壁厚度）+ 顶部亮面与轮毂高光；朝向仍由 headingDeg
/// 旋转（调用方外层旋转时传 0，避免双重旋转）；markerFor /
/// markerPainterFor 签名与调用约定不变。
/// v1.3.8 精细化重做：同一俯视 3D 风格上加细——汽车钣金缝线 /
/// 后视镜 / 格栅与保险杠 / 玻璃渐变反光 / 轮胎侧壁与辐条 /
/// 灯带与日行灯 / 车身纵向明暗渐变（取代大面积平铺白光）；
/// 摩托油箱·整流罩·座垫·尾部层次 / 车把把套与后视镜 /
/// 前后轮辐条与前叉；自行车车架三角管壁粗细区分 / 前后轮
/// 辐条 / 三种车把与座垫造型。细线一律设 1px 下限（hair），
/// 48px 及以上才叠加最细装饰（格栅纹、天窗），保证 36px
/// 地图尺寸下轮廓、灯、轮毂仍可辨认、不堆成噪点。
///
/// 品牌名仅作风格区分，非官方授权模型：摩托四种风格的命名
/// （杜卡迪 / 雅马哈 / 本田 / 川崎）只表示“这种外观风格”，
/// 画笔只画自绘矢量轮廓 + 品牌色点缀，绝不画官方 Logo、
/// 不贴官方图片、不声称品牌授权。选择子页里同样有这句声明。
/// 汽车与自行车不涉及品牌名，按车体 / 用途区分。
///
/// 下一版·第 3 条（3D 车标）：
/// 结论先写明——真 3D 模型实时渲染不可行：离线构建拿不到新的
/// 3D 模型渲染包，零第三方依赖的铁律下加不进来；多角度预渲染图
/// 同样不可行（没有模型库、没有连续角度渲染管线）。可行的最高档
/// 是俯仰透视伪 3D：街道记录主视角的俯仰角已可调（见
/// perspective_projection.dart，默认 65° 与旧值一致），车标画笔
/// 本身新增 pitchDeg——角度越大，车体纵向压扁越狠、侧壁挤出层
/// 越厚、地面阴影拉得越长，接近高德导航 3D 视角的感觉；但车标
/// 仍是 CustomPainter 矢量自绘，不是真 3D 模型，不要假装是。
/// 注意分工：记录页画笔收到的是不透明画笔，场景级压扁由记录页
/// 外层 canvas 变换做（见 recording_3d_map.dart）；画笔级
/// pitchDeg 供 markerFor / 选择页大预览直接用，两处不要叠加
/// （同一车标只压扁一次）。

// ------------------------------------------------------------------
// 风格枚举（styleKey 即持久化存的值，改名会断旧存档，勿随意改）
// ------------------------------------------------------------------

/// 汽车车体：轿车 / 跑车 / SUV / 皮卡 / 越野车。
/// 只追加、不改名、不调顺序：sedan / sport 仍是前两位，旧存档
/// 的 'sedan' / 'sport' 不受影响；新值追加在后。
enum CarMarkerStyle { sedan, sport, suv, pickup, offroad }

extension CarMarkerStyleLabel on CarMarkerStyle {
  String get key => name;
  String get label => switch (this) {
        CarMarkerStyle.sedan => '轿车',
        CarMarkerStyle.sport => '跑车',
        CarMarkerStyle.suv => 'SUV',
        CarMarkerStyle.pickup => '皮卡',
        CarMarkerStyle.offroad => '越野车',
      };

  /// 选择页副文案：一眼区分的造型要点（只描述本页画出的轮廓）。
  String get blurb => switch (this) {
        CarMarkerStyle.sedan => '三厢 · 修长车顶',
        CarMarkerStyle.sport => '低趴 · 尾翼',
        CarMarkerStyle.suv => '高车身 · 方正轮廓 · 行李架',
        CarMarkerStyle.pickup => '驾驶舱 + 开放货斗',
        CarMarkerStyle.offroad => '粗轮胎 · 行李架 · 前杠',
      };
  static CarMarkerStyle fromKey(String? k) => CarMarkerStyle.values
      .firstWhere((e) => e.name == k, orElse: () => CarMarkerStyle.sedan);
}

/// 摩托风格：名字仅作风格区分，非官方授权模型。
enum MotoMarkerStyle { ducati, yamaha, honda, kawasaki }

extension MotoMarkerStyleLabel on MotoMarkerStyle {
  String get key => name;
  String get label => switch (this) {
        MotoMarkerStyle.ducati => '杜卡迪风格',
        MotoMarkerStyle.yamaha => '雅马哈风格',
        MotoMarkerStyle.honda => '本田风格',
        MotoMarkerStyle.kawasaki => '川崎风格',
      };

  /// 品牌色点缀（自设近似色，仅用于车身一小块点缀色，非官方配色表）。
  Color get accent => switch (this) {
        MotoMarkerStyle.ducati => const Color(0xFFCC0000),
        MotoMarkerStyle.yamaha => const Color(0xFF0033CC),
        MotoMarkerStyle.honda => const Color(0xFFCC0000),
        MotoMarkerStyle.kawasaki => const Color(0xFF00AA44),
      };

  /// 选择页副文案：只描述本页画出的轮廓。
  String get blurb => switch (this) {
        MotoMarkerStyle.ducati => '仿赛 · 宽整流罩',
        MotoMarkerStyle.yamaha => '仿赛 · 均衡车身',
        MotoMarkerStyle.honda => '街车 · 窄车身',
        MotoMarkerStyle.kawasaki => '仿赛 · 尖鼻',
      };
  static MotoMarkerStyle fromKey(String? k) => MotoMarkerStyle.values
      .firstWhere((e) => e.name == k, orElse: () => MotoMarkerStyle.ducati);
}

/// 自行车轮廓：公路 / 山地 / 城市。
enum BikeMarkerStyle { road, mountain, city }

extension BikeMarkerStyleLabel on BikeMarkerStyle {
  String get key => name;
  String get label => switch (this) {
        BikeMarkerStyle.road => '公路',
        BikeMarkerStyle.mountain => '山地',
        BikeMarkerStyle.city => '城市',
      };

  /// 选择页副文案：只描述本页画出的轮廓。
  String get blurb => switch (this) {
        BikeMarkerStyle.road => '弯把 · 细胎',
        BikeMarkerStyle.mountain => '宽胎 · 平把',
        BikeMarkerStyle.city => '上翘把 · 通勤',
      };
  static BikeMarkerStyle fromKey(String? k) => BikeMarkerStyle.values
      .firstWhere((e) => e.name == k, orElse: () => BikeMarkerStyle.road);
}

// ------------------------------------------------------------------
// 选择模型与持久化键（总协调接入 store / AppPrefs 时照此键名写）
// ------------------------------------------------------------------
//
// 建议写进现有 profile.json（与 AppPrefs 同一文件，不另起文件）：
//   'vehicleMarkerCar'   : 'sedan' | 'sport' | 'suv' | 'pickup' |
//                            'offroad'                  （默认 'sedan'）
//   'vehicleMarkerMoto'  : 'ducati'|'yamaha'|'honda'|'kawasaki'
//                                                          （默认 'ducati'）
//   'vehicleMarkerBike'  : 'road' | 'mountain' | 'city' （默认 'road'）
// 旧存档缺失任一键时按上述默认值回填，不崩溃、不编造已选记录。

/// 三模式各自的车标选择（一次只对当前模式生效，另两模式各自保留）。
class VehicleMarkerSelection {
  final CarMarkerStyle car;
  final MotoMarkerStyle moto;
  final BikeMarkerStyle bike;

  const VehicleMarkerSelection({
    this.car = CarMarkerStyle.sedan,
    this.moto = MotoMarkerStyle.ducati,
    this.bike = BikeMarkerStyle.road,
  });

  /// 按当前出行模式取 styleKey（给地图层用）。
  String keyFor(TripMode mode) => switch (mode) {
        TripMode.car => car.key,
        TripMode.moto => moto.key,
        TripMode.bike => bike.key,
      };

  Map<String, dynamic> toJson() => {
        'vehicleMarkerCar': car.key,
        'vehicleMarkerMoto': moto.key,
        'vehicleMarkerBike': bike.key,
      };

  static VehicleMarkerSelection fromJson(Map<String, dynamic> j) =>
      VehicleMarkerSelection(
        car: CarMarkerStyleLabel.fromKey(j['vehicleMarkerCar'] as String?),
        moto: MotoMarkerStyleLabel.fromKey(j['vehicleMarkerMoto'] as String?),
        bike: BikeMarkerStyleLabel.fromKey(j['vehicleMarkerBike'] as String?),
      );

  VehicleMarkerSelection copyWith({
    CarMarkerStyle? car,
    MotoMarkerStyle? moto,
    BikeMarkerStyle? bike,
  }) =>
      VehicleMarkerSelection(
        car: car ?? this.car,
        moto: moto ?? this.moto,
        bike: bike ?? this.bike,
      );
}

/// 当前模式下可选的风格名（给选择页列表用，不含画笔）。
List<String> markerOptionsFor(TripMode mode) => switch (mode) {
      TripMode.car => CarMarkerStyle.values.map((e) => e.label).toList(),
      TripMode.moto => MotoMarkerStyle.values.map((e) => e.label).toList(),
      TripMode.bike => BikeMarkerStyle.values.map((e) => e.label).toList(),
    };

// ------------------------------------------------------------------
// 自绘画笔：全部矢量路径，不用任何图片资源，更不用官方 Logo
// ------------------------------------------------------------------

class VehicleMarkerPainter extends CustomPainter {
  final TripMode mode;
  final String styleKey;

  /// 车体主色；不传时按模式取默认值（汽车深灰 / 摩托黑 / 自行车灰）。
  final Color? bodyColor;

  /// 朝向（度，0 = 正北朝上）；地图层按 GPS 航向传入，静态预览传 0。
  final double headingDeg;

  /// 俯仰角（度，0 = 俯视，不压扁；默认 0，保持旧外观）。
  /// 街道 3D 视角用 35 / 50 / 65°：角度越大，车体纵向压扁越狠、
  /// 侧壁挤出越厚、地面阴影拉得越长（见 perspectiveMarkerScale
  /// 与 perspectiveExtrudeFactor，与透视投影同一套数）。
  /// 注意：记录页场景级压扁由外层 canvas 做，传给记录页的画笔
  /// 保持 pitchDeg = 0，不要两处叠加；本字段供 markerFor 直画
  /// （如选择页大预览）与将来调用方直传时用。
  final double pitchDeg;

  const VehicleMarkerPainter({
    required this.mode,
    required this.styleKey,
    this.bodyColor,
    this.headingDeg = 0,
    this.pitchDeg = 0,
  });

  /// 俯仰强度 0..1.2（0 = 俯视）：挤出与阴影据此加深。
  double get _pitchT => pitchDeg <= 0
      ? 0
      : (clampPitchDeg(pitchDeg) / perspectiveDefaultPitchDeg)
          .clamp(0.0, 1.2);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(headingDeg * math.pi / 180);
    if (pitchDeg > 0) {
      // 绕车体中心压扁：纵向压短、横向微张，贴合俯仰透视地面。
      final (sx, sy) = perspectiveMarkerScale(pitchDeg);
      canvas.scale(sx, sy);
    }
    canvas.translate(-cx, -cy);
    switch (mode) {
      case TripMode.car:
        _paintCar(canvas, size, CarMarkerStyleLabel.fromKey(styleKey));
      case TripMode.moto:
        _paintMoto(canvas, size, MotoMarkerStyleLabel.fromKey(styleKey));
      case TripMode.bike:
        _paintBike(canvas, size, BikeMarkerStyleLabel.fromKey(styleKey));
    }
    canvas.restore();
  }

  /// v1.2.0 双层地面阴影：外层宽淡投影（离地高度感）+ 内层
  /// 紧贴车体的深色接触影（地面贴合感），两者都向右下偏移，
  /// 光源方向一致，车标不飘。俯仰角越大，阴影向右下拖得越长
  /// （按 _pitchT 拉伸偏移与宽度，模拟低角度光照下的拖影）。
  void _shadow(Canvas canvas, Size size, double wFrac, double hFrac) {
    final w = size.width, h = size.height;
    final stretch = 1 + 0.6 * _pitchT;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5 + w * 0.05 * stretch, h * 0.5 + h * 0.07 * stretch),
        width: w * (wFrac + 0.10),
        height: h * (hFrac + 0.04),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5 + w * 0.02 * stretch, h * 0.5 + h * 0.03 * stretch),
        width: w * wFrac,
        height: h * hFrac,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.50),
    );
  }

  /// v1.2.0 侧壁挤出层：把 [path] 下移 [dy] 以暗色先画一遍，
  /// 再画本体，车体即有厚度而非一片平色；dy 很小，不改轮廓。
  /// 俯仰角越大挤出越厚（按 perspectiveExtrudeFactor 放大）。
  void _extrude(Canvas canvas, Path path, double dy) {
    canvas.save();
    canvas.translate(0, dy * perspectiveExtrudeFactor(pitchDeg));
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.restore();
  }

  /// v1.3.8：颜色明暗：f > 0 向白提亮、f < 0 向黑压暗（车身
  /// 纵向明暗渐变用，取代 v1.2.0 的大面积平铺白光）。
  Color _shade(Color c, double f) => f >= 0
      ? Color.lerp(c, Colors.white, f)!
      : Color.lerp(c, Colors.black, -f)!;

  /// v1.3.8：玻璃面板：纵向浅→深渐变 + 一条斜向反光带
  /// （clip 在圆角矩形内，反光不溢出玻璃边缘）。
  void _glassPanel(Canvas canvas, Rect rect, double radius) {
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(rect.left, rect.top),
            Offset(rect.left, rect.bottom),
            const [Color(0xFFD9F1FF), Color(0xFF8FC7E8)],
            const [0.0, 1.0],
          ));
    final band = Path()
      ..moveTo(rect.left + rect.width * 0.15, rect.bottom)
      ..lineTo(rect.left + rect.width * 0.45, rect.top)
      ..lineTo(rect.left + rect.width * 0.60, rect.top)
      ..lineTo(rect.left + rect.width * 0.30, rect.bottom)
      ..close();
    canvas.drawPath(
        band, Paint()..color = Colors.white.withValues(alpha: 0.35));
    canvas.restore();
  }

  void _paintCar(Canvas canvas, Size size, CarMarkerStyle style) {
    final w = size.width, h = size.height;
    final cx = w * 0.5;
    _shadow(canvas, size, 0.62, 0.92);
    final base = bodyColor ?? const Color(0xFF37474F);
    final dark = Paint()..color = Colors.black;
    final tyre = Paint()..color = const Color(0xFF111111);
    // 车型参数：轿车 / 跑车沿用 v1.3.8 的旧值（一字不动，36px
    // 像素测试按旧几何断言）；新三款只在自有参数上区分。
    // SUV / 皮卡 / 越野车轮廓方正（boxy：车头平直、侧面近直、
    // 车尾平直），轿车 / 跑车保持收窄流线轮廓。
    final sport = style == CarMarkerStyle.sport;
    final boxy = style == CarMarkerStyle.suv ||
        style == CarMarkerStyle.pickup ||
        style == CarMarkerStyle.offroad;
    final offroad = style == CarMarkerStyle.offroad;
    final pickup = style == CarMarkerStyle.pickup;
    // 细线下限：36px 地图尺寸下仍以 1px 实线呈现，不糊成灰雾；
    // 48px 及以上才叠加最细装饰（格栅纹、天窗），小尺寸不堆噪点。
    final hair = math.max(1.0, w * 0.018);
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..strokeWidth = hair
      ..style = PaintingStyle.stroke;
    // 四轮：胎壁外深内浅两层 + 十字辐条 + 轮毂亮点，跑车轮胎更宽，
    // SUV 次之，越野车最粗（胎高也更大）。
    final tw = w * (sport
        ? 0.10
        : offroad
            ? 0.115
            : style == CarMarkerStyle.suv
                ? 0.10
                : 0.09);
    final th = h * (offroad ? 0.18 : style == CarMarkerStyle.suv ? 0.17 : 0.16);
    final twFrac = tw / w;
    for (final y in [0.22, 0.66]) {
      for (final x in [0.17, 0.83 - twFrac]) {
        final rect = Rect.fromLTWH(w * x, h * y, tw, th);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)), tyre);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                rect.deflate(math.max(1.0, w * 0.012)),
                const Radius.circular(1)),
            Paint()..color = const Color(0xFF2B2B2B));
        final cc = rect.center;
        final spoke = Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = hair;
        canvas.drawLine(Offset(cc.dx, rect.top + th * 0.15),
            Offset(cc.dx, rect.bottom - th * 0.15), spoke);
        canvas.drawLine(Offset(rect.left + tw * 0.15, cc.dy),
            Offset(rect.right - tw * 0.15, cc.dy), spoke);
        canvas.drawCircle(cc, math.max(1.5, w * 0.022),
            Paint()..color = const Color(0xFFBDBDBD));
        // 越野车胎纹（仅 48px 及以上，36px 下不堆噪点）：
        // 每条胎外侧三道横纹，粗胎一眼可辨。
        if (offroad && w >= 48) {
          final tread = Paint()
            ..color = Colors.white.withValues(alpha: 0.28)
            ..strokeWidth = hair;
          for (final ty in [0.30, 0.50, 0.70]) {
            canvas.drawLine(
                Offset(rect.left + 1, rect.top + th * ty),
                Offset(rect.right - 1, rect.top + th * ty),
                tread);
          }
        }
      }
    }
    // 俯视车体：车头（上）在收窄，车尾（下）略宽；跑车车头更尖、
    // 车顶更短、尾翼更明显，轿车车顶更长、行李厢线更直。
    // 方正款：车头平直（宽 0.20w 的平鼻）、侧面近直、车尾平直。
    final noseY = h * 0.06, tailY = h * 0.94;
    final bodyPath = boxy
        ? (Path()
          ..moveTo(cx - w * 0.10, noseY)
          ..lineTo(cx + w * 0.10, noseY)
          ..quadraticBezierTo(w * 0.74, noseY + h * 0.03, w * 0.74, h * 0.18)
          ..lineTo(w * 0.75, h * 0.82)
          ..quadraticBezierTo(w * 0.75, tailY, w * 0.66, tailY)
          ..lineTo(w * 0.34, tailY)
          ..quadraticBezierTo(w * 0.25, tailY, w * 0.25, h * 0.82)
          ..lineTo(w * 0.26, h * 0.18)
          ..quadraticBezierTo(
              w * 0.26, noseY + h * 0.03, cx - w * 0.10, noseY)
          ..close())
        : (Path()
          ..moveTo(cx, noseY)
          ..quadraticBezierTo(w * 0.74, noseY + h * 0.02, w * 0.76, h * 0.18)
          ..lineTo(w * 0.78, h * 0.80)
          ..quadraticBezierTo(w * 0.78, tailY, w * 0.68, tailY)
          ..lineTo(w * 0.32, tailY)
          ..quadraticBezierTo(w * 0.22, tailY, w * 0.22, h * 0.80)
          ..lineTo(w * 0.24, h * 0.18)
          ..quadraticBezierTo(w * 0.26, noseY + h * 0.02, cx, noseY)
          ..close());
    _extrude(canvas, bodyPath, h * 0.035);
    // v1.3.8：车身纵向明暗渐变（两侧压暗、中央提亮，模拟曲面
    // 受光），取代 v1.2.0 的大面积平铺白光。
    canvas.drawPath(
        bodyPath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(w * 0.22, 0),
            Offset(w * 0.78, 0),
            [
              _shade(base, -0.28),
              _shade(base, 0.20),
              _shade(base, 0.12),
              _shade(base, -0.28),
            ],
            const [0.0, 0.32, 0.68, 1.0],
          ));
    // 车体侧面暗边：左右各一条窄暗带，强化立体厚度。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.235, h * 0.18, w * 0.03, h * 0.62),
            const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.15));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.735, h * 0.18, w * 0.03, h * 0.62),
            const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.15));
    // 后视镜：前门两侧各一小块（车体外沿）。
    final mirror = Paint()..color = Colors.black.withValues(alpha: 0.85);
    for (final mx in [0.185, 0.765]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * mx, h * 0.325, w * 0.05, h * 0.035),
              const Radius.circular(2)),
          mirror);
    }
    // 前风挡 / 车顶 / 后风挡（俯视自上而下）：玻璃带渐变与反光带。
    // SUV / 越野车车顶更长更高、前风挡更高；皮卡只有驾驶舱顶，
    // 后半是开放货斗（无后风挡、无长车顶，见下）。
    final roofY = switch (style) {
      CarMarkerStyle.sport => 0.38,
      CarMarkerStyle.suv => 0.34,
      CarMarkerStyle.pickup => 0.34,
      CarMarkerStyle.offroad => 0.34,
      CarMarkerStyle.sedan => 0.36,
    };
    final roofH = switch (style) {
      CarMarkerStyle.sport => 0.22,
      CarMarkerStyle.suv => 0.36,
      CarMarkerStyle.pickup => 0.20,
      CarMarkerStyle.offroad => 0.34,
      CarMarkerStyle.sedan => 0.30,
    };
    final frontGlassY = (style == CarMarkerStyle.suv || offroad) ? 0.20 : 0.22;
    final frontGlassH = (style == CarMarkerStyle.suv || offroad) ? 0.14 : 0.12;
    final rearGlassY = switch (style) {
      CarMarkerStyle.sport => 0.63,
      CarMarkerStyle.suv => 0.72,
      CarMarkerStyle.offroad => 0.70,
      CarMarkerStyle.sedan => 0.69,
      CarMarkerStyle.pickup => 0.56, // 驾驶舱后窗（小），不是后风挡。
    };
    _glassPanel(
        canvas,
        Rect.fromLTWH(w * 0.32, h * frontGlassY, w * 0.36, h * frontGlassH),
        3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.30, h * roofY, w * 0.40, h * roofH),
            const Radius.circular(4)),
        Paint()..color = _shade(base, -0.12));
    // 天窗（仅 48px 及以上，36px 下不堆细节）：车顶内嵌深色块。
    // 只给轿车 / 跑车；SUV 与越野车顶留给行李架/行李架杆，皮卡
    // 驾驶舱顶太短不画。
    if (w >= 48 && (sport || style == CarMarkerStyle.sedan)) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.35, h * (roofY + 0.05), w * 0.30,
                  h * (roofH - 0.10)),
              const Radius.circular(3)),
          Paint()..color = const Color(0xFF263238));
    }
    if (pickup) {
      // 驾驶舱后窗（小玻璃）+ 开放货斗：斗底深色、斗壁描边、
      // 三道纵向斗底筋、尾门缝线与尾门拉手。
      _glassPanel(
          canvas,
          Rect.fromLTWH(w * 0.36, h * rearGlassY, w * 0.28, h * 0.06),
          3);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.31, h * 0.64, w * 0.38, h * 0.24),
              const Radius.circular(2)),
          Paint()..color = _shade(base, -0.38));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.31, h * 0.64, w * 0.38, h * 0.24),
              const Radius.circular(2)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = hair);
      for (final bx in [0.40, 0.50, 0.60]) {
        canvas.drawLine(Offset(w * bx, h * 0.66), Offset(w * bx, h * 0.84),
            seam);
      }
      canvas.drawLine(
          Offset(w * 0.31, h * 0.86), Offset(w * 0.69, h * 0.86), seam);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.46, h * 0.845, w * 0.08, h * 0.018),
              const Radius.circular(1)),
          Paint()..color = Colors.black.withValues(alpha: 0.45));
    } else {
      _glassPanel(
          canvas,
          Rect.fromLTWH(w * 0.32, h * rearGlassY, w * 0.36, h * 0.09),
          3);
    }
    // SUV 行李架：车顶两侧纵杆；越野车行李架：纵杆 + 三道横杆。
    if (style == CarMarkerStyle.suv || offroad) {
      final rail = Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = math.max(1.5, w * 0.025)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(w * 0.335, h * (roofY + 0.02)),
          Offset(w * 0.335, h * (roofY + roofH - 0.02)), rail);
      canvas.drawLine(Offset(w * 0.665, h * (roofY + 0.02)),
          Offset(w * 0.665, h * (roofY + roofH - 0.02)), rail);
      if (offroad) {
        for (final ry in [0.08, 0.18, 0.28]) {
          canvas.drawLine(Offset(w * 0.335, h * (roofY + ry)),
              Offset(w * 0.665, h * (roofY + ry)), rail);
        }
      }
    }
    // 越野车：前杠（灯下横杠）+ 两侧脚踏板（前后轮之间）。
    if (offroad) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.28, h * 0.165, w * 0.44, h * 0.022),
              const Radius.circular(1)),
          Paint()..color = Colors.black.withValues(alpha: 0.55));
      final step = Paint()..color = const Color(0xFF9E9E9E).withValues(alpha: 0.65);
      for (final sx in [0.205, 0.775]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * sx, h * 0.50, w * 0.02, h * 0.12),
                const Radius.circular(1)),
            step);
      }
    }
    // 钣金缝线：机盖线、两道车门线、行李厢线（横贯车体不断线，
    // 位置落在玻璃与车顶之间，不压玻璃）。皮卡第二道车门线不画
    // （该位置是驾驶舱后窗与货斗交界），尾门缝线已画在货斗里。
    canvas.drawLine(Offset(w * 0.30, h * 0.205), Offset(w * 0.70, h * 0.205), seam);
    canvas.drawLine(Offset(w * 0.265, h * 0.40), Offset(w * 0.735, h * 0.40), seam);
    if (!pickup) {
      canvas.drawLine(Offset(w * 0.265, h * 0.62), Offset(w * 0.735, h * 0.62), seam);
    }
    // 轿车行李厢线 / 跑车尾翼；SUV 与越野车为尾门缝线，皮卡不画
    // （尾门缝线已在货斗段画过）。
    if (sport) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.24, h * 0.86, w * 0.52, h * 0.05),
              const Radius.circular(2)),
          dark);
    } else if (!pickup) {
      canvas.drawLine(Offset(w * 0.30, h * 0.82), Offset(w * 0.70, h * 0.82),
          seam);
    }
    // 前格栅：鼻尖中央深色块；48px 及以上加一条横纹。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.38, h * 0.062, w * 0.24, h * 0.03),
            const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.60));
    if (w >= 48) {
      canvas.drawLine(
          Offset(w * 0.40, h * 0.077),
          Offset(w * 0.60, h * 0.077),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.18)
            ..strokeWidth = hair);
    }
    // 前后保险杠：灯下细缝线（前）与尾部暗带（后）。
    canvas.drawLine(Offset(w * 0.28, h * 0.15), Offset(w * 0.72, h * 0.15), seam);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.30, h * 0.918, w * 0.40, h * 0.02),
            const Radius.circular(1)),
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    // 前灯：斜切梯形灯体 + 下沿日行灯带（亮白细线）。
    Path lampPath(bool left) {
      if (left) {
        return Path()
          ..moveTo(w * 0.26, h * 0.115)
          ..lineTo(w * 0.365, h * 0.095)
          ..lineTo(w * 0.375, h * 0.135)
          ..lineTo(w * 0.27, h * 0.148)
          ..close();
      }
      return Path()
        ..moveTo(w * 0.74, h * 0.115)
        ..lineTo(w * 0.635, h * 0.095)
        ..lineTo(w * 0.625, h * 0.135)
        ..lineTo(w * 0.73, h * 0.148)
        ..close();
    }

    final lamp = Paint()..color = const Color(0xFFFFF59D);
    canvas.drawPath(lampPath(true), lamp);
    canvas.drawPath(lampPath(false), lamp);
    final drl = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = hair;
    canvas.drawLine(
        Offset(w * 0.27, h * 0.148), Offset(w * 0.375, h * 0.135), drl);
    canvas.drawLine(
        Offset(w * 0.73, h * 0.148), Offset(w * 0.625, h * 0.135), drl);
    // 尾灯：贯穿式灯带 + 两端灯块。
    final tail = Paint()..color = const Color(0xFFE53935);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.27, h * 0.885, w * 0.46, h * 0.022),
            const Radius.circular(1)),
        tail);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.26, h * 0.89, w * 0.10, h * 0.04),
            const Radius.circular(2)),
        tail);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.64, h * 0.89, w * 0.10, h * 0.04),
            const Radius.circular(2)),
        tail);
  }

  void _paintMoto(Canvas canvas, Size size, MotoMarkerStyle style) {
    final w = size.width, h = size.height;
    final cx = w * 0.5;
    _shadow(canvas, size, 0.34, 0.92);
    final body = Paint()..color = bodyColor ?? const Color(0xFF212121);
    final accent = Paint()..color = style.accent;
    final tyre = Paint()..color = const Color(0xFF111111);
    final hair = math.max(1.0, w * 0.018);
    // 俯视两轮：前后纵向椭圆（前轮在上），轮胎宽按风格微调；
    // 胎面加内圈 + 三辐条，不再是纯黑块。
    final tw = w * (style == MotoMarkerStyle.honda ? 0.12 : 0.14);
    for (final yc in [0.16, 0.84]) {
      final rect = Rect.fromCenter(
          center: Offset(cx, h * yc), width: tw, height: h * 0.22);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)), tyre);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              rect.deflate(math.max(1.0, w * 0.015)),
              const Radius.circular(3)),
          Paint()
            ..color = const Color(0xFF2E2E2E)
            ..style = PaintingStyle.stroke
            ..strokeWidth = hair);
      final spoke = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = hair;
      final cc = rect.center;
      canvas.drawLine(
          Offset(cc.dx, rect.top + 2), Offset(cc.dx, rect.bottom - 2), spoke);
      canvas.drawLine(Offset(cc.dx - tw * 0.28, cc.dy - h * 0.06),
          Offset(cc.dx + tw * 0.28, cc.dy + h * 0.06), spoke);
      canvas.drawLine(Offset(cc.dx + tw * 0.28, cc.dy - h * 0.06),
          Offset(cc.dx - tw * 0.28, cc.dy + h * 0.06), spoke);
    }
    // 前叉：两条斜线连车把与前轮。
    final fork = Paint()
      ..color = const Color(0xFF9E9E9E).withValues(alpha: 0.85)
      ..strokeWidth = math.max(1.5, w * 0.03)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx - w * 0.045, h * 0.30), Offset(cx - w * 0.035, h * 0.10), fork);
    canvas.drawLine(
        Offset(cx + w * 0.045, h * 0.30), Offset(cx + w * 0.035, h * 0.10), fork);
    // 车把：前轮后方横杆 + 两端把套（加粗段）；后视镜：短斜杆 + 小镜面。
    final barPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = math.max(2.0, w * 0.035)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.30, h * 0.30), Offset(w * 0.70, h * 0.30), barPaint);
    final grip = Paint()
      ..color = Colors.black
      ..strokeWidth = math.max(2.5, w * 0.05)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.30, h * 0.30), Offset(w * 0.355, h * 0.30), grip);
    canvas.drawLine(
        Offset(w * 0.645, h * 0.30), Offset(w * 0.70, h * 0.30), grip);
    final stalk = Paint()
      ..color = Colors.black
      ..strokeWidth = hair;
    canvas.drawLine(
        Offset(w * 0.315, h * 0.30), Offset(w * 0.26, h * 0.255), stalk);
    canvas.drawLine(
        Offset(w * 0.685, h * 0.30), Offset(w * 0.74, h * 0.255), stalk);
    for (final mx in [0.25, 0.75]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(w * mx, h * 0.245),
                  width: w * 0.05,
                  height: h * 0.028),
              const Radius.circular(2)),
          Paint()..color = Colors.black);
    }
    final fairing = switch (style) {
      // 仿赛：宽整流罩 + 尖鼻；街车：窄油箱 + 短尾；其余介于其间。
      MotoMarkerStyle.ducati => Path()
        ..moveTo(cx, h * 0.32)
        ..quadraticBezierTo(w * 0.68, h * 0.34, w * 0.68, h * 0.48)
        ..lineTo(w * 0.64, h * 0.62)
        ..quadraticBezierTo(w * 0.60, h * 0.74, cx, h * 0.76)
        ..quadraticBezierTo(w * 0.40, h * 0.74, w * 0.36, h * 0.62)
        ..lineTo(w * 0.32, h * 0.48)
        ..quadraticBezierTo(w * 0.32, h * 0.34, cx, h * 0.32)
        ..close(),
      MotoMarkerStyle.yamaha => Path()
        ..moveTo(cx, h * 0.32)
        ..quadraticBezierTo(w * 0.64, h * 0.36, w * 0.64, h * 0.50)
        ..lineTo(w * 0.60, h * 0.64)
        ..quadraticBezierTo(w * 0.58, h * 0.74, cx, h * 0.76)
        ..quadraticBezierTo(w * 0.42, h * 0.74, w * 0.40, h * 0.64)
        ..lineTo(w * 0.36, h * 0.50)
        ..quadraticBezierTo(w * 0.36, h * 0.36, cx, h * 0.32)
        ..close(),
      MotoMarkerStyle.honda => Path()
        ..moveTo(cx, h * 0.34)
        ..quadraticBezierTo(w * 0.60, h * 0.38, w * 0.60, h * 0.50)
        ..lineTo(w * 0.56, h * 0.62)
        ..quadraticBezierTo(w * 0.54, h * 0.72, cx, h * 0.74)
        ..quadraticBezierTo(w * 0.46, h * 0.72, w * 0.44, h * 0.62)
        ..lineTo(w * 0.40, h * 0.50)
        ..quadraticBezierTo(w * 0.40, h * 0.38, cx, h * 0.34)
        ..close(),
      MotoMarkerStyle.kawasaki => Path()
        ..moveTo(cx, h * 0.30)
        ..quadraticBezierTo(w * 0.66, h * 0.36, w * 0.66, h * 0.48)
        ..lineTo(w * 0.62, h * 0.60)
        ..lineTo(w * 0.56, h * 0.72)
        ..lineTo(cx, h * 0.78)
        ..lineTo(w * 0.44, h * 0.72)
        ..lineTo(w * 0.38, h * 0.60)
        ..lineTo(w * 0.34, h * 0.48)
        ..quadraticBezierTo(w * 0.34, h * 0.36, cx, h * 0.30)
        ..close(),
    };
    _extrude(canvas, fairing, h * 0.03);
    canvas.drawPath(fairing, body);
    // 前灯：鼻尖下方淡黄小块（朝向可辨）。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.455, h * 0.335, w * 0.09, h * 0.022),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFFFFF9C4));
    // 油箱：缝线框出油箱区 + 高光条 + 油箱盖点。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.415, h * 0.40, w * 0.17, h * 0.14),
            const Radius.circular(4)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hair);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.44, h * 0.40, w * 0.06, h * 0.18),
            const Radius.circular(2)),
        Paint()..color = Colors.white.withValues(alpha: 0.20));
    canvas.drawCircle(Offset(cx, h * 0.44), math.max(1.2, w * 0.018),
        Paint()..color = Colors.white.withValues(alpha: 0.50));
    // 品牌色点缀条（仅一小块色条，不是 Logo；位于座垫上方，不被座垫盖住）。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.44, h * 0.575, w * 0.12, h * 0.04),
            const Radius.circular(2)),
        accent);
    // 座垫双层：骑手座（深）+ 尾座（浅）；尾部色条 + 红色尾灯。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.42, h * 0.625, w * 0.16, h * 0.06),
            const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.44, h * 0.685, w * 0.12, h * 0.04),
            const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.46, h * 0.725, w * 0.08, h * 0.018),
            const Radius.circular(1)),
        accent);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.465, h * 0.745, w * 0.07, h * 0.02),
            const Radius.circular(1)),
        Paint()..color = const Color(0xFFE53935));
  }

  void _paintBike(Canvas canvas, Size size, BikeMarkerStyle style) {
    final w = size.width, h = size.height;
    final cx = w * 0.5;
    final thick = style == BikeMarkerStyle.mountain;
    _shadow(canvas, size, 0.30, 0.92);
    final hair = math.max(1.0, w * 0.018);
    final tyre = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thick ? math.max(3, w * 0.07) : math.max(2, w * 0.04);
    // 俯视两轮：前后纵向轮圈（前轮在上），山地胎更粗；
    // 轮内加辐条（竖 / 横 / 双斜四线）+ 轴心点。
    for (final y in [0.16, 0.84]) {
      final rect = Rect.fromCenter(
          center: Offset(cx, h * y), width: w * 0.16, height: h * 0.22);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)), tyre);
      final spoke = Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = hair;
      final cc = rect.center;
      canvas.drawLine(
          Offset(cc.dx, rect.top + 2), Offset(cc.dx, rect.bottom - 2), spoke);
      canvas.drawLine(
          Offset(rect.left + 2, cc.dy), Offset(rect.right - 2, cc.dy), spoke);
      canvas.drawLine(Offset(cc.dx - w * 0.045, cc.dy - h * 0.07),
          Offset(cc.dx + w * 0.045, cc.dy + h * 0.07), spoke);
      canvas.drawLine(Offset(cc.dx + w * 0.045, cc.dy - h * 0.07),
          Offset(cc.dx - w * 0.045, cc.dy + h * 0.07), spoke);
      canvas.drawCircle(
          cc, math.max(1.5, w * 0.025), Paint()..color = Colors.black);
    }
    // 俯视车架三角：管壁粗细区分——下管最粗、上管 / 立管居中、
    // 前叉次之、后叉最细；先画一遍下移暗色（厚度），再画本体。
    final frameColor = bodyColor ?? const Color(0xFF78909C);
    final head = Offset(cx, h * 0.28);
    final bb = Offset(cx, h * 0.52);
    final seatTop = Offset(cx, h * 0.64);
    final frontAxle = Offset(cx, h * 0.16);
    final rearAxle = Offset(cx, h * 0.84);
    final tubes = <(Offset, Offset, double)>[
      (head, bb, w * 0.06), // 下管
      (head, seatTop, w * 0.05), // 上管
      (bb, seatTop, w * 0.05), // 立管
      (head, frontAxle, w * 0.045), // 前叉
      (seatTop, rearAxle, w * 0.03), // 后上叉
      (bb, rearAxle, w * 0.03), // 后下叉
    ];
    Paint tubePaint(Color c, double sw) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, sw)
      ..strokeCap = StrokeCap.round;
    for (final (a, b, sw) in tubes) {
      canvas.drawLine(a + const Offset(1.5, 2), b + const Offset(1.5, 2),
          tubePaint(Colors.black.withValues(alpha: 0.35), sw));
    }
    for (final (a, b, sw) in tubes) {
      canvas.drawLine(a, b, tubePaint(frameColor, sw));
    }
    // 牙盘：中轴处小圆盘 + 轴心点。
    canvas.drawCircle(
        bb,
        math.max(2.5, w * 0.05),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hair);
    canvas.drawCircle(
        bb, math.max(1.2, w * 0.015), Paint()..color = Colors.black);
    // 车把在前轮后方横置：公路为弯把（两端小折线）、
    // 山地为宽平把、城市为上翘宽把（两端向后弯折）。
    final barY = h * 0.28;
    final halfBar = w *
        (style == BikeMarkerStyle.mountain
            ? 0.26
            : style == BikeMarkerStyle.city
                ? 0.22
                : 0.20);
    final barPaint = tubePaint(frameColor, w * 0.045);
    canvas.drawLine(
        Offset(cx - halfBar, barY), Offset(cx + halfBar, barY), barPaint);
    if (style == BikeMarkerStyle.road) {
      canvas.drawLine(Offset(cx - halfBar, barY),
          Offset(cx - halfBar, barY + h * 0.05), barPaint);
      canvas.drawLine(Offset(cx + halfBar, barY),
          Offset(cx + halfBar, barY + h * 0.05), barPaint);
    } else if (style == BikeMarkerStyle.city) {
      canvas.drawLine(Offset(cx - halfBar, barY),
          Offset(cx - halfBar - w * 0.03, barY + h * 0.045), barPaint);
      canvas.drawLine(Offset(cx + halfBar, barY),
          Offset(cx + halfBar + w * 0.03, barY + h * 0.045), barPaint);
    }
    // 座垫：后宽前窄（圆角块）+ 鼻尖向前伸一小段。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, h * 0.655), width: w * 0.14, height: h * 0.045),
            const Radius.circular(2)),
        Paint()..color = Colors.black);
    canvas.drawLine(
        Offset(cx, h * 0.635),
        Offset(cx, h * 0.615),
        Paint()
          ..color = Colors.black
          ..strokeWidth = math.max(2, w * 0.03)
          ..strokeCap = StrokeCap.round);
    // 高光：下管旁一条细亮带。
    canvas.drawLine(
        Offset(cx + w * 0.035, h * 0.32),
        Offset(cx + w * 0.035, h * 0.50),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = math.max(1, w * 0.02));
  }

  @override
  bool shouldRepaint(covariant VehicleMarkerPainter old) =>
      old.mode != mode ||
      old.styleKey != styleKey ||
      old.bodyColor != bodyColor ||
      old.headingDeg != headingDeg ||
      old.pitchDeg != pitchDeg;
}

/// 按模式与选择返回车标 Widget（地图层直接用这个，不用自己拼画笔）。
///
/// [selection] 为当前三模式选择；[mode] 决定取哪一档；
/// [headingDeg] 为 GPS 航向（度），地图跟随朝向时传入；
/// [pitchDeg] 为俯仰角（度，0 = 俯视；街道 3D 视角传 35 / 50 / 65，
/// 车标按透视压扁 + 侧壁加厚；记录页场景级已压扁时传 0，勿叠加）；
/// [size] 默认 40，地图标注建议 36–48。
Widget markerFor(
  VehicleMarkerSelection selection,
  TripMode mode, {
  double headingDeg = 0,
  double pitchDeg = 0,
  double size = 40,
  Color? bodyColor,
}) {
  return SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: VehicleMarkerPainter(
        mode: mode,
        styleKey: selection.keyFor(mode),
        headingDeg: headingDeg,
        pitchDeg: pitchDeg,
        bodyColor: bodyColor,
      ),
    ),
  );
}

/// 按模式与选择返回画笔（调用方已有 CustomPaint / 地图自定义层时用）。
CustomPainter markerPainterFor(
  VehicleMarkerSelection selection,
  TripMode mode, {
  double headingDeg = 0,
  double pitchDeg = 0,
  Color? bodyColor,
}) =>
    VehicleMarkerPainter(
      mode: mode,
      styleKey: selection.keyFor(mode),
      headingDeg: headingDeg,
      pitchDeg: pitchDeg,
      bodyColor: bodyColor,
    );

// ------------------------------------------------------------------
// 共用浅底预览格（v1.3.8）
// ------------------------------------------------------------------

/// 车标预览格：64×64 深色圆角格 + 居中 56px 车标。
///
/// 主题设置分区（VehicleMarkerSettingsSection）与选择子页
/// （VehicleMarkerPickerPage）共用此组件，两处预览尺寸、底色、
/// 选中描边完全一致。下一版·第 3 条：浅底改深色 HUD 底
/// （#14161C），与全局黑色科幻风格统一；深色车体靠玻璃反光、
/// 前后灯与轮毂高光辨认，选中时描边 + 强调色辉光。
class VehicleMarkerPreviewTile extends StatelessWidget {
  final VehicleMarkerSelection selection;
  final TripMode mode;
  final bool selected;
  final Color accentColor;

  const VehicleMarkerPreviewTile({
    super.key,
    required this.selection,
    required this.mode,
    this.selected = false,
    this.accentColor = const Color(0xFFE10600),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF14161C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? accentColor : Colors.white12,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: markerFor(selection, mode, size: 56),
    );
  }
}

// ------------------------------------------------------------------
// 车标选择子页
// ------------------------------------------------------------------

/// 车标选择子页 Widget（可直接推路由）。
///
/// [initial] 为已存选择；[onChanged] 在每次点选时回调，由总协调
/// 持久化（键见文件头）并重建地图层；本页内部也立即 setState，
/// 所以点选后预览马上变化，不依赖总协调先回写。
/// 摩托页顶部固定有“品牌名仅作风格区分，非官方授权模型”声明。
class VehicleMarkerPickerPage extends StatefulWidget {
  final VehicleMarkerSelection initial;
  final ValueChanged<VehicleMarkerSelection>? onChanged;
  final Color accentColor;

  const VehicleMarkerPickerPage({
    super.key,
    this.initial = const VehicleMarkerSelection(),
    this.onChanged,
    this.accentColor = const Color(0xFFE10600),
  });

  @override
  State<VehicleMarkerPickerPage> createState() => _VehicleMarkerPickerPageState();
}

class _VehicleMarkerPickerPageState extends State<VehicleMarkerPickerPage> {
  late VehicleMarkerSelection _sel = widget.initial;
  TripMode _tab = TripMode.car;

  /// 该行自己的预览用选择（每行画自己风格，不是都画已选风格）。
  VehicleMarkerSelection _selectionForRow(String key) => switch (_tab) {
        TripMode.car => _sel.copyWith(car: CarMarkerStyleLabel.fromKey(key)),
        TripMode.moto => _sel.copyWith(moto: MotoMarkerStyleLabel.fromKey(key)),
        TripMode.bike => _sel.copyWith(bike: BikeMarkerStyleLabel.fromKey(key)),
      };

  void _pick(TripMode mode, String key) {
    setState(() {
      _sel = switch (mode) {
        TripMode.car => _sel.copyWith(car: CarMarkerStyleLabel.fromKey(key)),
        TripMode.moto => _sel.copyWith(moto: MotoMarkerStyleLabel.fromKey(key)),
        TripMode.bike => _sel.copyWith(bike: BikeMarkerStyleLabel.fromKey(key)),
      };
    });
    widget.onChanged?.call(_sel);
  }

  /// 当前选项卡下各行的副文案（只描述画出的轮廓）。
  String _blurbFor(String key) => switch (_tab) {
        TripMode.car => CarMarkerStyleLabel.fromKey(key).blurb,
        TripMode.moto => MotoMarkerStyleLabel.fromKey(key).blurb,
        TripMode.bike => BikeMarkerStyleLabel.fromKey(key).blurb,
      };

  @override
  Widget build(BuildContext context) {
    final options = switch (_tab) {
      TripMode.car => CarMarkerStyle.values
          .map((e) => (key: e.key, label: e.label, sel: _sel.car.key))
          .toList(),
      TripMode.moto => MotoMarkerStyle.values
          .map((e) => (key: e.key, label: e.label, sel: _sel.moto.key))
          .toList(),
      TripMode.bike => BikeMarkerStyle.values
          .map((e) => (key: e.key, label: e.label, sel: _sel.bike.key))
          .toList(),
    };
    final (currentLabel, currentKey) = switch (_tab) {
      TripMode.car => (_sel.car.label, _sel.car.key),
      TripMode.moto => (_sel.moto.label, _sel.moto.key),
      TripMode.bike => (_sel.bike.label, _sel.bike.key),
    };
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: const Text('地图车标'),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 4)),
            child: SegmentedButton<TripMode>(
              style: SegmentedButton.styleFrom(
                backgroundColor: const Color(0xFF121212),
                foregroundColor: Colors.white70,
                selectedBackgroundColor: widget.accentColor,
                selectedForegroundColor: Colors.white,
                side: const BorderSide(color: Colors.white12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              segments: const [
                ButtonSegment(value: TripMode.car, label: Text('汽车')),
                ButtonSegment(value: TripMode.moto, label: Text('摩托')),
                ButtonSegment(value: TripMode.bike, label: Text('自行车')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
          // 当前选择大预览：96px 倾斜预览（pitchDeg 45°，即街道
          // 3D 视角的压扁 + 挤出效果），右侧为当前风格名与要点。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1017),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: const Color(0xFF14161C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    alignment: Alignment.center,
                    child: markerFor(_sel, _tab, pitchDeg: 45, size: 96),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '当前选择',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _blurbFor(currentKey),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '倾斜预览 · 街道 3D 视角效果',
                          style: TextStyle(
                              color: widget.accentColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_tab == TripMode.moto)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  '品牌名仅作风格区分；车标为自绘轮廓，不使用官方 Logo。',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final o in options)
                  Card(
                    color: o.sel == o.key
                        ? const Color(0xFF1B1E26)
                        : const Color(0xFF121212),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: o.sel == o.key
                            ? widget.accentColor
                            : Colors.white12,
                        width: o.sel == o.key ? 1.5 : 1,
                      ),
                    ),
                    child: ListTile(
                      minLeadingWidth: 64,
                      horizontalTitleGap: 12,
                      leading: VehicleMarkerPreviewTile(
                        selection: _selectionForRow(o.key),
                        mode: _tab,
                        selected: o.sel == o.key,
                        accentColor: widget.accentColor,
                      ),
                      title: Text(
                        o.label,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _blurbFor(o.key),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      trailing: o.sel == o.key
                          ? Icon(Icons.check, color: widget.accentColor)
                          : null,
                      onTap: () => _pick(_tab, o.key),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  '选择只存本机，不上传。',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 总协调接线（不执行，仅供参考） ----------
// 1) AppPrefs.load/save 增加 vehicleMarkerCar / vehicleMarkerMoto /
//    vehicleMarkerBike 三个键（见 VehicleMarkerSelection.toJson/fromJson）。
// 2) 设置页“地图”或“外观”区加入口：推 VehicleMarkerPickerPage(
//      initial: 当前选择, onChanged: (s) { 存档; 地图层重建; })。
// 3) 地图层（refined_map.dart）绘制当前位置标时改用 markerFor(选择, 模式,
//    headingDeg: 航向)，不要再画固定圆点；静态预览 headingDeg 传 0。
