#!/bin/sh
# Xiaomi Note 3 (jason) / SDM660 - Extract OEM factory MAC from persist partition
# Safely binds physical WiFi and Bluetooth MACs without hardcoding personal data.
#
# Solves the ath10k_snoc "invalid MAC address; choosing random" issue on mainline Linux.
# High Qualcomm persist partition stores raw 6-byte binary MAC addresses in:
#   - /mnt/persist/wlan_bt/wlan.mac (WiFi)
#   - /mnt/persist/wlan_bt/bt.mac   (Bluetooth)
#
# This script:
# 1. Mounts the persist partition
# 2. Extracts both physical MAC addresses using POSIX od/awk
# 3. Configures systemd.link and NetworkManager policies
# 4. Spawns an asynchronous enforcer loop to catch wlan0 when remoteproc/ath10k loads

set -e

PERSIST_MNT="/mnt/persist"
PERSIST_DEV="/dev/disk/by-partlabel/persist"

# Ensure by-partlabel symlinks exist
if [ ! -e "$PERSIST_DEV" ]; then
    mkdir -p /dev/disk/by-partlabel
    for d in /sys/class/block/mmcblk1p*; do
        [ -e "$d" ] || continue
        l=$(cat "$d/uevent" 2>/dev/null | grep PARTNAME | cut -d= -f2)
        [ -n "$l" ] && ln -sf "/dev/$(basename "$d")" "/dev/disk/by-partlabel/$l"
    done
fi

mkdir -p "$PERSIST_MNT"
if [ -e "$PERSIST_DEV" ]; then
    mount -o ro "$PERSIST_DEV" "$PERSIST_MNT" 2>/dev/null || true
fi

WLAN_MAC=""
BT_MAC=""

if [ -f "$PERSIST_MNT/wlan_bt/wlan.mac" ]; then
    WLAN_MAC=$(od -An -tx1 -v "$PERSIST_MNT/wlan_bt/wlan.mac" 2>/dev/null | awk 'NF>=6 {printf "%s:%s:%s:%s:%s:%s", $1,$2,$3,$4,$5,$6}' | tr -d '\r\n ')
    echo "Found OEM Factory WiFi MAC: $WLAN_MAC"
fi

if [ -f "$PERSIST_MNT/wlan_bt/bt.mac" ]; then
    BT_MAC=$(od -An -tx1 -v "$PERSIST_MNT/wlan_bt/bt.mac" 2>/dev/null | awk 'NF>=6 {printf "%s:%s:%s:%s:%s:%s", $1,$2,$3,$4,$5,$6}' | tr -d '\r\n ')
    echo "Found OEM Factory BT MAC:   $BT_MAC"
fi

if [ -z "$WLAN_MAC" ]; then
    echo "Warning: Could not extract WiFi MAC from persist partition."
    exit 0
fi

# 1. Configure systemd-networkd / udev link rule
mkdir -p /etc/systemd/network
cat << EOF > /etc/systemd/network/10-wlan0.link
[Match]
OriginalName=wlan0

[Link]
MACAddress=$WLAN_MAC
EOF

# 2. Configure NetworkManager to disable MAC randomization and enforce physical MAC
mkdir -p /etc/NetworkManager/conf.d
cat << EOF > /etc/NetworkManager/conf.d/00-wifi-stability.conf
[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.cloned-mac-address=$WLAN_MAC
ethernet.cloned-mac-address=preserve
wifi.powersave=2
EOF

for f in /etc/NetworkManager/system-connections/*.nmconnection; do
    [ -f "$f" ] || continue
    if grep -q "^cloned-mac-address=" "$f"; then
        sed -i "s/^cloned-mac-address=.*/cloned-mac-address=$WLAN_MAC/" "$f"
    else
        sed -i "/^\[wifi\]/a cloned-mac-address=$WLAN_MAC" "$f"
    fi
done

# 3. Apply immediately if wlan0 interface is already up
if [ -d /sys/class/net/wlan0 ]; then
    cur_mac=$(cat /sys/class/net/wlan0/address 2>/dev/null || echo "")
    if [ "$cur_mac" != "$WLAN_MAC" ]; then
        echo "Updating current wlan0 MAC ($cur_mac -> $WLAN_MAC)..."
        ip link set dev wlan0 down 2>/dev/null || true
        ip link set dev wlan0 address "$WLAN_MAC" 2>/dev/null || true
        ip link set dev wlan0 up 2>/dev/null || true
        systemctl reload NetworkManager 2>/dev/null || true
    fi
fi

# 4. Asynchronous daemon: catch wlan0 when remoteproc/ath10k finishes delayed initialization (~20s)
(
    for i in $(seq 1 60); do
        if [ -d /sys/class/net/wlan0 ]; then
            cur=$(cat /sys/class/net/wlan0/address 2>/dev/null || echo "")
            if [ "$cur" != "$WLAN_MAC" ]; then
                ip link set dev wlan0 down 2>/dev/null || true
                ip link set dev wlan0 address "$WLAN_MAC" 2>/dev/null || true
                ip link set dev wlan0 up 2>/dev/null || true
                logger -t qualcomm-init "Enforced factory WiFi MAC from persist: $WLAN_MAC (was $cur)"
            fi
            break
        fi
        sleep 1
    done
) &

echo "OEM Factory MAC enforcement configured successfully."
