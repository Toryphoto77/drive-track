// 本地缓存：SPIFFS 上的 NDJSON 追加文件 + NVS 里的续传游标。
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool dt_store_init(void);

// 记录进行中才落盘，避免日常调试把 Flash 写满。
void dt_store_set_recording(bool recording);

bool dt_store_write_line(const char *line);

// 还有多少字节没同步给 App。
size_t dt_store_backlog(void);

// 续传一步：从游标读最多 max_bytes，经 BLE 发出后推进游标并持久化。
// 返回本次实际发出的字节数；0 表示已同步完或发送失败。
size_t dt_store_sync_step(size_t max_bytes);

// 清空缓存文件并把游标归零（App 确认收全后下发）。
void dt_store_clear(void);
