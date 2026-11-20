// IMU：Bosch BMI088（SPI 双片选），读加速度与角速度并输出姿态角。
#pragma once

#include <stdbool.h>

// 返回 false 表示没有找到芯片（接线或片选不对），调用方继续跑其余功能。
bool dt_imu_start(void);

// 初始化与采样任务是否已启动，供 /api/status 如实上报。
bool dt_imu_ready(void);
