/// 个人资料编辑页测试（v1.5.1，全页跳转替代卡片内编辑器）。
///
/// 覆盖：全部 8 行（昵称/性别/生日/行业/个人签名/座驾品牌/
/// 座驾型号/邮箱）与右上角保存都渲染；昵称为空时不保存、只报
/// 错；填好后保存回传全部字段（含座驾品牌型号）。

import 'package:drive_track/my_page.dart';
import 'package:drive_track/profile_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileEditPage', () {
    testWidgets('8 行 + 保存按钮都渲染，初始值回显', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditPage(
            username: '柴西',
            bio: 'hello',
            email: 'a@b.com',
            gender: '男',
            birthday: '1996-09-29',
            industry: '影视',
            vehicleBrand: '宝马',
            vehicleModel: 'M4',
            onSave: (_) {},
          ),
        ),
      );
      await tester.pump();
      for (final label in [
        '昵称',
        '性别',
        '生日',
        '行业',
        '个人签名',
        '座驾品牌',
        '座驾型号',
        '邮箱',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('柴西'), findsOneWidget);
      expect(find.text('男'), findsOneWidget);
      expect(find.text('1996-09-29'), findsOneWidget);
      expect(find.text('宝马'), findsOneWidget);
      expect(find.text('M4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('昵称为空时不保存、只报错', (tester) async {
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditPage(
            username: '柴西',
            bio: '',
            onSave: (_) => saved = true,
          ),
        ),
      );
      await tester.pump();
      // 清空昵称输入框（第一个 TextField）。
      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('昵称不能为空，请填写后再保存。'), findsOneWidget);
      expect(saved, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('填好后保存回传全部字段', (tester) async {
      ProfileEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditPage(
            username: '柴西',
            bio: '',
            gender: '男',
            birthday: '1996-09-29',
            industry: '影视',
            vehicleBrand: '宝马',
            vehicleModel: 'M4',
            onSave: (r) => result = r,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(result, isNotNull);
      expect(result!.username, '柴西');
      expect(result!.gender, '男');
      expect(result!.birthday, '1996-09-29');
      expect(result!.industry, '影视');
      expect(result!.vehicleBrand, '宝马');
      expect(result!.vehicleModel, 'M4');
      expect(tester.takeException(), isNull);
    });
  });
}
