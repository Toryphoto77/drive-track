#pragma once

#include <Arduino.h>

/// BLE 串口（Nordic UART Service）：把 NMEA 文本推给手机 App。
///
/// UUID 与 App 侧 blediy_gps.dart 一致：
///   服务 6e400001-b5a3-f393-e0a9-e50e24dcca9e
///   TX   6e400003-...（Notify，设备 -> 手机）
///   RX   6e400002-...（Write，手机 -> 设备）
///
/// 带宽：默认 MTU 23 时每包只有 20 字节，10Hz 的 GGA+RMC+GSA 会接近
/// 上限；因此 App 侧连接后会协商 MTU 247，本模块按协商值自动分片。
class BleNus {
 public:
  void begin(const char* deviceName);

  bool isConnected() const { return _connected; }
  uint16_t mtu() const { return _mtu; }

  /// 发送一段文本；未连接或未订阅时直接丢弃，不阻塞 GNSS 读取。
  void send(const char* data, size_t len);

  /// 取一条手机发来的命令（不含换行）。无命令返回 false。
  bool pollCommand(char* out, size_t outSize);

  uint32_t droppedChunks() const { return _dropped; }
  uint32_t sentChunks() const { return _sent; }

  // 供回调使用（内部实现，业务层不要调用）。
  void onConnected(uint16_t connHandle, uint16_t mtu);
  void onDisconnected();
  void onMtuChanged(uint16_t mtu);
  void onRxWrite(const uint8_t* data, size_t len);

 private:
  bool _connected = false;
  uint16_t _connHandle = 0;
  uint16_t _mtu = 23;
  uint32_t _dropped = 0;
  uint32_t _sent = 0;

  char _cmd[64] = {0};
  volatile bool _hasCmd = false;
  portMUX_TYPE _mux = portMUX_INITIALIZER_UNLOCKED;

  // 由 .cpp 内的回调转发过来，避免头文件暴露 NimBLE 类型。
  void* _tx = nullptr;
  void* _server = nullptr;
};
