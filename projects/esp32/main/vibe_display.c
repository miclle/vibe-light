#include "vibe_display.h"

#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
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
#include "vibe_display_maze_text.h"
#include "vibe_display_score.h"
#include "vibe_display_text.h"
#include "vibe_display_model.h"
#include "vibe_reference_maze.h"

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
#define RGB565_FOOTER 0xbdf7
#define RGB565_BLUE 0x047f
#define RGB565_PURPLE 0x8010
#define RGB565_GREEN 0x05e0
#define RGB565_RED 0xf800
#define RGB565_AMBER 0xfd20
#define RGB565_CYAN 0x07ff
#define RGB565_PINK 0xf81f
#define RGB565_PANEL 0x18e3
#define RGB565_MAZE 0x047f
#define RGB565_DOT 0xffe0

#define ANIMATION_PERIOD_MS VIBE_DISPLAY_ANIMATION_PERIOD_MS
#define ANIMATION_DOT_RADIUS 1

static esp_lcd_panel_handle_t panel_handle;
static uint16_t *framebuffer;
static SemaphoreHandle_t display_mutex;
static bool display_ready;
static vibe_display_signature_t last_render_signature;
static vibe_status_packet_t last_render_packet;
static esp_timer_handle_t animation_timer;
static int animation_tick;
static bool animation_running;

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
static void render_status(const vibe_status_packet_t *packet, int animation_phase);
static void render_task_rows(const vibe_status_packet_t *packet, int animation_phase);
static void render_codex_animation(const vibe_status_packet_t *packet, int animation_phase);
static void render_maze(const vibe_status_packet_t *packet, int animation_phase);
static void render_reference_maze_art(void);
static void render_animation_dots(const vibe_display_animation_frame_t *frames, int actor_count);
static void render_codex_actor(const vibe_display_animation_frame_t *frame);
static void render_center_ghost(int animation_phase);
static uint16_t color_for_state(vibe_display_state_t state);
static void animation_timer_callback(void *arg);
static void update_animation_timer(vibe_display_state_t state);

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
    vibe_display_draw_bind(framebuffer, LCD_H_RES, LCD_V_RES);
    vibe_display_text_bind(LCD_H_RES);

    ESP_ERROR_CHECK_WITHOUT_ABORT(init_lcd_panel());
    ESP_ERROR_CHECK_WITHOUT_ABORT(init_backlight());
    vibe_display_signature_reset(&last_render_signature);
    vibe_status_default(&last_render_packet);
    vibe_display_score_init();

    const esp_timer_create_args_t timer_args = {
        .callback = animation_timer_callback,
        .name = "vibe_anim",
    };
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_timer_create(&timer_args, &animation_timer));

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
        bool preserve_animation_tick = vibe_display_should_preserve_animation_tick(last_render_packet.state,
                                                                                  packet->state,
                                                                                  animation_running);
        last_render_packet = *packet;
        if (vibe_display_should_render(&last_render_signature, packet)) {
            if (!preserve_animation_tick) {
                animation_tick = 0;
            }
            render_status(packet, animation_tick);
        }
        xSemaphoreGive(display_mutex);
    }
    update_animation_timer(packet->state);
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

static void render_status(const vibe_status_packet_t *packet, int animation_phase)
{
    vibe_display_empty_state_t empty;
    bool has_empty_state = packet->task_count == 0;
    if (has_empty_state) {
        vibe_display_format_empty_state(packet, &empty);
    }

    uint16_t accent = has_empty_state && empty.quiet_header ? RGB565_PANEL : color_for_state(packet->state);
    if (vibe_display_animation_enabled(packet->state)) {
        int actor_count = vibe_display_animation_actor_count(packet->task_count, packet->active_count);
        vibe_display_maze_warm_pellet_cache(actor_count);
    }

    vibe_display_draw_fill_screen(RGB565_BLACK);
    vibe_display_draw_fill_rect(0, 0, LCD_H_RES, 82, accent);
    vibe_display_draw_fill_rect(VIBE_DISPLAY_MAZE_STAGE_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y,
                                VIBE_DISPLAY_MAZE_STAGE_W,
                                VIBE_DISPLAY_MAZE_STAGE_H,
                                RGB565_BLACK);
    vibe_display_draw_fill_rect(VIBE_DISPLAY_TASK_PANEL_X,
                                VIBE_DISPLAY_TASK_PANEL_Y,
                                VIBE_DISPLAY_TASK_PANEL_W,
                                VIBE_DISPLAY_TASK_PANEL_H,
                                RGB565_PANEL);

    const char *title = "VIBE LIGHT";
    vibe_display_text_draw((LCD_H_RES - vibe_display_text_width(title, 3)) / 2, 22, title, 3, RGB565_WHITE);

    vibe_display_usage_summary_t usage;
    vibe_display_format_usage_summary(packet, &usage);
    char usage_line[32];
    usage_line[0] = '\0';
    if (usage.reset_hint[0] != '\0') {
        snprintf(usage_line, sizeof(usage_line), "CODEX: %s", usage.reset_hint);
    } else if (usage.five_hour[0] != '\0' && usage.weekly[0] != '\0') {
        snprintf(usage_line, sizeof(usage_line), "CODEX: %s %s", usage.five_hour, usage.weekly);
    } else if (usage.five_hour[0] != '\0') {
        snprintf(usage_line, sizeof(usage_line), "CODEX: %s", usage.five_hour);
    } else if (usage.weekly[0] != '\0') {
        snprintf(usage_line, sizeof(usage_line), "CODEX: %s", usage.weekly);
    }
    if (usage_line[0] != '\0') {
        vibe_display_text_draw(24, 56, usage_line, 2, RGB565_WHITE);
    }
    render_maze(packet, animation_phase);

    if (packet->task_count > 0) {
        render_task_rows(packet, animation_phase);
    } else {
        vibe_display_text_draw(16, VIBE_DISPLAY_TASK_PANEL_Y + 28, empty.label, 2, RGB565_MUTED);
        vibe_display_text_draw_ellipsis(16,
                                        VIBE_DISPLAY_TASK_PANEL_Y + 84,
                                        empty.detail,
                                        empty.detail_scale,
                                        RGB565_WHITE,
                                        empty.detail_max_width);
    }

    char footer[48];
    vibe_display_footer_text(packet, footer, sizeof(footer));
    if (footer[0] != '\0') {
        vibe_display_text_draw(VIBE_DISPLAY_FOOTER_X,
                               VIBE_DISPLAY_FOOTER_Y,
                               footer,
                               VIBE_DISPLAY_FOOTER_SCALE,
                               RGB565_FOOTER);
    }
    vibe_display_draw_fill_rect(0,
                                VIBE_DISPLAY_FOOTER_BOTTOM_CLEAR_Y,
                                LCD_H_RES,
                                LCD_V_RES - VIBE_DISPLAY_FOOTER_BOTTOM_CLEAR_Y,
                                RGB565_PANEL);

    if (vibe_display_animation_enabled(packet->state)) {
        render_codex_animation(packet, animation_phase);
    }

    esp_lcd_panel_draw_bitmap(panel_handle, 0, 0, LCD_H_RES, LCD_V_RES, framebuffer);
}

static void render_task_rows(const vibe_status_packet_t *packet, int animation_phase)
{
    int rows = packet->task_count > VIBE_STATUS_MAX_TASKS ? VIBE_STATUS_MAX_TASKS : packet->task_count;
    int y = VIBE_DISPLAY_TASK_ROW_Y;
    for (int i = 0; i < rows; i++) {
        const vibe_status_task_t *task = &packet->tasks[i];
        vibe_display_task_row_t row;
        vibe_display_format_task_row_at_phase(task, packet->timestamp_ms, i, animation_phase, &row);

        uint16_t task_color = color_for_state(task->state);
        const int trailing_x = row.trailing[0] == '\0' ? LCD_H_RES : LCD_H_RES - 4 - vibe_display_text_width(row.trailing, 2);
        const int title_max_width = row.trailing[0] == '\0'
                                        ? LCD_H_RES - VIBE_DISPLAY_TASK_TEXT_X - 12
                                        : trailing_x - VIBE_DISPLAY_TASK_TEXT_X - 8;

        vibe_display_draw_fill_rect(VIBE_DISPLAY_TASK_SWATCH_X,
                                    y + VIBE_DISPLAY_TASK_SWATCH_Y_OFFSET,
                                    VIBE_DISPLAY_TASK_SWATCH_W,
                                    VIBE_DISPLAY_TASK_SWATCH_H,
                                    task_color);
        vibe_display_text_draw_ellipsis(VIBE_DISPLAY_TASK_TEXT_X, y, row.title, 2, RGB565_WHITE, title_max_width);
        if (row.trailing[0] != '\0') {
            vibe_display_text_draw(trailing_x, y, row.trailing, 2, RGB565_MUTED);
        }
        if (vibe_display_should_render_task_detail(task)) {
            vibe_display_text_draw_ellipsis(VIBE_DISPLAY_TASK_TEXT_X,
                               y + VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET,
                               task->detail,
                               2,
                               RGB565_MUTED,
                               LCD_H_RES - VIBE_DISPLAY_TASK_TEXT_X);
            y += VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE;
        } else {
            y += VIBE_DISPLAY_TASK_ROW_STRIDE;
        }
    }
}

static void render_maze(const vibe_status_packet_t *packet, int animation_phase)
{
    const int x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int y = VIBE_DISPLAY_MAZE_STAGE_Y;
    const int w = VIBE_DISPLAY_MAZE_STAGE_W;
    const int h = VIBE_DISPLAY_MAZE_FRAME_H;

    vibe_display_draw_fill_rect(x, y, w, h, RGB565_BLACK);
    render_reference_maze_art();

    vibe_display_maze_count_text_t text;
    vibe_display_format_maze_count_text(packet, &text);
    char score_text[VIBE_DISPLAY_MAZE_SCORE_TEXT_MAX];
    char high_score_text[VIBE_DISPLAY_MAZE_SCORE_TEXT_MAX];
    char level_text[VIBE_DISPLAY_MAZE_LEVEL_TEXT_MAX];
    int actor_count = vibe_display_animation_actor_count(packet->task_count, packet->active_count);
    int score = vibe_display_animation_enabled(packet->state)
                    ? vibe_display_maze_score(animation_phase,
                                              actor_count,
                                              packet->active_count,
                                              VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS)
                    : 0;
    int level = vibe_display_animation_enabled(packet->state)
                    ? vibe_display_maze_level(animation_phase,
                                              actor_count,
                                              VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS)
                    : 1;
    if (vibe_display_animation_enabled(packet->state)) {
        vibe_display_score_update(score);
    }
    vibe_display_format_maze_score_text(score, score_text, sizeof(score_text));
    vibe_display_format_maze_score_text(vibe_display_score_value(), high_score_text, sizeof(high_score_text));
    vibe_display_format_maze_level_text(level, level_text, sizeof(level_text));

    vibe_display_draw_fill_rect(VIBE_DISPLAY_MAZE_SCORE_LEFT_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_SCORE_CLEAR_Y,
                                VIBE_DISPLAY_MAZE_SCORE_RIGHT_X - VIBE_DISPLAY_MAZE_SCORE_LEFT_X + 1,
                                VIBE_DISPLAY_MAZE_SCORE_CLEAR_H,
                                RGB565_BLACK);
    vibe_display_draw_fill_rect(VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_SCORE_CLEAR_Y,
                                VIBE_DISPLAY_MAZE_HIGH_SCORE_RIGHT_X - VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X + 1,
                                VIBE_DISPLAY_MAZE_SCORE_CLEAR_H,
                                RGB565_BLACK);
    vibe_display_draw_fill_rect(VIBE_DISPLAY_MAZE_LEVEL_LEFT_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_LEVEL_CLEAR_Y,
                                VIBE_DISPLAY_MAZE_LEVEL_RIGHT_X - VIBE_DISPLAY_MAZE_LEVEL_LEFT_X + 1,
                                VIBE_DISPLAY_MAZE_LEVEL_CLEAR_H,
                                RGB565_BLACK);
    vibe_display_maze_text_draw(VIBE_DISPLAY_MAZE_SCORE_LEFT_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_SCORE_VALUE_Y,
                                score_text,
                                2,
                                RGB565_PINK,
                                LCD_H_RES);
    vibe_display_maze_text_draw_centered(VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X,
                                         VIBE_DISPLAY_MAZE_HIGH_SCORE_RIGHT_X,
                                         VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_SCORE_VALUE_Y,
                                         high_score_text,
                                         RGB565_PINK,
                                         LCD_H_RES);
    vibe_display_maze_text_draw(VIBE_DISPLAY_MAZE_LEVEL_LEFT_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_LEVEL_VALUE_Y,
                                "LEVEL",
                                2,
                                RGB565_WHITE,
                                LCD_H_RES);
    vibe_display_maze_text_draw(VIBE_DISPLAY_MAZE_LEVEL_VALUE_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_LEVEL_VALUE_Y,
                                level_text,
                                2,
                                RGB565_BLUE,
                                LCD_H_RES);

    const int count_y = VIBE_DISPLAY_MAZE_STAGE_Y + 294;
    const int clear_y = VIBE_DISPLAY_MAZE_STAGE_Y + 288;
    const int clear_h = 22;

    const int left_box_left = vibe_display_maze_display_x(20);
    const int left_box_right = vibe_display_maze_display_x(128);
    const int middle_box_left = vibe_display_maze_display_x(132);
    const int middle_box_right = vibe_display_maze_display_x(187);
    const int right_box_left = vibe_display_maze_display_x(192);
    const int right_box_right = vibe_display_maze_display_x(300);

    vibe_display_draw_fill_rect(left_box_left, clear_y, left_box_right - left_box_left + 1, clear_h, RGB565_BLACK);
    vibe_display_draw_fill_rect(middle_box_left, clear_y, middle_box_right - middle_box_left + 1, clear_h, RGB565_BLACK);
    vibe_display_draw_fill_rect(right_box_left, clear_y, right_box_right - right_box_left + 1, clear_h, RGB565_BLACK);

    vibe_display_maze_text_draw_centered(left_box_left,
                                         left_box_right,
                                         count_y,
                                         text.active,
                                         color_for_state(VIBE_DISPLAY_BUSY),
                                         LCD_H_RES);
    vibe_display_maze_text_draw_centered(middle_box_left,
                                         middle_box_right,
                                         count_y,
                                         text.waiting,
                                         color_for_state(VIBE_DISPLAY_WAITING),
                                         LCD_H_RES);
    vibe_display_maze_text_draw_centered(right_box_left,
                                         right_box_right,
                                         count_y,
                                         text.error,
                                         color_for_state(VIBE_DISPLAY_ERROR),
                                         LCD_H_RES);
}

static void render_reference_maze_art(void)
{
    for (int i = 0; i < VIBE_REFERENCE_MAZE_RUN_COUNT; i++) {
        const vibe_reference_maze_run_t *run = &VIBE_REFERENCE_MAZE_RUNS[i];
        vibe_display_draw_fill_rect(vibe_display_maze_display_x(run->x),
                                    VIBE_DISPLAY_MAZE_STAGE_Y + run->y,
                                    vibe_display_maze_display_run_width(run->x, run->length),
                                    1,
                                    run->color);
    }
}

static void render_codex_animation(const vibe_status_packet_t *packet, int animation_phase)
{
    int actor_count = vibe_display_animation_actor_count(packet->task_count, packet->active_count);
    vibe_display_animation_frame_t frames[VIBE_STATUS_MAX_TASKS];
    for (int i = 0; i < actor_count; i++) {
        vibe_display_animation_actor_frame(animation_phase, i, actor_count, packet->active_count, &frames[i]);
    }

    render_animation_dots(frames, actor_count);
    render_center_ghost(animation_phase);
    for (int i = 0; i < actor_count; i++) {
        render_codex_actor(&frames[i]);
    }
}

static void render_animation_dots(const vibe_display_animation_frame_t *frames, int actor_count)
{
    (void)frames;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (!vibe_display_maze_pellet_visible(i,
                                              animation_tick,
                                              actor_count,
                                              last_render_packet.active_count,
                                              VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS)) {
            continue;
        }

        int radius = vibe_display_maze_is_power_pellet(i, VIBE_DISPLAY_MAZE_PELLET_COUNT)
                         ? VIBE_DISPLAY_MAZE_POWER_PELLET_RADIUS
                         : ANIMATION_DOT_RADIUS;
        vibe_display_draw_fill_circle(dot.x, dot.y, radius, RGB565_DOT);
    }
}

static void render_codex_actor(const vibe_display_animation_frame_t *frame)
{
    vibe_display_animation_actor_t actor;
    vibe_display_animation_actor_shape(frame, &actor);

    vibe_display_draw_fill_circle(frame->x, frame->y, VIBE_DISPLAY_CODEX_ACTOR_RADIUS, RGB565_DOT);
    vibe_display_draw_fill_triangle(actor.mouth_tip_x, actor.mouth_tip_y,
                                    actor.mouth_a_x, actor.mouth_a_y,
                                    actor.mouth_b_x, actor.mouth_b_y,
                                    RGB565_BLACK);
    if (VIBE_DISPLAY_CODEX_ACTOR_EYE_RADIUS > 0) {
        vibe_display_draw_fill_circle(actor.eye_x, actor.eye_y, VIBE_DISPLAY_CODEX_ACTOR_EYE_RADIUS, RGB565_BLACK);
    }
}

static void render_center_ghost(int animation_phase)
{
    vibe_display_maze_ghost_frame_t ghost;
    vibe_display_maze_ghost_frame(animation_phase, &ghost);

    vibe_display_draw_fill_rect(VIBE_DISPLAY_MAZE_GHOST_CENTER_X - 24,
                                VIBE_DISPLAY_MAZE_GHOST_CENTER_Y - 20,
                                48,
                                38,
                                RGB565_BLACK);

    vibe_display_draw_fill_circle(ghost.x - 9, ghost.y - 7, 8, RGB565_RED);
    vibe_display_draw_fill_circle(ghost.x + 9, ghost.y - 7, 8, RGB565_RED);
    vibe_display_draw_fill_rect(ghost.x - 17, ghost.y - 7, 34, 19, RGB565_RED);
    vibe_display_draw_fill_rect(ghost.x - 15, ghost.y + 10, 8, 5, RGB565_RED);
    vibe_display_draw_fill_rect(ghost.x - 4, ghost.y + 10, 8, 5, RGB565_RED);
    vibe_display_draw_fill_rect(ghost.x + 7, ghost.y + 10, 8, 5, RGB565_RED);

    if (ghost.eyes_closed) {
        vibe_display_draw_fill_rect(ghost.x - 10, ghost.y - 8, 6, 2, RGB565_WHITE);
        vibe_display_draw_fill_rect(ghost.x + 4, ghost.y - 8, 6, 2, RGB565_WHITE);
        return;
    }

    vibe_display_draw_fill_circle(ghost.x - 7, ghost.y - 8, 4, RGB565_WHITE);
    vibe_display_draw_fill_circle(ghost.x + 7, ghost.y - 8, 4, RGB565_WHITE);
    vibe_display_draw_fill_circle(ghost.x - 6, ghost.y - 7, 2, RGB565_BLUE);
    vibe_display_draw_fill_circle(ghost.x + 8, ghost.y - 7, 2, RGB565_BLUE);
}

static uint16_t color_for_state(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_BUSY:
        return RGB565_BLUE;
    case VIBE_DISPLAY_WAITING:
        return RGB565_DOT;
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

static void animation_timer_callback(void *arg)
{
    (void)arg;

    if (!display_ready || !animation_running || animation_timer == NULL) {
        return;
    }

    if (xSemaphoreTake(display_mutex, 0) != pdTRUE) {
        return;
    }

    if (vibe_display_phase_refresh_enabled(last_render_packet.state)) {
        animation_tick++;
        render_status(&last_render_packet, animation_tick);
    }

    xSemaphoreGive(display_mutex);
}

static void update_animation_timer(vibe_display_state_t state)
{
    bool should_run = display_ready && animation_timer != NULL && vibe_display_phase_refresh_enabled(state);
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
