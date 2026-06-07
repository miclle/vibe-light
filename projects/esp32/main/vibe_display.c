#include "vibe_display.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_log.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_rgb.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "esp_lcd_panel_io_additions.h"
#include "esp_lcd_st7701.h"
#include "vibe_display_model.h"

static const char *TAG = "vibe_display";

#define LCD_H_RES 320
#define LCD_V_RES 820
#define LCD_BITS_PER_PIXEL 16

#define LCD_SPI_CS_GPIO 0
#define LCD_SPI_SCK_GPIO 2
#define LCD_SPI_SDO_GPIO 1

#define LCD_RGB_DE_GPIO 40
#define LCD_RGB_PCLK_GPIO 41
#define LCD_RGB_VSYNC_GPIO 39
#define LCD_RGB_HSYNC_GPIO 38
#define LCD_RGB_RESET_GPIO 16

#define LCD_RGB_R0_GPIO 17
#define LCD_RGB_R1_GPIO 46
#define LCD_RGB_R2_GPIO 3
#define LCD_RGB_R3_GPIO 8
#define LCD_RGB_R4_GPIO 18

#define LCD_RGB_G0_GPIO 14
#define LCD_RGB_G1_GPIO 13
#define LCD_RGB_G2_GPIO 12
#define LCD_RGB_G3_GPIO 11
#define LCD_RGB_G4_GPIO 10
#define LCD_RGB_G5_GPIO 9

#define LCD_RGB_B0_GPIO 21
#define LCD_RGB_B1_GPIO 5
#define LCD_RGB_B2_GPIO 45
#define LCD_RGB_B3_GPIO 48
#define LCD_RGB_B4_GPIO 47

#define LCD_BACKLIGHT_GPIO 6
// The ESP32-S3-LCD-3.16 backlight PWM is active-low: 0 is full brightness.
#define LCD_BACKLIGHT_DUTY 0

#define RGB565_BLACK 0x0000
#define RGB565_WHITE 0xffff
#define RGB565_MUTED 0x9cd3
#define RGB565_BLUE 0x047f
#define RGB565_PURPLE 0x8010
#define RGB565_GREEN 0x05e0
#define RGB565_RED 0xf800
#define RGB565_AMBER 0xfd20
#define RGB565_PANEL 0x18e3

static esp_lcd_panel_handle_t panel_handle;
static uint16_t *framebuffer;
static SemaphoreHandle_t display_mutex;
static bool display_ready;
static vibe_display_signature_t last_render_signature;

static const st7701_lcd_init_cmd_t lcd_init_cmds[] = {
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x13}, 5, 0},
    {0xEF, (uint8_t[]){0x08}, 1, 0},
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x10}, 5, 0},
    {0xC0, (uint8_t[]){0xE5, 0x02}, 2, 0},
    {0xC1, (uint8_t[]){0x15, 0x0A}, 2, 0},
    {0xC2, (uint8_t[]){0x07, 0x02}, 2, 0},
    {0xCC, (uint8_t[]){0x10}, 1, 0},
    {0xB0, (uint8_t[]){0x00, 0x08, 0x51, 0x0D, 0xCE, 0x06, 0x00, 0x08, 0x08, 0x24, 0x05, 0xD0, 0x0F, 0x6F, 0x36, 0x1F}, 16, 0},
    {0xB1, (uint8_t[]){0x00, 0x10, 0x4F, 0x0C, 0x11, 0x05, 0x00, 0x07, 0x07, 0x18, 0x02, 0xD3, 0x11, 0x6E, 0x34, 0x1F}, 16, 0},
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x11}, 5, 0},
    {0xB0, (uint8_t[]){0x4D}, 1, 0},
    {0xB1, (uint8_t[]){0x37}, 1, 0},
    {0xB2, (uint8_t[]){0x87}, 1, 0},
    {0xB3, (uint8_t[]){0x80}, 1, 0},
    {0xB5, (uint8_t[]){0x4A}, 1, 0},
    {0xB7, (uint8_t[]){0x85}, 1, 0},
    {0xB8, (uint8_t[]){0x21}, 1, 0},
    {0xB9, (uint8_t[]){0x00, 0x13}, 2, 0},
    {0xC0, (uint8_t[]){0x09}, 1, 0},
    {0xC1, (uint8_t[]){0x78}, 1, 0},
    {0xC2, (uint8_t[]){0x78}, 1, 0},
    {0xD0, (uint8_t[]){0x88}, 1, 0},
    {0xE0, (uint8_t[]){0x80, 0x00, 0x02}, 3, 100},
    {0xE1, (uint8_t[]){0x0F, 0xA0, 0x00, 0x00, 0x10, 0xA0, 0x00, 0x00, 0x00, 0x60, 0x60}, 11, 0},
    {0xE2, (uint8_t[]){0x30, 0x30, 0x60, 0x60, 0x45, 0xA0, 0x00, 0x00, 0x46, 0xA0, 0x00, 0x00, 0x00}, 13, 0},
    {0xE3, (uint8_t[]){0x00, 0x00, 0x33, 0x33}, 4, 0},
    {0xE4, (uint8_t[]){0x44, 0x44}, 2, 0},
    {0xE5, (uint8_t[]){0x0F, 0x4A, 0xA0, 0xA0, 0x11, 0x4A, 0xA0, 0xA0, 0x13, 0x4A, 0xA0, 0xA0, 0x15, 0x4A, 0xA0, 0xA0}, 16, 0},
    {0xE6, (uint8_t[]){0x00, 0x00, 0x33, 0x33}, 4, 0},
    {0xE7, (uint8_t[]){0x44, 0x44}, 2, 0},
    {0xE8, (uint8_t[]){0x10, 0x4A, 0xA0, 0xA0, 0x12, 0x4A, 0xA0, 0xA0, 0x14, 0x4A, 0xA0, 0xA0, 0x16, 0x4A, 0xA0, 0xA0}, 16, 0},
    {0xEB, (uint8_t[]){0x02, 0x00, 0x4E, 0x4E, 0xEE, 0x44, 0x00}, 7, 0},
    {0xED, (uint8_t[]){0xFF, 0xFF, 0x04, 0x56, 0x72, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x27, 0x65, 0x40, 0xFF, 0xFF}, 16, 0},
    {0xEF, (uint8_t[]){0x08, 0x08, 0x08, 0x40, 0x3F, 0x64}, 6, 0},
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x13}, 5, 0},
    {0xE8, (uint8_t[]){0x00, 0x0E}, 2, 0},
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x00}, 5, 0},
    {0x11, (uint8_t[]){0x00}, 0, 120},
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x13}, 5, 0},
    {0xE8, (uint8_t[]){0x00, 0x0C}, 2, 10},
    {0xE8, (uint8_t[]){0x00, 0x00}, 2, 0},
    {0xFF, (uint8_t[]){0x77, 0x01, 0x00, 0x00, 0x00}, 5, 0},
    {0x3A, (uint8_t[]){0x55}, 1, 0},
    {0x36, (uint8_t[]){0x00}, 1, 0},
    {0x35, (uint8_t[]){0x00}, 1, 0},
    {0x29, (uint8_t[]){0x00}, 0, 20},
};

static esp_err_t init_backlight(void);
static esp_err_t init_lcd_panel(void);
static void render_status(const vibe_status_packet_t *packet);
static void render_task_rows(const vibe_status_packet_t *packet);
static void fill_screen(uint16_t color);
static void fill_rect(int x, int y, int w, int h, uint16_t color);
static void draw_text(int x, int y, const char *text, int scale, uint16_t color);
static void draw_char(int x, int y, char c, int scale, uint16_t color);
static uint8_t glyph_row(char c, int row);
static uint16_t color_for_state(vibe_display_state_t state);

void vibe_display_init(void)
{
    display_mutex = xSemaphoreCreateMutex();
    if (display_mutex == NULL) {
        ESP_LOGE(TAG, "failed to create display mutex");
        return;
    }

    framebuffer = heap_caps_malloc(LCD_H_RES * LCD_V_RES * sizeof(uint16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (framebuffer == NULL) {
        ESP_LOGE(TAG, "failed to allocate LCD framebuffer");
        return;
    }

    ESP_ERROR_CHECK_WITHOUT_ABORT(init_lcd_panel());
    ESP_ERROR_CHECK_WITHOUT_ABORT(init_backlight());
    vibe_display_signature_reset(&last_render_signature);
    display_ready = panel_handle != NULL;
    ESP_LOGI(TAG, "%s", display_ready ? "LCD initialized" : "LCD initialization failed");
}

void vibe_display_show_status(const vibe_status_packet_t *packet)
{
    if (packet == NULL) {
        return;
    }

    ESP_LOGI(TAG, "Vibe Light | source=%s state=%s detail=%s active=%d waiting=%d error=%d tasks=%d ts=%lld",
             packet->source,
             vibe_display_state_to_string(packet->state),
             packet->detail,
             packet->active_count,
             packet->waiting_count,
             packet->error_count,
             packet->task_count,
             (long long)packet->timestamp_ms);

    if (display_ready && xSemaphoreTake(display_mutex, pdMS_TO_TICKS(500)) == pdTRUE) {
        if (vibe_display_should_render(&last_render_signature, packet)) {
            render_status(packet);
        }
        xSemaphoreGive(display_mutex);
    }
}

void vibe_display_show_error(const char *message)
{
    ESP_LOGW(TAG, "display error: %s", message == NULL ? "unknown error" : message);
}

static esp_err_t init_backlight(void)
{
    ledc_timer_config_t timer_conf = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_8_BIT,
        .timer_num = LEDC_TIMER_3,
        .freq_hz = 50 * 1000,
        .clk_cfg = LEDC_SLOW_CLK_RC_FAST,
    };
    ESP_RETURN_ON_ERROR(ledc_timer_config(&timer_conf), TAG, "configure backlight timer failed");

    ledc_channel_config_t ledc_conf = {
        .gpio_num = LCD_BACKLIGHT_GPIO,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_1,
        .intr_type = LEDC_INTR_DISABLE,
        .timer_sel = LEDC_TIMER_3,
        .duty = LCD_BACKLIGHT_DUTY,
        .hpoint = 0,
    };
    return ledc_channel_config(&ledc_conf);
}

static esp_err_t init_lcd_panel(void)
{
    spi_line_config_t line_config = {
        .cs_io_type = IO_TYPE_GPIO,
        .cs_gpio_num = LCD_SPI_CS_GPIO,
        .scl_io_type = IO_TYPE_GPIO,
        .scl_gpio_num = LCD_SPI_SCK_GPIO,
        .sda_io_type = IO_TYPE_GPIO,
        .sda_gpio_num = LCD_SPI_SDO_GPIO,
        .io_expander = NULL,
    };
    esp_lcd_panel_io_3wire_spi_config_t io_config = ST7701_PANEL_IO_3WIRE_SPI_CONFIG(line_config, 0);
    esp_lcd_panel_io_handle_t io_handle = NULL;
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_3wire_spi(&io_config, &io_handle), TAG, "create 3-wire SPI panel IO failed");

    esp_lcd_rgb_panel_config_t rgb_config = {
        .clk_src = LCD_CLK_SRC_DEFAULT,
        .data_width = 16,
        .bits_per_pixel = 16,
        .num_fbs = 2,
        .bounce_buffer_size_px = 10 * LCD_H_RES,
        .sram_trans_align = 4,
        .psram_trans_align = 64,
        .hsync_gpio_num = LCD_RGB_HSYNC_GPIO,
        .vsync_gpio_num = LCD_RGB_VSYNC_GPIO,
        .de_gpio_num = LCD_RGB_DE_GPIO,
        .pclk_gpio_num = LCD_RGB_PCLK_GPIO,
        .disp_gpio_num = -1,
        .data_gpio_nums = {
            LCD_RGB_B0_GPIO, LCD_RGB_B1_GPIO, LCD_RGB_B2_GPIO, LCD_RGB_B3_GPIO, LCD_RGB_B4_GPIO,
            LCD_RGB_G0_GPIO, LCD_RGB_G1_GPIO, LCD_RGB_G2_GPIO, LCD_RGB_G3_GPIO, LCD_RGB_G4_GPIO, LCD_RGB_G5_GPIO,
            LCD_RGB_R0_GPIO, LCD_RGB_R1_GPIO, LCD_RGB_R2_GPIO, LCD_RGB_R3_GPIO, LCD_RGB_R4_GPIO,
        },
        .timings = {
            .pclk_hz = 18 * 1000 * 1000,
            .h_res = LCD_H_RES,
            .v_res = LCD_V_RES,
            .hsync_pulse_width = 6,
            .hsync_back_porch = 30,
            .hsync_front_porch = 30,
            .vsync_pulse_width = 40,
            .vsync_back_porch = 20,
            .vsync_front_porch = 20,
            .flags.pclk_active_neg = false,
        },
        .flags.fb_in_psram = true,
    };

    st7701_vendor_config_t vendor_config = {
        .rgb_config = &rgb_config,
        .init_cmds = lcd_init_cmds,
        .init_cmds_size = sizeof(lcd_init_cmds) / sizeof(lcd_init_cmds[0]),
        .flags.mirror_by_cmd = 1,
        .flags.enable_io_multiplex = 0,
    };

    const esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = LCD_RGB_RESET_GPIO,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = LCD_BITS_PER_PIXEL,
        .vendor_config = &vendor_config,
    };

    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_st7701(io_handle, &panel_config, &panel_handle), TAG, "create ST7701 panel failed");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_reset(panel_handle), TAG, "reset LCD panel failed");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_init(panel_handle), TAG, "initialize LCD panel failed");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_disp_on_off(panel_handle, true), TAG, "turn LCD panel on failed");
    return ESP_OK;
}

static void render_status(const vibe_status_packet_t *packet)
{
    uint16_t accent = color_for_state(packet->state);
    fill_screen(RGB565_BLACK);
    fill_rect(0, 0, LCD_H_RES, 82, accent);
    fill_rect(18, 110, LCD_H_RES - 36, 170, RGB565_PANEL);
    fill_rect(18, 304, LCD_H_RES - 36, 420, RGB565_PANEL);

    draw_text(24, 22, "VIBE LIGHT", 3, RGB565_WHITE);
    draw_text(32, 132, packet->source, 2, RGB565_WHITE);
    draw_text(32, 178, vibe_display_state_to_title(packet->state), 4, accent);
    draw_text(32, 242, packet->detail, 2, RGB565_MUTED);

    if (packet->task_count > 0) {
        char counts[56];
        snprintf(counts, sizeof(counts), "ACTIVE %d  WAIT %d  ERR %d",
                 packet->active_count,
                 packet->waiting_count,
                 packet->error_count);
        draw_text(32, 318, counts, 2, RGB565_MUTED);
        render_task_rows(packet);
    } else {
        draw_text(32, 330, "NO ACTIVE TASKS", 2, RGB565_MUTED);
        draw_text(32, 386, packet->detail, 3, RGB565_WHITE);
    }

    char ts[48];
    snprintf(ts, sizeof(ts), "TS %lld", (long long)packet->timestamp_ms);
    draw_text(32, 746, ts, 2, RGB565_MUTED);

    esp_lcd_panel_draw_bitmap(panel_handle, 0, 0, LCD_H_RES, LCD_V_RES, framebuffer);
}

static void render_task_rows(const vibe_status_packet_t *packet)
{
    int rows = packet->task_count > VIBE_STATUS_MAX_TASKS ? VIBE_STATUS_MAX_TASKS : packet->task_count;
    for (int i = 0; i < rows; i++) {
        const vibe_status_task_t *task = &packet->tasks[i];
        vibe_display_task_row_t row;
        vibe_display_format_task_row(task, i, &row);

        int y = 360 + i * 70;
        uint16_t task_color = color_for_state(task->state);

        fill_rect(30, y - 10, 6, 54, task_color);
        fill_rect(44, y - 10, 56, 28, task_color);
        draw_text(50, y - 4, row.badge, 1, RGB565_BLACK);
        draw_text(110, y - 8, row.title, 2, RGB565_WHITE);
        draw_text(110, y + 24, row.subtitle, 1, RGB565_MUTED);
    }
}

static void fill_screen(uint16_t color)
{
    for (int i = 0; i < LCD_H_RES * LCD_V_RES; i++) {
        framebuffer[i] = color;
    }
}

static void fill_rect(int x, int y, int w, int h, uint16_t color)
{
    if (x < 0) {
        w += x;
        x = 0;
    }
    if (y < 0) {
        h += y;
        y = 0;
    }
    if (x + w > LCD_H_RES) {
        w = LCD_H_RES - x;
    }
    if (y + h > LCD_V_RES) {
        h = LCD_V_RES - y;
    }
    if (w <= 0 || h <= 0) {
        return;
    }

    for (int row = y; row < y + h; row++) {
        uint16_t *line = framebuffer + row * LCD_H_RES + x;
        for (int col = 0; col < w; col++) {
            line[col] = color;
        }
    }
}

static void draw_text(int x, int y, const char *text, int scale, uint16_t color)
{
    if (text == NULL) {
        return;
    }

    int cursor = x;
    for (const char *p = text; *p != '\0' && cursor < LCD_H_RES - 8; p++) {
        if (*p == '\n') {
            y += 8 * scale;
            cursor = x;
            continue;
        }
        draw_char(cursor, y, *p, scale, color);
        cursor += 6 * scale;
    }
}

static void draw_char(int x, int y, char c, int scale, uint16_t color)
{
    c = (char)toupper((unsigned char)c);
    for (int row = 0; row < 7; row++) {
        uint8_t bits = glyph_row(c, row);
        for (int col = 0; col < 5; col++) {
            if (bits & (1 << (4 - col))) {
                fill_rect(x + col * scale, y + row * scale, scale, scale, color);
            }
        }
    }
}

static uint8_t glyph_row(char c, int row)
{
    static const uint8_t digits[10][7] = {
        {0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e},
        {0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e},
        {0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f},
        {0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e},
        {0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02},
        {0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e},
        {0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e},
        {0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08},
        {0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e},
        {0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c},
    };
    static const uint8_t letters[26][7] = {
        {0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11},
        {0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e},
        {0x0f, 0x10, 0x10, 0x10, 0x10, 0x10, 0x0f},
        {0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e},
        {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f},
        {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10},
        {0x0f, 0x10, 0x10, 0x13, 0x11, 0x11, 0x0f},
        {0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11},
        {0x0e, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0e},
        {0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0e},
        {0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11},
        {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f},
        {0x11, 0x1b, 0x15, 0x15, 0x11, 0x11, 0x11},
        {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11},
        {0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e},
        {0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10},
        {0x0e, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0d},
        {0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11},
        {0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e},
        {0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04},
        {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e},
        {0x11, 0x11, 0x11, 0x11, 0x11, 0x0a, 0x04},
        {0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0a},
        {0x11, 0x11, 0x0a, 0x04, 0x0a, 0x11, 0x11},
        {0x11, 0x11, 0x0a, 0x04, 0x04, 0x04, 0x04},
        {0x1f, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1f},
    };

    if (row < 0 || row >= 7) {
        return 0;
    }
    if (c >= '0' && c <= '9') {
        return digits[c - '0'][row];
    }
    if (c >= 'A' && c <= 'Z') {
        return letters[c - 'A'][row];
    }

    switch (c) {
    case ' ':
        return 0x00;
    case '-':
        return row == 3 ? 0x1f : 0x00;
    case '_':
        return row == 6 ? 0x1f : 0x00;
    case '.':
        return row == 6 ? 0x04 : 0x00;
    case ':':
        return (row == 2 || row == 4) ? 0x04 : 0x00;
    case '/':
        return (uint8_t)(0x01 << (6 - row < 5 ? 6 - row : 0));
    default:
        return row == 0 || row == 6 ? 0x1f : (row == 3 ? 0x04 : 0x00);
    }
}

static uint16_t color_for_state(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_BUSY:
        return RGB565_BLUE;
    case VIBE_DISPLAY_WAITING:
        return RGB565_PURPLE;
    case VIBE_DISPLAY_SUCCESS:
        return RGB565_GREEN;
    case VIBE_DISPLAY_ERROR:
        return RGB565_RED;
    case VIBE_DISPLAY_OFFLINE:
        return RGB565_AMBER;
    case VIBE_DISPLAY_IDLE:
    default:
        return RGB565_WHITE;
    }
}
