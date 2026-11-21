// GNSS：u-blox NEO-M9N（UART1）收 NMEA 整句 -> 校验 -> 取 GGA/RMC -> 交给会话层。
//
// 接法（取自 V4.6 网表）：模块 TXD1 -> IO17（ESP32 RX），模块 RXD1 -> IO18（ESP32 TX）。
//
// 模块出厂波特率不一定是 9600，出货批次之间也不一致，所以启动时先探测
// 38400 / 115200 / 9600，命中后只发 UBX 配置（关掉 GSA/GSV、把导航频率提到
// 默认 25 Hz，App 可在 10/20/25 Hz 间切换），不改波特率——改波特率失败会把
// 模块留在“谁也不认识”的状态。
#include "dt_gnss.h"

#include <stdlib.h>
#include <string.h>

#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"

#include "dt_ble.h"
#include "dt_config.h"
#include "dt_session.h"
#include "dt_types.h"

static const char *TAG = "dt_gnss";

static dt_gps_sample_t s_sample;
static int64_t s_last_emit_us;
static uint32_t s_baud;
static volatile int s_rate_hz = DT_GNSS_TARGET_HZ;

static bool valid_rate(int hz)
{
    return hz == 10 || hz == 20 || hz == 25;
}

static void load_saved_rate(void)
{
    nvs_handle_t nvs;
    if (nvs_open(DT_STORE_NVS_NAMESPACE, NVS_READONLY, &nvs) != ESP_OK) {
        return;
    }
    uint8_t saved = 0;
    if (nvs_get_u8(nvs, "gnss_hz", &saved) == ESP_OK && valid_rate(saved)) {
        s_rate_hz = saved;
    }
    nvs_close(nvs);
}

static void save_rate(void)
{
    nvs_handle_t nvs;
    if (nvs_open(DT_STORE_NVS_NAMESPACE, NVS_READWRITE, &nvs) != ESP_OK) {
        ESP_LOGW(TAG, "GNSS 频率无法持久化：NVS 打开失败");
        return;
    }
    esp_err_t err = nvs_set_u8(nvs, "gnss_hz", (uint8_t)s_rate_hz);
    if (err == ESP_OK) {
        err = nvs_commit(nvs);
    }
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "GNSS 频率保存失败 %s", esp_err_to_name(err));
    }
    nvs_close(nvs);
}

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

// ---- 天线诊断：解析 GSV 里的 C/N0（参数见 DT_GNSS_DIAG_*）----
#if DT_GNSS_DIAG_ENABLE
typedef struct {
    char sys;      // talker 第 2 个字符：P=GPS L=GLONASS A=Galileo B=BeiDou Q=QZSS
    uint8_t prn;
    uint8_t cn0;   // dB-Hz
} diag_sat_t;

static diag_sat_t s_diag_sats[DT_GNSS_DIAG_MAX_SATS];
static int s_diag_sat_count;
static bool s_diag_active;
static int64_t s_diag_end_us;
static int64_t s_diag_next_us;

// 同一颗星会被多轮 GSV 重复上报，按 (星座, PRN) 去重并保留最新值。
static void diag_add(char sys, int prn, int cn0)
{
    if (prn <= 0 || prn > 255 || cn0 <= 0) {
        return;
    }
    for (int i = 0; i < s_diag_sat_count; i++) {
        if (s_diag_sats[i].sys == sys && s_diag_sats[i].prn == (uint8_t)prn) {
            s_diag_sats[i].cn0 = (uint8_t)cn0;
            return;
        }
    }
    if (s_diag_sat_count >= DT_GNSS_DIAG_MAX_SATS) {
        return;
    }
    s_diag_sats[s_diag_sat_count].sys = sys;
    s_diag_sats[s_diag_sat_count].prn = (uint8_t)prn;
    s_diag_sats[s_diag_sat_count].cn0 = (uint8_t)cn0;
    s_diag_sat_count++;
}
#endif

static void maybe_emit(void)
{
    int64_t now = esp_timer_get_time();
    if (now - s_last_emit_us < 1000000 / s_rate_hz) {
        return;
    }
    s_last_emit_us = now;
    // 统一时基：GPS 帧使用“收到该句子的 esp_timer 时刻”，
    // App 侧据此与 IMU/气压计做对齐，并扣除 GPS 解算延时。
    s_sample.ts_us = now;
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

#if DT_GNSS_DIAG_ENABLE
    // GSV：每句最多 4 颗星，每组字段为 PRN,仰角,方位,CN0；
    // 末尾不足 4 颗时后面几组没有 CN0，跳过即可。
    if (s_diag_active && field_ends_with(fields[0], "GSV") && count >= 4) {
        char sys = fields[0][2];  // "$GPGSV" -> 'P'
        for (int i = 4; i + 3 < count; i += 4) {
            if (fields[i + 3][0] == '\0') {
                continue;
            }
            diag_add(sys, atoi(fields[i]), atoi(fields[i + 3]));
        }
        return;
    }
#endif

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

static void configure_rate_hz(int hz)
{
    // CFG-RATE：测量周期(ms)、每周期导航次数、时间基准(1=GPS)。
    uint16_t period = (uint16_t)(1000 / hz);
    uint8_t rate[6] = {(uint8_t)(period & 0xFF), (uint8_t)(period >> 8),
                       0x01, 0x00, 0x01, 0x00};
    ubx_send(0x06, 0x08, rate, sizeof(rate));
}

static void configure_rate(void)
{
    configure_rate_hz(s_rate_hz);
}

static void configure_module(void)
{
    // CFG-MSG：把 NMEA GSA(0x02)、GSV(0x03) 的发送间隔设为 0。
    // 卫星数从 GGA 的第 7 字段取，足够用，关掉这两句能省一半串口带宽。
    const uint8_t msg_off_gsa[3] = {0xF0, 0x02, 0x00};
    const uint8_t msg_off_gsv[3] = {0xF0, 0x03, 0x00};
    ubx_send(0x06, 0x01, msg_off_gsa, sizeof(msg_off_gsa));
    ubx_send(0x06, 0x01, msg_off_gsv, sizeof(msg_off_gsv));
    configure_rate();
    vTaskDelay(pdMS_TO_TICKS(100));
}

#if DT_GNSS_DIAG_ENABLE
static void nmea_msg_rate(uint8_t msg_id, uint8_t rate)
{
    const uint8_t payload[3] = {0xF0, msg_id, rate};
    ubx_send(0x06, 0x01, payload, sizeof(payload));
}

// 进入诊断：先降频再开 GSV。顺序反了模块会在 25 Hz 上灌出一大串 GSV，
// 38400 bps 的串口直接溢出，连 GGA/RMC 都会丢。
static void diag_begin(void)
{
    s_diag_sat_count = 0;
    configure_rate_hz(1);
    vTaskDelay(pdMS_TO_TICKS(120));
    nmea_msg_rate(0x03, 1);
    s_diag_active = true;
    s_diag_end_us =
        esp_timer_get_time() + (int64_t)DT_GNSS_DIAG_WINDOW_MS * 1000;
}

static void diag_finish(void)
{
    nmea_msg_rate(0x03, 0);
    configure_rate();
    s_diag_active = false;
    s_diag_next_us =
        esp_timer_get_time() + (int64_t)DT_GNSS_DIAG_PERIOD_S * 1000000;

    if (s_diag_sat_count == 0) {
        ESP_LOGW(TAG, "天线CN0 无卫星数据（检查天线、馈线、接头与供电）");
        return;
    }

    int n = s_diag_sat_count;
    uint8_t cn0[DT_GNSS_DIAG_MAX_SATS];
    int sum = 0;
    for (int i = 0; i < n; i++) {
        cn0[i] = s_diag_sats[i].cn0;
        sum += cn0[i];
    }
    // 插入排序（降序）：最多几十颗星，够用且不额外占栈。
    for (int i = 1; i < n; i++) {
        uint8_t v = cn0[i];
        int j = i - 1;
        while (j >= 0 && cn0[j] < v) {
            cn0[j + 1] = cn0[j];
            j--;
        }
        cn0[j + 1] = v;
    }

    char strong[80];
    size_t off = 0;
    int show = n < DT_GNSS_DIAG_STRONG ? n : DT_GNSS_DIAG_STRONG;
    for (int i = 0; i < show; i++) {
        int wrote = snprintf(strong + off, sizeof(strong) - off, "%s%u",
                             i == 0 ? "" : " ", (unsigned)cn0[i]);
        if (wrote <= 0 || (size_t)wrote >= sizeof(strong) - off) {
            break;
        }
        off += (size_t)wrote;
    }
    ESP_LOGI(TAG, "天线CN0 强星=%s 平均=%.1f 星数=%d", strong,
             (double)sum / (double)n, n);
}

static void diag_tick(void)
{
    int64_t now = esp_timer_get_time();
    if (s_diag_active) {
        if (now >= s_diag_end_us) {
            diag_finish();
        }
        return;
    }
    if (now < s_diag_next_us) {
        return;
    }
    // 录制中保持全速率，顺延到下一轮；天线检查通常在安装/静置时做。
    s_diag_next_us = now + (int64_t)DT_GNSS_DIAG_PERIOD_S * 1000000;
    if (dt_session_active()) {
        return;
    }
    diag_begin();
}
#endif

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
#if DT_GNSS_DIAG_ENABLE
        diag_tick();
#endif
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
    load_saved_rate();
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
#if DT_GNSS_DIAG_ENABLE
    // 第一次诊断等模块完成定位后再做，否则只会打印“无卫星数据”。
    s_diag_next_us =
        esp_timer_get_time() + (int64_t)DT_GNSS_DIAG_FIRST_S * 1000000;
    ESP_LOGI(TAG, "天线诊断已启用：每 %d s 一次（窗口 %d ms），录制中跳过",
             DT_GNSS_DIAG_PERIOD_S, DT_GNSS_DIAG_WINDOW_MS);
#endif
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

int dt_gnss_rate_hz(void)
{
    return s_rate_hz;
}

bool dt_gnss_set_rate(int hz)
{
    if (!valid_rate(hz)) {
        return false;
    }
    if (s_rate_hz == hz) {
        return true;
    }
    s_rate_hz = hz;
    s_last_emit_us = 0;
    save_rate();
    if (s_baud != 0) {
        configure_rate();
    }
    ESP_LOGI(TAG, "GNSS 输出频率已切换为 %d Hz", hz);
    return true;
}
