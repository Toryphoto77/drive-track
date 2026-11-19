#include "nmea_util.h"

#include <stdio.h>
#include <string.h>

static int hexVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

bool nmeaChecksumOk(const char* line) {
  if (line == nullptr || line[0] != '$') return false;
  const char* star = strchr(line, '*');
  if (star == nullptr) return false;
  if (star[1] == '\0' || star[2] == '\0') return false;
  const int hi = hexVal(star[1]);
  const int lo = hexVal(star[2]);
  if (hi < 0 || lo < 0) return false;
  uint8_t sum = 0;
  for (const char* p = line + 1; p < star; ++p) {
    sum ^= static_cast<uint8_t>(*p);
  }
  return sum == static_cast<uint8_t>((hi << 4) | lo);
}

bool nmeaIsWanted(const char* line) {
  if (!nmeaChecksumOk(line)) return false;
  return strstr(line, "GGA") != nullptr || strstr(line, "RMC") != nullptr ||
         strstr(line, "GSA") != nullptr || strstr(line, "VTG") != nullptr;
}

void nmeaAppendChecksum(char* line, size_t cap) {
  if (line == nullptr || cap == 0 || line[0] != '$') return;
  const size_t len = strlen(line);
  if (len + 5 > cap) return;  // 放不下 *HH\r\n
  uint8_t sum = 0;
  for (size_t i = 1; i < len; ++i) {
    sum ^= static_cast<uint8_t>(line[i]);
  }
  snprintf(line + len, cap - len, "*%02X\r\n", sum);
}
