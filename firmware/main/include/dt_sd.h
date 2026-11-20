// microSD（SPI3 + FATFS）挂载与容量查询。
//
// 卡没插、接触不良或分区损坏时只返回失败，主功能与 BLE 不受影响，
// 会话缓存会自动回落到片内 SPIFFS（见 dt_store.c）。
#pragma once

#include <stdbool.h>
#include <stdint.h>

// 挂载（幂等）。成功返回 true。
bool dt_sd_init(void);

bool dt_sd_ready(void);

// 0=无卡/未初始化，1=已挂载，2=挂载失败（有卡但挂不上，通常是 FAT 损坏）
int dt_sd_state(void);

// 给 /api/status 用的稳定文案：ok / no_card / mount_fail / unmounted
const char *dt_sd_state_text(void);

// 重新读取容量（VFS 层查询，调用频率别太高）。
void dt_sd_refresh(void);

uint64_t dt_sd_total_kb(void);
uint64_t dt_sd_free_kb(void);
uint64_t dt_sd_free_bytes(void);
