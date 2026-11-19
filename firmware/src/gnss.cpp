#include "gnss.h"

#include <string.h>

#include "config.h"
#include "nmea_util.h"

namespace {
constexpr uint8_t kUbxSync1 = 0xB5;
constexpr uint8_t kUbxSync2 = 0x62;
}  // namespace

bool GnssReceiver::begin() {
  Serial1.end();
  Serial1.begin(GNSS_BAUD_BOOT, SERIAL_8N1, PIN_GNSS_RX, PIN_GNSS_TX);
  delay(50);
  return true;
}

void GnssReceiver::sendUbx(uint8_t cls, uint8_t id, const uint8_t* payload,
                           uint16_t len) {
  uint8_t head[6] = {kUbxSync1, kUbxSync2, cls, id,
                     static_cast<uint8_t>(len & 0xFF),
                     static_cast<uint8_t>(len >> 8)};
  uint8_t ckA = 0;
  uint8_t ckB = 0;
  auto feed = [&](uint8_t b) {
    ckA = static_cast<uint8_t>(ckA + b);
    ckB = static_cast<uint8_t>(ckB + ckA);
  };
  for (uint8_t b : head) feed(b);
  for (uint16_t i = 0; i < len; ++i) feed(payload[i]);

  Serial1.write(head, sizeof(head));
  if (len > 0) Serial1.write(payload, len);
  const uint8_t ck[2] = {ckA, ckB};
  Serial1.write(ck, 2);
  Serial1.flush();
}

void GnssReceiver::cfgPrt(uint32_t baud) {
  // UBX-CFG-PRT: portID=1(UART1), mode=8N1, 115200, 输入输出均允许 UBX+NMEA
  uint8_t p[20] = {0};
  p[0] = 1;  // portID: UART1
  const uint32_t mode = 0x000008D0;  // 8 bit, no parity, 1 stop
  memcpy(&p[4], &mode, 4);
  memcpy(&p[8], &baud, 4);
  const uint16_t proto = 0x0003;  // UBX + NMEA
  memcpy(&p[12], &proto, 2);
  memcpy(&p[14], &proto, 2);
  sendUbx(0x06, 0x00, p, sizeof(p));
}

void GnssReceiver::cfgRate(uint16_t measMs) {
  uint8_t p[6] = {0};
  memcpy(&p[0], &measMs, 2);      // measRate
  const uint16_t navRate = 1;     // 每个测量周期解算一次
  const uint16_t timeRef = 1;     // GPS 时间
  memcpy(&p[2], &navRate, 2);
  memcpy(&p[4], &timeRef, 2);
  sendUbx(0x06, 0x08, p, sizeof(p));
}

void GnssReceiver::cfgMsg(uint8_t msgClass, uint8_t msgId, uint8_t uart1Rate) {
  // UBX-CFG-MSG: class, id, rateDDC, rateUART1, rateUART2, rateUSB, rateSPI
  uint8_t p[7] = {msgClass, msgId, 0, uart1Rate, 0, 0, 0};
  sendUbx(0x06, 0x01, p, sizeof(p));
}

void GnssReceiver::configure(uint16_t rateHz) {
  if (rateHz < 1) rateHz = 10;
  const uint16_t measMs = static_cast<uint16_t>(1000 / rateHz);

  // 1) 先按出厂波特率尝试切到 115200；模块若已是 115200，这一步
  //    自然无效，下面的配置照样生效。
  cfgPrt(GNSS_BAUD_RUN);
  delay(200);
  Serial1.end();
  Serial1.begin(GNSS_BAUD_RUN, SERIAL_8N1, PIN_GNSS_RX, PIN_GNSS_TX);
  delay(100);

  // 2) 输出频率与语句集合。
  //    GGA：位置 + 卫星数 + HDOP + 海拔，App 的 Hz 也按 GGA 计。
  //    RMC：位置 + 速度 + 航向 + UTC。
  //    GSA：定位模式 / 参与解算卫星数。
  //    VTG 关闭（RMC 已带速度）；GSV/GLL 关闭以省带宽。
  cfgRate(measMs);
  cfgMsg(0xF0, 0x00, 1);  // GGA
  cfgMsg(0xF0, 0x04, 1);  // RMC
  cfgMsg(0xF0, 0x02, 1);  // GSA
  cfgMsg(0xF0, 0x05, 0);  // VTG
  cfgMsg(0xF0, 0x03, 0);  // GSV
  cfgMsg(0xF0, 0x01, 0);  // GLL
  delay(100);

  _len = 0;
  _forwarded = 0;
  _dropped = 0;
}

size_t GnssReceiver::pollLine(char* out, size_t outSize) {
  while (Serial1.available() > 0) {
    const int raw = Serial1.read();
    if (raw < 0) break;
    const char c = static_cast<char>(raw);

    if (c == '\n') {
      _buf[_len] = '\0';
      const bool wanted = nmeaIsWanted(_buf);
      if (wanted) {
        const int n = snprintf(out, outSize, "%s\r\n", _buf);
        _forwarded++;
        _len = 0;
        if (n > 0) return static_cast<size_t>(n);
      } else if (_len > 0) {
        _dropped++;
      }
      _len = 0;
      continue;
    }

    if (c == '\r') continue;
    if (_len < sizeof(_buf) - 1) {
      _buf[_len++] = c;
    } else {
      // 超长行（异常）：丢弃并重新同步到下一个换行。
      _len = 0;
      _dropped++;
    }
  }
  return 0;
}
