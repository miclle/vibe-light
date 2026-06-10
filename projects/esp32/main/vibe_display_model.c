#include "vibe_display_model.h"
#include "vibe_display_maze_data.h"

#include <stdio.h>
#include <string.h>

static uint32_t fnv1a_update(uint32_t hash, const void *data, size_t length);
static uint32_t fnv1a_update_text(uint32_t hash, const char *text);
static const char *badge_for_state(vibe_display_state_t state);
static void maze_pellet_at_index(int index, vibe_display_animation_frame_t *frame);
static void maze_frame_at_tick(int tick, int phase_offset, bool mouth_open, vibe_display_animation_frame_t *frame);
static bool maze_pellet_eaten_since_round_start(int pellet_index, int phase_offset, int elapsed_tick);
static bool maze_pellet_eaten_on_segment(int pellet_index, int from_path_position, int substep);
static bool maze_pellet_between_points(int pellet_index, const vibe_display_maze_point_t *from, int to_x, int to_y);
static int maze_pellet_round_ticks(int actor_count);
static void copy_text(char *dest, size_t dest_size, const char *source);
static void append_text(char *dest, size_t dest_size, const char *source);
static void format_count(char *dest, size_t dest_size, char label, int count);
static void format_maze_count(char *dest, size_t dest_size, const char *label, int count);
static void format_percent(char *dest, size_t dest_size, const char *label, int percent);
static int positive_mod(int value, int modulus);

void vibe_display_signature_reset(vibe_display_signature_t *signature)
{
    if (signature == NULL) {
        return;
    }

    signature->value = 0;
    signature->has_value = false;
}

uint32_t vibe_display_packet_signature(const vibe_status_packet_t *packet)
{
    if (packet == NULL) {
        return 0;
    }

    uint32_t hash = 2166136261u;
    hash = fnv1a_update(hash, &packet->version, sizeof(packet->version));
    hash = fnv1a_update_text(hash, packet->source);
    hash = fnv1a_update(hash, &packet->state, sizeof(packet->state));
    hash = fnv1a_update_text(hash, packet->detail);
    hash = fnv1a_update(hash, &packet->active_count, sizeof(packet->active_count));
    hash = fnv1a_update(hash, &packet->waiting_count, sizeof(packet->waiting_count));
    hash = fnv1a_update(hash, &packet->error_count, sizeof(packet->error_count));
    hash = fnv1a_update(hash, &packet->codex_5h_remaining_percent, sizeof(packet->codex_5h_remaining_percent));
    hash = fnv1a_update(hash, &packet->codex_7d_remaining_percent, sizeof(packet->codex_7d_remaining_percent));
    hash = fnv1a_update(hash, &packet->task_count, sizeof(packet->task_count));

    int rows = packet->task_count > VIBE_STATUS_MAX_TASKS ? VIBE_STATUS_MAX_TASKS : packet->task_count;
    for (int i = 0; i < rows; i++) {
        const vibe_status_task_t *task = &packet->tasks[i];
        hash = fnv1a_update_text(hash, task->title);
        hash = fnv1a_update_text(hash, task->source);
        hash = fnv1a_update(hash, &task->state, sizeof(task->state));
        hash = fnv1a_update_text(hash, task->detail);
        hash = fnv1a_update(hash, &task->context_used_percent, sizeof(task->context_used_percent));
    }

    return hash;
}

bool vibe_display_should_render(vibe_display_signature_t *signature, const vibe_status_packet_t *packet)
{
    if (signature == NULL || packet == NULL) {
        return false;
    }

    uint32_t next = vibe_display_packet_signature(packet);
    if (signature->has_value && signature->value == next) {
        return false;
    }

    signature->value = next;
    signature->has_value = true;
    return true;
}

void vibe_display_format_task_row(const vibe_status_task_t *task, int index, vibe_display_task_row_t *row)
{
    (void)index;

    if (row == NULL) {
        return;
    }

    memset(row, 0, sizeof(*row));
    if (task == NULL) {
        copy_text(row->badge, sizeof(row->badge), "TASK");
        copy_text(row->title, sizeof(row->title), "unknown");
        return;
    }

    copy_text(row->badge, sizeof(row->badge), badge_for_state(task->state));
    copy_text(row->title, sizeof(row->title), task->title[0] == '\0' ? "untitled" : task->title);
    format_percent(row->trailing, sizeof(row->trailing), "CTX", task->context_used_percent);

    if (task->source[0] != '\0' && task->detail[0] != '\0') {
        copy_text(row->subtitle, sizeof(row->subtitle), task->source);
        append_text(row->subtitle, sizeof(row->subtitle), " / ");
        append_text(row->subtitle, sizeof(row->subtitle), task->detail);
    } else if (task->detail[0] != '\0') {
        copy_text(row->subtitle, sizeof(row->subtitle), task->detail);
    } else if (task->source[0] != '\0') {
        copy_text(row->subtitle, sizeof(row->subtitle), task->source);
    } else {
        copy_text(row->subtitle, sizeof(row->subtitle), "task");
    }
}

void vibe_display_format_count_summary(const vibe_status_packet_t *packet, vibe_display_count_summary_t *summary)
{
    if (summary == NULL) {
        return;
    }

    memset(summary, 0, sizeof(*summary));
    if (packet == NULL) {
        format_count(summary->active, sizeof(summary->active), 'A', 0);
        format_count(summary->waiting, sizeof(summary->waiting), 'W', 0);
        format_count(summary->error, sizeof(summary->error), 'E', 0);
        return;
    }

    format_count(summary->active, sizeof(summary->active), 'A', packet->active_count);
    format_count(summary->waiting, sizeof(summary->waiting), 'W', packet->waiting_count);
    format_count(summary->error, sizeof(summary->error), 'E', packet->error_count);
}

void vibe_display_format_maze_count_text(const vibe_status_packet_t *packet, vibe_display_maze_count_text_t *text)
{
    if (text == NULL) {
        return;
    }

    memset(text, 0, sizeof(*text));
    if (packet == NULL) {
        format_maze_count(text->active, sizeof(text->active), "ACTIVE", 0);
        format_maze_count(text->waiting, sizeof(text->waiting), "WAIT", 0);
        format_maze_count(text->error, sizeof(text->error), "ERR", 0);
        return;
    }

    format_maze_count(text->active, sizeof(text->active), "ACTIVE", packet->active_count);
    format_maze_count(text->waiting, sizeof(text->waiting), "WAIT", packet->waiting_count);
    format_maze_count(text->error, sizeof(text->error), "ERR", packet->error_count);
}

void vibe_display_format_usage_summary(const vibe_status_packet_t *packet, vibe_display_usage_summary_t *summary)
{
    if (summary == NULL) {
        return;
    }

    memset(summary, 0, sizeof(*summary));
    if (packet == NULL) {
        return;
    }

    format_percent(summary->five_hour, sizeof(summary->five_hour), "5H", packet->codex_5h_remaining_percent);
    format_percent(summary->weekly, sizeof(summary->weekly), "7D", packet->codex_7d_remaining_percent);
}

void vibe_display_footer_text(const vibe_status_packet_t *packet, char *text, size_t text_size)
{
    (void)packet;

    if (text == NULL || text_size == 0) {
        return;
    }

    text[0] = '\0';
}

bool vibe_display_animation_enabled(vibe_display_state_t state)
{
    return state == VIBE_DISPLAY_BUSY;
}

int vibe_display_animation_step(int active_count)
{
    (void)active_count;
    return 1;
}

int vibe_display_animation_actor_count(int task_count, int active_count)
{
    int count = task_count > 0 ? task_count : active_count;
    if (count < 1) {
        return 1;
    }
    if (count > VIBE_STATUS_MAX_TASKS) {
        return VIBE_STATUS_MAX_TASKS;
    }
    return count;
}

void vibe_display_animation_frame(int tick, int active_count, vibe_display_animation_frame_t *frame)
{
    vibe_display_animation_actor_frame(tick, 0, 1, active_count, frame);
}

void vibe_display_animation_actor_frame(int tick, int actor_index, int actor_count, int active_count, vibe_display_animation_frame_t *frame)
{
    (void)active_count;

    if (frame == NULL) {
        return;
    }

    if (actor_count < 1) {
        actor_count = 1;
    }
    if (actor_count > VIBE_STATUS_MAX_TASKS) {
        actor_count = VIBE_STATUS_MAX_TASKS;
    }
    if (actor_index < 0) {
        actor_index = 0;
    }
    if (actor_index >= actor_count) {
        actor_index = actor_count - 1;
    }

    int phase_offset = (actor_index * VIBE_DISPLAY_ANIMATION_PATH_STEPS) / actor_count;
    maze_frame_at_tick(tick, phase_offset, (tick % 2) == 0, frame);
}

int vibe_display_maze_display_x(int reference_x)
{
    const int span = VIBE_DISPLAY_MAZE_REFERENCE_MAX_X - VIBE_DISPLAY_MAZE_REFERENCE_MIN_X;
    if (span <= 0) {
        return VIBE_DISPLAY_MAZE_STAGE_X + reference_x;
    }

    int scaled = ((reference_x - VIBE_DISPLAY_MAZE_REFERENCE_MIN_X) * (VIBE_DISPLAY_MAZE_STAGE_W - 1)) / span;
    if (scaled < 0) {
        scaled = 0;
    }
    if (scaled >= VIBE_DISPLAY_MAZE_STAGE_W) {
        scaled = VIBE_DISPLAY_MAZE_STAGE_W - 1;
    }
    return VIBE_DISPLAY_MAZE_STAGE_X + scaled;
}

int vibe_display_maze_display_run_width(int reference_x, int reference_length)
{
    if (reference_length <= 0) {
        return 0;
    }

    int start = vibe_display_maze_display_x(reference_x);
    int end = vibe_display_maze_display_x(reference_x + reference_length - 1);
    int width = end - start + 1;
    return width > 0 ? width : 1;
}

void vibe_display_maze_pellet_position(int pellet_index, int pellet_count, vibe_display_animation_frame_t *frame)
{
    if (frame == NULL) {
        return;
    }

    if (pellet_count < 1) {
        pellet_count = 1;
    }
    int index = pellet_index % pellet_count;
    if (index < 0) {
        index += pellet_count;
    }

    if (pellet_count == VIBE_DISPLAY_MAZE_PELLET_COUNT) {
        maze_pellet_at_index(index, frame);
        return;
    }

    int position = (index * VIBE_DISPLAY_ANIMATION_PATH_STEPS) / pellet_count;
    maze_frame_at_tick(position * VIBE_DISPLAY_ANIMATION_SUBSTEPS, 0, false, frame);
}

bool vibe_display_maze_is_power_pellet(int pellet_index, int pellet_count)
{
    if (pellet_count < 1) {
        return false;
    }

    int index = pellet_index % pellet_count;
    if (index < 0) {
        index += pellet_count;
    }

    if (pellet_count == VIBE_DISPLAY_MAZE_PELLET_COUNT) {
        return index == 30 || index == 31 || index == 149 || index == 150;
    }

    return index == 0 ||
           index == pellet_count / 3 ||
           index == (pellet_count * 2) / 3 ||
           index == pellet_count - 1;
}

bool vibe_display_maze_pellet_visible(int pellet_index,
                                      int tick,
                                      int actor_count,
                                      int active_count,
                                      int reset_ticks)
{
    if (actor_count < 1) {
        actor_count = 1;
    }
    if (actor_count > VIBE_STATUS_MAX_TASKS) {
        actor_count = VIBE_STATUS_MAX_TASKS;
    }
    (void)active_count;

    int round_ticks = maze_pellet_round_ticks(actor_count);
    if (reset_ticks > 0 && reset_ticks < round_ticks) {
        round_ticks = reset_ticks;
    }
    int round_tick = positive_mod(tick, round_ticks);

    for (int actor_index = 0; actor_index < actor_count; actor_index++) {
        int phase_offset = (actor_index * VIBE_DISPLAY_ANIMATION_PATH_STEPS) / actor_count;
        if (maze_pellet_eaten_since_round_start(pellet_index, phase_offset, round_tick)) {
            return false;
        }
    }

    return true;
}

static bool maze_pellet_eaten_since_round_start(int pellet_index, int phase_offset, int elapsed_tick)
{
    if (elapsed_tick < 0) {
        return false;
    }

    int completed_segments = elapsed_tick / VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    int substep = elapsed_tick % VIBE_DISPLAY_ANIMATION_SUBSTEPS;

    for (int step = 0; step < completed_segments; step++) {
        int path_position = positive_mod(phase_offset + step, VIBE_DISPLAY_ANIMATION_PATH_STEPS);
        if (maze_pellet_eaten_on_segment(pellet_index, path_position, VIBE_DISPLAY_ANIMATION_SUBSTEPS)) {
            return true;
        }
    }

    int current_path_position = positive_mod(phase_offset + completed_segments, VIBE_DISPLAY_ANIMATION_PATH_STEPS);
    return maze_pellet_eaten_on_segment(pellet_index, current_path_position, substep);
}

static bool maze_pellet_eaten_on_segment(int pellet_index, int from_path_position, int substep)
{
    int from_index = vibe_display_reference_path[positive_mod(from_path_position, VIBE_DISPLAY_ANIMATION_PATH_STEPS)];
    int to_index = vibe_display_reference_path[positive_mod(from_path_position + 1, VIBE_DISPLAY_ANIMATION_PATH_STEPS)];
    const vibe_display_maze_point_t *from = &vibe_display_reference_pellets[from_index];
    const vibe_display_maze_point_t *to = &vibe_display_reference_pellets[to_index];
    int clamped_substep = substep;

    if (clamped_substep < 0) {
        clamped_substep = 0;
    }
    if (clamped_substep > VIBE_DISPLAY_ANIMATION_SUBSTEPS) {
        clamped_substep = VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    }

    int current_x = from->x + ((to->x - from->x) * clamped_substep) / VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    int current_y = from->y + ((to->y - from->y) * clamped_substep) / VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    return maze_pellet_between_points(pellet_index, from, current_x, current_y);
}

static bool maze_pellet_between_points(int pellet_index, const vibe_display_maze_point_t *from, int to_x, int to_y)
{
    int index = positive_mod(pellet_index, VIBE_DISPLAY_MAZE_PELLET_COUNT);
    const vibe_display_maze_point_t *pellet = &vibe_display_reference_pellets[index];
    int dx = to_x - from->x;
    int dy = to_y - from->y;
    int px = pellet->x - from->x;
    int py = pellet->y - from->y;

    if (px * dy != py * dx) {
        return false;
    }

    int min_x = from->x < to_x ? from->x : to_x;
    int max_x = from->x > to_x ? from->x : to_x;
    int min_y = from->y < to_y ? from->y : to_y;
    int max_y = from->y > to_y ? from->y : to_y;
    return pellet->x >= min_x && pellet->x <= max_x &&
           pellet->y >= min_y && pellet->y <= max_y;
}

static int maze_pellet_round_ticks(int actor_count)
{
    static const int round_ticks_by_actor_count[VIBE_STATUS_MAX_TASKS + 1] = {
        0,
        731,
        377,
        277,
        199,
        165,
    };

    if (actor_count < 1) {
        actor_count = 1;
    }
    if (actor_count > VIBE_STATUS_MAX_TASKS) {
        actor_count = VIBE_STATUS_MAX_TASKS;
    }
    return round_ticks_by_actor_count[actor_count];
}

void vibe_display_animation_actor_shape(const vibe_display_animation_frame_t *frame, vibe_display_animation_actor_t *actor)
{
    if (frame == NULL || actor == NULL) {
        return;
    }

    const int radius = VIBE_DISPLAY_CODEX_ACTOR_RADIUS;
    const int reach = radius + 3;
    const int open = frame->mouth_open ? radius - 2 : 2;
    memset(actor, 0, sizeof(*actor));

    switch (frame->direction) {
    case VIBE_DISPLAY_DIRECTION_RIGHT:
        actor->mouth_tip_x = frame->x + reach;
        actor->mouth_tip_y = frame->y;
        actor->mouth_a_x = frame->x;
        actor->mouth_a_y = frame->y - open;
        actor->mouth_b_x = frame->x;
        actor->mouth_b_y = frame->y + open;
        actor->eye_x = frame->x + 5;
        actor->eye_y = frame->y - 7;
        break;
    case VIBE_DISPLAY_DIRECTION_DOWN:
        actor->mouth_tip_x = frame->x;
        actor->mouth_tip_y = frame->y + reach;
        actor->mouth_a_x = frame->x - open;
        actor->mouth_a_y = frame->y;
        actor->mouth_b_x = frame->x + open;
        actor->mouth_b_y = frame->y;
        actor->eye_x = frame->x + 7;
        actor->eye_y = frame->y + 5;
        break;
    case VIBE_DISPLAY_DIRECTION_LEFT:
        actor->mouth_tip_x = frame->x - reach;
        actor->mouth_tip_y = frame->y;
        actor->mouth_a_x = frame->x;
        actor->mouth_a_y = frame->y - open;
        actor->mouth_b_x = frame->x;
        actor->mouth_b_y = frame->y + open;
        actor->eye_x = frame->x - 5;
        actor->eye_y = frame->y - 7;
        break;
    case VIBE_DISPLAY_DIRECTION_UP:
    default:
        actor->mouth_tip_x = frame->x;
        actor->mouth_tip_y = frame->y - reach;
        actor->mouth_a_x = frame->x - open;
        actor->mouth_a_y = frame->y;
        actor->mouth_b_x = frame->x + open;
        actor->mouth_b_y = frame->y;
        actor->eye_x = frame->x + 7;
        actor->eye_y = frame->y - 5;
        break;
    }
}

static void maze_frame_at_tick(int tick, int phase_offset, bool mouth_open, vibe_display_animation_frame_t *frame)
{
    const int total_ticks = VIBE_DISPLAY_ANIMATION_PATH_STEPS * VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    int total_position = positive_mod(tick + phase_offset * VIBE_DISPLAY_ANIMATION_SUBSTEPS, total_ticks);
    int position = total_position / VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    int substep = total_position % VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    int index = vibe_display_reference_path[position];
    int next_index = vibe_display_reference_path[(position + 1) % VIBE_DISPLAY_ANIMATION_PATH_STEPS];
    const vibe_display_maze_point_t *point = &vibe_display_reference_pellets[index];
    const vibe_display_maze_point_t *next = &vibe_display_reference_pellets[next_index];
    int ax = vibe_display_maze_display_x(point->x);
    int bx = vibe_display_maze_display_x(next->x);
    int ay = VIBE_DISPLAY_MAZE_STAGE_Y + point->y;
    int by = VIBE_DISPLAY_MAZE_STAGE_Y + next->y;

    frame->x = ax + ((bx - ax) * substep) / VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    frame->y = ay + ((by - ay) * substep) / VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    frame->mouth_open = mouth_open;

    int dx = next->x - point->x;
    int dy = next->y - point->y;
    if (dx > 0) {
        frame->direction = VIBE_DISPLAY_DIRECTION_RIGHT;
    } else if (dx < 0) {
        frame->direction = VIBE_DISPLAY_DIRECTION_LEFT;
    } else if (dy > 0) {
        frame->direction = VIBE_DISPLAY_DIRECTION_DOWN;
    } else {
        frame->direction = VIBE_DISPLAY_DIRECTION_UP;
    }
}

static void maze_pellet_at_index(int index, vibe_display_animation_frame_t *frame)
{
    int local_index = index % VIBE_DISPLAY_MAZE_PELLET_COUNT;
    if (local_index < 0) {
        local_index += VIBE_DISPLAY_MAZE_PELLET_COUNT;
    }

    frame->x = vibe_display_maze_display_x(vibe_display_reference_pellets[local_index].x);
    frame->y = VIBE_DISPLAY_MAZE_STAGE_Y + vibe_display_reference_pellets[local_index].y;
    frame->direction = VIBE_DISPLAY_DIRECTION_RIGHT;
    frame->mouth_open = false;
}

static int positive_mod(int value, int modulus)
{
    if (modulus <= 0) {
        return 0;
    }

    int result = value % modulus;
    if (result < 0) {
        result += modulus;
    }
    return result;
}

static uint32_t fnv1a_update(uint32_t hash, const void *data, size_t length)
{
    const unsigned char *bytes = (const unsigned char *)data;
    for (size_t i = 0; i < length; i++) {
        hash ^= bytes[i];
        hash *= 16777619u;
    }
    return hash;
}

static uint32_t fnv1a_update_text(uint32_t hash, const char *text)
{
    if (text == NULL) {
        return fnv1a_update(hash, "", 1);
    }

    return fnv1a_update(hash, text, strlen(text) + 1);
}

static const char *badge_for_state(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_BUSY:
        return "RUN";
    case VIBE_DISPLAY_WAITING:
        return "WAIT";
    case VIBE_DISPLAY_SUCCESS:
        return "DONE";
    case VIBE_DISPLAY_ERROR:
        return "ERR";
    case VIBE_DISPLAY_OFFLINE:
        return "OFF";
    case VIBE_DISPLAY_IDLE:
    default:
        return "IDLE";
    }
}

static void copy_text(char *dest, size_t dest_size, const char *source)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    if (source == NULL) {
        source = "";
    }

    snprintf(dest, dest_size, "%s", source);
}

static void append_text(char *dest, size_t dest_size, const char *source)
{
    if (dest == NULL || source == NULL || dest_size == 0) {
        return;
    }

    size_t used = strnlen(dest, dest_size);
    if (used >= dest_size - 1) {
        return;
    }

    copy_text(dest + used, dest_size - used, source);
}

static void format_count(char *dest, size_t dest_size, char label, int count)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    if (count < 0) {
        count = 0;
    }
    snprintf(dest, dest_size, "%c%d", label, count);
}

static void format_maze_count(char *dest, size_t dest_size, const char *label, int count)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    if (count < 0) {
        count = 0;
    }
    snprintf(dest, dest_size, "%s %d", label, count);
}

static void format_percent(char *dest, size_t dest_size, const char *label, int percent)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    dest[0] = '\0';
    if (label == NULL || percent < 0) {
        return;
    }
    if (percent > 100) {
        percent = 100;
    }

    snprintf(dest, dest_size, "%s %d%%", label, percent);
}
