// GNSS：串口读 NMEA 整句，解析定位与速度，转交会话层。
#pragma once

#include <stdbool.h>

void dt_gnss_start(void);

// 最近一条 NMEA 的定位状态与卫星数，供 /api/status 使用。
bool dt_gnss_last_fix(void);
int dt_gnss_last_sats(void);
