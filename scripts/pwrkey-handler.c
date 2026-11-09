#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <time.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define POWER_DEV "/dev/input/event1"
#define VOLDOWN_DEV "/dev/input/event2"
#define BL_POWER_FILE "/sys/class/backlight/backlight/bl_power"
#define BRIGHTNESS_FILE "/sys/class/backlight/backlight/brightness"
#define DPMS_FILE "/sys/class/drm/card0-DSI-1/dpms"

static volatile int running = 1;
static int pwr_fd = -1;
static int voldown_fd = -1;
static int last_brightness = 2400; // ~60% default

static void sig_handler(int sig) {
    (void)sig;
    running = 0;
}

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

static void set_bl_power(int p) {
    FILE *f = fopen(BL_POWER_FILE, "w");
    if (f) {
        fprintf(f, "%d\n", p);
        fclose(f);
    }
}

static int is_screen_on(void) {
    // Check bl_power first (0 = UNBLANK / ON, 4 = POWERDOWN / OFF)
    FILE *f = fopen(BL_POWER_FILE, "r");
    if (f) {
        int p = 0;
        if (fscanf(f, "%d", &p) == 1) {
            fclose(f);
            if (p == 4) return 0; // Truly OFF
        } else {
            fclose(f);
        }
    }

    // Fallback: check DRM connector DPMS
    f = fopen(DPMS_FILE, "r");
    if (f) {
        char buf[16] = {0};
        if (fscanf(f, "%15s", buf) == 1) {
            fclose(f);
            if (strcmp(buf, "Off") == 0) return 0;
        } else {
            fclose(f);
        }
    }

    return 1; // ON
}

static void screen_off(void) {
    // 1. Preserve current brightness if valid
    int cur_b = get_brightness();
    if (cur_b > 200) {
        last_brightness = cur_b;
    }

    // 2. Instruct Mutter / Phoc compositor to enter DPMS Off (Mode 3)
    system("su - jason -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i 3' >/dev/null 2>&1");

    // 3. Hardware cutoff: force bl_power = 4 (FB_BLANK_POWERDOWN)
    set_bl_power(4);

    fprintf(stderr, "[pwrkey] Screen turned OFF (DPMS=3, bl_power=4, WLED=00)\n");
}

static void screen_on(void) {
    // 1. Instruct Mutter / Phoc compositor to enter DPMS On (Mode 0)
    system("su - jason -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i 0' >/dev/null 2>&1");

    // 2. Hardware enable: bl_power = 0 (FB_BLANK_UNBLANK)
    set_bl_power(0);

    // 3. Restore preserved brightness
    if (last_brightness < 200) last_brightness = 2400;
    set_brightness(last_brightness);

    // 4. Ensure desktop / user session is unlocked
    system("loginctl unlock-sessions >/dev/null 2>&1");

    fprintf(stderr, "[pwrkey] Screen turned ON (DPMS=0, bl_power=0, brightness=%d)\n", last_brightness);
}

int main(void) {
    fprintf(stderr, "[pwrkey] Starting Power & Volume-Down Toggle Daemon for Xiaomi Note 3...\n");

    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);

    // 1. Open Volume Down (Resin) - Primary Power Button Substitute
    voldown_fd = open(VOLDOWN_DEV, O_RDONLY | O_NONBLOCK);
    if (voldown_fd < 0) {
        perror("[pwrkey] Failed to open " VOLDOWN_DEV);
    } else {
        // Exclusively grab Volume Down so system doesn't lower audio volume
        if (ioctl(voldown_fd, EVIOCGRAB, 1) < 0) {
            perror("[pwrkey] Warning: Failed to grab " VOLDOWN_DEV " exclusively");
        } else {
            fprintf(stderr, "[pwrkey] Successfully grabbed Volume-Down (%s) as Power Key.\n", VOLDOWN_DEV);
        }
    }

    // 2. Open Power Key - Secondary fallback (if ever fixed or pressed)
    pwr_fd = open(POWER_DEV, O_RDONLY | O_NONBLOCK);
    if (pwr_fd >= 0) {
        if (ioctl(pwr_fd, EVIOCGRAB, 1) < 0) {
            perror("[pwrkey] Warning: Failed to grab " POWER_DEV " exclusively");
        } else {
            fprintf(stderr, "[pwrkey] Successfully grabbed Power Key (%s).\n", POWER_DEV);
        }
    }

    if (voldown_fd < 0 && pwr_fd < 0) {
        fprintf(stderr, "[pwrkey] Error: No valid power or volume key found. Exiting.\n");
        return 1;
    }

    struct pollfd pfds[2];
    int nr_fds = 0;

    if (voldown_fd >= 0) {
        pfds[nr_fds].fd = voldown_fd;
        pfds[nr_fds].events = POLLIN;
        nr_fds++;
    }
    if (pwr_fd >= 0) {
        pfds[nr_fds].fd = pwr_fd;
        pfds[nr_fds].events = POLLIN;
        nr_fds++;
    }

    long last_press_ms = 0;

    fprintf(stderr, "[pwrkey] Daemon active. Initial screen state: %s\n", is_screen_on() ? "ON" : "OFF");

    while (running) {
        int ret = poll(pfds, nr_fds, 500);
        if (ret > 0) {
            for (int i = 0; i < nr_fds; i++) {
                if (pfds[i].revents & POLLIN) {
                    struct input_event ev;
                    while (read(pfds[i].fd, &ev, sizeof(ev)) > 0) {
                        // Trigger on key release (value == 0) for Volume Down or Power
                        if (ev.type == EV_KEY && ev.value == 0 &&
                            (ev.code == KEY_VOLUMEDOWN || ev.code == KEY_POWER)) {

                            struct timespec ts;
                            clock_gettime(CLOCK_MONOTONIC, &ts);
                            long now_ms = ts.tv_sec * 1000 + ts.tv_nsec / 1000000;

                            // Debounce: 300 ms
                            if (now_ms - last_press_ms < 300) {
                                continue;
                            }
                            last_press_ms = now_ms;

                            fprintf(stderr, "[pwrkey] Key pressed (code=%d). Current state: %s\n",
                                    ev.code, is_screen_on() ? "ON" : "OFF");

                            if (is_screen_on()) {
                                screen_off();
                            } else {
                                screen_on();
                            }
                        }
                    }
                }
            }
        }
    }

    fprintf(stderr, "[pwrkey] Shutting down daemon...\n");
    if (voldown_fd >= 0) {
        ioctl(voldown_fd, EVIOCGRAB, 0);
        close(voldown_fd);
    }
    if (pwr_fd >= 0) {
        ioctl(pwr_fd, EVIOCGRAB, 0);
        close(pwr_fd);
    }

    return 0;
}
