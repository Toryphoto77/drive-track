/// 外置蓝牙 GPS 接收器的通用层：通道、协议适配器口子、设备名匹配、
/// 定位状态文案。纯逻辑、无 widget，可单测。
///
/// 本文件不持有任何设备的“已支持”断言：每个设备的真实状态以
/// device_center.dart 的档案卡为准；这里只给“通用 NMEA”与
/// “私有协议 stub”两种适配器，以及名称匹配与状态文案的纯函数。
import 'blediy_gps.dart';

/// 经典蓝牙 SPP 服务 UUID（串口协议，全部 SPP 设备共用）。
const String sppServiceUuid = '00001101-0000-1000-8000-00805F1A34B';

/// RaceBox 公开文档里的标准 NMEA UART 服务 / 特征（固件 3.3+ 才提供）。
/// 注意：这是 RaceBox 文档公开值，不是其它厂商的实测值；其它厂商
/// 绝不能套用。主 UART（U-Blox UBX 二进制）是私有协议，不在此列。
const String raceboxNmeaServiceUuid =
    '00001101-0000-1000-8000-00805F9B34FB';
const String raceboxNmeaTxUuid = '00001103-0000-1000-8000-00805F9B34FB';

/// DEXIAN D1 的 BLE 服务 UUID：Dexian Timer 官方 App（1.3.2）拆包实锤——
/// 官方 App 扫描即按此服务过滤。D1 用二进制协议（非 NMEA），官方 App
/// 订阅 GPS 数据 / GPS 时间 / 电池三路通知；数据特征候选为
/// 00000004-…与 00001ff8-…（哪路是数据通道未确认），包格式待实测抓包，
/// 绝不硬编。25Hz（用户确认）。
const String dexianServiceUuid = '00000003-0000-1000-8000-00805f9b34fb';

/// DEXIAN D1 的广播名模式（字符串）：官方 App 按此匹配设备名（如 dexian D1-XXXX），
/// 匹配时大小写不敏感。Dart 3.13 的 RegExp 构造不是 const，因此档案里只存
/// 模式字符串，匹配时再编译（见 device_center.dart 的 _profileNameMatches）。
const String dexianBroadcastNamePattern = r'^dexian\s+(\w+)-(\w+)$';

/// 蓝牙 GPS 的两种传输通道。
enum BtGpsChannel { ble, spp }

/// 协议适配器：按设备分流的口子。通用 NMEA 是唯一已实现的适配器；
/// 私有协议一律以 stub 存在（supported=false + 原因），结构上留出
/// 位置，但绝不假装已解析。
abstract class BtGpsProtocolAdapter {
  const BtGpsProtocolAdapter();

  String get id;
  String get label;
  bool get supported;
  String get note;
}

/// 通用 NMEA 文本适配器：输入即 NMEA 行，解析交给 BleDiyGpsFeed。
class GenericNmeaAdapter extends BtGpsProtocolAdapter {
  const GenericNmeaAdapter();

  @override
  String get id => 'generic_nmea';

  @override
  String get label => '通用 NMEA';

  @override
  bool get supported => true;

  @override
  String get note => '标准 NMEA 0183 文本（GGA / RMC / VTG / GSA）已实现。';
}

/// 私有协议 stub：结构占位，不解析任何字节。
class StubProtocolAdapter extends BtGpsProtocolAdapter {
  const StubProtocolAdapter({
    required this.id,
    required this.label,
    required this.note,
  });

  @override
  final String id;

  @override
  final String label;

  @override
  bool get supported => false;

  @override
  final String note;
}

/// 适配器注册表（按 id 查）。通用 NMEA 真实可用；其余两项是 stub：
/// - racebox_ubx：RaceBox 主 UART 走 U-Blox UBX 二进制，私有协议，
///   本 App 不实现；RaceBox 请走公开的 NMEA UART 服务（固件 3.3+）。
/// - dragy_proprietary：Dragy 私有数据流未公开，本 App 不解析；
///   兜底是 SPP 连接尝试 + BLE NUS 订阅尝试，若设备输出标准 NMEA
///   即可工作，否则暂不支持。
const Map<String, BtGpsProtocolAdapter> btGpsAdapters = {
  'generic_nmea': GenericNmeaAdapter(),
  'racebox_ubx': StubProtocolAdapter(
    id: 'racebox_ubx',
    label: 'RaceBox UBX（二进制）',
    note: 'U-Blox UBX 二进制私有协议暂不实现；请走公开 NMEA UART 服务（固件 3.3+），'
        '且不要同时订阅两种协议（官方文档警告会高丢包）。',
  ),
  'dragy_proprietary': StubProtocolAdapter(
    id: 'dragy_proprietary',
    label: 'Dragy 私有数据流',
    note: 'Dragy 私有数据流协议未公开，本 App 不解析；通用兜底为 SPP 连接尝试 + '
        'BLE NUS 订阅尝试，若设备输出标准 NMEA 即可工作。',
  ),
};

/// 设备名匹配（仅提示，不作身份断言）：
/// - 含分隔符的提示词（如 'p-9'、'bl-818'）用子串匹配（切词会把它拆散）；
/// - 无分隔符的短提示词（长度 ≤3，如 'd1'、'glo'、'drg'）按切词匹配，
///   要求等于某个词或为某个词的前缀：'DRG70' 命中 'drg'，但 'AudioD1x'
///   不命中 'd1'（'d1' 不是 'audiod1x' 的前缀）、'MyGloBall' 不命中
///   'glo'（'glo' 不是 'mygloball' 的前缀）；
/// - 其余长提示词用子串匹配。
bool btGpsNameMatches(String deviceName, List<String> hints) {
  final name = deviceName.toLowerCase();
  if (name.isEmpty) return false;
  final tokens = name
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  for (final hint in hints) {
    final h = hint.toLowerCase();
    if (h.isEmpty) continue;
    final hasSeparator = h.contains(RegExp(r'[^a-z0-9]'));
    if (!hasSeparator && h.length <= 3) {
      if (tokens.any((t) => t == h || t.startsWith(h))) return true;
    } else {
      if (name.contains(h)) return true;
    }
  }
  return false;
}

/// 定位状态文案（纯函数）：GGA 质量为主，GSA 模式为后缀。
/// 质量：1=GPS、2=差分、4=RTK固定、5=RTK浮动、6=估算、0=无效；
/// fix 为 null = 从未收到有效定位。
String btGpsFixStatusLabel(ExternalGpsFix? fix) {
  if (fix == null) return '无定位';
  final q = fix.fixQuality;
  final base = switch (q) {
    null => '定位中',
    0 => '无效定位',
    1 => 'GPS 定位',
    2 => '差分定位',
    4 => 'RTK 固定',
    5 => 'RTK 浮动',
    6 => '估算定位',
    _ => '定位中',
  };
  final mode = switch (fix.fixMode) {
    2 => ' · 2D',
    3 => ' · 3D',
    _ => '',
  };
  return '$base$mode';
}
