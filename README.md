# Xiaomi Mi Note 3 (jason) Mainline Linux Project
# 小米 Note 3（SDM660）主线 Linux 移植

[![Kernel](https://img.shields.io/badge/Linux-7.0.14-blue.svg)](https://kernel.org)
[![Platform](https://img.shields.io/badge/SoC-Qualcomm%20SDM660-orange.svg)]()
[![Distribution](https://img.shields.io/badge/RootFS-Debian%2012%20%2B%20Phosh-green.svg)]()
[![License](https://img.shields.io/badge/License-GPL%20v2-lightgrey.svg)](LICENSE)

本项目旨在将 **小米 Note 3（代号：`jason`，高通骁龙 SDM660，6GB+64GB）** 成功移植至现代化主线 Linux（Linux 7.0.14），并提供对高通骁龙 660 / 636 / 630 同架构机型（红米 Note 5、小米 6X、小米 Max 3 等）具有深度参考价值的通用内核补丁与排坑实践。

---

## 🌟 核心突破与技术亮点

1. **首发：攻破 SDM660 + WCN3990 WiFi/蓝牙 主线驱动两大历史死锁顽疾**
   - **根除扫网死锁（Patch 0002）**：彻底解决主线上 `ath10k_snoc` 驱动由于 0x82e 固件段冲突导致 Hexagon modem 崩溃死锁重启的问题；
   - **根除断连与换网固件崩溃（Patch 0003）**：深入分析 `mac80211` 调用时序，解决高通 WCN3990 芯片在 `_wlan_vdev_down` 时由于 AP peer 尚未完全注销引发的硬件级断言自毁（`Asserted in wlan_vdev.c:_w`），实现 2.4GHz / 5GHz 随时平滑切换、即开即用、持续实时扫网；
   - **出厂物理 MAC 自动固化**：自动提取并在冷启动时注入 persist 分区出厂物理 MAC，局域网 IP 稳定绑定。
2. **硬件级旁路直供（Hardware Bypass Mode）与四层防爆护盾**
   - 深入逆向高通 PM660 芯片寄存器，在主线内核中补齐 `CHARGING_ENABLE_CMD (0x42)` 硬件断充接口；
   - **外部 5V 正常供电主板，电池充放电流归零**，杜绝 9 年老旧电芯长期高压高温浮充鼓包；
   - 保持电池作为**断电 UPS 随时并联在线**，拔掉外部电线毫秒级无缝接管，绝不关机猝死；
   - 部署守护进程自动锁定在 45%~55%（约 3.85V）锂电黄金保存电压，支持 45℃ 紧急断充温控。
3. **攻破 Initramfs 虚拟串口阻塞，实现真正纯脱机独立冷启动**
   - 彻底查清高通设备在直插普通充电头/充电宝开机时因 USB CDC-ACM（`ttyGS0`）缺乏 Host 枚举导致的 TTY 同步阻塞死锁；
   - 提出异步化无阻塞引导架构，从分区挂载到 `switch_root` **仅耗时 1.28 秒**，彻底摆脱“必须插电脑才能进系统”的依赖。
4. **针对移动服务器与掌上终端的待机调优**
   - 改写系统底层按键事件，短按电源键实现物理一键息屏与唤醒；
   - 息屏后发热 LED 阵列电流彻底清零，CPU 处于微秒级节能待机（实测待机放电仅约 1.4%/小时），**SSH 与局域网服务 7×24 小时毫秒级在线秒响应**。
5. **原生 Debian 12 (bookworm) + Phosh 0.24 移动触控桌面闭环**
   - 采用 Wayland 合成器 `phoc`，1080×1920 原生竖屏 KMS 输出与 2x 缩放；
   - 完整打通 Freedreno Adreno 512 GPU 硬件加速与 Squeekboard 虚拟软键盘；
   - 预装系统设置（Settings / gnome-control-center）、文件管理（Nautilus）、浏览器（Web / Epiphany）与移动触控终端，冷启动 20 秒直入桌面。

---

## 📊 硬件功能支持状态表

| 硬件子系统 | 驱动栈 | 状态 | 详细说明 |
|---|---|---|---|
| **CPU 架构** | 8 核 Kryo 260 | 🟢 正常 | 4×A73 2.2GHz + 4×A53 1.8GHz 调度正常 |
| **GPU 加速** | Freedreno (Adreno 512) | 🟢 正常 | Mesa 开源驱动硬件加速渲染，Wayland 满帧运行 |
| **显示面板** | DPU + JDI 1080P FHD | 🟢 正常 | 1080×1920@60Hz 原生 KMS 驱动输出 |
| **多点触摸** | Synaptics S3330 (rmi4) | 🟢 正常 | 多点触控、压力感应、虚拟按键全通 |
| **无线网络** | WCN3990 (ath10k) | 🟢 正常 | 打入 0002 + 0003 补丁，5G/2.4G 随时平滑切换，扫网持续可用 |
| **蓝牙通信** | WCN3990 (hci_qca) | 🟢 正常 | 真实出厂物理 MAC 固化，Phosh 瓷贴与设备秒级扫描 |
| **电源与充电** | PM660 + qcom-battery | 🟢 正常 | 硬件旁路断充 + 45%~55% 电量锁定 + 备用 UPS |
| **脱机开机** | Initramfs (无阻塞) | 🟢 正常 | 解除 ttyGS0 阻塞，普通充电器/充电宝 20 秒自主进系统 |
| **物理按键** | PM8941 PON | 🟢 正常 | 音量加减可用，电源键支持物理亮屏/息屏秒级响应 |
| **网络时钟** | NTP 授时服务 | 🟢 正常 | 自动校时，解决 1970 年导致的 TLS 证书报错 |
| **音频外放** | PM660L / WSA8815 | 🚧 适配中 | 耳放走 INT0，机身外放扬声器走 INT4 + WSA8815 待收尾 |

---

## 📁 仓库目录结构

```text
├── dts/
│   └── sdm660-xiaomi-jason.dts                # 完整板级设备树（显示/触控/GPU/供电/WiFi/蓝牙）
├── patches/
│   ├── 0001-power-supply-pm660-hardware-bypass.patch       # PM660 芯片硬件旁路直供与断充补丁
│   ├── 0002-ath10k-wcn3990-fix-0x82e-crash.patch          # 根治 WCN3990 0x82e 扫网固件死锁补丁
│   └── 0003-ath10k-wcn3990-fix-disassoc-firmware-assert.patch # 根治断连与热点切换固件断言崩溃补丁
├── scripts/
│   ├── initramfs-init.sh                      # 异步化无阻塞 Initramfs 核心引导脚本
│   ├── battery-guardian.sh                    # 45%~55% 黄金电量保护守护进程
│   ├── pwrkey-handler.c                       # 物理电源键/音量键内核级独占拦截与背光秒开闭守护源码
│   ├── pwrkey-handler.service                 # pwrkey-handler systemd 开机自启服务
│   ├── gnome-no-blank.desktop                 # GNOME Session 抑制器（防止超时锁屏与DPMS竞态）
│   ├── pam-phosh                              # Phosh 免密登录 PAM 规则
│   ├── 30-mkbootimg.py                        # ABL 引导镜像打包工具
│   ├── repack-boot.py                         # 通用一键打包 boot.img 脚本
│   └── setup-mac-from-persist.sh              # 自动提取出厂真实物理 MAC 注入脚本
└── docs/
    ├── 开源分享-高通WCN3990断连与热点切换固件崩溃修复.md  # WCN3990 架构级重构与断言根治复盘
    ├── 开源分享-高通主线Linux纯脱机独立开机与Initramfs去死锁.md # TTY 阻塞与脱机独立开机机理解析
    ├── 开源分享-SDM660-WCN3990主线WiFi驱动突破.md         # 0x82e 扫网死锁技术分析
    ├── 电源保护与服务器待机设计规范.md                   # 芯片级寄存器逆向与四层防护实现
    └── 状态表.md                                     # 完整技术状态跟踪表
```

---

## 🛠️ 构建与刷写指南

### 1. 内核编译
在 Linux / WSL 环境下准备交叉编译工具链（LLVM/Clang）：
```bash
# 进入 Linux 7.0.14-sdm660 源码树
cd linux-7.0.14-sdm660

# 应用三项核心补丁
patch -p1 < /path/to/patches/0001-power-supply-pm660-hardware-bypass.patch
patch -p1 < /path/to/patches/0002-ath10k-wcn3990-fix-0x82e-crash.patch
patch -p1 < /path/to/patches/0003-ath10k-wcn3990-fix-disassoc-firmware-assert.patch

# 复制设备树
cp /path/to/dts/sdm660-xiaomi-jason.dts arch/arm64/boot/dts/qcom/

# 编译内核与设备树
make ARCH=arm64 LLVM=1 Image.gz dtbs -j$(nproc)
```

### 2. 打包 boot 引导镜像
```bash
python scripts/repack-boot.py \
  arch/arm64/boot/Image.gz \
  arch/arm64/boot/dts/qcom/sdm660-xiaomi-jason.dtb \
  initramfs.cpio.gz \
  boot-linux-jason.img
```

### 3. 刷入设备
手机长按「音量下 + 电源键」进入 Fastboot 模式：
```bash
fastboot flash boot boot-linux-jason.img
fastboot reboot
```

---

## 💡 同架构机友排坑问答（FAQ）

### Q1: 我的手机也是 SDM660 / WCN3990，主线上 Wi-Fi 一断开或一切换就搜不到热点，怎么解决？
* **A**: 请直接打入本项目提供的 `patches/0003-ath10k-wcn3990-fix-disassoc-firmware-assert.patch`。这是因为 `mac80211` 在解关联时发出的 `vdev_down` 早于 peer 注销，违反了高通移动端固件的生命周期约束。该补丁将 `vdev_down` 推迟至 peer 彻底注销后执行，可彻底消除断言自毁。详见：[开源分享-高通WCN3990断连与热点切换固件崩溃修复.md](docs/开源分享-高通WCN3990断连与热点切换固件崩溃修复.md)。

### Q2: 为什么我的手机插着电脑能开机进系统，插充电头或充电宝开机就死机卡在第一屏？
* **A**: 检查你的 `initramfs` 启动脚本（`/init`）中是否包含向 `/dev/ttyGS0`（USB 虚拟串口）直接输出日志的语句（如 `echo ... > /dev/ttyGS0`）。由于充电头没有 USB Host 枚举，Linux TTY 驱动会永久阻塞挂起该进程。请参考 `scripts/initramfs-init.sh` 改造为非阻塞异步输出。详见：[开源分享-高通主线Linux纯脱机独立开机与Initramfs去死锁.md](docs/开源分享-高通主线Linux纯脱机独立开机与Initramfs去死锁.md)。

### Q3: 手机电池已经好几年了，长期插着电做 Linux 服务器会不会鼓包？
* **A**: 会！锂电池长期在 4.35V~4.40V 满电高温浮充极易鼓包甚至起火。请参考本项目的 `0001` 补丁在内核中开启 PM660 芯片的 `0x42` 硬件断充寄存器，并配合 `battery-guardian.sh` 将电量常年锁定在 45%~55%（约 3.85V 黄金保存电压），实现纯外部供电与零浮充电流。详见：[电源保护与服务器待机设计规范.md](docs/电源保护与服务器待机设计规范.md)。

### Q4: 为什么每次重启后 WiFi MAC 地址都会变化（漂移），导致路由器每次分发不同的动态 IP？
* **A**: 高通移动端平台（如 SDM660/MSM8998）原厂物理 MAC 存储在 `persist` 分区的二进制文件 `/mnt/persist/wlan_bt/wlan.mac`（6 字节原始数据）。主线 Linux 的 `ath10k_snoc` 驱动由于未适配高通私有 NV 流程，驱动加载时读取 DTB 缺省必定打印 `invalid MAC address; choosing random` 并随机生成临时 MAC。若仅依赖简单的开机脚本去改 MAC，必然会因时序差（开机脚本在第 4 秒执行完毕退出，而 Hexagon DSP / ath10k 驱动在第 20 秒后才完全拉起并生成 `wlan0`）而静默失效。本项目提供了 `scripts/setup-mac-from-persist.sh`，采用 **systemd.link + NetworkManager 约束 + qualcomm-init 异步看门狗三层铁壁机制**，开机动态解析 `persist` 原厂二进制物理 MAC 并毫秒级自愈锁定，彻底根治 MAC 漂移并实现路由器固定 IP 永久绑定。

---

## 🔒 开源合规与设备安全免责声明

1. 本仓库严格遵循开源安全与隐私规范，**严禁上传任何手机序列号（Serial Number）、出厂物理 MAC、基带校准数据、私有分区备份及个人凭据**。
2. 手机专有固件（如高通签名固件、GPU zap 等）属于厂商知识产权，请使用提取工具从原厂官方 MIUI ROM 中获取，本仓库不分发任何专有商业固件。
3. 刷机与主线 Linux 移植具有一定门槛，操作前请务必完整备份 `persist`、`modemst1`、`modemst2` 等底层射频校准分区。

---

## 📄 开源许可证

本项目核心代码与补丁基于 [GNU General Public License v2.0 (GPL-2.0)](LICENSE) 开源。
