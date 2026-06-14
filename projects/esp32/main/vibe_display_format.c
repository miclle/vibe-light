#include "vibe_display_model.h"

#include <stdio.h>
#include <string.h>

#define VIBE_DISPLAY_HIGH_CONTEXT_PERCENT 80
#define VIBE_DISPLAY_CRITICAL_CONTEXT_PERCENT 90

static const char *badge_for_state(vibe_display_state_t state);
static const char *source_label(const char *source);
static void copy_text(char *dest, size_t dest_size, const char *source);
static void append_text(char *dest, size_t dest_size, const char *source);
static void format_count(char *dest, size_t dest_size, char label, int count);
static void format_maze_count(char *dest, size_t dest_size, const char *label, int count);
static void format_percent(char *dest, size_t dest_size, const char *label, int percent);
static void format_context_usage(char *dest, size_t dest_size, const vibe_status_task_t *task);
static vibe_display_trailing_severity_t context_trailing_severity(const vibe_status_task_t *task);
static void format_compact_token_count(char *dest, size_t dest_size, int tokens);
static bool format_reset_hint(char *dest, size_t dest_size, const char *label, int remaining_percent, int64_t reset_at_ms, int64_t now_ms);
static bool format_task_timing(char *dest, size_t dest_size, const vibe_status_task_t *task, int64_t now_ms);
static bool task_has_context_usage(const vibe_status_task_t *task);
static bool should_show_context_for_task(const vibe_status_task_t *task, int index, int phase);
static void compact_app_version(const char *app_version, char *dest, size_t dest_size);
static int positive_mod(int value, int modulus);

void vibe_display_format_task_row(const vibe_status_task_t *task, int index, vibe_display_task_row_t *row)
{
    vibe_display_format_task_row_at(task, 0, index, row);
}

void vibe_display_format_task_row_at(const vibe_status_task_t *task, int64_t now_ms, int index, vibe_display_task_row_t *row)
{
    vibe_display_format_task_row_at_phase(task, now_ms, index, 0, row);
}

void vibe_display_format_task_row_at_phase(const vibe_status_task_t *task, int64_t now_ms, int index, int phase, vibe_display_task_row_t *row)
{
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
    bool has_timing = format_task_timing(row->trailing, sizeof(row->trailing), task, now_ms);
    if (has_timing && should_show_context_for_task(task, index, phase)) {
        format_context_usage(row->trailing, sizeof(row->trailing), task);
        row->trailing_severity = context_trailing_severity(task);
    } else if (!has_timing) {
        format_context_usage(row->trailing, sizeof(row->trailing), task);
        row->trailing_severity = context_trailing_severity(task);
    }

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

bool vibe_display_should_render_task_detail(const vibe_status_task_t *task)
{
    return task != NULL && task->detail[0] != '\0';
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
    if (!format_reset_hint(summary->reset_hint,
                           sizeof(summary->reset_hint),
                           "5H",
                           packet->codex_5h_remaining_percent,
                           packet->codex_5h_reset_at_ms,
                           packet->timestamp_ms)) {
        format_reset_hint(summary->reset_hint,
                          sizeof(summary->reset_hint),
                          "7D",
                          packet->codex_7d_remaining_percent,
                          packet->codex_7d_reset_at_ms,
                          packet->timestamp_ms);
    }
}

void vibe_display_format_usage_line(const vibe_display_usage_summary_t *summary, char *text, size_t text_size)
{
    if (text == NULL || text_size == 0) {
        return;
    }

    text[0] = '\0';
    if (summary == NULL) {
        return;
    }

    if (summary->five_hour[0] != '\0' && summary->weekly[0] != '\0') {
        snprintf(text, text_size, "CODEX: %s %s", summary->five_hour, summary->weekly);
    } else if (summary->five_hour[0] != '\0') {
        snprintf(text, text_size, "CODEX: %s", summary->five_hour);
    } else if (summary->weekly[0] != '\0') {
        snprintf(text, text_size, "CODEX: %s", summary->weekly);
    }
}

void vibe_display_format_usage_reset_line(const vibe_display_usage_summary_t *summary, char *text, size_t text_size)
{
    if (text == NULL || text_size == 0) {
        return;
    }

    text[0] = '\0';
    if (summary == NULL || summary->reset_hint[0] == '\0') {
        return;
    }

    snprintf(text, text_size, "%s", summary->reset_hint);
}

void vibe_display_format_empty_state(const vibe_status_packet_t *packet, vibe_display_empty_state_t *empty)
{
    if (empty == NULL) {
        return;
    }

    memset(empty, 0, sizeof(*empty));
    copy_text(empty->label, sizeof(empty->label), "NO ACTIVE TASKS");
    empty->detail_scale = 2;
    empty->detail_max_width = 288;
    empty->quiet_header = true;
    if (packet == NULL || packet->detail[0] == '\0' || strcmp(packet->detail, "no active tasks") == 0) {
        copy_text(empty->detail, sizeof(empty->detail), vibe_display_state_to_title(packet == NULL ? VIBE_DISPLAY_IDLE : packet->state));
        return;
    }

    copy_text(empty->detail, sizeof(empty->detail), packet->detail);
}

void vibe_display_footer_text(const vibe_status_packet_t *packet, char *text, size_t text_size)
{
    if (text == NULL || text_size == 0) {
        return;
    }

    text[0] = '\0';
    if (packet == NULL) {
        return;
    }

    if (packet->state == VIBE_DISPLAY_OFFLINE) {
        snprintf(text, text_size, "OFFLINE");
        return;
    }

    snprintf(text, text_size, "%s %s", source_label(packet->source), packet->version <= 1 ? "LEGACY" : "LIVE");
}

void vibe_display_firmware_version_text(const char *app_version, char *text, size_t text_size)
{
    if (text == NULL || text_size == 0) {
        return;
    }

    text[0] = '\0';
    if (app_version == NULL || app_version[0] == '\0') {
        return;
    }

    char compact_version[9];
    compact_app_version(app_version, compact_version, sizeof(compact_version));
    snprintf(text, text_size, "FW %s", compact_version);
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

static const char *source_label(const char *source)
{
    if (source == NULL || source[0] == '\0') {
        return "SRC";
    }
    if (strcmp(source, "codex") == 0) {
        return "CODEX";
    }
    if (strcmp(source, "claude") == 0) {
        return "CLAUDE";
    }
    if (strcmp(source, "manual") == 0) {
        return "MANUAL";
    }
    return "OTHER";
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

static void format_context_usage(char *dest, size_t dest_size, const vibe_status_task_t *task)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    dest[0] = '\0';
    if (task == NULL) {
        return;
    }

    if (task->context_used_tokens >= 0 && task->context_window_tokens > 0) {
        char used[8];
        char window[8];
        format_compact_token_count(used, sizeof(used), task->context_used_tokens);
        format_compact_token_count(window, sizeof(window), task->context_window_tokens);
        int written = snprintf(dest, dest_size, "CTX %s/%s", used, window);
        if (written >= 0 && (size_t)written < dest_size) {
            return;
        }
        snprintf(dest, dest_size, "CTX %s", used);
        return;
    }

    format_percent(dest, dest_size, "CTX", task->context_used_percent);
}

static vibe_display_trailing_severity_t context_trailing_severity(const vibe_status_task_t *task)
{
    if (task == NULL || task->context_used_percent < VIBE_DISPLAY_HIGH_CONTEXT_PERCENT) {
        return VIBE_DISPLAY_TRAILING_NEUTRAL;
    }
    if (task->context_used_percent >= VIBE_DISPLAY_CRITICAL_CONTEXT_PERCENT) {
        return VIBE_DISPLAY_TRAILING_CRITICAL;
    }
    return VIBE_DISPLAY_TRAILING_WARNING;
}

static void format_compact_token_count(char *dest, size_t dest_size, int tokens)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    if (tokens < 0) {
        tokens = 0;
    }
    if (tokens < 1000) {
        snprintf(dest, dest_size, "%d", tokens);
        return;
    }

    int tenths = (tokens + 50) / 100;
    if (tenths < 100) {
        snprintf(dest, dest_size, "%d.%dK", tenths / 10, tenths % 10);
        return;
    }

    int thousands = (tokens + 500) / 1000;
    if (thousands > 999) {
        thousands = 999;
    }
    snprintf(dest, dest_size, "%dK", thousands);
}

static bool format_reset_hint(char *dest, size_t dest_size, const char *label, int remaining_percent, int64_t reset_at_ms, int64_t now_ms)
{
    if (dest == NULL || dest_size == 0) {
        return false;
    }

    dest[0] = '\0';
    if (label == NULL || remaining_percent < 0 || remaining_percent > 20 || reset_at_ms <= now_ms || now_ms <= 0) {
        return false;
    }

    int64_t remaining_minutes = (reset_at_ms - now_ms + 59999) / 60000;
    if (remaining_minutes < 1) {
        remaining_minutes = 1;
    }
    if (remaining_minutes < 60) {
        snprintf(dest, dest_size, "%s RESET %lldm", label, (long long)remaining_minutes);
        return true;
    }

    int64_t remaining_hours = (remaining_minutes + 59) / 60;
    if (remaining_hours < 48) {
        snprintf(dest, dest_size, "%s RESET %lldh", label, (long long)remaining_hours);
        return true;
    }

    int64_t remaining_days = (remaining_hours + 23) / 24;
    if (remaining_days > 99) {
        remaining_days = 99;
    }
    snprintf(dest, dest_size, "%s RESET %lldd", label, (long long)remaining_days);
    return true;
}

static bool format_task_timing(char *dest, size_t dest_size, const vibe_status_task_t *task, int64_t now_ms)
{
    if (dest == NULL || dest_size == 0 || task == NULL || now_ms <= 0 || task->updated_at_ms <= 0 ||
        now_ms < task->updated_at_ms) {
        return false;
    }

    int64_t elapsed_seconds = (now_ms - task->updated_at_ms) / 1000;
    if (task->state == VIBE_DISPLAY_BUSY || task->state == VIBE_DISPLAY_WAITING) {
        if (elapsed_seconds > 99 * 60 + 59) {
            elapsed_seconds = 99 * 60 + 59;
        }
        const char *prefix = task->state == VIBE_DISPLAY_WAITING ? "WAIT" : "RUN";
        snprintf(dest,
                 dest_size,
                 "%s %02lld:%02lld",
                 prefix,
                 (long long)(elapsed_seconds / 60),
                 (long long)(elapsed_seconds % 60));
        return true;
    }

    if (elapsed_seconds < 60) {
        snprintf(dest, dest_size, "%llds ago", (long long)elapsed_seconds);
    } else if (elapsed_seconds < 60 * 60) {
        snprintf(dest, dest_size, "%lldm ago", (long long)(elapsed_seconds / 60));
    } else {
        int64_t hours = elapsed_seconds / (60 * 60);
        if (hours > 99) {
            hours = 99;
        }
        snprintf(dest, dest_size, "%lldh ago", (long long)hours);
    }
    return true;
}

static bool should_show_context_for_task(const vibe_status_task_t *task, int index, int phase)
{
    if (task == NULL || !task_has_context_usage(task) ||
        (task->state != VIBE_DISPLAY_BUSY && task->state != VIBE_DISPLAY_WAITING)) {
        return false;
    }

    bool high_context = task->context_used_percent >= VIBE_DISPLAY_HIGH_CONTEXT_PERCENT;
    int slot = positive_mod((phase / 12) + index, high_context ? 2 : 4);
    return slot == (high_context ? 1 : 3);
}

static bool task_has_context_usage(const vibe_status_task_t *task)
{
    if (task == NULL) {
        return false;
    }

    return task->context_used_percent >= 0 ||
           (task->context_used_tokens >= 0 && task->context_window_tokens > 0);
}

static void compact_app_version(const char *app_version, char *dest, size_t dest_size)
{
    if (dest == NULL || dest_size == 0) {
        return;
    }

    dest[0] = '\0';
    if (app_version == NULL || app_version[0] == '\0') {
        return;
    }

    const size_t max_visible_version_chars = dest_size - 1;
    bool dirty = false;
    char version[32];
    snprintf(version, sizeof(version), "%s", app_version);
    char *dirty_suffix = strrchr(version, '-');
    if (dirty_suffix != NULL && strcmp(dirty_suffix, "-dirty") == 0) {
        dirty = true;
        dirty_suffix[0] = '\0';
    }

    const char *compact = version;
    size_t length = strlen(version);
    if (length > max_visible_version_chars) {
        const char *last_dash = strrchr(version, '-');
        if (last_dash != NULL && last_dash[1] != '\0' && strlen(last_dash + 1) <= max_visible_version_chars) {
            compact = last_dash + 1;
        }
    }

    size_t copy_limit = dirty && max_visible_version_chars > 0 ? max_visible_version_chars - 1 : max_visible_version_chars;
    snprintf(dest, dest_size, "%.*s", (int)copy_limit, compact);
    if (dirty && dest[0] != '\0') {
        size_t dest_length = strlen(dest);
        if (dest_length + 1 < dest_size) {
            dest[dest_length] = '*';
            dest[dest_length + 1] = '\0';
        }
    }
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
