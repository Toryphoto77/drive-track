import 'package:drive_track/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// v1.0.9：首页大方块底部留白公式（不含系统底部 inset 的固定部分）。
// v1.7.4：药丸高 68 + 药丸底部 12 + 间隙 12 = 92；实际底部留白 =
// 92 + MediaQuery.of(context).padding.bottom（见 main.dart _buildModePages）。
void main() {
  test('v1.7.4 home big-action bottom clearance base is 92 (68 pill + 12 bottom + 12 gap)', () {
    expect(kPillNavHeight, 68.0);
    expect(kPillNavHeight + 12 + 12, 92.0);
    // v1.5.4：4 项导航栏加宽到 288（每项仍 72 节距）。
    expect(kPillNavWidth, 288.0);
  });
}
