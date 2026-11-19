#include "imu_bmi088.h"

#include <Wire.h>

#include "config.h"

namespace {
// BMI088 寄存器
constexpr uint8_t ACC_CHIP_ID = 0x00;
constexpr uint8_t ACC_CHIP_ID_VALUE = 0x1E;
constexpr uint8_t ACC_CONF = 0x40;
constexpr uint8_t ACC_RANGE = 0x41;
constexpr uint8_t ACC_PWR_CONF = 0x7C;
constexpr uint8_t ACC_PWR_CTRL = 0x7D;
constexpr uint8_t ACC_SOFTRESET = 0x7E;
constexpr uint8_t ACC_DATA = 0x12;

constexpr uint8_t GYR_CHIP_ID = 0x00;
constexpr uint8_t GYR_CHIP_ID_VALUE = 0x0F;
constexpr uint8_t GYR_RANGE = 0x0F;
constexpr uint8_t GYR_BANDWIDTH = 0x10;
constexpr uint8_t GYR_LPM1 = 0x11;
constexpr uint8_t GYR_SOFTRESET = 0x14;
constexpr uint8_t GYR_DATA = 0x02;

// ±6g 量程：5460 LSB/g；±500dps 量程：65.6 LSB/dps
constexpr float kAccelLsbPerG = 5460.0f;
constexpr float kGyroLsbPerDps = 65.6f;

int16_t le16(const uint8_t* p) {
  return static_cast<int16_t>(static_cast<uint16_t>(p[0]) |
                              (static_cast<uint16_t>(p[1]) << 8));
}
}  // namespace

bool ImuBmi088::writeReg(uint8_t addr, uint8_t reg, uint8_t value) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

bool ImuBmi088::readRegs(uint8_t addr, uint8_t reg, uint8_t* out, size_t len) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  const size_t got = Wire.requestFrom(static_cast<uint16_t>(addr),
                                      static_cast<uint8_t>(len));
  if (got != len) return false;
  for (size_t i = 0; i < len; ++i) out[i] = Wire.read();
  return true;
}

bool ImuBmi088::begin() {
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQ_HZ);

  uint8_t id = 0;
  if (!readRegs(BMI088_ACC_ADDR, ACC_CHIP_ID, &id, 1) ||
      id != ACC_CHIP_ID_VALUE) {
    Serial.printf("[IMU] accel id mismatch: 0x%02X\n", id);
    return false;
  }
  if (!readRegs(BMI088_GYR_ADDR, GYR_CHIP_ID, &id, 1) ||
      id != GYR_CHIP_ID_VALUE) {
    Serial.printf("[IMU] gyro id mismatch: 0x%02X\n", id);
    return false;
  }

  // 加速度计：软复位 -> 上电 -> 进入正常模式 -> ±6g / 100Hz
  writeReg(BMI088_ACC_ADDR, ACC_SOFTRESET, 0xB6);
  delay(50);
  writeReg(BMI088_ACC_ADDR, ACC_PWR_CTRL, 0x04);  // accel on
  delay(10);
  writeReg(BMI088_ACC_ADDR, ACC_PWR_CONF, 0x00);  // active
  writeReg(BMI088_ACC_ADDR, ACC_RANGE, 0x01);     // ±6g
  writeReg(BMI088_ACC_ADDR, ACC_CONF, 0xA8);      // 100Hz, normal bwp

  // 陀螺仪：软复位 -> 正常模式 -> ±500dps / 100Hz、32Hz 带宽
  writeReg(BMI088_GYR_ADDR, GYR_SOFTRESET, 0xB6);
  delay(30);
  writeReg(BMI088_GYR_ADDR, GYR_LPM1, 0x00);
  writeReg(BMI088_GYR_ADDR, GYR_RANGE, 0x02);     // ±500dps
  writeReg(BMI088_GYR_ADDR, GYR_BANDWIDTH, 0x08); // 100Hz / 32Hz

  delay(20);
  return true;
}

bool ImuBmi088::read() {
  uint8_t raw[6] = {0};

  // 陀螺仪数据 0x02..0x07
  if (!readRegs(BMI088_GYR_ADDR, GYR_DATA, raw, sizeof(raw))) return false;
  for (int i = 0; i < 3; ++i) {
    _gyroDps[i] = le16(&raw[i * 2]) / kGyroLsbPerDps;
  }

  // 加速度计数据必须先空读一次 0x12，再读 6 字节（芯片手册要求）。
  uint8_t dummy = 0;
  readRegs(BMI088_ACC_ADDR, ACC_DATA, &dummy, 1);
  if (!readRegs(BMI088_ACC_ADDR, ACC_DATA, raw, sizeof(raw))) return false;
  for (int i = 0; i < 3; ++i) {
    _accelG[i] = le16(&raw[i * 2]) / kAccelLsbPerG;
  }
  return true;
}
