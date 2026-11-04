#!/bin/sh
# Acpid Power Key Handler for Xiaomi Note 3 (jason)
# Toggle screen backlight without shutting down

BRIGHTNESS="/sys/class/backlight/backlight/brightness"

if [ -f "$BRIGHTNESS" ]; then
    cur=$(cat "$BRIGHTNESS" 2>/dev/null || echo 0)
    if [ "$cur" -gt 0 ]; then
        echo 0 > "$BRIGHTNESS"
        logger -t acpi-pwrkey "PowerKey pressed: Screen OFF"
    else
        echo 1023 > "$BRIGHTNESS"
        logger -t acpi-pwrkey "PowerKey pressed: Screen ON"
    fi
fi
