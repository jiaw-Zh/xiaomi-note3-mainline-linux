#!/bin/busybox sh
# 探针 init（P2 版）：挂文件系统 → 建 USB 网络(RNDIS+ACM) → 从主机拉 Alpine → tmpfs 当根并 switch_root。
# 拉不到就留在串口 shell 里，不阻塞、不动设备。

/bin/busybox --install -s /bin 2>/dev/null
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc     proc     /proc
mount -t sysfs    sys      /sys
mount -t devtmpfs dev      /dev 2>/dev/null
mkdir -p /dev/pts && mount -t devpts devpts /dev/pts 2>/dev/null
mount -t configfs configfs /sys/kernel/config 2>/dev/null
mkdir -p /etc /tmp /var/lib/misc

log_msg() {
  echo "<6>PROBE: $1" > /dev/kmsg 2>/dev/null
  [ -n "$LOG" ] && echo "$1" >> "$LOG" 2>/dev/null
  ( echo "$1" > /dev/ttyGS0 2>/dev/null ) &
}

MARK="jason-p2 $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "<6>PROBE: $MARK init reached" > /dev/kmsg

{
  echo "== marker: $MARK"
  echo "== DT model:"; cat /proc/device-tree/model 2>/dev/null; echo
  echo "== mem:"; grep -E "MemTotal|MemAvailable" /proc/meminfo
} > /tmp/report.txt 2>&1

# ---------- USB gadget：RNDIS（网络）+ ACM（串口）----------
setup_gadget() {
  G=/sys/kernel/config/usb_gadget/g1
  mkdir -p "$G" 2>/dev/null; cd "$G" || return 1
  echo 0x1d6b > idVendor;  echo 0x0104 > idProduct
  echo 0x0100 > bcdDevice; echo 0x0200 > bcdUSB
  mkdir -p strings/0x409
  echo "jason"       > strings/0x409/serialnumber
  echo "mainline"    > strings/0x409/manufacturer
  echo "jason-p2"    > strings/0x409/product
  mkdir -p configs/c.1/strings/0x409
  echo "rndis+acm" > configs/c.1/strings/0x409/configuration

  mkdir -p functions/rndis.usb0 2>/dev/null
  echo "02:1a:11:00:00:01" > functions/rndis.usb0/dev_addr 2>/dev/null
  echo "02:1a:11:00:00:02" > functions/rndis.usb0/host_addr 2>/dev/null
  ln -sf functions/rndis.usb0 configs/c.1/ 2>/dev/null

  mkdir -p functions/acm.usb0 2>/dev/null
  ln -sf functions/acm.usb0 configs/c.1/ 2>/dev/null

  # USB 大容量存储：把 /root/boot-new.img 暴露成 U 盘，主机可直接往设备里写镜像
  dd if=/dev/zero of=/root/boot-new.img bs=1M count=16 2>/dev/null
  if mkdir -p functions/mass_storage.0 2>/dev/null \
     && echo /root/boot-new.img > functions/mass_storage.0/lun.0/file 2>/dev/null \
     && ln -sf functions/mass_storage.0 configs/c.1/ 2>/dev/null; then
    echo "msc: enabled" >> /tmp/report.txt
  else
    echo "msc: setup failed, continue without it" >> /tmp/report.txt
  fi

  UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
  echo "UDC=$UDC" >> /tmp/report.txt
  if [ -n "$UDC" ] && ! echo "$UDC" > UDC 2>/dev/null; then
    # 绑定失败：摘掉 MSC 再绑一次，保证 ACM 串口一定要起来
    rmdir configs/c.1/mass_storage.0 2>/dev/null
    echo "$UDC" > UDC 2>/dev/null
  fi
  for r in /sys/class/usb_role/*/role; do
    [ -w "$r" ] && echo peripheral > "$r" 2>/dev/null
  done
}
setup_gadget


# ---------- 网络 ----------
ifconfig usb0 192.168.42.1 netmask 255.255.255.0 up 2>/dev/null
cat > /etc/udhcpd.conf <<EOF
start 192.168.42.100
end   192.168.42.110
interface usb0
option subnet 255.255.255.0
option router 192.168.42.1
option dns 192.168.42.1
option lease 3600
EOF
touch /var/lib/misc/udhcpd.leases
udhcpd /etc/udhcpd.conf 2>/dev/null &

# ---------- 根文件系统：直接挂 p71 ----------
echo "<6>PROBE: mounting p71" > /dev/kmsg
LOG=""
mkdir -p /newroot
PART=""
i=0
while [ $i -lt 60 ]; do
  for d in /dev/mmcblk*p71; do [ -b "$d" ] && PART=$d; done
  [ -n "$PART" ] && break
  sleep 1; i=$((i+1))
done
log_msg "part=$PART"
log_msg "devs: $(ls /dev/mmcblk* 2>&1 | tr '\n' ' ')"
log_msg "parts tail: $(tail -4 /proc/partitions | tr '\n' ' ')"
if [ -n "$PART" ] && mount -t ext4 "$PART" /newroot 2>/tmp/m.err; then
  LOG=/newroot/bootlog.txt
  { echo "=== boot $(date -u +%H:%M:%S) ==="; echo "p71 mounted"; } > "$LOG"
  log_msg "=== ROOTLOG BEGIN ==="
  log_msg "p71 mounted; init=$(ls -l /newroot/sbin/init 2>&1)"
  if [ ! -x /newroot/sbin/init ] && [ -f /newroot/rootfs.tar.gz ]; then
    log_msg "extracting rootfs (Linux side) ..."
    echo "extract start" >> "$LOG"
    tar -xzf /newroot/rootfs.tar.gz -C /newroot 2>/tmp/e.log
    log_msg "tar rc=$? err=$(tail -2 /tmp/e.log 2>/dev/null | tr '\n' ' ')"
    echo "tar rc=$?" >> "$LOG"
  fi
  # 修 rootfs：applet 软链 + 用 initramfs 里的 inittab 模板整份覆盖（不用 sed，避免写坏文件）
  for a in getty start-stop-daemon su sh mount umount ls cat cp mv rm mkdir ln sleep reboot halt poweroff dmesg modprobe swapon swapoff hostname id; do
    if [ ! -e "/newroot/bin/$a" ] && [ ! -e "/newroot/sbin/$a" ]; then
      ln -sf /bin/busybox "/newroot/bin/$a" 2>/dev/null
    fi
  done
  if [ -f /inittab.new ]; then
    cp /inittab.new /newroot/etc/inittab 2>/dev/null && log_msg "inittab replaced from template"
    sed -i "s|/bin/tqftpserv -d$|/bin/tqftpserv -d &|" /newroot/etc/local.d/50-wifi.start 2>/dev/null || true
  fi
  sync
  # Fix /newroot/sbin/init for merged-usr / systemd:
  if [ -e /newroot/lib/systemd/systemd ]; then
    ln -sf ../lib/systemd/systemd /newroot/sbin/init
    # Also ensure serial-getty on ttyGS0 (COM5) for easy debug
    mkdir -p /newroot/etc/systemd/system/getty.target.wants
    ln -sf /lib/systemd/system/serial-getty@.service /newroot/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service 2>/dev/null || true
    # 彻底解除 qualcomm-init.sh 中的 systemctl 依赖死锁
    if [ -f /newroot/usr/local/bin/qualcomm-init.sh ]; then
      sed -i '/systemctl start tqftpserv/d' /newroot/usr/local/bin/qualcomm-init.sh
      sed -i '/systemctl start rmtfs/d' /newroot/usr/local/bin/qualcomm-init.sh
    fi
  fi

  if [ -x /newroot/sbin/init ] || [ -x /newroot/lib/systemd/systemd ]; then
    mkdir -p /newroot/proc /newroot/sys /newroot/dev /newroot/tmp /newroot/run
    mount -t proc proc /newroot/proc 2>/dev/null
    mount -t sysfs sys /newroot/sys 2>/dev/null
    mount -t devtmpfs dev /newroot/dev 2>/dev/null
    # wlroots 需要 /dev/shm：缺了会在分配 keymap 时失败并 SIGSEGV
    mkdir -p /newroot/dev/shm
    mount -t tmpfs -o mode=1777 tmpfs /newroot/dev/shm 2>/dev/null
    log_msg "switching root to p71 ..."
    echo "switching" >> "$LOG"
    exec switch_root /newroot /sbin/init
  else
    log_msg "NO /sbin/init on p71"
    echo "NO init" >> "$LOG"
    /bin/sh </dev/ttyGS0 >/dev/ttyGS0 2>&1 &
  fi
else
  log_msg "p71 mount FAILED: $(cat /tmp/m.err 2>/dev/null | tr '\n' ' ')"
fi

# ---------- 兜底：看门狗时长从 /watchdog-secs 读，默认 180 秒 ----------
WD=$(cat /watchdog-secs 2>/dev/null || echo 180)
echo "<6>PROBE: watchdog=${WD}s" > /dev/kmsg
( sleep "$WD"; echo "<6>PROBE: watchdog fired (${WD}s), rebooting" > /dev/kmsg; sync; echo b > /proc/sysrq-trigger ) &
while true; do sleep 30; done
