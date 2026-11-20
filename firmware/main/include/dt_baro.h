#pragma once

#include <stdbool.h>
#include <stdint.h>

// 一次气压计读数（已做温度/压力补偿）
typedef struct {
    float temp_c;
    float press_pa;
    float alt_m;   // 以 1013.25 hPa 为基准的粗略海拔
} dt_baro_sample_t;

// 启动 I2C + BMP390，创建 1 Hz 采样任务。失败返回 false，其余功能不受影响。
bool dt_baro_start(void);

// 取最近一次读数（未启动或尚未采到时返回 false）
bool dt_baro_read(dt_baro_sample_t *out);
