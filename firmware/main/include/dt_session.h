// 会话层：把传感器数据打包成 JSON 行，负责收发、缓存与汇总。
#pragma once

#include <stddef.h>
#include <stdbool.h>

#include "dt_baro.h"
#include "dt_types.h"

void dt_session_init(void);

void dt_session_on_gps(const dt_gps_sample_t *sample);
void dt_session_on_imu(const dt_imu_sample_t *sample);
void dt_session_on_baro(const dt_baro_sample_t *sample);
void dt_session_on_obd(const dt_obd_sample_t *sample);

bool dt_session_active(void);
void dt_session_start(void);
void dt_session_stop(void);

// App 下发的 JSON 指令（经 BLE RX 进来）。
void dt_session_handle_command(const char *json, size_t len);

// 由主循环每秒调用：心跳、缓存自动续传。
void dt_session_tick(void);
