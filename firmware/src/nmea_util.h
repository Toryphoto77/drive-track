#pragma once

#include <stddef.h>
#include <stdint.h>

// NMEA 校验：$ 与 * 之间的字符逐位异或，与 * 后两位十六进制比较。
// 无 * 段返回 false（模块输出必须带校验，避免把半行噪声转给 App）。
bool nmeaChecksumOk(const char* line);

// 是否为本固件要转发的定位语句（GGA / RMC / GSA / VTG）。
bool nmeaIsWanted(const char* line);

// 给以 '$' 开头的语句追加 "*HH\r\n"（原地写入，cap 为缓冲区总容量）。
void nmeaAppendChecksum(char* line, size_t cap);
