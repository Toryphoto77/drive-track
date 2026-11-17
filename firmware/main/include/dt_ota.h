// WiFi 热点 + HTTP 服务 + 双分区 OTA。
//
// 协议（与 lib/firmware_update_service.dart 对齐）：
//   GET  /api/info   -> {model, fw, build, freeHeap, uptimeMs}
//   POST /api/ota    -> 请求体为固件 .bin，头 X-Firmware-Sha256 为 64 位十六进制
//                       校验通过后写入备用分区并重启，返回 {"ok":true}
#pragma once

void dt_ota_start(void);
