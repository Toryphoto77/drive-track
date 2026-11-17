// BLE NUS 通道：App 的 nordicUartServiceUuid 等常量是标准 Nordic UART
// 的前 31 个字符（Android 侧用 contains 匹配），所以这里必须用完整的
// 128 位标准 UUID。
#include "dt_ble.h"

#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "host/ble_hs_mbuf.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "os/os_mbuf.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "dt_ble";

// 6e400001-b5a3-f393-e0a9-e50e24dcca9e（NUS 服务）
static const ble_uuid128_t s_svc_uuid =
    BLE_UUID128_INIT(0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
                     0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e);
// 6e400002-...（RX：手机写入）
static const ble_uuid128_t s_rx_uuid =
    BLE_UUID128_INIT(0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
                     0x93, 0xf3, 0xa3, 0xb5, 0x02, 0x00, 0x40, 0x6e);
// 6e400003-...（TX：设备通知）
static const ble_uuid128_t s_tx_uuid =
    BLE_UUID128_INIT(0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
                     0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e);

static uint8_t s_own_addr_type;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_tx_val_handle;
static bool s_subscribed;
static char s_name[24] = "DriveTrack";
static SemaphoreHandle_t s_tx_lock;
static dt_ble_cmd_cb_t s_cmd_cb;

static int dt_ble_access(uint16_t conn_handle, uint16_t attr_handle,
                         struct ble_gatt_access_ctxt *ctxt, void *arg);

static const struct ble_gatt_svc_def s_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_svc_uuid.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {
                    .uuid = &s_rx_uuid.u,
                    .access_cb = dt_ble_access,
                    .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
                },
                {
                    .uuid = &s_tx_uuid.u,
                    .access_cb = dt_ble_access,
                    .flags = BLE_GATT_CHR_F_NOTIFY,
                },
                {0},
            },
    },
    {0},
};

static int dt_ble_gap_event(struct ble_gap_event *event, void *arg);

static void dt_ble_advertise(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = &s_svc_uuid;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "广播数据设置失败 rc=%d", rc);
        return;
    }

    // 128 位服务 UUID 占了广播包大半，名称放进扫描响应。
    struct ble_hs_adv_fields rsp = {0};
    rsp.name = (const uint8_t *)s_name;
    rsp.name_len = (uint8_t)strlen(s_name);
    rsp.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&rsp);
    if (rc != 0) {
        ESP_LOGE(TAG, "扫描响应设置失败 rc=%d", rc);
        return;
    }

    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &params,
                           dt_ble_gap_event, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY) {
        ESP_LOGE(TAG, "开始广播失败 rc=%d", rc);
    } else {
        ESP_LOGI(TAG, "广播中：%s", s_name);
    }
}

static int dt_ble_gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_conn_handle = event->connect.conn_handle;
            s_subscribed = false;
            ESP_LOGI(TAG, "手机已连接 handle=%d", s_conn_handle);
        } else {
            s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
            dt_ble_advertise();
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "连接断开 reason=%d", event->disconnect.reason);
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        s_subscribed = false;
        dt_ble_advertise();
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_tx_val_handle) {
            s_subscribed = event->subscribe.cur_notify;
            ESP_LOGI(TAG, "通知订阅=%d", s_subscribed);
        }
        return 0;

    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "MTU=%d", event->mtu.value);
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        dt_ble_advertise();
        return 0;

    default:
        return 0;
    }
}

static int dt_ble_access(uint16_t conn_handle, uint16_t attr_handle,
                         struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        char buf[192];
        uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
        if (len >= sizeof(buf)) {
            len = sizeof(buf) - 1;
        }
        if (ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL) != 0) {
            return BLE_ATT_ERR_UNLIKELY;
        }
        buf[len] = '\0';
        if (s_cmd_cb != NULL) {
            s_cmd_cb(buf, len);
        }
        return 0;
    }
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        if (os_mbuf_append(ctxt->om, s_name, strlen(s_name)) != 0) {
            return BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        return 0;
    }
    return BLE_ATT_ERR_UNLIKELY;
}

static void dt_ble_on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (rc != 0) {
        ESP_LOGE(TAG, "地址初始化失败 rc=%d", rc);
        return;
    }
    rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "own_addr_type 推断失败 rc=%d", rc);
        return;
    }
    uint16_t def_handle = 0;
    rc = ble_gatts_find_chr(&s_svc_uuid.u, &s_tx_uuid.u, &def_handle,
                            &s_tx_val_handle);
    if (rc != 0) {
        ESP_LOGE(TAG, "未找到 TX 特征 rc=%d", rc);
    }
    dt_ble_advertise();
}

static void dt_ble_on_reset(int reason)
{
    ESP_LOGW(TAG, "协议栈复位 reason=%d", reason);
}

static void dt_ble_host_task(void *param)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void dt_ble_init(const char *device_name)
{
    if (device_name != NULL && device_name[0] != '\0') {
        strncpy(s_name, device_name, sizeof(s_name) - 1);
    }
    s_tx_lock = xSemaphoreCreateMutex();
    configASSERT(s_tx_lock != NULL);

    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = dt_ble_on_sync;
    ble_hs_cfg.reset_cb = dt_ble_on_reset;

    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_svc_gap_device_name_set(s_name);

    int rc = ble_gatts_count_cfg(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_count_cfg rc=%d", rc);
        return;
    }
    rc = ble_gatts_add_svcs(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_add_svcs rc=%d", rc);
        return;
    }

    nimble_port_freertos_init(dt_ble_host_task);
    ESP_LOGI(TAG, "BLE 已启动，名称 %s", s_name);
}

bool dt_ble_connected(void)
{
    return s_conn_handle != BLE_HS_CONN_HANDLE_NONE && s_subscribed;
}

void dt_ble_set_cmd_callback(dt_ble_cmd_cb_t cb)
{
    s_cmd_cb = cb;
}

bool dt_ble_send_line(const char *line)
{
    // 没连上或手机还没订阅 TX 时直接返回 false，
    // 让上层把这一行落到本地缓存，避免数据静默丢失。
    if (line == NULL || s_conn_handle == BLE_HS_CONN_HANDLE_NONE ||
        !s_subscribed) {
        return false;
    }
    if (s_tx_lock == NULL || xSemaphoreTake(s_tx_lock, pdMS_TO_TICKS(200)) != pdTRUE) {
        return false;
    }

    char buf[360];
    size_t len = strlen(line);
    if (len + 1 > sizeof(buf)) {
        len = sizeof(buf) - 2;
    }
    memcpy(buf, line, len);
    buf[len++] = '\n';

    uint16_t mtu = ble_att_mtu(s_conn_handle);
    size_t chunk = (mtu > 23 ? (size_t)mtu : 23) - 3;
    if (chunk > 180) {
        chunk = 180;
    }

    bool ok = true;
    size_t off = 0;
    while (off < len) {
        size_t n = len - off;
        if (n > chunk) {
            n = chunk;
        }
        struct os_mbuf *om = ble_hs_mbuf_from_flat(buf + off, (uint16_t)n);
        if (om == NULL) {
            ok = false;
            break;
        }
        int rc = ble_gatts_notify_custom(s_conn_handle, s_tx_val_handle, om);
        if (rc != 0) {
            os_mbuf_free_chain(om);
            ok = false;
            break;
        }
        off += n;
        // 分片太密会打爆协议栈缓冲，留出一点发送间隔。
        if (off < len) {
            vTaskDelay(pdMS_TO_TICKS(4));
        }
    }

    xSemaphoreGive(s_tx_lock);
    return ok;
}
