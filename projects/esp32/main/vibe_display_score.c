#include "vibe_display_score.h"

#include "esp_log.h"
#include "nvs.h"
#include "vibe_display_model.h"

#define SCORE_STORAGE_NAMESPACE "vibe"
#define SCORE_STORAGE_KEY "maze_hi"
#define SCORE_PERSIST_STEP 1000

static const char *TAG = "vibe_display_score";

static vibe_display_maze_high_score_t maze_high_score;
static int last_persisted_maze_high_score;

static int load_maze_high_score(void);
static void save_maze_high_score_if_dirty(bool force);

void vibe_display_score_init(void)
{
    last_persisted_maze_high_score = load_maze_high_score();
    vibe_display_maze_high_score_init(&maze_high_score, last_persisted_maze_high_score);
}

int vibe_display_score_value(void)
{
    return maze_high_score.value;
}

bool vibe_display_score_update(int score)
{
    if (!vibe_display_maze_high_score_update(&maze_high_score, score)) {
        return false;
    }

    save_maze_high_score_if_dirty(false);
    return true;
}

void vibe_display_score_flush(void)
{
    save_maze_high_score_if_dirty(true);
}

static int load_maze_high_score(void)
{
    nvs_handle_t handle;
    int32_t stored_score = 0;
    esp_err_t err = nvs_open(SCORE_STORAGE_NAMESPACE, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return 0;
    }
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "failed to open score storage: %s", esp_err_to_name(err));
        return 0;
    }

    err = nvs_get_i32(handle, SCORE_STORAGE_KEY, &stored_score);
    nvs_close(handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return 0;
    }
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "failed to read high score: %s", esp_err_to_name(err));
        return 0;
    }
    if (stored_score < 0) {
        return 0;
    }
    return stored_score;
}

static void save_maze_high_score_if_dirty(bool force)
{
    nvs_handle_t handle;
    esp_err_t err;

    if (!maze_high_score.dirty) {
        return;
    }
    if (!force && maze_high_score.value < last_persisted_maze_high_score + SCORE_PERSIST_STEP) {
        return;
    }

    err = nvs_open(SCORE_STORAGE_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "failed to open score storage for write: %s", esp_err_to_name(err));
        return;
    }

    err = nvs_set_i32(handle, SCORE_STORAGE_KEY, maze_high_score.value);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);

    if (err != ESP_OK) {
        ESP_LOGW(TAG, "failed to save high score: %s", esp_err_to_name(err));
        return;
    }

    last_persisted_maze_high_score = maze_high_score.value;
    maze_high_score.dirty = false;
    ESP_LOGI(TAG, "saved maze high score: %d", maze_high_score.value);
}
