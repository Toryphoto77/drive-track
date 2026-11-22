// WiFi 热点 + HTTP 服务 + 双分区 OTA。热点不再开机常驻，
// 由 App 通过 BLE 下发 {"cmd":"ota-start"} 按需开启，空闲 120s 自动关闭。
//
// 协议（与 lib/firmware_update_service.dart 对齐）：
//   GET  /api/info   -> {model, fw, build, freeHeap, uptimeMs}
//   POST /api/ota    -> 请求体为固件 .bin，头 X-Firmware-Sha256 为 64 位十六进制
//                       校验通过后写入备用分区并重启，返回 {"ok":true}
#pragma once

#include <stdbool.h>

// 按需开启热点与 HTTP 服务。重复调用安全。
void dt_ota_start(void);

// 关闭热点，把射频还给 BLE。升级进行中调用会被忽略。
void dt_ota_stop(void);

bool dt_ota_active(void);

// 热点名，形如 DriveTrack-A1B2；与 BLE 广播名一致。
const char *dt_ota_ssid(void);
