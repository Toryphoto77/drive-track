import 'dart:ui';

import 'package:drive_track/vehicle_3d_models.dart';
import 'package:drive_track/vehicle_markers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('真实三维车辆网格', () {
    test('每种汽车造型都有车身、座舱和四轮，且顶点具有真实高度', () {
      for (final style in CarMarkerStyle.values) {
        final mesh = Vehicle3DMesh.car(style.key);
        expect(mesh.vertices, isNotEmpty, reason: style.key);
        expect(
          mesh.faces.any((f) => f.part == Vehicle3DPart.body),
          isTrue,
          reason: '${style.key} body',
        );
        expect(
          mesh.faces.any((f) => f.part == Vehicle3DPart.cabin),
          isTrue,
          reason: '${style.key} cabin',
        );
        expect(
          mesh.faces.any((f) => f.part == Vehicle3DPart.wheel),
          isTrue,
          reason: '${style.key} wheels',
        );
        expect(mesh.wheelCount, 4, reason: style.key);
        expect(
          mesh.vertices.map((v) => v.y).toSet().length,
          greaterThan(2),
          reason: '${style.key} must have height, not a flat outline',
        );
        expect(
          mesh.vertices.map((v) => v.z).toSet().length,
          greaterThan(2),
          reason: '${style.key} must have length',
        );
      }
    });

    test('五种汽车网格几何互不相同', () {
      final signatures = <String, String>{};
      for (final style in CarMarkerStyle.values) {
        final mesh = Vehicle3DMesh.car(style.key);
        signatures[style.key] = mesh.vertices
            .map(
              (v) =>
                  '${v.x.toStringAsFixed(3)},'
                  '${v.y.toStringAsFixed(3)},${v.z.toStringAsFixed(3)}',
            )
            .join(';');
      }
      expect(signatures.values.toSet().length, CarMarkerStyle.values.length);
    });

    test('卡丁车采用开放式独立网格而不是汽车轮廓换色', () {
      final car = Vehicle3DMesh.car('sedan');
      final kart = Vehicle3DMesh.kart('sedan');
      expect(kart.isKart, isTrue);
      expect(kart.wheelCount, 4);
      expect(kart.faces.any((f) => f.part == Vehicle3DPart.cabin), isTrue);
      expect(kart.vertices.length, isNot(car.vertices.length));
      expect(kart.faces.length, isNot(car.faces.length));
    });
  });

  group('三维透视投影与光照', () {
    test('全部车型与视角的投影坐标和深度均为有限值', () {
      for (final style in CarMarkerStyle.values) {
        for (final isKart in [false, true]) {
          final mesh = isKart
              ? Vehicle3DMesh.kart(style.key)
              : Vehicle3DMesh.car(style.key);
          for (final yaw in [-135.0, 0.0, 42.0, 180.0]) {
            for (final pitch in [0.0, 32.0, 70.0]) {
              final projected = projectVehicle3DMesh(
                mesh,
                const Size(180, 180),
                yawDeg: yaw,
                pitchDeg: pitch,
                zoom: 1.2,
              );
              expect(projected, isNotEmpty);
              for (final face in projected) {
                expect(face.depth.isFinite, isTrue);
                expect(face.depth, greaterThan(0));
                expect(face.illumination.isFinite, isTrue);
                for (final point in face.points) {
                  expect(point.dx.isFinite, isTrue);
                  expect(point.dy.isFinite, isTrue);
                }
              }
            }
          }
        }
      }
    });

    test('面按深度从远到近排序，供画笔遮挡绘制', () {
      final faces = projectVehicle3DMesh(
        Vehicle3DMesh.car('suv'),
        const Size(200, 180),
        yawDeg: 38,
        pitchDeg: 34,
      );
      for (var i = 1; i < faces.length; i++) {
        expect(faces[i - 1].depth, greaterThanOrEqualTo(faces[i].depth));
      }
    });

    test('旋转同时改变屏幕投影和可见面深度', () {
      String signature(List<Vehicle3DProjectedFace> faces) => faces
          .map(
            (f) =>
                '${f.depth.toStringAsFixed(4)}:${f.points.map((p) => '${p.dx.toStringAsFixed(2)},${p.dy.toStringAsFixed(2)}').join('|')}',
          )
          .join(';');
      final mesh = Vehicle3DMesh.car('sport');
      final before = projectVehicle3DMesh(
        mesh,
        const Size(200, 200),
        yawDeg: 0,
        pitchDeg: 32,
      );
      final after = projectVehicle3DMesh(
        mesh,
        const Size(200, 200),
        yawDeg: 90,
        pitchDeg: 32,
      );
      expect(signature(after), isNot(signature(before)));
    });

    test('缩放改变投影尺寸但不产生非有限值', () {
      Rect bounds(List<Vehicle3DProjectedFace> faces) {
        final points = faces.expand((f) => f.points).toList();
        return Rect.fromLTRB(
          points.map((p) => p.dx).reduce((a, b) => a < b ? a : b),
          points.map((p) => p.dy).reduce((a, b) => a < b ? a : b),
          points.map((p) => p.dx).reduce((a, b) => a > b ? a : b),
          points.map((p) => p.dy).reduce((a, b) => a > b ? a : b),
        );
      }

      final mesh = Vehicle3DMesh.car('sedan');
      final normal = bounds(
        projectVehicle3DMesh(
          mesh,
          const Size(200, 200),
          yawDeg: 25,
          pitchDeg: 30,
        ),
      );
      final zoomed = bounds(
        projectVehicle3DMesh(
          mesh,
          const Size(200, 200),
          yawDeg: 25,
          pitchDeg: 30,
          zoom: 1.4,
        ),
      );
      expect(zoomed.width, greaterThan(normal.width));
      expect(zoomed.height, greaterThan(normal.height));
      expect(zoomed.left.isFinite && zoomed.top.isFinite, isTrue);
    });

    test('不同朝向的表面接收不同光照', () {
      final faces = projectVehicle3DMesh(
        Vehicle3DMesh.car('sedan'),
        const Size(200, 200),
        yawDeg: 30,
        pitchDeg: 35,
      );
      expect(
        faces.map((f) => f.illumination.toStringAsFixed(3)).toSet().length,
        greaterThan(2),
      );
      for (final face in faces) {
        expect(face.illumination, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
