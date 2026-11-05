#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <time.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define POWER_DEV "/dev/input/event1"
#define VOLDOWN_DEV "/dev/input/event2"
#define VOLUP_DEV "/dev/input/event3"
#define BRIGHTNESS_FILE "/sys/class/backlight/backlight/brightness"
#define TARGET_BRIGHTNESS 2000

static int screen_state = 1; // 1 = ON, 0 = OFF
static int voldown_fd = -1;
static int volup_fd = -1;

static int get_brightness(void) {
    FILE *f = fopen(BRIGHTNESS_FILE, "r");
    if (!f) return 0;
    int b = 0;
    if (fscanf(f, "%d", &b) != 1) b = 0;
    fclose(f);
    return b;
}

static void set_brightness(int b) {
    FILE *f = fopen(BRIGHTNESS_FILE, "w");
    if (f) {
        fprintf(f, "%d\n", b);
        fclose(f);
    }
}

static void grab_volume_keys(int grab) {
    if (voldown_fd >= 0) {
        int r = ioctl(voldown_fd, EVIOCGRAB, grab ? 1 : 0);
        if (grab) {
            struct input_event ev;
            while (read(voldown_fd, &ev, sizeof(ev)) > 0);
        }
        fprintf(stderr, "[pwrkey] grab voldown (%d) result: %d\n", grab, r);
    }
    if (volup_fd >= 0) {
        int r = ioctl(volup_fd, EVIOCGRAB, grab ? 1 : 0);
        if (grab) {
            struct input_event ev;
            while (read(volup_fd, &ev, sizeof(ev)) > 0);
        }
        fprintf(stderr, "[pwrkey] grab volup (%d) result: %d\n", grab, r);
    }
}

static void ensure_display_on(void) {
    // Safety net: ensure Mutter PowerSaveMode is 0 and session is unlocked
    system("runuser -u jason -- env HOME=/home/jason USER=jason XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 0>' >/dev/null 2>&1");
    system("loginctl unlock-sessions >/dev/null 2>&1");
}

static void screen_off(void) {
    screen_state = 0;
    set_brightness(0);
    grab_volume_keys(1);
    fprintf(stderr, "[pwrkey] Screen turned OFF (backlight=0, volkeys grabbed)\n");
}

static void screen_on(void) {
    screen_state = 1;
    grab_volume_keys(0);
    ensure_display_on();
    set_brightness(TARGET_BRIGHTNESS);
    fprintf(stderr, "[pwrkey] Screen turned ON (backlight=%d, volkeys released)\n", TARGET_BRIGHTNESS);
}

int main(void) {
    fprintf(stderr, "[pwrkey] Initializing robust power key & backlight daemon...\n");

    int pwr_fd = open(POWER_DEV, O_RDONLY | O_NONBLOCK);
    if (pwr_fd < 0) {
        perror("Failed to open " POWER_DEV);
        return 1;
    }

    // Grab power key exclusively so GNOME/phoc/logind don't interfere
    if (ioctl(pwr_fd, EVIOCGRAB, 1) < 0) {
        perror("Warning: failed to grab power key exclusively");
    } else {
        fprintf(stderr, "[pwrkey] Successfully grabbed power key exclusively.\n");
    }

    voldown_fd = open(VOLDOWN_DEV, O_RDONLY | O_NONBLOCK);
    volup_fd = open(VOLUP_DEV, O_RDONLY | O_NONBLOCK);

    struct pollfd pfd;
    pfd.fd = pwr_fd;
    pfd.events = POLLIN;

    long last_press_ms = 0;

    // Synchronize initial state: ensure display pipeline is active and unlocked
    ensure_display_on();
    int b = get_brightness();
    if (b > 100) {
        screen_state = 1;
        grab_volume_keys(0);
        fprintf(stderr, "[pwrkey] Initial state: ON (brightness=%d)\n", b);
    } else {
        screen_state = 0;
        set_brightness(0);
        grab_volume_keys(1);
        fprintf(stderr, "[pwrkey] Initial state: OFF (brightness=0)\n", b);
    }

    while (1) {
        int ret = poll(&pfd, 1, 100);
        if (ret > 0 && (pfd.revents & POLLIN)) {
            struct input_event ev;
            while (read(pwr_fd, &ev, sizeof(ev)) > 0) {
                if (ev.type == EV_KEY && ev.code == KEY_POWER && ev.value == 0) { // Key release
                    struct timespec ts;
                    clock_gettime(CLOCK_MONOTONIC, &ts);
                    long now_ms = ts.tv_sec * 1000 + ts.tv_nsec / 1000000;

                    // Debounce: 250ms
                    if (now_ms - last_press_ms < 250) {
                        continue;
                    }
                    last_press_ms = now_ms;

                    if (screen_state == 1) {
                        screen_off();
                    } else {
                        screen_on();
                    }
                }
            }
        } else {
            // Enforcement when screen is OFF
            if (screen_state == 0) {
                // Drain any accumulated volume key presses
                if (voldown_fd >= 0) {
                    struct input_event ev;
                    while (read(voldown_fd, &ev, sizeof(ev)) > 0);
                }
                if (volup_fd >= 0) {
                    struct input_event ev;
                    while (read(volup_fd, &ev, sizeof(ev)) > 0);
                }
                // Ensure backlight stays completely 0
                int cur_b = get_brightness();
                if (cur_b > 0) {
                    set_brightness(0);
                }
            }
        }
    }

    grab_volume_keys(0);
    ioctl(pwr_fd, EVIOCGRAB, 0);
    if (voldown_fd >= 0) close(voldown_fd);
    if (volup_fd >= 0) close(volup_fd);
    close(pwr_fd);
    return 0;
}
