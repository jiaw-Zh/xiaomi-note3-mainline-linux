#!/bin/bash
set -e

echo "============================================================"
echo " [Step 1] Building Debian 12 (Bookworm) aarch64 Rootfs for Jason"
echo "============================================================"

# Ensure binfmt registration for qemu-aarch64
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  cat /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
fi

ROOTFS="/root/jason-build/debian12-rootfs"
ARCH="arm64"
DEBIAN_MIRROR="http://mirrors.aliyun.com/debian/"

# 1. Clean previous build
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS/var/cache/apt/archives"

# Restore package cache if available
if [ -d /root/jason-build/debcache ]; then
  cp /root/jason-build/debcache/*.deb "$ROOTFS/var/cache/apt/archives/" 2>/dev/null || true
fi

# 2. Run debootstrap
echo ">>> Running debootstrap (arm64, bookworm)..."
debootstrap --arch="$ARCH" \
  --components=main,contrib,non-free,non-free-firmware \
  --include=systemd,systemd-sysv,libpam-systemd,udev,dbus,network-manager,openssh-server,sudo,curl,ca-certificates,chrony,locales,tzdata,iproute2,procps,kmod,pciutils,usbutils,parted,e2fsprogs,iptables,nftables,nano,wget,zstd,wpasupplicant \
  bookworm "$ROOTFS" "$DEBIAN_MIRROR"

# 3. Setup QEMU user emulation inside chroot
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
mkdir -p "$ROOTFS/usr/libexec/qemu-binfmt"
ln -sf /usr/bin/qemu-aarch64-static "$ROOTFS/usr/libexec/qemu-binfmt/aarch64-binfmt-P"

# 4. Configure APT sources
cat << 'EOF' > "$ROOTFS/etc/apt/sources.list"
deb http://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF

# 5. Hostname & Hosts
echo "jason-debian" > "$ROOTFS/etc/hostname"
cat << 'EOF' > "$ROOTFS/etc/hosts"
127.0.0.1   localhost
127.0.1.1   jason-debian
::1         localhost ip6-localhost ip6-loopback
EOF

# 6. DNS fallback
cat << 'EOF' > "$ROOTFS/etc/resolv.conf"
nameserver 223.5.5.5
nameserver 119.29.29.29
EOF

# 7. Filesystem Table (/etc/fstab)
cat << 'EOF' > "$ROOTFS/etc/fstab"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/mmcblk1p71 /               ext4    defaults,noatime,errors=remount-ro 0 1
/dev/mmcblk1p66 /mnt/modem      ext4    ro,defaults     0       2
/dev/mmcblk1p61 /mnt/persist    ext4    defaults        0       2
EOF
mkdir -p "$ROOTFS/mnt/modem" "$ROOTFS/mnt/persist"

# 8. User Accounts & SSH Config
echo ">>> Configuring root password and SSH..."
chroot "$ROOTFS" /bin/bash -c "echo 'root:root' | chpasswd"

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config"
sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config"

mkdir -p "$ROOTFS/root/.ssh"
chmod 700 "$ROOTFS/root/.ssh"
cat << 'EOF' > "$ROOTFS/root/.ssh/authorized_keys"
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ07+9VRfM66RlYmA9VSGq+qEVN2Vsm6cI/e2zZyxTcP 19050@jiawang
EOF
chmod 600 "$ROOTFS/root/.ssh/authorized_keys"

# 9. Logind configuration (Crucial: power key must NOT shut down or suspend)
cat << 'EOF' >> "$ROOTFS/etc/systemd/logind.conf"

[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
EOF

# 10. WiFi Connection via NetworkManager
echo ">>> Pre-configuring NetworkManager WiFi connections..."
mkdir -p "$ROOTFS/etc/NetworkManager/system-connections"
chmod 700 "$ROOTFS/etc/NetworkManager/system-connections"

cat << 'EOF' > "$ROOTFS/etc/NetworkManager/system-connections/TPLINNNNK-5G.nmconnection"
[connection]
id=TPLINNNNK-5G
uuid=ba77a22d-66af-4889-b298-181c5a0cf4a8
type=wifi
interface-name=wlan0

[wifi]
cloned-mac-address=18:f0:e4:15:6a:7a
mode=infrastructure
ssid=TPLINNNNK-5G

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=zjw19970221

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto
EOF
chmod 600 "$ROOTFS/etc/NetworkManager/system-connections/TPLINNNNK-5G.nmconnection"

# 11. Copy Kernel Modules
echo ">>> Installing Kernel Modules..."
mkdir -p "$ROOTFS/lib/modules"
cp -a /root/jason-build/modules_out/lib/modules/* "$ROOTFS/lib/modules/"
chroot "$ROOTFS" depmod -a 7.0.14-sdm660

# 12. Copy Qualcomm Firmware from Phone (Byte-exact & verified)
echo ">>> Streaming firmware from phone..."
mkdir -p "$ROOTFS/lib/firmware"
ssh -i /root/.ssh/id_jason -o StrictHostKeyChecking=no root@192.168.6.125 "tar -cf - -C /lib/firmware ." | tar -xf - -C "$ROOTFS/lib/firmware/"

# 13. Battery Guardian Service
echo ">>> Setting up Battery Guardian Service..."
cat << 'EOF' > "$ROOTFS/usr/local/bin/battery-guardian.sh"
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
EOF
chmod +x "$ROOTFS/usr/local/bin/battery-guardian.sh"

cat << 'EOF' > "$ROOTFS/etc/systemd/system/battery-guardian.service"
[Unit]
Description=Xiaomi Note 3 Battery Guardian (PM660 Hardware Bypass & 45-55% SoC Lock)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/battery-guardian.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 14. Configure Chrony NTP
echo ">>> Configuring Chrony NTP..."
sed -i 's/^pool /#pool /' "$ROOTFS/etc/chrony/chrony.conf"
echo "server ntp.aliyun.com iburst" >> "$ROOTFS/etc/chrony/chrony.conf"

# 15. Timezone & Locales
echo ">>> Setting timezone and locales..."
chroot "$ROOTFS" /bin/bash -c "ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo 'Asia/Shanghai' > /etc/timezone"
chroot "$ROOTFS" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen"

# 16. Enable Essential Services
echo ">>> Enabling systemd services..."
chroot "$ROOTFS" systemctl enable NetworkManager
chroot "$ROOTFS" systemctl enable ssh
chroot "$ROOTFS" systemctl enable chrony
chroot "$ROOTFS" systemctl enable battery-guardian
chroot "$ROOTFS" systemctl enable serial-getty@ttyMSM0.service || true

# 17. Clean up QEMU binary
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
rm -f "$ROOTFS/usr/libexec/qemu-binfmt/aarch64-binfmt-P"

# 18. Pack Tarball
echo ">>> Packaging debian12-jason-rootfs.tar.gz..."
cd "$ROOTFS"
tar -czf /root/jason-build/debian12-jason-rootfs.tar.gz .
echo "============================================================"
echo " DEBIAN 12 AARCH64 ROOTFS READY: /root/jason-build/debian12-jason-rootfs.tar.gz"
echo "============================================================"
