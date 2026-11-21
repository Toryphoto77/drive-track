// GNSS：串口读 NMEA 整句，解析定位与速度，转交会话层。
#pragma once

#include <stdbool.h>

void dt_gnss_start(void);

// 最近一条 NMEA 的定位状态与卫星数，供 /api/status 使用。
bool dt_gnss_last_fix(void);
int dt_gnss_last_sats(void);

// 当前导航/上报频率；只接受硬件支持的 10 / 20 / 25 Hz。
// 设置会写入 NVS，掉电后恢复；非法档位返回 false。
int dt_gnss_rate_hz(void);
bool dt_gnss_set_rate(int hz);
