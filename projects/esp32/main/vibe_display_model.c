#include "vibe_display_model.h"

#include <stdio.h>
#include <string.h>

static uint32_t fnv1a_update(uint32_t hash, const void *data, size_t length);
static uint32_t fnv1a_update_text(uint32_t hash, const char *text);
static const char *badge_for_state(vibe_display_state_t state);
static void maze_pellet_at_index(int index, vibe_display_animation_frame_t *frame);
static void maze_frame_at_position(int position, bool mouth_open, vibe_display_animation_frame_t *frame);
static void copy_text(char *dest, size_t dest_size, const char *source);
static void append_text(char *dest, size_t dest_size, const char *source);
static void format_count(char *dest, size_t dest_size, char label, int count);

typedef struct {
    int16_t x;
    int16_t y;
} maze_point_t;

// Extracted from docs/Pac-Man-Mini-320x320.png and scaled to the 320px maze stage.
static const maze_point_t reference_pellets[VIBE_DISPLAY_MAZE_PELLET_COUNT] = {
    {29, 43}, {38, 43}, {48, 43}, {57, 43}, {66, 43}, {76, 43},
    {85, 43}, {95, 43}, {105, 43}, {114, 43}, {124, 43}, {133, 43},
    {143, 43}, {176, 43}, {186, 43}, {195, 43}, {204, 43}, {214, 43},
    {223, 43}, {233, 43}, {242, 43}, {252, 43}, {261, 43}, {271, 43},
    {280, 43}, {290, 43}, {235, 52}, {85, 53}, {143, 53}, {176, 53},
    {30, 56}, {290, 56}, {85, 61}, {143, 61}, {176, 61}, {235, 61},
    {29, 71}, {39, 71}, {48, 71}, {57, 71}, {67, 71}, {76, 71},
    {85, 71}, {95, 71}, {104, 71}, {114, 71}, {124, 71}, {133, 71},
    {143, 71}, {153, 71}, {166, 71}, {175, 71}, {185, 71}, {195, 71},
    {205, 71}, {215, 71}, {225, 71}, {235, 71}, {243, 71}, {252, 71},
    {262, 71}, {271, 71}, {281, 71}, {290, 71}, {29, 80}, {85, 80},
    {114, 80}, {206, 80}, {235, 80}, {290, 80}, {29, 90}, {85, 90},
    {114, 90}, {206, 90}, {235, 90}, {290, 90}, {29, 99}, {39, 99},
    {48, 99}, {57, 99}, {67, 99}, {76, 99}, {85, 99}, {114, 99},
    {124, 99}, {133, 99}, {143, 99}, {176, 99}, {186, 99}, {195, 99},
    {205, 99}, {235, 99}, {244, 99}, {253, 99}, {262, 99}, {271, 99},
    {281, 99}, {290, 99}, {85, 108}, {235, 108}, {85, 118}, {235, 118},
    {85, 127}, {235, 127}, {85, 137}, {235, 137}, {85, 146}, {235, 146},
    {85, 155}, {235, 155}, {85, 164}, {235, 164}, {85, 174}, {235, 174},
    {85, 184}, {235, 184}, {85, 193}, {235, 193}, {29, 196}, {39, 196},
    {48, 196}, {57, 196}, {67, 196}, {76, 196}, {95, 196}, {105, 196},
    {114, 196}, {124, 196}, {133, 196}, {178, 196}, {187, 196}, {196, 196},
    {205, 196}, {214, 196}, {224, 196}, {243, 196}, {253, 196}, {262, 196},
    {271, 196}, {281, 196}, {290, 196}, {85, 203}, {235, 203}, {29, 205},
    {178, 205}, {290, 205}, {85, 213}, {235, 213}, {178, 214}, {30, 219},
    {290, 219}, {85, 222}, {235, 222}, {40, 223}, {50, 223}, {95, 223},
    {104, 223}, {114, 223}, {124, 223}, {133, 223}, {143, 223}, {158, 223},
    {167, 223}, {177, 223}, {187, 223}, {196, 223}, {206, 223}, {216, 223},
    {225, 223}, {270, 223}, {279, 223}, {50, 232}, {85, 232}, {114, 232},
    {205, 232}, {235, 232}, {270, 232}, {50, 241}, {85, 241}, {114, 241},
    {206, 241}, {235, 241}, {270, 241}, {29, 250}, {39, 250}, {48, 250},
    {57, 250}, {67, 250}, {76, 250}, {85, 250}, {114, 250}, {124, 250},
    {133, 250}, {143, 250}, {177, 250}, {186, 250}, {196, 250}, {205, 250},
    {235, 250}, {244, 250}, {253, 250}, {262, 250}, {271, 250}, {281, 250},
    {290, 250}, {29, 259}, {143, 259}, {177, 259}, {290, 259}, {29, 268},
    {143, 268}, {177, 268}, {290, 268},
};

static const uint16_t reference_path[VIBE_DISPLAY_ANIMATION_PATH_STEPS] = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 28, 33, 48,
    44, 40, 36, 30, 64, 70, 76, 77, 78, 79, 80, 81, 41, 37, 38, 39,
    42, 27, 32, 65, 71, 82, 98, 100, 102, 104, 106, 108, 110, 112, 114, 116,
    141, 146, 151, 155, 156, 157, 158, 159, 128, 124, 121, 118, 119, 120, 122, 123,
    125, 126, 127, 126, 125, 123, 122, 120, 119, 118, 143, 149, 143, 118, 121, 124,
    128, 159, 160, 161, 162, 163, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138,
    139, 140, 145, 150, 145, 140, 139, 138, 137, 136, 135, 134, 133, 132, 131, 130,
    164, 165, 152, 115, 107, 99, 57, 19, 15, 13, 14, 16, 17, 18, 20, 21,
    22, 23, 24, 25, 31, 63, 59, 55, 51, 29, 34, 29, 51, 47, 43, 45,
    46, 49, 50, 52, 53, 54, 56, 58, 60, 61, 62, 61, 60, 58, 92, 91,
    35, 26, 68, 74, 101, 103, 105, 109, 111, 113, 117, 142, 147, 175, 181, 182,
    169, 170, 169, 176, 202, 198, 199, 200, 201, 203, 204, 208, 212, 208, 204, 203,
    201, 200, 199, 198, 202, 176, 169, 182, 181, 175, 147, 142, 117, 113, 111, 109,
    105, 103, 101, 74, 68, 26, 35, 91, 93, 94, 95, 96, 97, 69, 75, 69,
    97, 96, 95, 94, 93, 91, 92, 58, 56, 54, 67, 73, 90, 87, 88, 89,
    88, 87, 90, 73, 67, 54, 53, 52, 50, 49, 46, 45, 66, 72, 83, 84,
    85, 86, 85, 84, 83, 72, 66, 45, 43, 47, 51, 55, 59, 63, 31, 25,
    24, 23, 22, 21, 20, 18, 17, 16, 14, 13, 15, 19, 57, 99, 107, 115,
    152, 166, 167, 168, 167, 166, 174, 180, 197, 194, 195, 196, 195, 194, 207, 211,
    210, 193, 190, 173, 179, 173, 190, 191, 192, 191, 190, 193, 206, 193, 210, 211,
    207, 194, 197, 180, 174, 166, 152, 165, 164, 130, 129, 144, 148, 144, 129, 163,
    162, 161, 160, 159, 158, 157, 156, 155, 151, 172, 178, 177, 154, 153, 154, 171,
    185, 183, 184, 186, 187, 188, 189, 188, 187, 186, 184, 183, 205, 209, 205, 183,
    185, 171, 154, 177, 178, 172, 151, 146, 141, 116, 114, 112, 110, 108, 106, 104,
    102, 100, 98, 82, 71, 65, 32, 27, 42, 39, 38, 37, 41, 81, 80, 79,
    78, 77, 76, 70, 64, 30, 36, 40, 44, 48, 33, 28, 12, 11, 10, 9,
    8, 7, 6, 5, 4, 3, 2, 1, 0,
};

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
    int position = (tick + phase_offset) % VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    if (position < 0) {
        position += VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    }

    maze_frame_at_position(position, (tick % 2) == 0, frame);
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
                                      int recovery_ticks)
{
    vibe_display_animation_frame_t pellet;
    vibe_display_maze_pellet_position(pellet_index, VIBE_DISPLAY_MAZE_PELLET_COUNT, &pellet);

    if (actor_count < 1) {
        actor_count = 1;
    }
    if (actor_count > VIBE_STATUS_MAX_TASKS) {
        actor_count = VIBE_STATUS_MAX_TASKS;
    }
    if (recovery_ticks < 0) {
        recovery_ticks = 0;
    }

    for (int age = 0; age <= recovery_ticks; age++) {
        for (int actor_index = 0; actor_index < actor_count; actor_index++) {
            vibe_display_animation_frame_t frame;
            vibe_display_animation_actor_frame(tick - age, actor_index, actor_count, active_count, &frame);
            int dx = pellet.x - frame.x;
            int dy = pellet.y - frame.y;
            if (dx > -VIBE_DISPLAY_MAZE_PELLET_EAT_RADIUS && dx < VIBE_DISPLAY_MAZE_PELLET_EAT_RADIUS &&
                dy > -VIBE_DISPLAY_MAZE_PELLET_EAT_RADIUS && dy < VIBE_DISPLAY_MAZE_PELLET_EAT_RADIUS) {
                return false;
            }
        }
    }

    return true;
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
    if (position < 0) {
        position %= VIBE_DISPLAY_ANIMATION_PATH_STEPS;
        position += VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    }
    position %= VIBE_DISPLAY_ANIMATION_PATH_STEPS;

    int index = reference_path[position];
    int next_index = reference_path[(position + 1) % VIBE_DISPLAY_ANIMATION_PATH_STEPS];
    const maze_point_t *point = &reference_pellets[index];
    const maze_point_t *next = &reference_pellets[next_index];

    frame->x = vibe_display_maze_display_x(point->x);
    frame->y = VIBE_DISPLAY_MAZE_STAGE_Y + point->y;
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

    frame->x = vibe_display_maze_display_x(reference_pellets[local_index].x);
    frame->y = VIBE_DISPLAY_MAZE_STAGE_Y + reference_pellets[local_index].y;
    frame->direction = VIBE_DISPLAY_DIRECTION_RIGHT;
    frame->mouth_open = false;
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
