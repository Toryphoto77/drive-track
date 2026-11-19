#pragma once

#include <Arduino.h>

/// NEO-M9N 串口接收与 UBX 配置。
///
/// 设计口径：
/// - 只做“配置 + 透传”：不解析经纬度，不重排语句；模块输出什么就按行
///   转发什么，避免在固件里二次引入坐标误差。
/// - 配置用 legacy UBX-CFG-PRT / CFG-RATE / CFG-MSG，M9 系列仍兼容，
///   比 VALSET 键值更不易写错。
/// - 启动时先把 UART1 切到 115200（M9N 出厂 38400），否则 10Hz 以上
///   的 NMEA 带宽不够。
class GnssReceiver {
 public:
  bool begin();

  /// 配置波特率、输出频率与语句集合。须在 begin() 之后调用。
  void configure(uint16_t rateHz);

  /// 取一行完整的、需要转发的 NMEA 语句（含 \r\n）。
  /// 没有完整行时返回 0。
  size_t pollLine(char* out, size_t outSize);

  uint32_t forwardedLines() const { return _forwarded; }
  uint32_t droppedLines() const { return _dropped; }

 private:
  void sendUbx(uint8_t cls, uint8_t id, const uint8_t* payload, uint16_t len);
  void cfgPrt(uint32_t baud);
  void cfgRate(uint16_t measMs);
  void cfgMsg(uint8_t msgClass, uint8_t msgId, uint8_t uart1Rate);

  char _buf[128] = {0};
  size_t _len = 0;
  uint32_t _forwarded = 0;
  uint32_t _dropped = 0;
};
