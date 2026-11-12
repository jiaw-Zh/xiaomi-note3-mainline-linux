#!/bin/sh
# WiFi Guardian Daemon for Xiaomi Note 3 (jason)
# Detects WiFi disassociations / firmware MAC state deadlocks
# Recovers connection via clean radio power-cycle and prevents endless scan heating

IFACE="wlan0"
CHECK_INTERVAL=30
FAIL_THRESHOLD=3       # 3 * 30s = 90s of continuous disconnection
MAX_RESETS=3           # Max consecutive resets before long backoff
LONG_BACKOFF=180       # 3 minutes cooldown if AP is genuinely unreachable

fail_count=0
reset_count=0

logger -t wifi-guardian "WiFi Guardian started (interface: $IFACE, fail_threshold: ${FAIL_THRESHOLD}x${CHECK_INTERVAL}s)"

while true; do
    # 1. Check if interface exists in kernel
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        fail_count=$((fail_count + 1))
    else
        # 2. Get NetworkManager state for wlan0
        state=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)
        
        # 3. Check IP address
        has_ip=$(ip -4 addr show dev "$IFACE" 2>/dev/null | grep -c "inet ")

        if [ "$state" = "connected" ] && [ "$has_ip" -ge 1 ]; then
            # Link is healthy
            if [ "$fail_count" -gt 0 ] || [ "$reset_count" -gt 0 ]; then
                logger -t wifi-guardian "Wi-Fi link healthy ($IFACE connected, IP assigned). Counters cleared."
            fi
            fail_count=0
            reset_count=0
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # Link is degraded or disconnected
        fail_count=$((fail_count + 1))
        logger -t wifi-guardian "Wi-Fi not connected (state: '${state:-unknown}', has_ip: $has_ip, fail: $fail_count/$FAIL_THRESHOLD)"
    fi

    # 4. Handle recovery threshold
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
        if [ "$reset_count" -lt "$MAX_RESETS" ]; then
            reset_count=$((reset_count + 1))
            logger -t wifi-guardian "Triggering radio reset #$reset_count to clear WCN3990 state deadlock..."
            nmcli radio wifi off 2>/dev/null || true
            sleep 3
            nmcli radio wifi on 2>/dev/null || true
            fail_count=0
            # Give NetworkManager 25 seconds to authenticate and obtain DHCP
            sleep 25
            continue
        else
            # Excessive resets: Router is likely turned off or device is out of range.
            # Enter long backoff to stop active radio scanning and prevent thermal heating!
            logger -t wifi-guardian "Wi-Fi still offline after $MAX_RESETS resets. AP likely powered off/out of range. Entering ${LONG_BACKOFF}s cooling sleep..."
            nmcli radio wifi off 2>/dev/null || true
            sleep "$LONG_BACKOFF"
            logger -t wifi-guardian "Cooling backoff finished. Turning radio back on to test availability..."
            nmcli radio wifi on 2>/dev/null || true
            fail_count=0
            reset_count=1
            sleep 25
            continue
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
