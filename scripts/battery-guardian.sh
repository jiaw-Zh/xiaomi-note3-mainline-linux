#!/bin/sh
# Battery Guardian Daemon for Xiaomi Note 3 (jason)
# Target: 45% - 55% State of Charge, Hardware Bypass Mode, Thermal Safety
# Hysteresis state machine to completely eliminate 30-second chattering/oscillation

CHG_EN="/sys/class/power_supply/pm660-charger/charging_enabled"
BATT_CAP="/sys/class/power_supply/qcom-battery/capacity"
BATT_VOLT="/sys/class/power_supply/qcom-battery/voltage_now"
BATT_TEMP="/sys/class/power_supply/qcom-battery/temp"

MAX_CAP=55
MIN_CAP=45
# Absolute hard ceiling to prevent overvoltage even if capacity gauge desyncs
HARD_MAX_VOLT=4150000 
MAX_TEMP=450 # 45.0 C

echo "[$(date)] Battery Guardian started. Target SoC: $MIN_CAP% - $MAX_CAP%, HardMaxVolt=${HARD_MAX_VOLT}uV"

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
        # 2. Hard Overvoltage Emergency Stop
        elif [ "$volt" -ge "$HARD_MAX_VOLT" ]; then
            if [ "$en" -eq 1 ]; then
                echo 0 > "$CHG_EN"
                logger -t battery-guardian "Hard overvoltage ${volt}uV >= ${HARD_MAX_VOLT}uV! Charging cut off."
            fi
        # 3. Upper Capacity Reached: STOP charging (Enter Hardware Bypass)
        elif [ "$cap" -ge "$MAX_CAP" ]; then
            if [ "$en" -eq 1 ]; then
                echo 0 > "$CHG_EN"
                logger -t battery-guardian "Target upper SoC reached (${cap}% >= ${MAX_CAP}%). Hardware Bypass ACTIVE."
            fi
        # 4. Lower Capacity Reached: RESUME charging (Exit Hardware Bypass)
        elif [ "$cap" -le "$MIN_CAP" ]; then
            if [ "$en" -eq 0 ]; then
                echo 1 > "$CHG_EN"
                logger -t battery-guardian "SoC dropped to ${cap}% <= ${MIN_CAP}%. Hardware charging RESUMED."
            fi
        fi
    fi
    sleep 30
done
