import 'package:drive_track/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// v1.0.6：首页大方块底部留白公式（不含系统底部 inset 的固定部分）。
// 药丸高 52 + 药丸底部 12 + 间隙 12 = 76；实际底部留白 =
// 76 + MediaQuery.of(context).padding.bottom（见 main.dart _buildModePages）。
void main() {
  test('v1.0.6 home big-action bottom clearance base is 76 (52 pill + 12 bottom + 12 gap)', () {
    expect(kPillNavHeight, 52.0);
    expect(kPillNavHeight + 12 + 12, 76.0);
    expect(kPillNavWidth, 176.0);
  });
}
