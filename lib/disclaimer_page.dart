import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'card_style.dart';
import 'glass_button.dart';

/// v1.0.2 独立免责声明页（UI 外壳工人新增，第 10 项归属）。
///
/// 由关于页拆出：关于页不再放安全 / 免责区，侧拉菜单“安全说明”
/// 改推本页（见 main.dart _openSafetySection）。
/// 措辞完整，不弱化；以下七条为任务硬性要求，全部在正文里出现：
/// 数据仅供参考、不构成驾驶建议、遵守交通法规、不要在公开道路上
/// 追逐竞技驾驶、不要超速驾驶、仅在正规封闭赛道使用赛道模式、
/// App 不对驾驶行为负责。

/// 免责声明正文条目（短句，不写成长文；前两条为公开道路置顶声明）。
const List<String> kDisclaimerItems = [
  '本 App 提供的轨迹、速度、G 值、评分、油耗与圈速等数据仅供参考，不构成驾驶建议，也不得作为专业计时或安全判断依据。',
  '请始终遵守交通法规，行车中不操作手机，手机须固定在支架上。',
  '不要在公开道路上追逐竞技驾驶。',
  '不要超速驾驶。',
  '赛道模式仅在正规封闭赛道使用，街道模式不适用于竞技驾驶。',
  '汽车须系好安全带，摩托须戴头盔、手套；视频与语音播报不得分散注意力。',
  '定位与行程数据仅存本机，不上传；App 不对驾驶行为负责，因驾驶行为产生的后果由驾驶者自行承担。',
];

class DisclaimerPage extends StatelessWidget {
  /// 主协调接线用路由名（main.dart 已注册本路由）。
  static const String routeName = '/disclaimer';

  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('免责声明'),
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 24, 16, 32)),
        children: [
          const Text(
            '免责声明',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '使用驰迹 DriveTrack 前请阅读以下声明；开始记录即表示你已知悉并接受本声明。',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 16),
          // 置顶两条：红框 + 红色加粗，与其它条目区分，不藏在末尾。
          DriveTrackInnerCard(
            borderColor: Colors.redAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in const [
                  '不要在公开道路上追逐竞技驾驶',
                  '不要超速驾驶',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in kDisclaimerItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
