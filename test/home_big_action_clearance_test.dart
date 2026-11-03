import 'package:drive_track/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// v1.0.9：首页大方块底部留白公式（不含系统底部 inset 的固定部分）。
// 药丸高 56 + 药丸底部 12 + 间隙 12 = 80；实际底部留白 =
// 80 + MediaQuery.of(context).padding.bottom（见 main.dart _buildModePages）。
void main() {
  test('v1.0.9 home big-action bottom clearance base is 80 (56 pill + 12 bottom + 12 gap)', () {
    expect(kPillNavHeight, 56.0);
    expect(kPillNavHeight + 12 + 12, 80.0);
    expect(kPillNavWidth, 216.0);
  });
}
