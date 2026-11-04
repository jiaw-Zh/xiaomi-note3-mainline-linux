#!/bin/sh
# Xiaomi Note 3 (jason) - Extract OEM factory MAC from persist partition
# Safely binds physical WiFi and Bluetooth MACs without hardcoding personal data

PERSIST_MNT="/mnt/persist"
PERSIST_DEV="/dev/disk/by-partlabel/persist"

mkdir -p "$PERSIST_MNT"
if [ -e "$PERSIST_DEV" ]; then
    mount -o ro "$PERSIST_DEV" "$PERSIST_MNT" 2>/dev/null
    
    # WiFi MAC: /mnt/persist/wlan_bt/wlan.mac
    if [ -f "$PERSIST_MNT/wlan_bt/wlan.mac" ]; then
        wmac=$(head -n 1 "$PERSIST_MNT/wlan_bt/wlan.mac" | tr -d '\r\n ')
        echo "Found factory WiFi MAC: $wmac"
        # Can be set via ip link set wlan0 address "$wmac"
    fi
    
    # Bluetooth MAC: /mnt/persist/wlan_bt/bt.mac
    if [ -f "$PERSIST_MNT/wlan_bt/bt.mac" ]; then
        bmac=$(head -n 1 "$PERSIST_MNT/wlan_bt/bt.mac" | tr -d '\r\n ')
        echo "Found factory Bluetooth MAC: $bmac"
    fi
    
    umount "$PERSIST_MNT" 2>/dev/null
fi
