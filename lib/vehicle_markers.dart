import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models.dart';

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

// ------------------------------------------------------------------
// 风格枚举（styleKey 即持久化存的值，改名会断旧存档，勿随意改）
// ------------------------------------------------------------------

/// 汽车车体：轿车 / 跑车。
enum CarMarkerStyle { sedan, sport }

extension CarMarkerStyleLabel on CarMarkerStyle {
  String get key => name;
  String get label => switch (this) {
        CarMarkerStyle.sedan => '轿车',
        CarMarkerStyle.sport => '跑车',
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
  static BikeMarkerStyle fromKey(String? k) => BikeMarkerStyle.values
      .firstWhere((e) => e.name == k, orElse: () => BikeMarkerStyle.road);
}

// ------------------------------------------------------------------
// 选择模型与持久化键（总协调接入 store / AppPrefs 时照此键名写）
// ------------------------------------------------------------------
//
// 建议写进现有 profile.json（与 AppPrefs 同一文件，不另起文件）：
//   'vehicleMarkerCar'   : 'sedan' | 'sport'            （默认 'sedan'）
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

  const VehicleMarkerPainter({
    required this.mode,
    required this.styleKey,
    this.bodyColor,
    this.headingDeg = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(headingDeg * math.pi / 180);
    canvas.translate(-cx, -cy);
    switch (mode) {
      case TripMode.car:
        _paintCar(canvas, size,
            CarMarkerStyleLabel.fromKey(styleKey) == CarMarkerStyle.sport);
      case TripMode.moto:
        _paintMoto(canvas, size, MotoMarkerStyleLabel.fromKey(styleKey));
      case TripMode.bike:
        _paintBike(canvas, size, BikeMarkerStyleLabel.fromKey(styleKey));
    }
    canvas.restore();
  }

  /// v1.2.0 双层地面阴影：外层宽淡投影（离地高度感）+ 内层
  /// 紧贴车体的深色接触影（地面贴合感），两者都向右下偏移，
  /// 光源方向一致，车标不飘。
  void _shadow(Canvas canvas, Size size, double wFrac, double hFrac) {
    final w = size.width, h = size.height;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5 + w * 0.05, h * 0.5 + h * 0.07),
        width: w * (wFrac + 0.10),
        height: h * (hFrac + 0.04),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5 + w * 0.02, h * 0.5 + h * 0.03),
        width: w * wFrac,
        height: h * hFrac,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.50),
    );
  }

  /// v1.2.0 侧壁挤出层：把 [path] 下移 [dy] 以暗色先画一遍，
  /// 再画本体，车体即有厚度而非一片平色；dy 很小，不改轮廓。
  void _extrude(Canvas canvas, Path path, double dy) {
    canvas.save();
    canvas.translate(0, dy);
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

  void _paintCar(Canvas canvas, Size size, bool sport) {
    final w = size.width, h = size.height;
    final cx = w * 0.5;
    _shadow(canvas, size, 0.62, 0.92);
    final base = bodyColor ?? const Color(0xFF37474F);
    final dark = Paint()..color = Colors.black;
    final tyre = Paint()..color = const Color(0xFF111111);
    // 细线下限：36px 地图尺寸下仍以 1px 实线呈现，不糊成灰雾；
    // 48px 及以上才叠加最细装饰（格栅纹、天窗），小尺寸不堆噪点。
    final hair = math.max(1.0, w * 0.018);
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..strokeWidth = hair
      ..style = PaintingStyle.stroke;
    // 四轮：胎壁外深内浅两层 + 十字辐条 + 轮毂亮点，跑车轮胎更宽。
    final tw = w * (sport ? 0.10 : 0.09), th = h * 0.16;
    final twFrac = sport ? 0.10 : 0.09;
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
      }
    }
    // 俯视车体：车头（上）在收窄，车尾（下）略宽；跑车车头更尖、
    // 车顶更短、尾翼更明显，轿车车顶更长、行李厢线更直。
    final noseY = h * 0.06, tailY = h * 0.94;
    final bodyPath = Path()
      ..moveTo(cx, noseY)
      ..quadraticBezierTo(w * 0.74, noseY + h * 0.02, w * 0.76, h * 0.18)
      ..lineTo(w * 0.78, h * 0.80)
      ..quadraticBezierTo(w * 0.78, tailY, w * 0.68, tailY)
      ..lineTo(w * 0.32, tailY)
      ..quadraticBezierTo(w * 0.22, tailY, w * 0.22, h * 0.80)
      ..lineTo(w * 0.24, h * 0.18)
      ..quadraticBezierTo(w * 0.26, noseY + h * 0.02, cx, noseY)
      ..close();
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
    _glassPanel(
        canvas, Rect.fromLTWH(w * 0.32, h * 0.22, w * 0.36, h * 0.12), 3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                w * 0.30, h * (sport ? 0.38 : 0.36), w * 0.40, h * (sport ? 0.22 : 0.30)),
            const Radius.circular(4)),
        Paint()..color = _shade(base, -0.12));
    // 天窗（仅 48px 及以上，36px 下不堆细节）：车顶内嵌深色块。
    if (w >= 48) {
      final roofY = sport ? 0.38 : 0.36;
      final roofH = sport ? 0.22 : 0.30;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.35, h * (roofY + 0.05), w * 0.30,
                  h * (roofH - 0.10)),
              const Radius.circular(3)),
          Paint()..color = const Color(0xFF263238));
    }
    _glassPanel(
        canvas,
        Rect.fromLTWH(
            w * 0.32, h * (sport ? 0.63 : 0.69), w * 0.36, h * 0.09),
        3);
    // 钣金缝线：机盖线、两道车门线、行李厢线（横贯车体不断线，
    // 位置落在玻璃与车顶之间，不压玻璃）。
    canvas.drawLine(Offset(w * 0.30, h * 0.205), Offset(w * 0.70, h * 0.205), seam);
    canvas.drawLine(Offset(w * 0.265, h * 0.40), Offset(w * 0.735, h * 0.40), seam);
    canvas.drawLine(Offset(w * 0.265, h * 0.62), Offset(w * 0.735, h * 0.62), seam);
    // 轿车行李厢线 / 跑车尾翼。
    if (sport) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.24, h * 0.86, w * 0.52, h * 0.05),
              const Radius.circular(2)),
          dark);
    } else {
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
      old.headingDeg != headingDeg;
}

/// 按模式与选择返回车标 Widget（地图层直接用这个，不用自己拼画笔）。
///
/// [selection] 为当前三模式选择；[mode] 决定取哪一档；
/// [headingDeg] 为 GPS 航向（度），地图跟随朝向时传入；
/// [size] 默认 40，地图标注建议 36–48。
Widget markerFor(
  VehicleMarkerSelection selection,
  TripMode mode, {
  double headingDeg = 0,
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
  Color? bodyColor,
}) =>
    VehicleMarkerPainter(
      mode: mode,
      styleKey: selection.keyFor(mode),
      headingDeg: headingDeg,
      bodyColor: bodyColor,
    );

// ------------------------------------------------------------------
// 共用浅底预览格（v1.3.8）
// ------------------------------------------------------------------

/// 车标浅底预览格：64×64 浅色圆角格 + 居中 56px 车标。
///
/// 主题设置分区（VehicleMarkerSettingsSection）与选择子页
/// （VehicleMarkerPickerPage）共用此组件，两处预览尺寸、底色、
/// 选中描边完全一致；浅底让深色车体在黑色主题下仍可辨认。
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
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? accentColor : Colors.white24,
          width: selected ? 2 : 1,
        ),
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
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(title: const Text('地图车标')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<TripMode>(
              segments: const [
                ButtonSegment(value: TripMode.car, label: Text('汽车')),
                ButtonSegment(value: TripMode.moto, label: Text('摩托')),
                ButtonSegment(value: TripMode.bike, label: Text('自行车')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
          if (_tab == TripMode.moto)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '品牌名仅作风格区分，非官方授权模型；车标为自绘矢量轮廓，不使用官方 Logo。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final o in options)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      minLeadingWidth: 64,
                      horizontalTitleGap: 12,
                      leading: VehicleMarkerPreviewTile(
                        selection: _selectionForRow(o.key),
                        mode: _tab,
                        selected: o.sel == o.key,
                        accentColor: widget.accentColor,
                      ),
                      title: Text(o.label),
                      trailing: o.sel == o.key
                          ? Icon(Icons.check, color: widget.accentColor)
                          : null,
                      onTap: () => _pick(_tab, o.key),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  '选择只存本机（profile.json 的 vehicleMarkerCar / '
                  'vehicleMarkerMoto / vehicleMarkerBike 三个键），不上传。',
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
