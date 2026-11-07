import 'package:flutter/material.dart';

/// 行程 GPS 来源（v1.2.16，B 路：行程 GPS 来源标签）。
///
/// 只做来源标注：不改接管/回落逻辑，不改计时判定与圈速口径。
/// 来源只在保存新行程时由轨迹点 provider 统计一次后存入索引
/// （TripMeta JSON 键 'gps'）；老行程不回填，缺键一律 unknown，
/// 列表与详情页不打标签、不编造来源。
enum GpsSource { external, phone, mixed, unknown }

extension GpsSourceLabel on GpsSource {
  /// 中文标签。unknown 无标签（界面不显示）。
  String get label => switch (this) {
        GpsSource.external => '外接 GPS',
        GpsSource.phone => '手机 GPS',
        GpsSource.mixed => '混合',
        GpsSource.unknown => '',
      };

  /// 徽标配色：外接绿、手机灰、混合琥珀。
  Color get chipColor => switch (this) {
        GpsSource.external => const Color(0xFF4CAF50),
        GpsSource.phone => const Color(0xFF9E9E9E),
        GpsSource.mixed => const Color(0xFFFFB300),
        GpsSource.unknown => Colors.transparent,
      };

  /// JSON 键解析：缺键 / null / 非法值一律回退 unknown，绝不抛错。
  static GpsSource fromKey(String? key) => GpsSource.values.firstWhere(
        (e) => e.name == key,
        orElse: () => GpsSource.unknown,
      );
}

/// 按轨迹点 provider 统计来源（纯函数）。
///
/// provider 实际取值以 recorder.dart 为准：
/// - 外接注入点恒写 'external'（Recorder.onExternalFix）；
/// - 手机点写原生 Location.getProvider() 原始值（'gps' / 'network' /
///   'fused' 等，缺失时为空串，见 Recorder.onLocation）。
/// 因此：'external'（大小写不敏感）归外接；其余非空值一律归手机侧；
/// 空串 / 全空白视为“该点无 provider”，不计入任何一方。
/// 空列表、或全部点都无 provider 时返回 unknown。
GpsSource classifyGpsSource(Iterable<String> providers) {
  var hasExternal = false;
  var hasPhone = false;
  for (final raw in providers) {
    final p = raw.trim().toLowerCase();
    if (p.isEmpty) continue;
    if (p == 'external') {
      hasExternal = true;
    } else {
      hasPhone = true;
    }
  }
  if (hasExternal && hasPhone) return GpsSource.mixed;
  if (hasExternal) return GpsSource.external;
  if (hasPhone) return GpsSource.phone;
  return GpsSource.unknown;
}

/// GPS 来源徽标：彩色圆点 + 中文标签的胶囊。unknown 时返回
/// SizedBox.shrink（不占位、不显示），调用方无需再判空。
class GpsSourceChip extends StatelessWidget {
  final GpsSource source;
  const GpsSourceChip({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    if (source == GpsSource.unknown) return const SizedBox.shrink();
    final color = source.chipColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            source.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// 外接 GPS 的实时连接状态（设备中心写入、赛道设置页等处只读）。
///
/// 只有一个写入方：device_center.dart 的 ExternalGpsSection 在
/// 连接 / 断开事件里调 [updateExternalGpsStatus]；其余页面只
/// 通过 [externalGpsStatus] 监听显示，不自己猜状态。
/// App 启动时默认未连接；状态只在内存里，不持久化。
class ExternalGpsStatus {
  /// 是否已连上外置 GPS（BLE 或 SPP）。
  final bool connected;

  /// 已连接设备的广播名（未连接时为空串）。
  final String deviceName;

  /// 连接通道：'ble' 或 'spp'，未连接时为空串。
  final String channel;

  /// 二进制协议设备（如 DEXIAN D1）：已连通 GATT 但不订阅、不解析、
  /// 不出定位，行程仍用手机 GPS。false = NMEA / SPP 路径，定位
  /// 优先用外接设备。
  final bool binaryOnly;

  const ExternalGpsStatus({
    this.connected = false,
    this.deviceName = '',
    this.channel = '',
    this.binaryOnly = false,
  });

  static const disconnected = ExternalGpsStatus();
}

/// 外接 GPS 连接状态的唯一共享源。
final ValueNotifier<ExternalGpsStatus> externalGpsStatus =
    ValueNotifier<ExternalGpsStatus>(ExternalGpsStatus.disconnected);

/// 设备中心在连接状态变化时调用（唯一写入入口）。
void updateExternalGpsStatus(ExternalGpsStatus status) {
  externalGpsStatus.value = status;
}
