import 'dart:math' as math;
import 'dart:ui';

/// 自建的轻量三维车辆网格：x 为车宽、y 为离地高度、z 为车头方向。
/// 不包含品牌标识，也不声称是任何品牌授权或精确复刻模型。
enum Vehicle3DPart { body, cabin, wheel, detail }

enum Vehicle3DMaterial {
  body,
  glass,
  tyre,
  rim,
  headlight,
  tailLight,
  metal,
  dark,
  seat,
}

class Vehicle3DPoint {
  final double x;
  final double y;
  final double z;

  const Vehicle3DPoint(this.x, this.y, this.z);

  Vehicle3DPoint operator -(Vehicle3DPoint other) =>
      Vehicle3DPoint(x - other.x, y - other.y, z - other.z);

  Vehicle3DPoint cross(Vehicle3DPoint other) => Vehicle3DPoint(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double dot(Vehicle3DPoint other) => x * other.x + y * other.y + z * other.z;

  Vehicle3DPoint normalized() {
    final length = math.sqrt(x * x + y * y + z * z);
    if (length < 0.000001) return const Vehicle3DPoint(0, 1, 0);
    return Vehicle3DPoint(x / length, y / length, z / length);
  }
}

class Vehicle3DFace {
  final List<int> indices;
  final Vehicle3DPart part;
  final Vehicle3DMaterial material;

  const Vehicle3DFace(
    this.indices, {
    required this.part,
    required this.material,
  });
}

class Vehicle3DMesh {
  final String styleKey;
  final bool isKart;
  final List<Vehicle3DPoint> vertices;
  final List<Vehicle3DFace> faces;
  final int wheelCount;

  const Vehicle3DMesh._({
    required this.styleKey,
    required this.isKart,
    required this.vertices,
    required this.faces,
    required this.wheelCount,
  });

  static final Map<String, Vehicle3DMesh> _cache = {};

  factory Vehicle3DMesh.car(String styleKey) =>
      _cache.putIfAbsent('car:$styleKey', () => _buildCar(styleKey));

  factory Vehicle3DMesh.kart(String styleKey) =>
      _cache.putIfAbsent('kart:$styleKey', () => _buildKart(styleKey));
}

class Vehicle3DProjectedFace {
  final List<Offset> points;
  final double depth;
  final double illumination;
  final Vehicle3DFace source;

  const Vehicle3DProjectedFace({
    required this.points,
    required this.depth,
    required this.illumination,
    required this.source,
  });
}

class _BodySection {
  final double z;
  final double halfWidth;
  final double bottom;
  final double top;

  const _BodySection(this.z, this.halfWidth, this.bottom, this.top);
}

class _MeshBuilder {
  final List<Vehicle3DPoint> vertices = [];
  final List<Vehicle3DFace> faces = [];
  int wheelCount = 0;

  int vertex(double x, double y, double z) {
    vertices.add(Vehicle3DPoint(x, y, z));
    return vertices.length - 1;
  }

  void face(List<int> indices, Vehicle3DPart part, Vehicle3DMaterial material) {
    faces.add(Vehicle3DFace(indices, part: part, material: material));
  }

  void box(
    double cx,
    double cy,
    double cz,
    double width,
    double height,
    double length,
    Vehicle3DMaterial material, {
    Vehicle3DPart part = Vehicle3DPart.detail,
  }) {
    final x0 = cx - width / 2, x1 = cx + width / 2;
    final y0 = cy - height / 2, y1 = cy + height / 2;
    final z0 = cz - length / 2, z1 = cz + length / 2;
    final v = [
      vertex(x0, y0, z0),
      vertex(x1, y0, z0),
      vertex(x1, y1, z0),
      vertex(x0, y1, z0),
      vertex(x0, y0, z1),
      vertex(x1, y0, z1),
      vertex(x1, y1, z1),
      vertex(x0, y1, z1),
    ];
    face([v[0], v[3], v[2], v[1]], part, material);
    face([v[4], v[5], v[6], v[7]], part, material);
    face([v[0], v[4], v[7], v[3]], part, material);
    face([v[1], v[2], v[6], v[5]], part, material);
    face([v[3], v[7], v[6], v[2]], part, material);
    face([v[0], v[1], v[5], v[4]], part, material);
  }

  void loft(List<_BodySection> sections) {
    final rings = <List<int>>[];
    for (final section in sections) {
      final w = section.halfWidth;
      final b = section.bottom;
      final t = section.top;
      final shoulder = b + (t - b) * 0.68;
      rings.add([
        vertex(-w * 0.82, b, section.z),
        vertex(w * 0.82, b, section.z),
        vertex(w, b + (t - b) * 0.20, section.z),
        vertex(w, shoulder, section.z),
        vertex(w * 0.84, t, section.z),
        vertex(-w * 0.84, t, section.z),
        vertex(-w, shoulder, section.z),
        vertex(-w, b + (t - b) * 0.20, section.z),
      ]);
    }
    face(
      rings.first.reversed.toList(),
      Vehicle3DPart.body,
      Vehicle3DMaterial.body,
    );
    face(rings.last, Vehicle3DPart.body, Vehicle3DMaterial.body);
    for (var r = 0; r < rings.length - 1; r++) {
      for (var i = 0; i < 8; i++) {
        final next = (i + 1) % 8;
        face(
          [rings[r][i], rings[r][next], rings[r + 1][next], rings[r + 1][i]],
          Vehicle3DPart.body,
          Vehicle3DMaterial.body,
        );
      }
    }
  }

  void cabin({
    required double halfWidth,
    required double baseY,
    required double topY,
    required double frontZ,
    required double rearZ,
    required double roofFrontZ,
    required double roofRearZ,
  }) {
    final lowerWidth = halfWidth * 0.91;
    final upperWidth = halfWidth * 0.75;
    final v = [
      vertex(-lowerWidth, baseY, rearZ),
      vertex(lowerWidth, baseY, rearZ),
      vertex(lowerWidth, baseY, frontZ),
      vertex(-lowerWidth, baseY, frontZ),
      vertex(-upperWidth, topY, roofRearZ),
      vertex(upperWidth, topY, roofRearZ),
      vertex(upperWidth, topY, roofFrontZ),
      vertex(-upperWidth, topY, roofFrontZ),
    ];
    face([v[0], v[1], v[2], v[3]], Vehicle3DPart.cabin, Vehicle3DMaterial.body);
    face([v[4], v[7], v[6], v[5]], Vehicle3DPart.cabin, Vehicle3DMaterial.body);
    face(
      [v[3], v[2], v[6], v[7]],
      Vehicle3DPart.cabin,
      Vehicle3DMaterial.glass,
    );
    face(
      [v[0], v[4], v[5], v[1]],
      Vehicle3DPart.cabin,
      Vehicle3DMaterial.glass,
    );
    face(
      [v[0], v[3], v[7], v[4]],
      Vehicle3DPart.cabin,
      Vehicle3DMaterial.glass,
    );
    face(
      [v[1], v[5], v[6], v[2]],
      Vehicle3DPart.cabin,
      Vehicle3DMaterial.glass,
    );
  }

  void cylinderX({
    required double cx,
    required double cy,
    required double cz,
    required double radius,
    required double width,
    required Vehicle3DMaterial sideMaterial,
    required Vehicle3DMaterial capMaterial,
    required Vehicle3DPart part,
    int segments = 12,
  }) {
    final left = <int>[], right = <int>[];
    for (var i = 0; i < segments; i++) {
      final angle = i * math.pi * 2 / segments;
      final y = cy + radius * math.sin(angle);
      final z = cz + radius * math.cos(angle);
      left.add(vertex(cx - width / 2, y, z));
      right.add(vertex(cx + width / 2, y, z));
    }
    for (var i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      face([left[i], left[next], right[next], right[i]], part, sideMaterial);
    }
    face(left.reversed.toList(), part, capMaterial);
    face(right, part, capMaterial);
  }

  void wheel(double x, double z, double radius, double width) {
    final y = radius + 0.08;
    cylinderX(
      cx: x,
      cy: y,
      cz: z,
      radius: radius,
      width: width,
      sideMaterial: Vehicle3DMaterial.tyre,
      capMaterial: Vehicle3DMaterial.tyre,
      part: Vehicle3DPart.wheel,
    );
    cylinderX(
      cx: x + (x.isNegative ? -width * 0.46 : width * 0.46),
      cy: y,
      cz: z,
      radius: radius * 0.57,
      width: width * 0.16,
      sideMaterial: Vehicle3DMaterial.metal,
      capMaterial: Vehicle3DMaterial.rim,
      part: Vehicle3DPart.wheel,
      segments: 10,
    );
    wheelCount++;
  }

  Vehicle3DMesh build(String styleKey, bool isKart) => Vehicle3DMesh._(
    styleKey: styleKey,
    isKart: isKart,
    vertices: List.unmodifiable(vertices),
    faces: List.unmodifiable(faces),
    wheelCount: wheelCount,
  );
}

Vehicle3DMesh _buildCar(String styleKey) {
  final b = _MeshBuilder();
  final sport = styleKey == 'sport';
  final suv = styleKey == 'suv';
  final pickup = styleKey == 'pickup';
  final offroad = styleKey == 'offroad';
  final length = pickup
      ? 4.9
      : suv
      ? 4.55
      : offroad
      ? 4.35
      : sport
      ? 4.25
      : 4.4;
  final width = offroad
      ? 1.98
      : suv || pickup
      ? 1.92
      : sport
      ? 1.90
      : 1.82;
  final bodyTop = suv || pickup
      ? 0.84
      : offroad
      ? 0.90
      : sport
      ? 0.56
      : 0.68;
  final wheelRadius = offroad
      ? 0.40
      : suv || pickup
      ? 0.36
      : sport
      ? 0.30
      : 0.32;
  final cabinTop = suv || offroad
      ? 1.62
      : pickup
      ? 1.50
      : sport
      ? 1.00
      : 1.24;
  final cabinFront = pickup
      ? 1.15
      : suv
      ? 1.10
      : offroad
      ? 0.95
      : sport
      ? 0.40
      : 0.68;
  final cabinRear = pickup
      ? -0.10
      : suv
      ? -1.62
      : offroad
      ? -1.40
      : sport
      ? -0.98
      : -1.15;
  final roofFront = pickup
      ? 0.72
      : suv
      ? 0.68
      : offroad
      ? 0.55
      : sport
      ? -0.05
      : 0.20;
  final roofRear = pickup
      ? -0.42
      : suv
      ? -1.28
      : offroad
      ? -1.08
      : sport
      ? -0.70
      : -0.78;

  // 多截面收腰车身：前后保险杠收窄、轮拱处外扩，避免一块长方体
  // 贯穿全车；各车型仍由车长、车宽、座舱和附加结构区分。
  b.loft([
    _BodySection(-length / 2, width * 0.36, 0.30, bodyTop * 0.72),
    _BodySection(-length * 0.43, width * 0.44, 0.26, bodyTop * 0.88),
    _BodySection(-length * 0.31, width * 0.50, 0.23, bodyTop),
    _BodySection(0, width * 0.47, 0.23, bodyTop * 0.98),
    _BodySection(length * 0.30, width * 0.50, 0.23, bodyTop),
    _BodySection(length * 0.43, width * 0.43, 0.26, bodyTop * 0.88),
    _BodySection(
      length / 2,
      width * (sport ? 0.32 : 0.37),
      0.30,
      bodyTop * (sport ? 0.68 : 0.82),
    ),
  ]);
  b.cabin(
    halfWidth: width * 0.48,
    baseY: bodyTop - 0.03,
    topY: cabinTop,
    frontZ: cabinFront,
    rearZ: cabinRear,
    roofFrontZ: roofFront,
    roofRearZ: roofRear,
  );
  if (!pickup) {
    // 车顶玻璃与细面板分割线让俯视车标也能读出座舱，而非一块平顶。
    b.box(
      0,
      cabinTop + 0.012,
      (roofFront + roofRear) / 2,
      width * (sport ? 0.42 : 0.48),
      0.024,
      (roofFront - roofRear) * (suv || offroad ? 0.46 : 0.58),
      Vehicle3DMaterial.glass,
      part: Vehicle3DPart.cabin,
    );
  }
  for (final z in [-length * 0.39, length * 0.39]) {
    b.box(
      0,
      bodyTop + 0.012,
      z,
      width * 0.62,
      0.022,
      0.025,
      Vehicle3DMaterial.dark,
      part: Vehicle3DPart.body,
    );
  }

  final tyreWidth = offroad
      ? 0.30
      : sport
      ? 0.25
      : 0.22;
  for (final z in [-length * 0.31, length * 0.31]) {
    b.wheel(-width * 0.51, z, wheelRadius, tyreWidth);
    b.wheel(width * 0.51, z, wheelRadius, tyreWidth);
  }

  for (final side in [-1.0, 1.0]) {
    b.box(
      side * width * 0.29,
      bodyTop + 0.015,
      length / 2 - 0.10,
      width * 0.22,
      0.055,
      0.22,
      Vehicle3DMaterial.headlight,
      part: Vehicle3DPart.body,
    );
    b.box(
      side * width * 0.31,
      bodyTop + 0.015,
      -length / 2 + 0.10,
      width * 0.20,
      0.055,
      0.22,
      Vehicle3DMaterial.tailLight,
      part: Vehicle3DPart.body,
    );
    b.box(
      side * width * 0.53,
      bodyTop + 0.17,
      cabinFront - 0.18,
      0.18,
      0.10,
      0.22,
      Vehicle3DMaterial.body,
    );
  }
  b.box(
    0,
    bodyTop * 0.54,
    length / 2 + 0.045,
    width * 0.36,
    0.18,
    0.05,
    Vehicle3DMaterial.dark,
    part: Vehicle3DPart.body,
  );
  b.box(
    0,
    0.27,
    length / 2 + 0.07,
    width * 0.88,
    0.10,
    0.10,
    Vehicle3DMaterial.metal,
  );
  b.box(
    0,
    0.29,
    -length / 2 - 0.06,
    width * 0.88,
    0.10,
    0.10,
    Vehicle3DMaterial.dark,
  );

  if (sport) {
    b.box(
      0,
      bodyTop + 0.28,
      -length * 0.41,
      width * 0.82,
      0.08,
      0.25,
      Vehicle3DMaterial.dark,
    );
    for (final x in [-0.48, 0.48]) {
      b.box(
        x,
        bodyTop + 0.13,
        -length * 0.41,
        0.07,
        0.28,
        0.08,
        Vehicle3DMaterial.metal,
      );
    }
  }
  if (suv || offroad) {
    for (final x in [-width * 0.29, width * 0.29]) {
      b.box(
        x,
        cabinTop + 0.06,
        (roofFront + roofRear) / 2,
        0.06,
        0.08,
        roofFront - roofRear + 0.18,
        Vehicle3DMaterial.metal,
      );
    }
  }
  if (offroad) {
    for (final z in [
      roofRear + 0.18,
      (roofFront + roofRear) / 2,
      roofFront - 0.18,
    ]) {
      b.box(
        0,
        cabinTop + 0.10,
        z,
        width * 0.66,
        0.055,
        0.07,
        Vehicle3DMaterial.metal,
      );
    }
    b.box(
      0,
      0.38,
      length / 2 + 0.14,
      width * 0.94,
      0.20,
      0.14,
      Vehicle3DMaterial.dark,
    );
  }
  if (pickup) {
    final bedRear = -length / 2 + 0.28;
    final bedFront = cabinRear - 0.16;
    final y = bodyTop + 0.015;
    final v = [
      b.vertex(-width * 0.35, y, bedRear),
      b.vertex(width * 0.35, y, bedRear),
      b.vertex(width * 0.35, y, bedFront),
      b.vertex(-width * 0.35, y, bedFront),
    ];
    b.face(v, Vehicle3DPart.body, Vehicle3DMaterial.dark);
    for (final x in [-width * 0.41, width * 0.41]) {
      b.box(
        x,
        bodyTop + 0.12,
        (bedRear + bedFront) / 2,
        0.10,
        0.26,
        bedFront - bedRear,
        Vehicle3DMaterial.body,
        part: Vehicle3DPart.body,
      );
    }
  }
  return b.build(styleKey, false);
}

Vehicle3DMesh _buildKart(String styleKey) {
  final b = _MeshBuilder();
  final sport = styleKey == 'sport';
  final offroad = styleKey == 'offroad';
  final noseWidth = sport ? 0.28 : 0.36;
  b.loft([
    _BodySection(-1.02, 0.28, 0.18, 0.34),
    _BodySection(-0.72, 0.36, 0.16, 0.40),
    _BodySection(0.28, 0.31, 0.16, 0.40),
    _BodySection(0.92, 0.27, 0.17, sport ? 0.29 : 0.34),
    _BodySection(1.32, noseWidth, 0.18, sport ? 0.25 : 0.30),
  ]);
  for (final x in [-0.48, 0.48]) {
    b.box(
      x,
      0.31,
      -0.10,
      0.34,
      0.28,
      0.95,
      Vehicle3DMaterial.body,
      part: Vehicle3DPart.body,
    );
  }
  b.box(
    0,
    0.39,
    -0.22,
    0.52,
    0.12,
    0.60,
    Vehicle3DMaterial.seat,
    part: Vehicle3DPart.cabin,
  );
  b.box(
    0,
    0.75,
    -0.52,
    0.58,
    0.72,
    0.16,
    Vehicle3DMaterial.seat,
    part: Vehicle3DPart.cabin,
  );
  b.box(
    0,
    0.52,
    0.28,
    0.07,
    0.55,
    0.07,
    Vehicle3DMaterial.metal,
    part: Vehicle3DPart.cabin,
  );
  b.box(
    0,
    0.78,
    0.28,
    0.40,
    0.07,
    0.10,
    Vehicle3DMaterial.dark,
    part: Vehicle3DPart.cabin,
  );
  b.box(
    0,
    0.45,
    -0.91,
    0.58,
    0.45,
    0.48,
    Vehicle3DMaterial.metal,
    part: Vehicle3DPart.body,
  );
  final frontRadius = offroad ? 0.31 : 0.27;
  final rearRadius = offroad ? 0.36 : 0.32;
  for (final z in [0.82, -0.79]) {
    b.box(0, 0.27, z, 1.52, 0.08, 0.09, Vehicle3DMaterial.metal);
  }
  for (final z in [-1.02, -0.91, -0.80]) {
    b.box(0, 0.69, z, 0.46, 0.035, 0.035, Vehicle3DMaterial.dark);
  }
  for (final x in [-0.83, 0.83]) {
    b.wheel(x, 0.82, frontRadius, 0.27);
    b.wheel(x, -0.79, rearRadius, 0.31);
  }
  b.box(
    0,
    0.20,
    1.25,
    sport ? 1.55 : 1.42,
    0.08,
    0.26,
    Vehicle3DMaterial.body,
    part: Vehicle3DPart.body,
  );
  b.box(
    0,
    0.85,
    -1.14,
    styleKey == 'suv' ? 1.25 : 1.08,
    0.09,
    0.24,
    Vehicle3DMaterial.body,
    part: Vehicle3DPart.body,
  );
  for (final x in [-0.32, 0.32]) {
    b.box(x, 0.62, -1.12, 0.06, 0.44, 0.08, Vehicle3DMaterial.metal);
  }
  b.box(
    0,
    0.32,
    1.43,
    0.34,
    0.09,
    0.05,
    Vehicle3DMaterial.headlight,
    part: Vehicle3DPart.body,
  );
  b.box(
    0,
    0.45,
    -1.20,
    0.28,
    0.09,
    0.05,
    Vehicle3DMaterial.tailLight,
    part: Vehicle3DPart.body,
  );
  return b.build(styleKey, true);
}

class _ProjectedVertex {
  final Offset point;
  final double depth;

  const _ProjectedVertex(this.point, this.depth);
}

/// 透视投影、逐面深度排序和方向光计算。返回的面可直接按列表顺序绘制。
List<Vehicle3DProjectedFace> projectVehicle3DMesh(
  Vehicle3DMesh mesh,
  Size size, {
  double yawDeg = 0,
  double pitchDeg = 0,
  double zoom = 1,
}) {
  if (mesh.vertices.isEmpty ||
      mesh.faces.isEmpty ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return const [];
  }
  final safeYaw = yawDeg.isFinite ? yawDeg : 0.0;
  final safePitch = pitchDeg.isFinite ? pitchDeg.clamp(0.0, 80.0) : 0.0;
  final safeZoom = zoom.isFinite && zoom > 0 ? zoom : 1.0;
  final yaw = safeYaw * math.pi / 180;
  final pitch = safePitch * math.pi / 180;
  final cy = math.cos(yaw), sy = math.sin(yaw);
  final cp = math.cos(pitch), sp = math.sin(pitch);
  const cameraDistance = 10.0;
  final projected = <_ProjectedVertex>[];
  for (final vertex in mesh.vertices) {
    final x = cy * vertex.x + sy * vertex.z;
    final z = -sy * vertex.x + cy * vertex.z;
    final vertical = vertex.y * sp + z * cp;
    final closeness = vertex.y * cp + z * sp;
    final depth = math.max(0.35, cameraDistance - closeness);
    projected.add(
      _ProjectedVertex(Offset(x / depth, -vertical / depth), depth),
    );
  }

  var minX = projected.first.point.dx, maxX = minX;
  var minY = projected.first.point.dy, maxY = minY;
  for (final vertex in projected.skip(1)) {
    minX = math.min(minX, vertex.point.dx);
    maxX = math.max(maxX, vertex.point.dx);
    minY = math.min(minY, vertex.point.dy);
    maxY = math.max(maxY, vertex.point.dy);
  }
  final rawWidth = math.max(0.0001, maxX - minX);
  final rawHeight = math.max(0.0001, maxY - minY);
  final fit =
      math.min(size.width * 0.80 / rawWidth, size.height * 0.80 / rawHeight) *
      safeZoom;
  final centerX = (minX + maxX) / 2;
  final centerY = (minY + maxY) / 2;
  Offset screenPoint(_ProjectedVertex vertex) => Offset(
    size.width / 2 + (vertex.point.dx - centerX) * fit,
    size.height / 2 + (vertex.point.dy - centerY) * fit,
  );

  const light = Vehicle3DPoint(-0.42, 0.82, 0.38);
  final normalizedLight = light.normalized();
  final result = <Vehicle3DProjectedFace>[];
  for (final face in mesh.faces) {
    if (face.indices.length < 3) continue;
    final a = mesh.vertices[face.indices[0]];
    final b = mesh.vertices[face.indices[1]];
    final c = mesh.vertices[face.indices[2]];
    final normal = (b - a).cross(c - a).normalized();
    final diffuse = normal.dot(normalizedLight).abs();
    final illumination = (0.36 + diffuse * 0.64).clamp(0.0, 1.0).toDouble();
    final depth =
        face.indices
            .map((index) => projected[index].depth)
            .reduce((sum, value) => sum + value) /
        face.indices.length;
    result.add(
      Vehicle3DProjectedFace(
        points: face.indices
            .map((index) => screenPoint(projected[index]))
            .toList(growable: false),
        depth: depth,
        illumination: illumination,
        source: face,
      ),
    );
  }
  result.sort((a, b) => b.depth.compareTo(a.depth));
  return result;
}
