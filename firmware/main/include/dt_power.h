// 电源与指示灯：VBAT 采样、状态灯、低电提示灯。
#pragma once

#include <stdbool.h>

// 启动 ADC 采样与灯控任务。返回 false 表示 ADC 初始化失败。
bool dt_power_start(void);

// 最近一次电池电压（mV）。未采样到返回 0。
int dt_power_batt_mv(void);
