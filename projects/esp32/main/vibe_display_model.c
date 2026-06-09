#include "vibe_display_model.h"

#include <stdio.h>
#include <string.h>

static uint32_t fnv1a_update(uint32_t hash, const void *data, size_t length);
static uint32_t fnv1a_update_text(uint32_t hash, const char *text);
static const char *badge_for_state(vibe_display_state_t state);
static int abs_int(int value);
static void maze_pellet_at_index(int index, vibe_display_animation_frame_t *frame);
static void maze_frame_at_position(int position, bool mouth_open, vibe_display_animation_frame_t *frame);
static void copy_text(char *dest, size_t dest_size, const char *source);
static void append_text(char *dest, size_t dest_size, const char *source);
static void format_count(char *dest, size_t dest_size, char label, int count);

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
    hash = fnv1a_update(hash, &packet->task_count, sizeof(packet->task_count));

    int rows = packet->task_count > VIBE_STATUS_MAX_TASKS ? VIBE_STATUS_MAX_TASKS : packet->task_count;
    for (int i = 0; i < rows; i++) {
        const vibe_status_task_t *task = &packet->tasks[i];
        hash = fnv1a_update_text(hash, task->title);
        hash = fnv1a_update_text(hash, task->source);
        hash = fnv1a_update(hash, &task->state, sizeof(task->state));
        hash = fnv1a_update_text(hash, task->detail);
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
    if (active_count >= 5) {
        return 3;
    }
    if (active_count >= 2) {
        return 2;
    }
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

    int step = vibe_display_animation_step(active_count);
    int phase_offset = (actor_index * VIBE_DISPLAY_ANIMATION_PATH_STEPS) / actor_count;
    int position = (tick * step + phase_offset) % VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    if (position < 0) {
        position += VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    }

    maze_frame_at_position(position, (tick % 2) == 0, frame);
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
    maze_frame_at_position(position, false, frame);
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
        return index == 0 || index == 21 || index == 56 || index == 77;
    }

    return index == 0 ||
           index == pellet_count / 3 ||
           index == (pellet_count * 2) / 3 ||
           index == pellet_count - 1;
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

static void maze_frame_at_position(int position, bool mouth_open, vibe_display_animation_frame_t *frame)
{
    static const struct {
        int x;
        int y;
    } maze_path[] = {
        {VIBE_DISPLAY_MAZE_STAGE_X + 168, VIBE_DISPLAY_MAZE_STAGE_Y + 238},
        {VIBE_DISPLAY_MAZE_STAGE_X + 252, VIBE_DISPLAY_MAZE_STAGE_Y + 238},
        {VIBE_DISPLAY_MAZE_STAGE_X + 252, VIBE_DISPLAY_MAZE_STAGE_Y + 62},
        {VIBE_DISPLAY_MAZE_STAGE_X + 78, VIBE_DISPLAY_MAZE_STAGE_Y + 62},
        {VIBE_DISPLAY_MAZE_STAGE_X + 78, VIBE_DISPLAY_MAZE_STAGE_Y + 104},
        {VIBE_DISPLAY_MAZE_STAGE_X + 132, VIBE_DISPLAY_MAZE_STAGE_Y + 104},
        {VIBE_DISPLAY_MAZE_STAGE_X + 132, VIBE_DISPLAY_MAZE_STAGE_Y + 150},
        {VIBE_DISPLAY_MAZE_STAGE_X + 188, VIBE_DISPLAY_MAZE_STAGE_Y + 150},
        {VIBE_DISPLAY_MAZE_STAGE_X + 188, VIBE_DISPLAY_MAZE_STAGE_Y + 104},
        {VIBE_DISPLAY_MAZE_STAGE_X + 238, VIBE_DISPLAY_MAZE_STAGE_Y + 104},
        {VIBE_DISPLAY_MAZE_STAGE_X + 238, VIBE_DISPLAY_MAZE_STAGE_Y + 238},
        {VIBE_DISPLAY_MAZE_STAGE_X + 168, VIBE_DISPLAY_MAZE_STAGE_Y + 238},
    };

    if (position < 0) {
        position += VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    }
    position %= VIBE_DISPLAY_ANIMATION_PATH_STEPS;

    const int point_count = (int)(sizeof(maze_path) / sizeof(maze_path[0]));
    const int segment_count = point_count - 1;
    int total_length = 0;
    for (int i = 0; i < segment_count; i++) {
        total_length += abs_int(maze_path[i + 1].x - maze_path[i].x);
        total_length += abs_int(maze_path[i + 1].y - maze_path[i].y);
    }

    int target = (position * total_length) / VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    int segment = 0;
    int walked = 0;
    while (segment < segment_count) {
        int length = abs_int(maze_path[segment + 1].x - maze_path[segment].x) +
                     abs_int(maze_path[segment + 1].y - maze_path[segment].y);
        if (target < walked + length || segment == segment_count - 1) {
            break;
        }
        walked += length;
        segment++;
    }

    int ax = maze_path[segment].x;
    int ay = maze_path[segment].y;
    int bx = maze_path[segment + 1].x;
    int by = maze_path[segment + 1].y;
    int local = target - walked;
    int segment_length = abs_int(bx - ax) + abs_int(by - ay);
    if (segment_length <= 0) {
        segment_length = 1;
    }

    frame->x = ax + ((bx - ax) * local) / segment_length;
    frame->y = ay + ((by - ay) * local) / segment_length;
    frame->mouth_open = mouth_open;

    int dx = bx - ax;
    int dy = by - ay;
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
    static const struct {
        int x1;
        int y1;
        int x2;
        int y2;
        int count;
    } lanes[] = {
        {VIBE_DISPLAY_MAZE_STAGE_X + 78, VIBE_DISPLAY_MAZE_STAGE_Y + 62,
         VIBE_DISPLAY_MAZE_STAGE_X + 144, VIBE_DISPLAY_MAZE_STAGE_Y + 62, 11},
        {VIBE_DISPLAY_MAZE_STAGE_X + 176, VIBE_DISPLAY_MAZE_STAGE_Y + 62,
         VIBE_DISPLAY_MAZE_STAGE_X + 252, VIBE_DISPLAY_MAZE_STAGE_Y + 62, 11},
        {VIBE_DISPLAY_MAZE_STAGE_X + 78, VIBE_DISPLAY_MAZE_STAGE_Y + 104,
         VIBE_DISPLAY_MAZE_STAGE_X + 144, VIBE_DISPLAY_MAZE_STAGE_Y + 104, 10},
        {VIBE_DISPLAY_MAZE_STAGE_X + 176, VIBE_DISPLAY_MAZE_STAGE_Y + 104,
         VIBE_DISPLAY_MAZE_STAGE_X + 252, VIBE_DISPLAY_MAZE_STAGE_Y + 104, 10},
        {VIBE_DISPLAY_MAZE_STAGE_X + 78, VIBE_DISPLAY_MAZE_STAGE_Y + 150,
         VIBE_DISPLAY_MAZE_STAGE_X + 132, VIBE_DISPLAY_MAZE_STAGE_Y + 150, 7},
        {VIBE_DISPLAY_MAZE_STAGE_X + 188, VIBE_DISPLAY_MAZE_STAGE_Y + 150,
         VIBE_DISPLAY_MAZE_STAGE_X + 252, VIBE_DISPLAY_MAZE_STAGE_Y + 150, 7},
        {VIBE_DISPLAY_MAZE_STAGE_X + 78, VIBE_DISPLAY_MAZE_STAGE_Y + 238,
         VIBE_DISPLAY_MAZE_STAGE_X + 144, VIBE_DISPLAY_MAZE_STAGE_Y + 238, 11},
        {VIBE_DISPLAY_MAZE_STAGE_X + 176, VIBE_DISPLAY_MAZE_STAGE_Y + 238,
         VIBE_DISPLAY_MAZE_STAGE_X + 252, VIBE_DISPLAY_MAZE_STAGE_Y + 238, 11},
        {VIBE_DISPLAY_MAZE_STAGE_X + 82, VIBE_DISPLAY_MAZE_STAGE_Y + 68,
         VIBE_DISPLAY_MAZE_STAGE_X + 82, VIBE_DISPLAY_MAZE_STAGE_Y + 230, 6},
        {VIBE_DISPLAY_MAZE_STAGE_X + 132, VIBE_DISPLAY_MAZE_STAGE_Y + 68,
         VIBE_DISPLAY_MAZE_STAGE_X + 132, VIBE_DISPLAY_MAZE_STAGE_Y + 230, 6},
        {VIBE_DISPLAY_MAZE_STAGE_X + 188, VIBE_DISPLAY_MAZE_STAGE_Y + 68,
         VIBE_DISPLAY_MAZE_STAGE_X + 188, VIBE_DISPLAY_MAZE_STAGE_Y + 230, 6},
        {VIBE_DISPLAY_MAZE_STAGE_X + 238, VIBE_DISPLAY_MAZE_STAGE_Y + 68,
         VIBE_DISPLAY_MAZE_STAGE_X + 238, VIBE_DISPLAY_MAZE_STAGE_Y + 230, 6},
    };

    int local_index = index % VIBE_DISPLAY_MAZE_PELLET_COUNT;
    if (local_index < 0) {
        local_index += VIBE_DISPLAY_MAZE_PELLET_COUNT;
    }

    for (size_t i = 0; i < sizeof(lanes) / sizeof(lanes[0]); i++) {
        if (local_index >= lanes[i].count) {
            local_index -= lanes[i].count;
            continue;
        }

        int divisor = lanes[i].count > 1 ? lanes[i].count - 1 : 1;
        frame->x = lanes[i].x1 + ((lanes[i].x2 - lanes[i].x1) * local_index) / divisor;
        frame->y = lanes[i].y1 + ((lanes[i].y2 - lanes[i].y1) * local_index) / divisor;
        frame->direction = VIBE_DISPLAY_DIRECTION_RIGHT;
        frame->mouth_open = false;
        return;
    }

    frame->x = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET;
    frame->y = VIBE_DISPLAY_MAZE_STAGE_Y + 238;
    frame->direction = VIBE_DISPLAY_DIRECTION_RIGHT;
    frame->mouth_open = false;
}

static int abs_int(int value)
{
    return value < 0 ? -value : value;
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
