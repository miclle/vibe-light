#include "vibe_health.h"

#include <stdio.h>
#include <string.h>

static int append_json_string(char *dest, size_t dest_size, const char *value);

int vibe_health_format_json(char *payload, size_t payload_size, const vibe_health_snapshot_t *snapshot)
{
    if (payload == NULL || payload_size == 0 || snapshot == NULL) {
        return -1;
    }

    const char *device = snapshot->device == NULL ? "" : snapshot->device;
    const char *last_state = snapshot->last_state == NULL ? "idle" : snapshot->last_state;
    const char *last_parse_error = snapshot->last_parse_error == NULL ? "" : snapshot->last_parse_error;
    const char *firmware_version = snapshot->firmware_version == NULL ? "" : snapshot->firmware_version;
    const char *project_name = snapshot->project_name == NULL ? "" : snapshot->project_name;
    const char *running_slot = snapshot->running_slot == NULL ? "" : snapshot->running_slot;
    const char *rollback_state = snapshot->rollback_state == NULL ? "" : snapshot->rollback_state;

    int written = snprintf(payload,
                           payload_size,
                           "{\"connected\":%s,\"device\":\"",
                           snapshot->connected ? "true" : "false");
    if (written < 0 || (size_t)written >= payload_size) {
        return -1;
    }

    int escaped = append_json_string(payload + written, payload_size - (size_t)written, device);
    if (escaped < 0) {
        return -1;
    }
    written += escaped;

    int tail = snprintf(payload + written,
                        payload_size - (size_t)written,
                        "\",\"freeHeapBytes\":%u,\"lastState\":\"",
                        snapshot->free_heap_bytes);
    if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
        return -1;
    }
    written += tail;

    escaped = append_json_string(payload + written, payload_size - (size_t)written, last_state);
    if (escaped < 0) {
        return -1;
    }
    written += escaped;

    tail = snprintf(payload + written,
                    payload_size - (size_t)written,
                    "\",\"minFreeHeapBytes\":%u,\"uptimeMs\":%lld,\"v\":1",
                    snapshot->min_free_heap_bytes,
                    (long long)snapshot->uptime_ms);
    if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
        return -1;
    }
    written += tail;

    if (project_name[0] != '\0') {
        tail = snprintf(payload + written, payload_size - (size_t)written, ",\"firmwareVersion\":\"");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
        escaped = append_json_string(payload + written, payload_size - (size_t)written, firmware_version);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;

        tail = snprintf(payload + written,
                        payload_size - (size_t)written,
                        "\",\"otaCapable\":%s,\"projectName\":\"",
                        snapshot->ota_capable ? "true" : "false");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
        escaped = append_json_string(payload + written, payload_size - (size_t)written, project_name);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;

        tail = snprintf(payload + written,
                        payload_size - (size_t)written,
                        "\",\"signedUpdatesRequired\":%s",
                        snapshot->signed_updates_required ? "true" : "false");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;

        tail = snprintf(payload + written, payload_size - (size_t)written, ",\"rollbackState\":\"");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
        escaped = append_json_string(payload + written, payload_size - (size_t)written, rollback_state);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;

        tail = snprintf(payload + written, payload_size - (size_t)written, "\",\"runningSlot\":\"");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
        escaped = append_json_string(payload + written, payload_size - (size_t)written, running_slot);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;
        tail = snprintf(payload + written, payload_size - (size_t)written, "\"");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
    }

    if (snapshot->has_animation_tick) {
        tail = snprintf(payload + written,
                        payload_size - (size_t)written,
                        ",\"animationTick\":%d",
                        snapshot->animation_tick);
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
    }

    if (snapshot->has_backlight_on) {
        tail = snprintf(payload + written,
                        payload_size - (size_t)written,
                        ",\"backlightOn\":%s",
                        snapshot->backlight_on ? "true" : "false");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
    }

    if (snapshot->has_indicator_on) {
        tail = snprintf(payload + written,
                        payload_size - (size_t)written,
                        ",\"indicatorOn\":%s",
                        snapshot->indicator_on ? "true" : "false");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
    }

    if (last_parse_error[0] != '\0') {
        tail = snprintf(payload + written, payload_size - (size_t)written, ",\"lastParseError\":\"");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;

        escaped = append_json_string(payload + written, payload_size - (size_t)written, last_parse_error);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;

        tail = snprintf(payload + written, payload_size - (size_t)written, "\"");
        if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
            return -1;
        }
        written += tail;
    }

    tail = snprintf(payload + written, payload_size - (size_t)written, "}");
    if (tail < 0 || (size_t)tail >= payload_size - (size_t)written) {
        return -1;
    }
    written += tail;
    return written;
}

static int append_json_string(char *dest, size_t dest_size, const char *value)
{
    if (dest == NULL || dest_size == 0) {
        return -1;
    }

    size_t used = 0;
    for (const char *cursor = value == NULL ? "" : value; *cursor != '\0'; cursor++) {
        const char *chunk = NULL;
        char escaped[7];
        size_t chunk_len = 0;

        switch (*cursor) {
        case '\\':
            chunk = "\\\\";
            chunk_len = 2;
            break;
        case '"':
            chunk = "\\\"";
            chunk_len = 2;
            break;
        case '\n':
            chunk = "\\n";
            chunk_len = 2;
            break;
        case '\r':
            chunk = "\\r";
            chunk_len = 2;
            break;
        case '\t':
            chunk = "\\t";
            chunk_len = 2;
            break;
        default:
            if ((unsigned char)*cursor < 0x20) {
                snprintf(escaped, sizeof(escaped), "\\u%04x", (unsigned char)*cursor);
                chunk = escaped;
                chunk_len = 6;
            } else {
                escaped[0] = *cursor;
                escaped[1] = '\0';
                chunk = escaped;
                chunk_len = 1;
            }
            break;
        }

        if (used + chunk_len >= dest_size) {
            return -1;
        }
        memcpy(dest + used, chunk, chunk_len);
        used += chunk_len;
    }

    dest[used] = '\0';
    return (int)used;
}
