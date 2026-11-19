#pragma once

#include <Arduino.h>

/// BMI088 六轴 IMU（加速度计 + 陀螺仪），I2C 直连，不依赖第三方库。
///
/// 说明：当前 App 尚未消费外部 IMU 数据，本模块先负责上电自检与
/// 低频采样，便于验证硬件；数据推送开关见 config.h 的
/// ENABLE_IMU_STREAM，默认关闭。
class ImuBmi088 {
 public:
  bool begin();

  /// 读取一次数据；任一轴读取失败返回 false。
  bool read();

  float accelG(int axis) const { return _accelG[axis]; }    // 0=X 1=Y 2=Z
  float gyroDps(int axis) const { return _gyroDps[axis]; }  // 0=X 1=Y 2=Z

 private:
  bool writeReg(uint8_t addr, uint8_t reg, uint8_t value);
  bool readRegs(uint8_t addr, uint8_t reg, uint8_t* out, size_t len);

  float _accelG[3] = {0, 0, 0};
  float _gyroDps[3] = {0, 0, 0};
};
