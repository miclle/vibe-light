#include "vibe_orientation.h"

#include <stdbool.h>
#include <stdint.h>

#include "driver/i2c.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"

#define ORIENTATION_I2C_PORT I2C_NUM_0
#define ORIENTATION_I2C_SDA_GPIO 15
#define ORIENTATION_I2C_SCL_GPIO 7
#define ORIENTATION_I2C_FREQ_HZ 400000

#define QMI8658_ADDR_PRIMARY 0x6b
#define QMI8658_ADDR_SECONDARY 0x6a
#define QMI8658_REG_WHO_AM_I 0x00
#define QMI8658_REG_CTRL1 0x02
#define QMI8658_REG_CTRL2 0x03
#define QMI8658_REG_CTRL7 0x08
#define QMI8658_REG_AX_L 0x35
#define QMI8658_WHO_AM_I_VALUE 0x05
#define QMI8658_ACCEL_SCALE_MG_PER_LSB_NUM 1000
#define QMI8658_ACCEL_SCALE_MG_PER_LSB_DEN 16384

static const char *TAG = "vibe_orientation";

static bool orientation_ready;
static uint8_t qmi8658_addr;
static vibe_display_orientation_t last_orientation = VIBE_DISPLAY_ORIENTATION_PORTRAIT;

static esp_err_t qmi8658_read_reg(uint8_t addr, uint8_t reg, uint8_t *value);
static esp_err_t qmi8658_write_reg(uint8_t addr, uint8_t reg, uint8_t value);
static bool qmi8658_probe(uint8_t addr);
static bool qmi8658_read_accel_mg(int *x_mg, int *y_mg);
static int16_t read_i16_le(const uint8_t *bytes);

void vibe_orientation_init(void)
{
    i2c_config_t config = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = ORIENTATION_I2C_SDA_GPIO,
        .scl_io_num = ORIENTATION_I2C_SCL_GPIO,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = ORIENTATION_I2C_FREQ_HZ,
        .clk_flags = 0,
    };

    esp_err_t err = i2c_param_config(ORIENTATION_I2C_PORT, &config);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "I2C config failed: %s", esp_err_to_name(err));
        return;
    }

    err = i2c_driver_install(ORIENTATION_I2C_PORT, I2C_MODE_MASTER, 0, 0, 0);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "I2C driver install failed: %s", esp_err_to_name(err));
        return;
    }

    if (qmi8658_probe(QMI8658_ADDR_PRIMARY)) {
        qmi8658_addr = QMI8658_ADDR_PRIMARY;
    } else if (qmi8658_probe(QMI8658_ADDR_SECONDARY)) {
        qmi8658_addr = QMI8658_ADDR_SECONDARY;
    } else {
        ESP_LOGW(TAG, "QMI8658 not found; keeping portrait display");
        return;
    }

    orientation_ready = true;
    ESP_LOGI(TAG, "QMI8658 ready at 0x%02x", qmi8658_addr);
}

vibe_display_orientation_t vibe_orientation_current(void)
{
    int x_mg = 0;
    int y_mg = 0;

    if (!orientation_ready || !qmi8658_read_accel_mg(&x_mg, &y_mg)) {
        return last_orientation;
    }

    last_orientation = vibe_display_orientation_from_accel_mg(x_mg, y_mg, last_orientation);
    return last_orientation;
}

static bool qmi8658_probe(uint8_t addr)
{
    uint8_t who_am_i = 0;
    if (qmi8658_read_reg(addr, QMI8658_REG_WHO_AM_I, &who_am_i) != ESP_OK ||
        who_am_i != QMI8658_WHO_AM_I_VALUE) {
        return false;
    }

    if (qmi8658_write_reg(addr, QMI8658_REG_CTRL1, 0x60) != ESP_OK ||
        qmi8658_write_reg(addr, QMI8658_REG_CTRL2, 0x03) != ESP_OK ||
        qmi8658_write_reg(addr, QMI8658_REG_CTRL7, 0x01) != ESP_OK) {
        return false;
    }
    return true;
}

static bool qmi8658_read_accel_mg(int *x_mg, int *y_mg)
{
    uint8_t bytes[4] = {0};
    esp_err_t err = i2c_master_write_read_device(ORIENTATION_I2C_PORT,
                                                 qmi8658_addr,
                                                 (uint8_t[]){QMI8658_REG_AX_L},
                                                 1,
                                                 bytes,
                                                 sizeof(bytes),
                                                 pdMS_TO_TICKS(20));
    if (err != ESP_OK) {
        ESP_LOGD(TAG, "QMI8658 accel read failed: %s", esp_err_to_name(err));
        return false;
    }

    int x_raw = read_i16_le(&bytes[0]);
    int y_raw = read_i16_le(&bytes[2]);
    *x_mg = (x_raw * QMI8658_ACCEL_SCALE_MG_PER_LSB_NUM) / QMI8658_ACCEL_SCALE_MG_PER_LSB_DEN;
    *y_mg = (y_raw * QMI8658_ACCEL_SCALE_MG_PER_LSB_NUM) / QMI8658_ACCEL_SCALE_MG_PER_LSB_DEN;
    return true;
}

static esp_err_t qmi8658_read_reg(uint8_t addr, uint8_t reg, uint8_t *value)
{
    return i2c_master_write_read_device(ORIENTATION_I2C_PORT,
                                        addr,
                                        &reg,
                                        1,
                                        value,
                                        1,
                                        pdMS_TO_TICKS(20));
}

static esp_err_t qmi8658_write_reg(uint8_t addr, uint8_t reg, uint8_t value)
{
    uint8_t bytes[] = {reg, value};
    return i2c_master_write_to_device(ORIENTATION_I2C_PORT,
                                      addr,
                                      bytes,
                                      sizeof(bytes),
                                      pdMS_TO_TICKS(20));
}

static int16_t read_i16_le(const uint8_t *bytes)
{
    return (int16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}
