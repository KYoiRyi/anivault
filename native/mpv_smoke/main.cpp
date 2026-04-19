#include <iostream>
#include <mpv/client.h>

static inline void check_error(int status) {
    if (status < 0) {
        std::cerr << "mpv API error: " << mpv_error_string(status) << std::endl;
        exit(1);
    }
}

int main() {
    mpv_handle *ctx = mpv_create();
    if (!ctx) {
        std::cerr << "failed creating mpv context" << std::endl;
        return 1;
    }

    check_error(mpv_set_option_string(ctx, "vo", "gpu-next"));
    check_error(mpv_set_option_string(ctx, "hwdec", "auto"));
    check_error(mpv_set_option_string(ctx, "terminal", "yes"));
    check_error(mpv_set_option_string(ctx, "msg-level", "all=v"));
    check_error(mpv_set_option_string(ctx, "glsl-shader", "ArtCNN_C4F32.glsl"));

    check_error(mpv_initialize(ctx));

    const char *cmd[] = {
        "loadfile",
        "[VCB-Studio] Haikyuu!! 2nd Season [01][Ma10p_1080p][x265_flac].mkv",
        nullptr,
    };
    check_error(mpv_command(ctx, cmd));

    std::cout << "Loading video with mpv. Close the player window to exit." << std::endl;

    while (true) {
        mpv_event *event = mpv_wait_event(ctx, -1);
        if (event->event_id == MPV_EVENT_SHUTDOWN) {
            break;
        }
    }

    mpv_terminate_destroy(ctx);
    return 0;
}
