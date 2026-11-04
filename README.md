# Xiaomi Mi Note 3 (jason) Mainline Linux Project
# 小米 Note 3（SDM660）主线 Linux 移植与服务器级电源保护工程

[![Kernel](https://img.shields.io/badge/Linux-7.0.14-blue.svg)](https://kernel.org)
[![Platform](https://img.shields.io/badge/SoC-Qualcomm%20SDM660-orange.svg)]()
[![Distribution](https://img.shields.io/badge/RootFS-Debian%2012%20%2B%20Phosh-green.svg)]()
[![License](https://img.shields.io/badge/License-GPL%20v2-lightgrey.svg)](LICENSE)

本项目旨在将**小米 Note 3（代号：`jason`，高通骁龙 SDM660，6GB+64GB）**成功移植至现代化主线 Linux（Linux 7.0.14），并针对 **7×24 小时低功耗微型服务器** 工况进行深度电源防护与系统调优。

---

## 🌟 核心突破与技术亮点

1. **全国首发：攻破 SDM660 + WCN3990 WiFi/蓝牙 主线死锁历史顽疾**
   - 彻底解决了高通主线上多年来 `ath10k_snoc` 驱动由于 0x82e 固件段冲突导致 modem 崩溃死锁重启的问题；
   - 实现了双出厂物理 MAC 自动固化与蓝牙/Wi-Fi 全功能稳定联网。
2. **硬件级旁路直供（Hardware Bypass Mode）与四层防爆护盾**
   - 深入逆向高通 PM660 芯片寄存器，在主线内核中补齐 `CHARGING_ENABLE_CMD (0x42)` 硬件断充接口；
   - **外部 5V 正常供电主板，电池充放电流归零**，杜绝 9 年老旧电芯长期高压高温浮充鼓包；
   - 保持电池作为**断电 UPS 随时并联在线**，拔掉外部电线毫秒级无缝接管，绝不关机猝死；
   - 部署守护进程自动锁定在 45%~55%（约 3.85V）锂电黄金保存电压，支持 45℃ 紧急断充温控。
3. **针对移动服务器的待机与物理按键调优**
   - 改写系统底层按键事件，短按电源键实现物理一键息屏与唤醒；
   - 息屏后发热 LED 阵列电流彻底清零，CPU 处于微秒级节能待机，**SSH 与局域网服务 7×24 小时毫秒级在线秒响应**。
4. **原生 Debian 12 (bookworm) + Phosh 0.24 移动触控桌面闭环**
   - 采用 Wayland 合成器 `phoc`，1080×1920 原生竖屏 KMS 输出与 2x 缩放；
   - 完整打通 Freedreno Adreno 512 GPU 硬件加速与 Squeekboard 虚拟软键盘；
   - 预装 `gnome-console` 移动触控终端，彻底去除开机锁屏与密码校验，冷启动 20 秒直入桌面；
   - 彻底修复 Qualcomm SDM660 基带 Modem 读扇区死锁与 Hexagon DSP TQFTP 固件分发异常。

---

## 📊 硬件功能支持状态表

| 硬件子系统 | 驱动栈 | 状态 | 详细说明 |
|---|---|---|---|
| **CPU 架构** | 8 核 Kryo 260 |  正常 | 4×A73 2.2GHz + 4×A53 1.8GHz 调度正常 |
| **GPU 加速** | Freedreno (Adreno 512) |  正常 | Mesa 开源驱动硬件加速渲染，Wayland 满帧运行 |
| **显示面板** | DPU + JDI 1080P FHD |  正常 | 1080×1920@60Hz 原生 KMS 驱动输出 |
| **多点触摸** | Synaptics S3330 (rmi4) |  正常 | 多点触控、压力感应、虚拟按键全通 |
| **无线网络** | WCN3990 (ath10k) |  正常 | 打入 0x82e 补丁，5G/2.4G 稳定连接，出厂 MAC 绑定 |
| **蓝牙通信** | WCN3990 (hci_qca) |  正常 | 真实出厂物理 MAC 固化，Phosh 瓷贴与设备秒级扫描 |
| **电源与充电** | PM660 + qcom-battery |  正常 | 硬件旁路断充 + 45%~55% 电量锁定 + 备用 UPS |
| **物理按键** | PM8941 PON |  正常 | 音量加减可用，电源键支持物理亮屏/息屏切换 |
| **网络时钟** | NTP 授时服务 |  正常 | 自动校时，解决 1970 年导致的 TLS 证书报错 |
| **音频外放** | PM660L / WSA8815 | 🚧 适配中 | 耳放走 INT0，机身外放扬声器走 INT4 + WSA8815 待收尾 |

---

## 📁 仓库目录结构

```text
├── dts/
│   └── sdm660-xiaomi-jason.dts                # 完整板级设备树（显示/触控/GPU/供电/WiFi/蓝牙）
├── patches/
│   ├── 0001-power-supply-pm660-hardware-bypass.patch # PM660 芯片硬件旁路直供与断充补丁
│   └── 0002-ath10k-wcn3990-fix-0x82e-crash.patch    # 根治 WCN3990 0x82e 固件死锁补丁
├── scripts/
│   ├── battery-guardian.sh                    # 45%~55% 黄金电量保护守护进程
│   ├── battery-guardian.initd                 # OpenRC 系统开机自启服务
│   ├── acpi-pwrkey.sh                         # 电源键物理一键息屏/唤醒脚本
│   ├── 30-mkbootimg.py                        # ABL 引导镜像打包工具
│   ├── repack-boot.py                         # 通用一键打包 boot.img 脚本
│   └── setup-mac-from-persist.sh              # 自动提取出厂真实物理 MAC 注入脚本
└── docs/
    ├── 开源分享-SDM660-WCN3990主线WiFi驱动突破.md  # 详细技术复盘与分析
    ├── 电源保护与服务器待机设计规范.md            # 芯片级寄存器逆向与四层防护实现
    └── 状态表.md                              # 完整技术状态跟踪表
```

---

## 🛠️ 构建与刷写指南

### 1. 内核编译
在 Linux / WSL 环境下准备交叉编译工具链（LLVM/Clang）：
```bash
# 进入 Linux 7.0.14-sdm660 源码树
cd linux-7.0.14-sdm660

# 应用核心补丁
patch -p1 < /path/to/patches/0001-power-supply-pm660-hardware-bypass.patch
patch -p1 < /path/to/patches/0002-ath10k-wcn3990-fix-0x82e-crash.patch

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

## 🔒 开源合规与设备安全免责声明

1. 本仓库严格遵循开源安全与隐私规范，**严禁上传任何手机序列号（Serial Number）、出厂物理 MAC、基带校准数据、私有分区备份及个人凭据**。
2. 手机专有固件（如高通签名固件、GPU zap 等）属于厂商知识产权，请使用提取工具从原厂官方 MIUI ROM 中获取，本仓库不分发任何专有商业固件。
3. 刷机与主线 Linux 移植具有一定门槛，操作前请务必完整备份 `persist`、`modemst1`、`modemst2` 等底层射频校准分区。

---

## 📄 开源许可证

本项目核心代码与补丁基于 [GNU General Public License v2.0 (GPL-2.0)](LICENSE) 开源。
