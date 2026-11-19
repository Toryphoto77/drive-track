#pragma once

#include <Arduino.h>
#include <Adafruit_BMP3XX.h>

/// BMP390 气压计：提供气压与温度，可用于海拔平滑（后续接入）。
class BaroBmp390 {
 public:
  bool begin();
  bool read();

  float pressureHpa() const { return _pressureHpa; }
  float temperatureC() const { return _temperatureC; }

 private:
  Adafruit_BMP3XX _bmp;
  float _pressureHpa = 0;
  float _temperatureC = 0;
};
