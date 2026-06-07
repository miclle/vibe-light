#include "vibe_display_model.h"

#include <stdio.h>
#include <string.h>

static uint32_t fnv1a_update(uint32_t hash, const void *data, size_t length);
static uint32_t fnv1a_update_text(uint32_t hash, const char *text);
static const char *badge_for_state(vibe_display_state_t state);
static void copy_text(char *dest, size_t dest_size, const char *source);
static void append_text(char *dest, size_t dest_size, const char *source);

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

void vibe_display_animation_frame(int tick, int active_count, vibe_display_animation_frame_t *frame)
{
    if (frame == NULL) {
        return;
    }

    int step = vibe_display_animation_step(active_count);
    int position = (tick * step) % VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    if (position < 0) {
        position += VIBE_DISPLAY_ANIMATION_PATH_STEPS;
    }

    const int left = 18;
    const int right = 302;
    const int top = 92;
    const int bottom = 788;
    const int side_steps = VIBE_DISPLAY_ANIMATION_PATH_STEPS / 4;
    int segment = position / side_steps;
    int offset = position % side_steps;

    frame->mouth_open = (tick % 2) == 0;

    switch (segment) {
    case 0:
        frame->x = left + ((right - left) * offset) / side_steps;
        frame->y = top;
        frame->direction = VIBE_DISPLAY_DIRECTION_RIGHT;
        break;
    case 1:
        frame->x = right;
        frame->y = top + ((bottom - top) * offset) / side_steps;
        frame->direction = VIBE_DISPLAY_DIRECTION_DOWN;
        break;
    case 2:
        frame->x = right - ((right - left) * offset) / side_steps;
        frame->y = bottom;
        frame->direction = VIBE_DISPLAY_DIRECTION_LEFT;
        break;
    default:
        frame->x = left;
        frame->y = bottom - ((bottom - top) * offset) / side_steps;
        frame->direction = VIBE_DISPLAY_DIRECTION_UP;
        break;
    }
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
