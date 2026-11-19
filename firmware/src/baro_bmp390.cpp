#include "baro_bmp390.h"

#include "config.h"

bool BaroBmp390::begin() {
  if (!_bmp.begin_I2C(BMP390_ADDR)) {
    Serial.println("[BARO] BMP390 not found");
    return false;
  }
  _bmp.setTemperatureOversampling(BMP3_OVERSAMPLING_8X);
  _bmp.setPressureOversampling(BMP3_OVERSAMPLING_8X);
  _bmp.setIIRFilterCoeff(BMP3_IIR_FILTER_COEFF_3);
  _bmp.setOutputDataRate(BMP3_ODR_50_HZ);
  return true;
}

bool BaroBmp390::read() {
  if (!_bmp.performReading()) return false;
  _pressureHpa = _bmp.pressure / 100.0f;
  _temperatureC = _bmp.temperature;
  return true;
}
