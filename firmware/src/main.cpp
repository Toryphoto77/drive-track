#include <Arduino.h>

#include <cstring>

#include "baro_bmp390.h"
#include "ble_nus.h"
#include "config.h"
#include "gnss.h"
#include "imu_bmi088.h"
#include "nmea_util.h"

namespace {
GnssReceiver g_gnss;
BleNus g_ble;
#if ENABLE_IMU
ImuBmi088 g_imu;
bool g_imuOk = false;
#endif
#if ENABLE_BARO
BaroBmp390 g_baro;
bool g_baroOk = false;
#endif

uint16_t g_rateHz = GNSS_RATE_HZ;
bool g_hasFix = false;
uint32_t g_lastFixMs = 0;

// 从 GGA 第 7 个字段（fix quality）判断是否有定位。
bool ggaHasFix(const char* line) {
  if (line == nullptr || strstr(line, "GGA") == nullptr) return false;
  int field = 0;
  for (const char* p = line; *p != '\0'; ++p) {
    if (*p == ',') {
      ++field;
      if (field == 6) {
        return p[1] >= '1' && p[1] <= '9';
      }
    }
  }
  return false;
}

void handleCommand(const char* cmd) {
  if (strncmp(cmd, "RATE=", 5) == 0) {
    const int hz = atoi(cmd + 5);
    if (hz >= 1 && hz <= 25) {
      g_rateHz = static_cast<uint16_t>(hz);
      g_gnss.configure(g_rateHz);
      Serial.printf("[CFG] rate -> %u Hz\n", g_rateHz);
    }
  } else if (strcmp(cmd, "STATUS?") == 0) {
    char out[128];
    snprintf(out, sizeof(out),
             "$PDRT,STATUS,rate=%u,fix=%d,lines=%lu,mtu=%u,drops=%lu",
             g_rateHz, g_hasFix ? 1 : 0,
             static_cast<unsigned long>(g_gnss.forwardedLines()), g_ble.mtu(),
             static_cast<unsigned long>(g_ble.droppedChunks()));
    nmeaAppendChecksum(out, sizeof(out));
    g_ble.send(out, strlen(out));
    Serial.print(out);
  } else if (strcmp(cmd, "REBOOT") == 0) {
    Serial.println("[CFG] reboot");
    delay(50);
    ESP.restart();
  }
}
}  // namespace

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("[DriveTrack] booting");

#if ENABLE_STATUS_LED
  pinMode(PIN_STATUS_LED, OUTPUT);
  digitalWrite(PIN_STATUS_LED, LOW);
#endif

  g_gnss.begin();
  g_gnss.configure(g_rateHz);
  Serial.printf("[GNSS] uart1 rx=%d tx=%d rate=%uHz baud=%d\n", PIN_GNSS_RX,
                PIN_GNSS_TX, g_rateHz, GNSS_BAUD_RUN);

#if ENABLE_IMU
  g_imuOk = g_imu.begin();
  Serial.printf("[IMU] %s\n", g_imuOk ? "BMI088 ok" : "BMI088 failed");
#endif
#if ENABLE_BARO
  g_baroOk = g_baro.begin();
  Serial.printf("[BARO] %s\n", g_baroOk ? "BMP390 ok" : "BMP390 failed");
#endif

  g_ble.begin(DEVICE_NAME);
  Serial.printf("[BLE] advertising as %s\n", DEVICE_NAME);
}

void loop() {
  static char line[160];
  static uint32_t lastHealth = 0;
  static uint32_t lastImu = 0;

  // 1) GNSS -> BLE：逐行转发；未连接时 send() 内部直接丢弃，
  //    不会因 BLE 未就绪阻塞串口读取。
  size_t n = 0;
  while ((n = g_gnss.pollLine(line, sizeof(line))) > 0) {
    if (ggaHasFix(line)) {
      g_hasFix = true;
      g_lastFixMs = millis();
    }
    g_ble.send(line, n);
  }

  // 2) 手机命令（RATE= / STATUS? / REBOOT）
  char cmd[64];
  while (g_ble.pollCommand(cmd, sizeof(cmd))) {
    handleCommand(cmd);
  }

  // 3) 定位超时：5 秒没有有效 GGA 视为失锁（与 App 的回落窗口一致）。
  if (g_hasFix && millis() - g_lastFixMs > 5000) {
    g_hasFix = false;
  }

#if ENABLE_IMU
  // IMU 低频采样，仅用于自检 / 后续扩展；默认不占用 BLE 带宽。
  if (g_imuOk && millis() - lastImu >= 200) {
    lastImu = millis();
    if (!g_imu.read()) {
      g_imuOk = false;
      Serial.println("[IMU] read failed, disabled");
    }
  }
#endif

#if ENABLE_BARO
  if (g_baroOk && millis() - lastHealth >= 1000) {
    if (!g_baro.read()) g_baroOk = false;
  }
#endif

#if ENABLE_STATUS_LED
  // 有心跳定位慢闪，无定位快闪。
  const uint32_t period = g_hasFix ? 1000 : 200;
  digitalWrite(PIN_STATUS_LED, (millis() % period) < (period / 2) ? HIGH : LOW);
#endif

  // 4) 每秒健康日志（串口调试口）
  if (millis() - lastHealth >= 5000) {
    lastHealth = millis();
    Serial.printf("[STAT] fix=%d lines=%lu sent=%lu drop=%lu",
                  g_hasFix ? 1 : 0,
                  static_cast<unsigned long>(g_gnss.forwardedLines()),
                  static_cast<unsigned long>(g_ble.sentChunks()),
                  static_cast<unsigned long>(g_ble.droppedChunks()));
#if ENABLE_IMU
    Serial.printf(" imu=%d ax=%.2f ay=%.2f az=%.2f", g_imuOk ? 1 : 0,
                  g_imu.accelG(0), g_imu.accelG(1), g_imu.accelG(2));
#endif
#if ENABLE_BARO
    Serial.printf(" baro=%d p=%.1fhPa t=%.1fC", g_baroOk ? 1 : 0,
                  g_baro.pressureHpa(), g_baro.temperatureC());
#endif
    Serial.println();
  }

  delay(1);
}
