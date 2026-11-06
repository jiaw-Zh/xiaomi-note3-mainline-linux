# 开源分享：高通平台主线 Linux 纯脱机独立开机与 Initramfs 虚拟串口死锁根治指南

> **适用平台**：Qualcomm Snapdragon 全系列（SDM660 / SDM845 / SM8150 / SM8250 等所有高通平台）  
> **适用场景**：将 Android 手机刷为主线 Linux（Debian / postmarketOS / Arch ARM / Ubuntu），作为移动服务器、旁路由或随身 Linux 终端  
> **核心痛点**：**插着电脑时可以正常开机进系统；但插着普通充电头、充电宝或脱机开机时卡死黑屏，必须插一下电脑的 USB 才能进入系统**。

---

## 一、 诡异的故障现象与困惑

在为高通骁龙设备自制启动镜像（`boot.img`）和初始内存盘（`initramfs`）时，很多开发者为了方便早期调机，都会启用 USB Gadget 的虚拟串口（如 CDC-ACM，在手机端表现为 `/dev/ttyGS0`，在电脑端表现为 `COMx` 或 `/dev/ttyACM0`），并在 `initramfs` 的启动脚本中输出挂载进度：

```sh
echo "mounting root partition..." > /dev/ttyGS0
echo "switching root..." > /dev/ttyGS0
```

随后，大家都会遇到一个极其诡异的现象：
1. **连接电脑 USB 时**：开机一切顺畅，串口正常打印，秒进桌面或 shell；
2. **脱离电脑独立使用时**：
   - 使用原装充电头、快充头、充电宝直插电源开机；
   - 手机震动一下，屏幕亮起，然后就**永久卡在第一屏或黑屏**；
   - 即使等待十分钟也无法进入系统，无法联网，SSH 连不上；
3. **“接一下电脑瞬间复活”**：
   - 只要用数据线把手机往电脑的 USB 口上一插，手机瞬间继续往下跑，并在几秒钟内成功进入系统！

很多朋友会怀疑是高通电源管理（PMIC）、关机充电动画（Off-mode charging）、或者内核电压不足导致的，但**真正的致命根因出在 Linux TTY 驱动子系统的阻塞机制**上。

---

## 二、 底层死锁机理深入剖析

### 1. 物理引脚与 USB 枚举机制的差异
* **插电脑时**：电脑是标准的 **USB Host（主机）**。手机连上电脑后，电脑的 USB 控制器立即与手机的 DWC3 控制器完成握手并执行**USB 枚举**。随后，内核中的 USB Gadget Serial 驱动完成链路就绪配置。
* **插充电头/充电宝时**：普通的电源适配器仅连接了 `VBUS（5V）` 和 `GND` 引脚，**不存在任何 USB 主机控制器，根本不可能发起 USB 枚举**！

### 2. Linux TTY 驱动的阻塞（Blocking I/O）特性
在 Linux 的 TTY 架构下，虚拟串口 `/dev/ttyGS0` 是由内核 `drivers/usb/gadget/function/u_serial.c` 提供的。

当脚本以标准重定向方式写入时：
```sh
echo "part=$PART" > /dev/ttyGS0
```
BusyBox / Shell 会调用底层的 `open("/dev/ttyGS0", O_WRONLY)`。
在标准阻塞模式下，若驱动检测到**底层 USB 端点未连接到主机（Host Disconnected / Not Configured）**，或者缺少载波信号（Carrier），**`open()` 系统调用会直接进入休眠睡眠状态，等待 USB 主机上线！**

### 3. 为什么接一下电脑就能进系统？
当处于死锁状态的手机被插入电脑 USB 瞬间：
1. 电脑端瞬间触发 USB 总线复位并完成枚举；
2. 手机端 USB Gadget 状态机跃迁至 `CONFIGURED`；
3. 内核立即唤醒阻塞在 `open("/dev/ttyGS0")` 上的 BusyBox `sh` 进程；
4. 阻塞解除，脚本毫秒级向下执行 `switch_root /newroot /sbin/init`，系统这才“正常启动”。

---

## 三、 彻底根治方案：Initramfs 异步化与非阻塞设计

要让高通设备变成真正能够**脱机独立开机**的设备，必须在 `initramfs` 阶段彻底剔除任何对 `/dev/ttyGS0` 的同步阻塞式调用。

### 1. 封装安全的非阻塞日志函数 `log_msg`
在 `initramfs` 的核心引导脚本 `/init` 的最前端，定义统一的无阻塞日志函数：

```sh
log_msg() {
  # 1. 写入内核环形缓冲区（主线硬件串口 ttyMSM0 和 dmesg 均可查看，100% 绝对无阻塞）
  echo "<6>PROBE: $1" > /dev/kmsg 2>/dev/null

  # 2. 如果 rootfs 已挂载，同步追加到文件日志
  [ -n "$LOG" ] && echo "$1" >> "$LOG" 2>/dev/null

  # 3. 关键：将向虚拟串口 ttyGS0 的输出放入后台异步子进程！
  # 即使没插电脑、ttyGS0 挂起，后台子进程睡眠也绝对不影响前台主启动流程 1 毫秒！
  ( echo "$1" > /dev/ttyGS0 2>/dev/null ) &
}
```

### 2. 重构启动脚本主干路
将脚本中原有的所有直接重定向彻底替换：

```diff
- echo "part=$PART" > /dev/ttyGS0
- echo "devs: $(ls /dev/mmcblk* 2>&1 | tr '\n' ' ')" > /dev/ttyGS0
- echo "parts tail: $(tail -4 /proc/partitions | tr '\n' ' ')" > /dev/ttyGS0
+ log_msg "part=$PART"
+ log_msg "devs: $(ls /dev/mmcblk* 2>&1 | tr '\n' ' ')"
+ log_msg "parts tail: $(tail -4 /proc/partitions | tr '\n' ' ')"

  if [ -n "$PART" ] && mount -t ext4 "$PART" /newroot 2>/tmp/m.err; then
    LOG=/newroot/bootlog.txt
-   echo "=== ROOTLOG BEGIN ===" > /dev/ttyGS0
-   echo "p71 mounted; init=$(ls -l /newroot/sbin/init 2>&1)" > /dev/ttyGS0
+   log_msg "=== ROOTLOG BEGIN ==="
+   log_msg "p71 mounted; init=$(ls -l /newroot/sbin/init 2>&1)"
    ...
-   echo "switching root to p71 ..." > /dev/ttyGS0
+   log_msg "switching root to p71 ..."
    exec switch_root /newroot /sbin/init
  fi
```

---

## 四、 实测效果对比

改造完成后，重新打包生成 `initramfs` 并刷入 `boot` 分区实测：

* **直插充电头开机实测**：
  手机插在普通 5V/2A 充电头上按下电源键，从内核加载到挂载分区、再到完成 `switch_root`，内核环形缓冲区记录的耗时为：
  ```text
  [ 6.437231] PROBE: init reached
  [ 6.539319] PROBE: mounting p71
  [ 7.547204] PROBE: part=/dev/mmcblk1p71
  [ 7.611122] PROBE: === ROOTLOG BEGIN ===
  [ 7.716267] PROBE: switching root to p71 ...
  ```
  **从挂载到最终进入 Debian 操作系统，仅耗时 1.28 秒！** 全程无任何等待停顿，冷启动 20 秒直入 Phosh 桌面并自动连接 Wi-Fi。

* **连接电脑调试实测**：
  如果将手机插在电脑上开机，后台子进程会正常打开 `/dev/ttyGS0`，电脑端串口助手依然能完整收到所有调试日志，**两套使用场景完美兼顾**。

---

## 五、 示例参考代码

本仓库已将完整经过生产验证的 `initramfs` 引导脚本开源提供：
[`scripts/initramfs-init.sh`](../scripts/initramfs-init.sh)
建议所有在高通骁龙平台折腾 Linux 的机友参考该架构，彻底避免由于调试输出导致的脱机开机假死。
