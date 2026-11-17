// CAN / OBD-II：TWAI 收帧，解析常用 OBD PID。
#pragma once

#include <stdbool.h>
#include <stdint.h>

// 返回 false 表示 TWAI 初始化失败（没接收发器或引脚冲突）。
bool dt_can_start(void);

// 主动向 0x7DF 请求一个 OBD PID（轮询由本模块自己排程）。
void dt_can_request_pid(uint8_t pid);
