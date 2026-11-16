// BLE 数据通道：Nordic UART Service（与 App 现有 NUS 订阅逻辑一致）。
#pragma once

#include <stddef.h>
#include <stdbool.h>

// 设备广播名，形如 DriveTrack-A1B2。
void dt_ble_init(const char *device_name);

bool dt_ble_connected(void);

// 发送一整行 JSON（内部补 '\n' 并按 MTU 分片）。未连接返回 false。
bool dt_ble_send_line(const char *line);

// App 通过 RX 特征下发的指令（一行 JSON），在此注册回调。
typedef void (*dt_ble_cmd_cb_t)(const char *json, size_t len);
void dt_ble_set_cmd_callback(dt_ble_cmd_cb_t cb);
