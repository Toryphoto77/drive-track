#pragma once

#include <stdbool.h>
#include <stdint.h>

// 一次气压计读数（已做温度/压力补偿）
typedef struct {
    float temp_c;
    float press_pa;
    float alt_m;   // 以 1013.25 hPa 为基准的粗略海拔
    float rel_alt_m; // 相对开机自动零点的高度，用于赛道高差/坡度
    int64_t ts_us;   // 统一时基（esp_timer，开机微秒）
} dt_baro_sample_t;

// 启动 I2C + BMP390，创建 10 Hz 采样任务。失败返回 false，其余功能不受影响。
bool dt_baro_start(void);

// 取最近一次读数（未启动或尚未采到时返回 false）
bool dt_baro_read(dt_baro_sample_t *out);

// 初始化与采样任务是否已启动，供 /api/status 如实上报。
bool dt_baro_ready(void);

// 自动零点标定是否完成（开机静置采若干帧后自动求基准气压，无需手动操作）。
bool dt_baro_calibrated(void);
