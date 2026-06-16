#include "vibe_display_portrait.h"

#include <stdbool.h>

#include "vibe_display_draw.h"
#include "vibe_display_maze_text.h"
#include "vibe_display_model.h"
#include "vibe_display_render.h"
#include "vibe_display_score.h"
#include "vibe_display_text.h"
#include "vibe_reference_maze.h"

#define ANIMATION_DOT_RADIUS 1

static void render_task_rows(const vibe_status_packet_t *packet, int animation_phase, int screen_w);
static void render_maze(const vibe_status_packet_t *packet, int animation_phase, int screen_w);
static void render_reference_maze_art(void);
static void render_codex_animation(const vibe_status_packet_t *packet, int animation_phase);
static void render_animation_dots(const vibe_status_packet_t *packet, int animation_phase, int actor_count);
static void render_codex_actor(const vibe_display_animation_frame_t *frame);
static void render_center_ghost(int animation_phase);

void vibe_display_portrait_render(const vibe_status_packet_t *packet,
                                  int animation_phase,
                                  uint16_t *framebuffer,
                                  int screen_w,
                                  int screen_h,
                                  const char *firmware_version)
{
    if (packet == NULL || framebuffer == NULL || screen_w <= 0 || screen_h <= 0) {
        return;
    }

    vibe_display_draw_bind(framebuffer, screen_w, screen_h);
    vibe_display_text_bind(screen_w);

    vibe_display_empty_state_t empty;
    bool has_empty_state = packet->task_count == 0;
    if (has_empty_state) {
        vibe_display_format_empty_state(packet, &empty);
    }

    uint16_t header_color = has_empty_state && empty.quiet_header
                                ? RGB565_PANEL
                                : vibe_display_header_color_for_state(packet->state);
    if (vibe_display_animation_enabled(packet->state)) {
        int actor_count = vibe_display_animation_actor_count(packet->task_count, packet->active_count);
        vibe_display_maze_warm_pellet_cache(actor_count);
    }

    vibe_display_draw_fill_screen(RGB565_BLACK);
    vibe_display_draw_fill_rect(0, 0, screen_w, 82, header_color);
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
    vibe_display_text_draw((screen_w - vibe_display_text_width(title, 3)) / 2, 22, title, 3, RGB565_WHITE);

    vibe_display_usage_summary_t usage;
    vibe_display_format_usage_summary(packet, &usage);
    char usage_line[32];
    char reset_line[24];
    vibe_display_format_usage_line(&usage, usage_line, sizeof(usage_line));
    vibe_display_format_usage_reset_line(&usage, reset_line, sizeof(reset_line));
    if (usage_line[0] != '\0') {
        vibe_display_text_draw(16, VIBE_DISPLAY_USAGE_LINE_Y, usage_line, 2, RGB565_WHITE);
    }
    if (reset_line[0] != '\0') {
        int reset_x = (screen_w - vibe_display_text_width(reset_line, 1)) / 2;
        vibe_display_text_draw(reset_x < 16 ? 16 : reset_x, 72, reset_line, 1, RGB565_AMBER);
    }
    render_maze(packet, animation_phase, screen_w);

    if (packet->task_count > 0) {
        render_task_rows(packet, animation_phase, screen_w);
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

    if (firmware_version != NULL && firmware_version[0] != '\0') {
        const int version_x = screen_w - VIBE_DISPLAY_FIRMWARE_VERSION_RIGHT_MARGIN -
                              vibe_display_text_width(firmware_version, VIBE_DISPLAY_FIRMWARE_VERSION_SCALE);
        vibe_display_text_draw(version_x < VIBE_DISPLAY_FOOTER_X ? VIBE_DISPLAY_FOOTER_X : version_x,
                               VIBE_DISPLAY_FOOTER_Y,
                               firmware_version,
                               VIBE_DISPLAY_FIRMWARE_VERSION_SCALE,
                               RGB565_FOOTER);
    }
    vibe_display_draw_fill_rect(0,
                                VIBE_DISPLAY_FOOTER_BOTTOM_CLEAR_Y,
                                screen_w,
                                screen_h - VIBE_DISPLAY_FOOTER_BOTTOM_CLEAR_Y,
                                RGB565_PANEL);

    if (vibe_display_animation_enabled(packet->state)) {
        render_codex_animation(packet, animation_phase);
    }
}

static void render_task_rows(const vibe_status_packet_t *packet, int animation_phase, int screen_w)
{
    int rows = packet->task_count > VIBE_STATUS_MAX_TASKS ? VIBE_STATUS_MAX_TASKS : packet->task_count;
    int y = VIBE_DISPLAY_TASK_ROW_Y;
    for (int i = 0; i < rows; i++) {
        const vibe_status_task_t *task = &packet->tasks[i];
        vibe_display_task_row_t row;
        vibe_display_format_task_row_at_phase(task, packet->timestamp_ms, i, animation_phase, &row);

        uint16_t task_color = vibe_display_color_for_state(task->state);
        const int trailing_x = row.trailing[0] == '\0' ? screen_w : screen_w - 4 - vibe_display_text_width(row.trailing, 2);
        const int title_max_width = row.trailing[0] == '\0'
                                        ? screen_w - VIBE_DISPLAY_TASK_TEXT_X - 12
                                        : trailing_x - VIBE_DISPLAY_TASK_TEXT_X - 8;

        vibe_display_draw_fill_rect(VIBE_DISPLAY_TASK_SWATCH_X,
                                    y + VIBE_DISPLAY_TASK_SWATCH_Y_OFFSET,
                                    VIBE_DISPLAY_TASK_SWATCH_W,
                                    VIBE_DISPLAY_TASK_SWATCH_H,
                                    task_color);
        vibe_display_text_draw_ellipsis(VIBE_DISPLAY_TASK_TEXT_X, y, row.title, 2, RGB565_WHITE, title_max_width);
        if (row.trailing[0] != '\0') {
            vibe_display_text_draw(trailing_x,
                                   y,
                                   row.trailing,
                                   2,
                                   vibe_display_color_for_trailing_severity(row.trailing_severity));
        }
        if (vibe_display_should_render_task_detail(task)) {
            vibe_display_text_draw_ellipsis(VIBE_DISPLAY_TASK_TEXT_X,
                                            y + VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET,
                                            task->detail,
                                            2,
                                            RGB565_MUTED,
                                            screen_w - VIBE_DISPLAY_TASK_TEXT_X);
            y += VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE;
        } else {
            y += VIBE_DISPLAY_TASK_ROW_STRIDE;
        }
    }
}

static void render_maze(const vibe_status_packet_t *packet, int animation_phase, int screen_w)
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
                                screen_w);
    vibe_display_maze_text_draw_centered(VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X,
                                         VIBE_DISPLAY_MAZE_HIGH_SCORE_RIGHT_X,
                                         VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_SCORE_VALUE_Y,
                                         high_score_text,
                                         RGB565_PINK,
                                         screen_w);
    vibe_display_maze_text_draw(VIBE_DISPLAY_MAZE_LEVEL_LEFT_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_LEVEL_VALUE_Y,
                                "LEVEL",
                                2,
                                RGB565_WHITE,
                                screen_w);
    vibe_display_maze_text_draw(VIBE_DISPLAY_MAZE_LEVEL_VALUE_X,
                                VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_LEVEL_VALUE_Y,
                                level_text,
                                2,
                                RGB565_BLUE,
                                screen_w);

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
                                         vibe_display_color_for_state(VIBE_DISPLAY_BUSY),
                                         screen_w);
    vibe_display_maze_text_draw_centered(middle_box_left,
                                         middle_box_right,
                                         count_y,
                                         text.waiting,
                                         vibe_display_color_for_state(VIBE_DISPLAY_WAITING),
                                         screen_w);
    vibe_display_maze_text_draw_centered(right_box_left,
                                         right_box_right,
                                         count_y,
                                         text.error,
                                         vibe_display_color_for_state(VIBE_DISPLAY_ERROR),
                                         screen_w);
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

    render_animation_dots(packet, animation_phase, actor_count);
    render_center_ghost(animation_phase);
    for (int i = 0; i < actor_count; i++) {
        render_codex_actor(&frames[i]);
    }
}

static void render_animation_dots(const vibe_status_packet_t *packet, int animation_phase, int actor_count)
{
    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (!vibe_display_maze_pellet_visible(i,
                                              animation_phase,
                                              actor_count,
                                              packet->active_count,
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
