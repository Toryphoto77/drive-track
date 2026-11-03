/// GoPro Open GoPro BLE 协议的纯 Dart 逻辑。
///
/// 来源：GoPro 官方公开文档 Open GoPro（gopro.github.io/OpenGoPro），
/// 包括 BLE 教程 1（连接）、教程 2（TLV 命令）与教程 3（TLV 响应）。
/// 本文件只做字节构造与响应解析，不依赖 Flutter widget，可直接单元测试。
///
/// 诚实边界：
/// - 这里的 UUID 与快门命令字节是公开文档值，不是“已在本机跑通”的证明。
/// - 真正下发命令需要原生层按蓝牙 GATT 写特征并订阅响应特征，
///   现有 MainActivity.kt 没有通用写特征方法（见 device_center.dart 注释
///   与回执里的原生方法规格表），所以 Dart 侧目前只能构造字节、不能执行。
/// - 未在本机验证过的命令一律不写进本文件；WiFi 热点密码等未在公开
///   摘要里核对到编号的特征，本文件不编造编号。

/// GoPro 128-bit UUID 的固定前后缀：GP-XXXX = b5f9XXXX-aa8d-11e3-9046-0002a5d5c51b。
String goproUuid(int suffix) =>
    'b5f9${suffix.toRadixString(16).padLeft(4, '0')}-aa8d-11e3-9046-0002a5d5c51b';

/// 广播里用于过滤 GoPro 的 16-bit 服务 UUID（0xFEA6）。
const String goproAdvertisedServiceUuid =
    '0000fea6-0000-1000-8000-00805f9b34fb';

/// 控制与查询服务（FEA6）下的特征。
const String goproCommandWriteUuid = 'b5f90072-aa8d-11e3-9046-0002a5d5c51b';
const String goproCommandResponseUuid = 'b5f90073-aa8d-11e3-9046-0002a5d5c51b';
const String goproSettingsWriteUuid = 'b5f90074-aa8d-11e3-9046-0002a5d5c51b';
const String goproSettingsResponseUuid = 'b5f90075-aa8d-11e3-9046-0002a5d5c51b';
const String goproQueryWriteUuid = 'b5f90076-aa8d-11e3-9046-0002a5d5c51b';
const String goproQueryResponseUuid = 'b5f90077-aa8d-11e3-9046-0002a5d5c51b';

/// WiFi 热点服务 GP-0001 下已核对的特征：SSID（只读）、热点电源（可写）。
/// 热点密码特征同属该服务，公开摘要里未核对到编号，本文件不编造；
/// 按 Open GoPro 教程 1，读取需加密的特征会触发系统配对弹窗。
const String goproWifiApServiceUuid = 'b5f90001-aa8d-11e3-9046-0002a5d5c51b';
const String goproWifiApSsidUuid = 'b5f90002-aa8d-11e3-9046-0002a5d5c51b';
const String goproWifiApPowerUuid = 'b5f90004-aa8d-11e3-9046-0002a5d5c51b';

/// 扫描过滤条件：广播服务 UUID 列表里含 0xFEA6（大小写不敏感）。
/// 注意：DriveTrack 现有原生扫描只过滤 1818/1816/180d，GoPro 不会出现在
/// 现有扫描结果里；原生补齐扫描过滤前，本函数只用于“识别已拿到的广播”，
/// 不代表本机扫描已能发现 GoPro。
bool isGoProAdvertisement(List<String> serviceUuids) => serviceUuids.any(
      (u) => u.toLowerCase().contains('fea6'),
    );

/// 通用 TLV 命令构造：[总长度, 命令 ID, 参数长度, 参数…]。
/// 例：快门命令 ID=0x01、参数单字节 0x01/0x00 时，得到
/// [0x03, 0x01, 0x01, 0x01]（开）或 [0x03, 0x01, 0x01, 0x00]（关），
/// 与 Open GoPro 教程 2 的 Set Shutter 表一致。
List<int> buildTlvCommand(int commandId, List<int> parameter) {
  final body = <int>[commandId, parameter.length, ...parameter];
  return <int>[body.length, ...body];
}

/// 开始录像：Set Shutter On，公开文档字节 [0x03, 0x01, 0x01, 0x01]。
List<int> buildGoProStartRecording() => buildTlvCommand(0x01, const [0x01]);

/// 停止录像：Set Shutter Off，公开文档字节 [0x03, 0x01, 0x01, 0x00]。
List<int> buildGoProStopRecording() => buildTlvCommand(0x01, const [0x00]);

/// Get Version 命令，公开文档字节 [0x01, 0x51]；连接后应先查版本，
/// 再决定相机支持的命令集（教程 3 建议）。
List<int> buildGoProGetVersion() => const [0x01, 0x51];

/// TLV 命令响应解析结果。
class GoProCommandResponse {
  const GoProCommandResponse({
    required this.commandId,
    required this.status,
    required this.payload,
    required this.raw,
    this.error,
  });

  /// 命令 ID（响应第 2 字节）。
  final int commandId;

  /// 状态字节：0 = 成功，非 0 = 相机返回的错误码。
  final int status;

  bool get ok => error == null && status == 0;

  /// 状态字节之后的载荷（版本查询等有载荷的命令用它）。
  final List<int> payload;

  /// 原始响应字节。
  final List<int> raw;

  /// 解析失败原因；为 null 表示格式合法（成功与否看 [status]）。
  final String? error;
}

/// 解析一条 TLV 命令响应。
///
/// 格式约定（与公开示例一致）：第 1 字节 = 其后字节总数，
/// 第 2 字节 = 命令 ID，第 3 字节 = 状态（0 成功），其余为载荷。
/// 例：快门成功响应 [0x02, 0x01, 0x00]；版本响应
/// [0x06, 0x51, 0x00, 0x01, 0x02, 0x01, 0x00]。
/// 长度不符、字节不足、ID 与期望不符时返回带 [GoProCommandResponse.error]
/// 的结果，调用方绝不能把它当成功处理。多包分片与 protobuf 响应
/// 本函数不处理，遇到即判为解析失败。
GoProCommandResponse parseGoProCommandResponse(
  List<int> bytes, {
  int? expectedCommandId,
}) {
  GoProCommandResponse fail(String reason) => GoProCommandResponse(
        commandId: bytes.length >= 2 ? bytes[1] : -1,
        status: bytes.length >= 3 ? bytes[2] : -1,
        payload: const [],
        raw: List<int>.unmodifiable(bytes),
        error: reason,
      );
  if (bytes.length < 3) return fail('响应过短：至少需要长度、ID、状态 3 字节');
  if (bytes[0] != bytes.length - 1) {
    return fail('长度字节与实际长度不符，可能为分片或非 TLV 响应');
  }
  if (expectedCommandId != null && bytes[1] != expectedCommandId) {
    return fail('响应命令 ID 与期望不符');
  }
  return GoProCommandResponse(
    commandId: bytes[1],
    status: bytes[2],
    payload: List<int>.unmodifiable(bytes.sublist(3)),
    raw: List<int>.unmodifiable(bytes),
  );
}
