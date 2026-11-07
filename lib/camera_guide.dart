import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Insta360 与 DJI 的向导式连接说明数据与页面。
///
/// 铁律：本页绝不显示假的已连接状态。
/// - Insta360 / DJI 目前没有品牌官方 SDK 接入本 App；原生层已有
///   getConnectedWifiSsid（返回当前系统 Wi-Fi SSID），向导页的检测按钮
///   实际调用它。但它只证明手机连了某个 Wi-Fi，不证明连的是相机热点、
///   更不证明品牌 App 已连上相机，所以“已连接”仍只能以品牌 App 内显示
///   与系统 Wi-Fi 实际连接为准，本页只给向导步骤，不宣称本 App 已连上相机。
/// - 页面顶部的 Beta 横幅与状态行必须保留；删掉它们就等于在造假连接。

enum CameraGuideBrand { insta360, dji }

class CameraGuide {
  const CameraGuide({
    required this.brand,
    required this.displayName,
    required this.brandAppName,
    required this.connectionSummary,
    required this.wifiSteps,
    required this.appSteps,
    required this.tripSyncNotes,
    required this.limitations,
  });

  final CameraGuideBrand brand;
  final String displayName;
  final String brandAppName;
  final String connectionSummary;
  final List<String> wifiSteps;
  final List<String> appSteps;
  final List<String> tripSyncNotes;
  final List<String> limitations;
}

const Map<CameraGuideBrand, CameraGuide> cameraGuides = {
  CameraGuideBrand.insta360: CameraGuide(
    brand: CameraGuideBrand.insta360,
    displayName: 'Insta360',
    brandAppName: 'Insta360 App',
    connectionSummary: '向导式连接：相机开 Wi-Fi 热点 → 手机连上该热点 → '
        '在 Insta360 App 内完成连接。本 App 目前不直连相机。',
    wifiSteps: [
      '1. 相机开机，在相机设置里打开 Wi-Fi。',
      '2. 记下相机屏幕显示的 Wi-Fi 热点名称与密码（不要猜默认密码）。',
      '3. 手机打开系统 Wi-Fi 设置，连接该相机热点；连上后可能暂时无互联网。',
      '4. 回到 Insta360 App，按 App 内提示添加并连接相机。',
    ],
    appSteps: [
      '1. 打开 Insta360 App，按提示完成相机添加与配对。',
      '2. 若 App 要求登录或激活账号，按品牌 App 提示完成。',
      '3. 在 App 内确认能看到相机画面 / 文件列表，才算品牌侧连接成功。',
    ],
    tripSyncNotes: [
      '行程结束后，先在 Insta360 App 内导出需要的视频，再通过系统分享或文件方式与行程对齐。',
      '时间对齐需手动核对：以相机视频时间戳与行程开始时间为准。',
      '行车记录中途不要断开相机热点传文件，请停车后操作。',
    ],
    limitations: [
      '不能在 App 内预览、遥控录像或下载相机文件。',
      '热点名称、密码、菜单位置以相机屏幕与品牌 App 为准，各型号可能不同。',
    ],
  ),
  CameraGuideBrand.dji: CameraGuide(
    brand: CameraGuideBrand.dji,
    displayName: 'DJI',
    brandAppName: 'DJI Mimo App（运动相机）',
    connectionSummary: '向导式连接：相机开 Wi-Fi 热点 → 手机连上该热点 → '
        '在 DJI Mimo App 内完成连接。本 App 目前不直连相机。',
    wifiSteps: [
      '1. 相机开机，在相机设置里打开 Wi-Fi。',
      '2. 记下相机屏幕显示的 Wi-Fi 热点名称与密码（不要猜默认密码）。',
      '3. 手机打开系统 Wi-Fi 设置，连接该相机热点；连上后可能暂时无互联网。',
      '4. 回到 DJI Mimo App，按 App 内提示添加并连接相机。',
    ],
    appSteps: [
      '1. 打开 DJI Mimo App，按提示完成相机添加与连接。',
      '2. 若 App 要求登录、激活或固件升级，按品牌 App 提示完成。',
      '3. 在 App 内确认能看到相机画面 / 文件列表，才算品牌侧连接成功。',
      'DJI 无人机用 DJI Fly 等 App，不在本向导范围内。',
    ],
    tripSyncNotes: [
      '行程结束后，先在 DJI Mimo App 内导出需要的视频，再通过系统分享或文件方式与行程对齐。',
      '时间对齐需手动核对：以相机视频时间戳与行程开始时间为准。',
      '行车记录中途不要断开相机热点传文件，请停车后操作。',
    ],
    limitations: [
      '不能在 App 内预览、遥控录像或下载相机文件。',
      '热点名称、密码、菜单位置以相机屏幕与品牌 App 为准，各型号可能不同。',
    ],
  ),
};

/// 向导页：只展示步骤与真实状态说明，不展示“已连接”。
class CameraGuidePage extends StatefulWidget {
  const CameraGuidePage({super.key, required this.brand, this.onBack});

  final CameraGuideBrand brand;
  final VoidCallback? onBack;

  @override
  State<CameraGuidePage> createState() => _CameraGuidePageState();
}

class _CameraGuidePageState extends State<CameraGuidePage> {
  String? _detectNote;

  /// 尝试实际检测当前 Wi-Fi：调用原生层已有的 getConnectedWifiSsid，
  /// 返回当前系统 SSID 或 null；失败时如实显示检测失败，不假装测到了。
  Future<void> _tryDetectWifi() async {
    setState(() => _detectNote = '正在检测…');
    try {
      final ssid = await const MethodChannel('drivetrack/native')
          .invokeMethod<String>('getConnectedWifiSsid');
      setState(() {
        _detectNote = ssid == null || ssid.isEmpty
            ? '未检测到相机热点：请先按下方步骤在系统 Wi-Fi 里连接相机热点。'
            : '当前 Wi-Fi：$ssid（仅为系统当前连接，不代表已连接相机。）';
      });
    } on MissingPluginException {
      setState(() => _detectNote = 'Wi-Fi 检测失败：请按下方步骤在系统 Wi-Fi 里手动确认连接。');
    } on PlatformException {
      setState(() => _detectNote = 'Wi-Fi 检测失败：请按下方步骤在系统 Wi-Fi 里手动确认连接。');
    } catch (_) {
      setState(() => _detectNote = 'Wi-Fi 检测失败：请按下方步骤在系统 Wi-Fi 里手动确认连接。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final guide = cameraGuides[widget.brand]!;
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text('${guide.displayName} 连接向导',
            style: const TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: const Text(
              '本页不显示已连接状态。连接是否成功以系统 Wi-Fi '
              '实际连接与品牌 App 内显示为准。',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          Text(guide.connectionSummary,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _tryDetectWifi,
            icon: const Icon(Icons.wifi_find, size: 18),
            label: const Text('检测当前 Wi-Fi'),
          ),
          if (_detectNote != null) ...[
            const SizedBox(height: 8),
            Text(_detectNote!,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          _Section(title: '一、连接相机 Wi-Fi 热点', lines: guide.wifiSteps),
          _Section(title: '二、在品牌 App 内连接（${guide.brandAppName}）', lines: guide.appSteps),
          _Section(title: '三、行程结束后同步', lines: guide.tripSyncNotes),
          _Section(title: '限制', lines: guide.limitations),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
