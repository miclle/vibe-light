#include "vibe_display.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_rgb.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "esp_lcd_panel_io_additions.h"
#include "esp_lcd_st7701.h"
#include "vibe_cjk_font.h"
#include "vibe_display_draw.h"
#include "vibe_display_landscape.h"
#include "vibe_display_portrait.h"
#include "vibe_display_score.h"
#include "vibe_display_text.h"
#include "vibe_display_model.h"
#include "vibe_orientation.h"

static const char *TAG = "vibe_display";

#define LCD_H_RES 320
#define LCD_V_RES 820
#define LCD_BITS_PER_PIXEL 16
#define LCD_RGB_FRAMEBUFFER_COUNT 3

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

#define ANIMATION_PERIOD_MS VIBE_DISPLAY_ANIMATION_PERIOD_MS

static esp_lcd_panel_handle_t panel_handle;
static uint16_t *framebuffer;
static uint16_t *display_framebuffers[LCD_RGB_FRAMEBUFFER_COUNT];
static bool display_framebuffer_valid[LCD_RGB_FRAMEBUFFER_COUNT];
static uint16_t *landscape_framebuffer;
static SemaphoreHandle_t display_mutex;
static bool display_ready;
static vibe_display_signature_t last_render_signature;
static vibe_status_packet_t last_render_packet;
static esp_timer_handle_t animation_timer;
static TaskHandle_t animation_task;
static int animation_tick;
static bool animation_running;
static bool backlight_on;
static vibe_display_orientation_t last_render_orientation = VIBE_DISPLAY_ORIENTATION_PORTRAIT;
static int display_framebuffer_index = -1;

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
static bool init_panel_framebuffers(void);
static uint16_t *next_render_framebuffer(void);
static int render_framebuffer_slot(const uint16_t *target);
static void invalidate_render_framebuffers(void);
static void render_status(const vibe_status_packet_t *packet, int animation_phase);
static void render_status_to_framebuffer(const vibe_status_packet_t *packet, int animation_phase, uint16_t *target);
static void render_portrait_animation_phase(const vibe_status_packet_t *packet, int animation_phase);
static void bind_portrait_framebuffer(void);
static void animation_refresh_task(void *arg);
static void animation_timer_callback(void *arg);
static void update_animation_timer(vibe_display_state_t state, vibe_display_orientation_t orientation);

void vibe_display_init(void)
{
    display_mutex = xSemaphoreCreateMutex();
    if (display_mutex == NULL) {
        ESP_LOGE(TAG, "failed to create display mutex");
        return;
    }

    landscape_framebuffer = heap_caps_malloc(VIBE_DISPLAY_LANDSCAPE_W * VIBE_DISPLAY_LANDSCAPE_H * sizeof(uint16_t),
                                             MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (landscape_framebuffer == NULL) {
        ESP_LOGW(TAG, "failed to allocate landscape framebuffer; portrait display remains available");
    }

    ESP_ERROR_CHECK_WITHOUT_ABORT(init_lcd_panel());
    if (panel_handle != NULL && init_panel_framebuffers()) {
        bind_portrait_framebuffer();
    }
    esp_err_t backlight_result = init_backlight();
    if (backlight_result == ESP_OK) {
        backlight_on = true;
    }
    ESP_ERROR_CHECK_WITHOUT_ABORT(backlight_result);
    vibe_display_signature_reset(&last_render_signature);
    vibe_status_default(&last_render_packet);
    vibe_display_score_init();

    const esp_timer_create_args_t timer_args = {
        .callback = animation_timer_callback,
        .name = "vibe_anim",
    };
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_timer_create(&timer_args, &animation_timer));
    if (xTaskCreate(animation_refresh_task,
                    "vibe_anim_render",
                    4096,
                    NULL,
                    4,
                    &animation_task) != pdPASS) {
        ESP_LOGW(TAG, "failed to create animation refresh task; animated refresh disabled");
        animation_task = NULL;
    }

    display_ready = panel_handle != NULL && framebuffer != NULL;
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
        vibe_display_orientation_t orientation = vibe_orientation_current();
        vibe_display_state_t previous_state = last_render_packet.state;
        bool preserve_animation_tick = vibe_display_should_preserve_animation_tick(last_render_packet.state,
                                                                                  packet->state,
                                                                                  animation_running);
        last_render_packet = *packet;
        if (vibe_display_should_flush_score_on_state_change(previous_state, packet->state)) {
            vibe_display_score_flush();
        }
        bool packet_changed = vibe_display_should_render(&last_render_signature, packet);
        bool orientation_changed = last_render_orientation != orientation;
        if (packet_changed || orientation_changed) {
            invalidate_render_framebuffers();
            if (!preserve_animation_tick) {
                animation_tick = 0;
            }
            if (packet_changed &&
                vibe_display_status_refresh_advances_animation(packet->state) &&
                !vibe_display_mode_phase_refresh_enabled(packet->state, orientation)) {
                animation_tick += VIBE_DISPLAY_ANIMATION_SUBSTEPS;
            }
            last_render_orientation = orientation;
            render_status(packet, animation_tick);
        }
        xSemaphoreGive(display_mutex);
    }
    update_animation_timer(packet->state, last_render_orientation);
}

void vibe_display_show_error(const char *message)
{
    ESP_LOGW(TAG, "display error: %s", message == NULL ? "unknown error" : message);
}

int vibe_display_animation_tick(void)
{
    return animation_tick;
}

bool vibe_display_backlight_on(void)
{
    return backlight_on;
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
        .num_fbs = LCD_RGB_FRAMEBUFFER_COUNT,
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

static bool init_panel_framebuffers(void)
{
    void *fb0 = NULL;
    void *fb1 = NULL;
    void *fb2 = NULL;
    esp_err_t result = esp_lcd_rgb_panel_get_frame_buffer(panel_handle, LCD_RGB_FRAMEBUFFER_COUNT, &fb0, &fb1, &fb2);
    if (result != ESP_OK || fb0 == NULL || fb1 == NULL || fb2 == NULL) {
        ESP_LOGE(TAG, "failed to get RGB panel framebuffers: %s", esp_err_to_name(result));
        return false;
    }

    display_framebuffers[0] = (uint16_t *)fb0;
    display_framebuffers[1] = (uint16_t *)fb1;
    display_framebuffers[2] = (uint16_t *)fb2;
    framebuffer = next_render_framebuffer();
    return framebuffer != NULL;
}

static uint16_t *next_render_framebuffer(void)
{
    if (display_framebuffers[0] == NULL || display_framebuffers[1] == NULL || display_framebuffers[2] == NULL) {
        return framebuffer;
    }

    display_framebuffer_index = (display_framebuffer_index + 1) % LCD_RGB_FRAMEBUFFER_COUNT;
    framebuffer = display_framebuffers[display_framebuffer_index];
    return framebuffer;
}

static int render_framebuffer_slot(const uint16_t *target)
{
    for (int i = 0; i < LCD_RGB_FRAMEBUFFER_COUNT; i++) {
        if (display_framebuffers[i] == target) {
            return i;
        }
    }
    return -1;
}

static void invalidate_render_framebuffers(void)
{
    for (int i = 0; i < LCD_RGB_FRAMEBUFFER_COUNT; i++) {
        display_framebuffer_valid[i] = false;
    }
}

static void render_status(const vibe_status_packet_t *packet, int animation_phase)
{
    uint16_t *target = next_render_framebuffer();
    if (target == NULL) {
        return;
    }

    render_status_to_framebuffer(packet, animation_phase, target);
    int slot = render_framebuffer_slot(target);
    if (slot >= 0) {
        display_framebuffer_valid[slot] = true;
    }
    esp_lcd_panel_draw_bitmap(panel_handle, 0, 0, LCD_H_RES, LCD_V_RES, target);
}

static void render_status_to_framebuffer(const vibe_status_packet_t *packet, int animation_phase, uint16_t *target)
{
    char firmware_version[32];
    const esp_app_desc_t *app_desc = esp_app_get_description();
    vibe_display_firmware_version_text(app_desc == NULL ? NULL : app_desc->version,
                                       firmware_version,
                                       sizeof(firmware_version));

    if (last_render_orientation == VIBE_DISPLAY_ORIENTATION_LANDSCAPE && landscape_framebuffer != NULL) {
        vibe_display_landscape_render(packet,
                                      animation_phase,
                                      target,
                                      LCD_H_RES,
                                      LCD_V_RES,
                                      landscape_framebuffer);
    } else {
        vibe_display_portrait_render(packet,
                                     animation_phase,
                                     target,
                                     LCD_H_RES,
                                     LCD_V_RES,
                                     firmware_version);
    }
}

static void render_portrait_animation_phase(const vibe_status_packet_t *packet, int animation_phase)
{
    uint16_t *target = next_render_framebuffer();
    if (target == NULL) {
        return;
    }

    int slot = render_framebuffer_slot(target);
    if (slot >= 0 && !display_framebuffer_valid[slot]) {
        render_status_to_framebuffer(packet, animation_phase, target);
        display_framebuffer_valid[slot] = true;
    } else {
        vibe_display_portrait_render_animation_phase(packet, animation_phase, target, LCD_H_RES, LCD_V_RES);
    }
    esp_lcd_panel_draw_bitmap(panel_handle, 0, 0, LCD_H_RES, LCD_V_RES, target);
}

static void bind_portrait_framebuffer(void)
{
    if (framebuffer == NULL) {
        return;
    }
    vibe_display_draw_bind(framebuffer, LCD_H_RES, LCD_V_RES);
    vibe_display_text_bind(LCD_H_RES);
}

static void animation_timer_callback(void *arg)
{
    (void)arg;

    if (!display_ready || !animation_running || animation_timer == NULL || animation_task == NULL) {
        return;
    }

    xTaskNotifyGive(animation_task);
}

static void animation_refresh_task(void *arg)
{
    (void)arg;

    while (true) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        if (!display_ready || !animation_running) {
            continue;
        }

        if (xSemaphoreTake(display_mutex, pdMS_TO_TICKS(100)) != pdTRUE) {
            continue;
        }

        vibe_display_orientation_t orientation = vibe_orientation_current();
        bool orientation_changed = last_render_orientation != orientation;
        last_render_orientation = orientation;
        if (vibe_display_mode_phase_refresh_enabled(last_render_packet.state, last_render_orientation)) {
            animation_tick++;
            render_portrait_animation_phase(&last_render_packet, animation_tick);
        } else if (orientation_changed) {
            invalidate_render_framebuffers();
            render_status(&last_render_packet, animation_tick);
        }

        xSemaphoreGive(display_mutex);
        taskYIELD();
    }
}

static void update_animation_timer(vibe_display_state_t state, vibe_display_orientation_t orientation)
{
    bool should_run = display_ready && animation_timer != NULL && animation_task != NULL &&
                      vibe_display_mode_phase_refresh_enabled(state, orientation);
    if (should_run && !animation_running) {
        animation_tick = 0;
        if (esp_timer_start_periodic(animation_timer, ANIMATION_PERIOD_MS * 1000) == ESP_OK) {
            animation_running = true;
        }
        return;
    }

    if (!should_run && animation_running) {
        esp_timer_stop(animation_timer);
        animation_running = false;
        vibe_display_score_flush();
    }
}
