// microSD 走 SPI3（IMU 占着 SPI2，别混用总线和 DMA 通道）。
//
// 引脚取自 V4.6 网表：CS=IO12、CD=IO13、SCK=IO38、MOSI=IO39、MISO=IO40，
// 其中 IO33~37 被八线 PSRAM 占用，所以 SD 只能用 38/39/40 这组。
#include "dt_sd.h"

#include <string.h>

#include "driver/gpio.h"
#include "driver/sdspi_host.h"
#include "driver/spi_common.h"
#include "esp_log.h"
#include "esp_vfs_fat.h"
#include "sdmmc_cmd.h"

#include "dt_config.h"

static const char *TAG = "dt_sd";

static sdmmc_card_t *s_card;
static int s_state;  // 0=无卡 1=已挂载 2=挂载失败
static uint64_t s_total_kb;
static uint64_t s_free_kb;

// 有卡检测脚就先用它挡掉“没插卡”的 200 ms 超时。
static bool card_present(void)
{
#if DT_SD_CD_GPIO >= 0
    gpio_config_t in = {
        .pin_bit_mask = 1ULL << DT_SD_CD_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&in);
    // V4.6 卡座 CD 是低电平有效。
    return gpio_get_level(DT_SD_CD_GPIO) == 0;
#else
    return true;
#endif
}

void dt_sd_refresh(void)
{
    uint64_t total = 0;
    uint64_t free_bytes = 0;
    if (s_state == 1 &&
        esp_vfs_fat_info(DT_SD_MOUNT_POINT, &total, &free_bytes) == ESP_OK) {
        s_total_kb = total / 1024;
        s_free_kb = free_bytes / 1024;
    }
}

bool dt_sd_init(void)
{
    if (s_state == 1) {
        return true;
    }
    if (!card_present()) {
        s_state = 0;
        ESP_LOGW(TAG, "卡座无卡（CD 电平为空）");
        return false;
    }

    sdmmc_host_t host = SDSPI_HOST_DEFAULT();
    host.slot = SPI3_HOST;
    // 20 MHz：杜邦线或排针转接也能稳定跑，量产可再往上调。
    host.max_freq_khz = 20000;

    spi_bus_config_t bus = {
        .mosi_io_num = DT_SD_MOSI_GPIO,
        .miso_io_num = DT_SD_MISO_GPIO,
        .sclk_io_num = DT_SD_SCK_GPIO,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 4000,
    };
    esp_err_t err = spi_bus_initialize(host.slot, &bus, SDSPI_DEFAULT_DMA);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "SPI3 初始化失败 %s", esp_err_to_name(err));
        s_state = 2;
        return false;
    }

    esp_vfs_fat_sdmmc_mount_config_t mount_cfg = {
        // 绝不自动格式化：用户卡里可能有别的数据。
        .format_if_mount_failed = false,
        .max_files = 5,
        .allocation_unit_size = 16 * 1024,
    };
    sdspi_device_config_t slot = SDSPI_DEVICE_CONFIG_DEFAULT();
    slot.gpio_cs = DT_SD_CS_GPIO;
    slot.host_id = host.slot;

    err = esp_vfs_fat_sdspi_mount(DT_SD_MOUNT_POINT, &host, &slot, &mount_cfg,
                                  &s_card);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "SD 挂载失败 %s（卡未格式化或接触不良）",
                 esp_err_to_name(err));
        s_state = 2;
        return false;
    }

    s_state = 1;
    dt_sd_refresh();
    ESP_LOGI(TAG, "SD 已挂载：%llu MB，剩余 %llu MB",
             (unsigned long long)(s_total_kb / 1024),
             (unsigned long long)(s_free_kb / 1024));
    return true;
}

bool dt_sd_ready(void)
{
    return s_state == 1;
}

int dt_sd_state(void)
{
    return s_state;
}

const char *dt_sd_state_text(void)
{
    switch (s_state) {
    case 1:
        return "ok";
    case 2:
        return "mount_fail";
    default:
        return "no_card";
    }
}

uint64_t dt_sd_total_kb(void)
{
    return s_total_kb;
}

uint64_t dt_sd_free_kb(void)
{
    return s_free_kb;
}

uint64_t dt_sd_free_bytes(void)
{
    return s_free_kb * 1024ULL;
}
