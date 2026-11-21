// 本地缓存：SPIFFS 上的 NDJSON 追加文件 + NVS 里的续传游标。
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool dt_store_init(void);

// 开始一次新会话文件：SD 上生成 session_0001.ndjson 这类独立文件，
// 每次录制不覆盖上一场；SPIFFS 容量小，仍复用单文件并清空。
// 返回 false 表示存储不可用（录制照常，只是不落盘）。
bool dt_store_begin_session(void);

// 当前存储是否在 SD 卡上。SD 才做全量独立记录；
// SPIFFS 只缓存 BLE 断线期间的增量，避免写满片内 Flash。
bool dt_store_is_sd(void);

// 当前会话文件名（不含路径）；未开始会话时返回 NULL。
const char *dt_store_current_file(void);

// 一次录制期间可写的字节数（供 /api/status 展示）。
uint64_t dt_store_free_bytes(void);

// 记录进行中才落盘，避免日常调试把 Flash 写满。
void dt_store_set_recording(bool recording);

// 写一行 NDJSON。delivered 表示这行已经通过 BLE 实时发出：
// SD 全量记录时仍落盘，但游标直接前进，重连后不会重复回放已收到的行。
bool dt_store_write_line(const char *line, bool delivered);

// 还有多少字节没同步给 App。
size_t dt_store_backlog(void);

// 续传一步：从游标读最多 max_bytes，经 BLE 发出后推进游标并持久化。
// 返回本次实际发出的字节数；0 表示已同步完或发送失败。
size_t dt_store_sync_step(size_t max_bytes);

// 清空缓存文件并把游标归零（App 确认收全后下发）。
void dt_store_clear(void);
