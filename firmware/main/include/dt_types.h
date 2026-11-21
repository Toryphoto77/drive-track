// 各传感器模块与数据处理层之间的公共数据结构。
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool fix;             // 是否已定位
    uint8_t sats;         // 卫星数
    double lat;           // 十进制度，南纬为负
    double lon;           // 十进制度，西经为负
    float alt_m;
    float speed_kph;
    float course_deg;     // 航向，正北 0，顺时针
    float hdop;
    int64_t ts_us;        // 统一时基：收到该帧时的 esp_timer 微秒数
} dt_gps_sample_t;

typedef struct {
    float ax, ay, az;     // 加速度，单位 g
    float gx, gy, gz;     // 角速度，单位 deg/s
    float roll_deg;
    float pitch_deg;
    int64_t ts_us;        // 统一时基：采样时的 esp_timer 微秒数
} dt_imu_sample_t;

typedef struct {
    bool has_rpm;
    bool has_speed;
    bool has_throttle;
    bool has_coolant;
    float rpm;
    float speed_kph;
    float throttle_pct;
    float coolant_c;
} dt_obd_sample_t;

// 一段记录结束后的本机汇总。App 侧还会做更完整的走线分析，
// 这里只保留掉线时也能独立给出的关键指标。
typedef struct {
    uint32_t duration_s;
    float distance_m;
    float vmax_kph;
    float vavg_kph;
    float max_lat_g;
    float max_long_g;
    uint32_t samples;
} dt_session_summary_t;
