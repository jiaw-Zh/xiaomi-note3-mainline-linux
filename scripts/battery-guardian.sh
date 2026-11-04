#!/bin/sh
# Battery Guardian Daemon for Xiaomi Note 3 (jason)
# Target: 45% - 55% State of Charge, Hardware Bypass Mode, Thermal Safety

CHG_EN="/sys/class/power_supply/pm660-charger/charging_enabled"
BATT_CAP="/sys/class/power_supply/qcom-battery/capacity"
BATT_VOLT="/sys/class/power_supply/qcom-battery/voltage_now"
BATT_TEMP="/sys/class/power_supply/qcom-battery/temp"

MAX_CAP=55
MIN_CAP=45
MAX_VOLT=3950000
MAX_TEMP=450 # 45.0 C

echo "[$(date)] Battery Guardian started. Max=$MAX_CAP%, Min=$MIN_CAP%, MaxVolt=${MAX_VOLT}uV"

while true; do
    if [ -f "$CHG_EN" ] && [ -f "$BATT_CAP" ]; then
        cap=$(cat "$BATT_CAP" 2>/dev/null || echo 50)
        volt=$(cat "$BATT_VOLT" 2>/dev/null || echo 3850000)
        temp=$(cat "$BATT_TEMP" 2>/dev/null || echo 300)
        en=$(cat "$CHG_EN" 2>/dev/null || echo 1)

        # 1. Thermal Emergency Stop
        if [ "$temp" -ge "$MAX_TEMP" ]; then
            if [ "$en" -eq 1 ]; then
                echo 0 > "$CHG_EN"
                logger -t battery-guardian "CRITICAL: Battery temp ${temp}dC >= ${MAX_TEMP}dC! Charging cut off."
            fi
        # 2. Reached upper threshold or high voltage: STOP charging (Hardware Bypass)
        elif [ "$cap" -ge "$MAX_CAP" ] || [ "$volt" -ge "$MAX_VOLT" ]; then
            if [ "$en" -eq 1 ]; then
                echo 0 > "$CHG_EN"
                logger -t battery-guardian "Threshold reached (Cap: ${cap}%, Volt: ${volt}uV). Hardware charging STOPPED (Bypass active)."
            fi
        # 3. Dropped below lower threshold: RESUME charging
        elif [ "$cap" -le "$MIN_CAP" ]; then
            if [ "$en" -eq 0 ]; then
                echo 1 > "$CHG_EN"
                logger -t battery-guardian "Cap dropped to ${cap}% <= ${MIN_CAP}%. Hardware charging RESUMED."
            fi
        fi
    fi
    sleep 30
done
