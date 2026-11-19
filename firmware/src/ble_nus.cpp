#include "ble_nus.h"

#include <NimBLEDevice.h>

#include <cstring>

#include "config.h"

namespace {
constexpr char kServiceUuid[] = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
constexpr char kTxUuid[] = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
constexpr char kRxUuid[] = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

BleNus* g_ble = nullptr;

class ServerCallbacks : public NimBLEServerCallbacks {
 public:
  void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override {
    if (g_ble != nullptr) {
      const uint16_t mtu = server->getPeerMTU(connInfo.getConnHandle());
      g_ble->onConnected(connInfo.getConnHandle(), mtu);
    }
  }

  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo,
                    int reason) override {
    (void)server;
    (void)connInfo;
    (void)reason;
    if (g_ble != nullptr) g_ble->onDisconnected();
    // 断开后重新广播，手机可直接重连。
    NimBLEDevice::startAdvertising();
  }

  void onMTUChange(uint16_t mtu, NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    if (g_ble != nullptr) g_ble->onMtuChanged(mtu);
  }
};

class RxCallbacks : public NimBLECharacteristicCallbacks {
 public:
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    const NimBLEAttValue value = characteristic->getValue();
    if (g_ble != nullptr && value.length() > 0) {
      g_ble->onRxWrite(value.data(), value.length());
    }
  }
};
}  // namespace

void BleNus::begin(const char* deviceName) {
  g_ble = this;
  NimBLEDevice::init(deviceName);
  NimBLEDevice::setMTU(517);  // 本机期望的最大 MTU，实际以协商结果为准

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  _server = server;

  NimBLEService* service = server->createService(kServiceUuid);
  NimBLECharacteristic* tx =
      service->createCharacteristic(kTxUuid, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* rx = service->createCharacteristic(
      kRxUuid, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  rx->setCallbacks(new RxCallbacks());
  _tx = tx;

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setName(deviceName);
  adv->addServiceUUID(NimBLEUUID(kServiceUuid));
  adv->enableScanResponse(true);
  adv->start();
}

void BleNus::send(const char* data, size_t len) {
  if (!_connected || _tx == nullptr || data == nullptr || len == 0) return;
  auto* tx = static_cast<NimBLECharacteristic*>(_tx);

  // 未订阅时 notify() 会返回 false，直接丢弃，避免阻塞串口读取。
  const size_t payload = (_mtu > 23 ? _mtu : 23) - 3;
  size_t offset = 0;
  while (offset < len) {
    const size_t n = (len - offset < payload) ? (len - offset) : payload;
    if (!tx->notify(reinterpret_cast<const uint8_t*>(data + offset), n)) {
      _dropped++;
      return;
    }
    _sent++;
    offset += n;
  }
}

bool BleNus::pollCommand(char* out, size_t outSize) {
  if (!_hasCmd || out == nullptr || outSize == 0) return false;
  bool got = false;
  portENTER_CRITICAL(&_mux);
  if (_hasCmd) {
    strncpy(out, _cmd, outSize - 1);
    out[outSize - 1] = '\0';
    _hasCmd = false;
    got = true;
  }
  portEXIT_CRITICAL(&_mux);
  return got;
}

void BleNus::onConnected(uint16_t connHandle, uint16_t mtu) {
  _connected = true;
  _connHandle = connHandle;
  if (mtu > 0) _mtu = mtu;
  Serial.printf("[BLE] connected, mtu=%u\n", _mtu);
}

void BleNus::onDisconnected() {
  _connected = false;
  _connHandle = 0;
  _mtu = 23;
  Serial.println("[BLE] disconnected, re-advertising");
}

void BleNus::onMtuChanged(uint16_t mtu) {
  if (mtu > 0) _mtu = mtu;
  Serial.printf("[BLE] mtu negotiated: %u\n", _mtu);
}

void BleNus::onRxWrite(const uint8_t* data, size_t len) {
  portENTER_CRITICAL(&_mux);
  size_t n = len < sizeof(_cmd) - 1 ? len : sizeof(_cmd) - 1;
  memcpy(_cmd, data, n);
  // 去掉手机端可能附带的换行 / 回车。
  while (n > 0 && (_cmd[n - 1] == '\n' || _cmd[n - 1] == '\r' ||
                   _cmd[n - 1] == ' ')) {
    --n;
  }
  _cmd[n] = '\0';
  _hasCmd = n > 0;
  portEXIT_CRITICAL(&_mux);
}
