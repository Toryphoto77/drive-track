// GNSS：u-blox NEO-M9N（UART1）收 NMEA 整句 -> 校验 -> 取 GGA/RMC -> 交给会话层。
//
// 接法（取自 V4.6 网表）：模块 TXD1 -> IO17（ESP32 RX），模块 RXD1 -> IO18（ESP32 TX）。
//
// 模块出厂波特率不一定是 9600，出货批次之间也不一致，所以启动时先探测
// 38400 / 115200 / 9600，命中后只发 UBX 配置（关掉 GSA/GSV、把导航频率提到
// 10 Hz），不改波特率——改波特率失败会把模块留在“谁也不认识”的状态。
#include "dt_gnss.h"

#include <stdlib.h>
#include <string.h>

#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "dt_ble.h"
#include "dt_config.h"
#include "dt_session.h"
#include "dt_types.h"

static const char *TAG = "dt_gnss";

static dt_gps_sample_t s_sample;
static int64_t s_last_emit_us;
static uint32_t s_baud;

// 把 ddmm.mmmm / dddmm.mmmm 转成十进制度。
static bool nmea_coord(const char *field, const char *hemi, double *out)
{
    if (field == NULL || field[0] == '\0' || hemi == NULL || hemi[0] == '\0') {
        return false;
    }
    double raw = strtod(field, NULL);
    if (raw <= 0) {
        return false;
    }
    int deg = (int)(raw / 100.0);
    double min = raw - deg * 100.0;
    double value = deg + min / 60.0;
    if (hemi[0] == 'S' || hemi[0] == 'W') {
        value = -value;
    }
    *out = value;
    return true;
}

static bool sentence_checksum_ok(const char *line)
{
    const char *star = strchr(line, '*');
    if (star == NULL || strlen(star) < 3) {
        // 有些模块不输出校验位，放行。
        return star == NULL;
    }
    uint8_t sum = 0;
    for (const char *p = line + 1; p < star; p++) {
        sum ^= (uint8_t)*p;
    }
    char hex[3] = {star[1], star[2], '\0'};
    unsigned long want = strtoul(hex, NULL, 16);
    return sum == (uint8_t)want;
}

static void parse_fields(char *line, char *fields[], int max_fields, int *count)
{
    int n = 0;
    char *p = line;
    while (p != NULL && n < max_fields) {
        fields[n++] = p;
        char *comma = strchr(p, ',');
        if (comma == NULL) {
            break;
        }
        *comma = '\0';
        p = comma + 1;
    }
    *count = n;
}

static bool field_ends_with(const char *id, const char *suffix)
{
    size_t id_len = strlen(id);
    size_t suffix_len = strlen(suffix);
    return id_len >= suffix_len &&
           strcmp(id + id_len - suffix_len, suffix) == 0;
}

static void maybe_emit(void)
{
    int64_t now = esp_timer_get_time();
    if (now - s_last_emit_us < (int64_t)DT_GNSS_EMIT_MS * 1000) {
        return;
    }
    s_last_emit_us = now;
#if DT_SERIAL_TELEMETRY
    // 首板联调：把定位关键值打到串口，tools/verify_board.ps1 据此判断是否出数。
    static int64_t s_last_log_us;
    if (now - s_last_log_us >= (int64_t)DT_SERIAL_TELEMETRY_MS * 1000) {
        s_last_log_us = now;
        ESP_LOGI(TAG, "fix=%d sats=%u lat=%.6f lon=%.6f spd=%.1f",
                 s_sample.fix ? 1 : 0, (unsigned)s_sample.sats, s_sample.lat,
                 s_sample.lon, s_sample.speed_kph);
    }
#endif
    dt_session_on_gps(&s_sample);
}

static void handle_sentence(char *line)
{
    if (!sentence_checksum_ok(line)) {
        return;
    }

#if DT_BLE_NMEA_PASSTHROUGH
    // App 的蓝牙 GPS 只认标准 NMEA 文本，所以 GGA / RMC 原样转发一份。
    // 必须赶在 parse_fields 把逗号改成 '\0' 之前发出去。
    if (strlen(line) >= 6 &&
        ((strncmp(line + 3, "GGA", 3) == 0) ||
         (strncmp(line + 3, "RMC", 3) == 0))) {
        dt_ble_send_line(line);
    }
#endif

    char *star = strchr(line, '*');
    if (star != NULL) {
        *star = '\0';
    }

    char *fields[20] = {0};
    int count = 0;
    parse_fields(line, fields, 20, &count);
    if (count < 1) {
        return;
    }

    if (field_ends_with(fields[0], "GGA") && count >= 10) {
        int fix_quality = atoi(fields[6]);
        s_sample.fix = fix_quality > 0;
        s_sample.sats = (uint8_t)atoi(fields[7]);
        s_sample.hdop = (float)atof(fields[8]);
        s_sample.alt_m = (float)atof(fields[9]);
        double lat = 0;
        double lon = 0;
        if (nmea_coord(fields[2], fields[3], &lat) &&
            nmea_coord(fields[4], fields[5], &lon)) {
            s_sample.lat = lat;
            s_sample.lon = lon;
        }
        maybe_emit();
        return;
    }

    if (field_ends_with(fields[0], "RMC") && count >= 9) {
        s_sample.fix = fields[2][0] == 'A';
        float knots = (float)atof(fields[7]);
        s_sample.speed_kph = knots * 1.852f;
        s_sample.course_deg = (float)atof(fields[8]);
        double lat = 0;
        double lon = 0;
        if (nmea_coord(fields[3], fields[4], &lat) &&
            nmea_coord(fields[5], fields[6], &lon)) {
            s_sample.lat = lat;
            s_sample.lon = lon;
        }
        maybe_emit();
    }
}

// ---- UBX 下发（只用于配置，不做应答解析）----
static void ubx_send(uint8_t cls, uint8_t id, const uint8_t *payload,
                     uint16_t len)
{
    uint8_t pkt[32];
    size_t n = 0;
    if (len > 20) {
        return;
    }
    pkt[n++] = 0xB5;
    pkt[n++] = 0x62;
    pkt[n++] = cls;
    pkt[n++] = id;
    pkt[n++] = (uint8_t)(len & 0xFF);
    pkt[n++] = (uint8_t)(len >> 8);
    for (uint16_t i = 0; i < len; i++) {
        pkt[n++] = payload[i];
    }
    // 校验从 class 开始，到 payload 结束。
    uint8_t ck_a = 0;
    uint8_t ck_b = 0;
    for (size_t i = 2; i < n; i++) {
        ck_a += pkt[i];
        ck_b += ck_a;
    }
    pkt[n++] = ck_a;
    pkt[n++] = ck_b;
    uart_write_bytes(DT_GNSS_UART_PORT, (const char *)pkt, n);
    uart_wait_tx_done(DT_GNSS_UART_PORT, pdMS_TO_TICKS(200));
}

static void configure_module(void)
{
    // CFG-MSG：把 NMEA GSA(0x02)、GSV(0x03) 的发送间隔设为 0。
    // 卫星数从 GGA 的第 7 字段取，足够用，关掉这两句能省一半串口带宽。
    const uint8_t msg_off_gsa[3] = {0xF0, 0x02, 0x00};
    const uint8_t msg_off_gsv[3] = {0xF0, 0x03, 0x00};
    ubx_send(0x06, 0x01, msg_off_gsa, sizeof(msg_off_gsa));
    ubx_send(0x06, 0x01, msg_off_gsv, sizeof(msg_off_gsv));

#if DT_GNSS_TARGET_HZ > 0
    // CFG-RATE：测量周期(ms)、每周期导航次数、时间基准(1=GPS)。
    uint16_t period = (uint16_t)(1000 / DT_GNSS_TARGET_HZ);
    uint8_t rate[6] = {(uint8_t)(period & 0xFF), (uint8_t)(period >> 8),
                       0x01, 0x00, 0x01, 0x00};
    ubx_send(0x06, 0x08, rate, sizeof(rate));
#endif
    vTaskDelay(pdMS_TO_TICKS(100));
}

// 按给定波特率听 1.2 秒，收到 2 句校验通过的 NMEA 就算命中。
static bool probe_baud(uint32_t baud)
{
    uart_set_baudrate(DT_GNSS_UART_PORT, baud);
    uart_flush_input(DT_GNSS_UART_PORT);
    vTaskDelay(pdMS_TO_TICKS(50));

    char line[96];
    size_t len = 0;
    int valid = 0;
    int64_t deadline = esp_timer_get_time() + 1200000;

    while (esp_timer_get_time() < deadline) {
        uint8_t c = 0;
        int got = uart_read_bytes(DT_GNSS_UART_PORT, &c, 1, pdMS_TO_TICKS(100));
        if (got <= 0) {
            continue;
        }
        if (c == '\n' || c == '\r') {
            if (len > 6) {
                line[len] = '\0';
                if (line[0] == '$' && sentence_checksum_ok(line)) {
                    if (++valid >= 2) {
                        return true;
                    }
                }
            }
            len = 0;
            continue;
        }
        if (len < sizeof(line) - 1) {
            line[len++] = (char)c;
        } else {
            len = 0;  // 超长，多半是波特率不对，丢弃重来
        }
    }
    return false;
}

static void gnss_task(void *arg)
{
    uint8_t chunk[256];
    char line[128];
    size_t len = 0;

    while (true) {
        int got = uart_read_bytes(DT_GNSS_UART_PORT, chunk, sizeof(chunk),
                                 pdMS_TO_TICKS(200));
        for (int i = 0; i < got; i++) {
            char c = (char)chunk[i];
            if (c == '\n' || c == '\r') {
                if (len > 0) {
                    line[len] = '\0';
                    if (line[0] == '$') {
                        handle_sentence(line);
                    }
                    len = 0;
                }
                continue;
            }
            if (len < sizeof(line) - 1) {
                line[len++] = c;
            } else {
                len = 0;  // 超长，丢弃重来
            }
        }
    }
}

void dt_gnss_start(void)
{
    const uart_config_t cfg = {
        .baud_rate = 38400,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_param_config(DT_GNSS_UART_PORT, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "串口参数失败 %s", esp_err_to_name(err));
        return;
    }
    err = uart_set_pin(DT_GNSS_UART_PORT, DT_GNSS_TX_GPIO, DT_GNSS_RX_GPIO,
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "串口引脚失败 %s", esp_err_to_name(err));
        return;
    }
    err = uart_driver_install(DT_GNSS_UART_PORT, DT_GNSS_BUF_SIZE, 512, 0, NULL,
                              0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "串口驱动安装失败 %s", esp_err_to_name(err));
        return;
    }

    static const uint32_t candidates[] = {38400, 115200, 9600};
    s_baud = 0;
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        if (probe_baud(candidates[i])) {
            s_baud = candidates[i];
            break;
        }
    }

    if (s_baud == 0) {
        // 一句都没收到也不能直接退出：可能模块还没定位/没接天线，
        // 先用 9600 跑着，能看到原始日志便于排查。
        s_baud = 9600;
        uart_set_baudrate(DT_GNSS_UART_PORT, s_baud);
        ESP_LOGW(TAG, "未探测到 NMEA，暂按 %u bps 运行", (unsigned)s_baud);
    } else {
        ESP_LOGI(TAG, "GNSS 波特率探测命中 %u bps", (unsigned)s_baud);
#if DT_GNSS_TARGET_HZ > 0
        configure_module();
#endif
    }

    uart_flush_input(DT_GNSS_UART_PORT);
    xTaskCreate(gnss_task, "dt_gnss", 4096, NULL, 5, NULL);
    ESP_LOGI(TAG, "GNSS 已启动 uart%d tx=IO%d rx=IO%d %u bps", DT_GNSS_UART_PORT,
             DT_GNSS_TX_GPIO, DT_GNSS_RX_GPIO, (unsigned)s_baud);
}

bool dt_gnss_last_fix(void)
{
    return s_sample.fix;
}

int dt_gnss_last_sats(void)
{
    return (int)s_sample.sats;
}
