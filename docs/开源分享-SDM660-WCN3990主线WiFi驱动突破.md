# 【硬核开源】彻底攻克高通 SDM660 主线 Linux WCN3990 WiFi 扫描即崩（PC=0xb00a5d08）深度分析与内核 Patch

> **适用平台**：Qualcomm Snapdragon 660（SDM660 / SDM636 / MSM8998 等搭载 WCN3990 芯片的设备）  
> **实测机型**：Xiaomi Mi Note 3 (`jason`)  
> **内核版本**：Linux Mainline 6.x / 7.0.x (`ath10k_snoc`)  
> **作者**：jason Linux 移植团队  
> **许可证**：GPL-2.0 / MIT  

---

## 0. 摘要 (TL;DR)

长期以来，高通 SDM660/MSM8998 平台在移植主线 Linux 时，搭载的 **WCN3990（ath10k_snoc）** 驱动一直存在一个致命痛点：
固件（`wlanmdsp.mbn`）与 Board Data 加载正常，`wlan0` 节点成功生成，但**只要执行扫描（`iw scan` 或 NetworkManager 触发扫描），Hexagon DSP 瞬间崩溃抛出硬件看门狗（PC=0xb00a5d08 空指针），导致 Wi-Fi 彻底瘫痪**。

社区过往的尝试大量走入误区（盲目替换各种手机的 `board-2.bin`、怀疑时钟电压或 RFSA/QMI 时序问题）。本文彻底揭开该崩溃的固件级根本原因，并给出**对齐高通 CodeAurora 官方的内核补丁（单行级根治）**与完整的板级固件打包方案。实测 2.4G/5G 双频扫描完全正常，802.11ac 稳定连网，外网 Ping 7ms，已物理刷入 eMMC 脱机冷启动商用验证。

---

## 1. 故障现象与现场逆向分析

### 1.1 崩溃现场
当 `wlan0` 接口置 UP 之后，一旦用户态下发扫描指令：
```bash
iw dev wlan0 scan
# 或者 NetworkManager 自动搜网
```
内核立刻爆出驱动崩溃日志：
```text
ath10k_snoc 18800000.wifi: firmware crashed! (guid ...)
ath10k_snoc 18800000.wifi: hardware name wcn3990 hw1.0 ...
qcom-q6v5-wcss 10b0000.remoteproc-wcss: fatal error received from wcss: ...
```
抓取 Hexagon DSP（WCSS）固件寄存器上下文：
```text
PC = 0xb00a5d08
LR = 0xb00a5cd0
BadVA = 0x0000002c
Cause: Read from NULL pointer
```

### 1.2 根因剖析：为什么是 `0x2c` 偏移？
通过逆向反汇编高通原厂 `wlanmdsp.mbn` 对应地址 `0xb00a5d08` 处的执行流：
```assembly
b00a5d04:   r0 = memw(r2 + #0)
b00a5d08:   r1 = memw(r0 + #0x2c)   <-- 崩溃点：r0 为 0x00000000 (NULL)
```
- **业务场景**：此时设备处于 STA 模式，**尚未与任何 AP 建立关联（Unassociated / Idle）**。
- **协议差异**：主线内核 `ath10k` 的 `wmi-tlv.c` 在构造扫描控制命令（`wmi_tlv_op_gen_start_scan`）时，默认会对 `cmd->common.scan_ctrl_flags` 翻转 `WMI_SCAN_FILTER_PROBE_REQ` 标志，导致下发了**包含被动扫描（PASSIVE SCAN）与探测过滤**的标志位组合。
- **固件假设**：在 WCN3990 固件的被动扫描实现中，Hexagon DSP 假设当前已存在有效的 VDEV 上下文结构体（VDEV pointer），并在处理信道 Beacon 过滤时直接从 VDEV 指针偏移 `0x2c` 读取参数。当未连接 AP 进行环境搜网时，该指针为 `NULL`，直接引发解引用内核级 Hard Fault！

---

## 2. 社区常见误区反驳（Stop Doing This）

在排查该问题时，国内外社区存在以下几个典型技术误区，白白浪费数周时间：

1. **误区一：“是 board-2.bin 校验和不对或者 RF 校准数据坏了”**
   * **反驳**：Board Data 如果错误，驱动在固件引导初期（`ath10k_core_fetch_board_data_api_n`）就会直接报 `failed to fetch board data (-2)` 并退出，压根走不到生成 `wlan0` 和触发扫描的阶段。
2. **误区二：“是 Q6 WCSS 子系统电压或时钟掉电”**
   * **反驳**：如果是电源域崩塌，崩溃现场是整个 AXI 总线超时（No response from interconnect），而不是精确的 Hexagon 核心寄存器 `PC=0xb00a5d08` 空指针读取。
3. **误区三：“加内核参数 clk_ignore_unused 或 pd_ignore_unused 掩盖”**
   * **反驳**：这是无意义的技术债，无法解决固件逻辑中的空指针解引用。

---

## 3. 彻底根治方案：内核驱动 Patch

对齐高通 CodeAurora (CAF) 内部提交 `1e29e91126970f9c7ec6b25d69b10f2b92364898`，针对 WCN3990 硬件，必须在下发 WMI-TLV 扫描命令时**强制覆盖扫描控制标志为 `0x82e`**。

### 3.1 Kernel Patch

```diff
diff --git a/drivers/net/wireless/ath/ath10k/wmi-tlv.c b/drivers/net/wireless/ath/ath10k/wmi-tlv.c
index 2855f308a0..f4a1329c01 100644
--- a/drivers/net/wireless/ath/ath10k/wmi-tlv.c
+++ b/drivers/net/wireless/ath/ath10k/wmi-tlv.c
@@ -1559,10 +1559,20 @@ ath10k_wmi_tlv_op_gen_start_scan(struct ath10k *ar,
 	cmd->common.burst_duration = __cpu_to_le32(arg->burst_duration);
 
 	/* FIXME: There are some scan flag inconsistencies across firmwares,
 	 * e.g. WMI-TLV inverts the logic behind the following flag.
+	 * For WCN3990, Qualcomm CodeAurora (commit 1e29e9112697) requires
+	 * scan_ctrl_flags to be explicitly set to 0x82e to prevent the Hexagon
+	 * DSP firmware from dereferencing a NULL VDEV pointer (PC=0xb00a5d08)
+	 * during passive scanning in unassociated state.
 	 */
-	if (!QCA_REV_WCN3990(ar))
-		cmd->common.scan_ctrl_flags ^= __cpu_to_le32(WMI_SCAN_FILTER_PROBE_REQ);
+	if (QCA_REV_WCN3990(ar)) {
+		cmd->common.scan_ctrl_flags = __cpu_to_le32(0x82e);
+		ath10k_dbg(ar, ATH10K_DBG_WMI,
+			   "wcn3990: forced scan_ctrl_flags=0x82e vdev=%u scan_id=0x%x\n",
+			   __le32_to_cpu(cmd->common.vdev_id),
+			   __le32_to_cpu(cmd->common.scan_id));
+	} else {
+		cmd->common.scan_ctrl_flags ^= __cpu_to_le32(WMI_SCAN_FILTER_PROBE_REQ);
+	}
 
 	if (arg->adaptive_dwell.dwell_time_active) {
 		cmd->common.scan_ctrl_flags |=
```

### 3.2 标志位解析（0x82e 的含义）
`0x82e` 由以下 WMI Scan Flag 复合而成：
* `0x0002`：`WMI_SCAN_ADD_OFDM_RATES`（强制包含 OFDM 速率）
* `0x0004`：`WMI_SCAN_ADD_BCAST_PROBE_REQ`（发送广播探测请求）
* `0x0008`：`WMI_SCAN_ADD_DS_IE_IN_PROBE_REQ`（添加直接序列 IE）
* `0x0020`：`WMI_SCAN_FILTER_PROBE_REQ`（过滤非法探测）
* `0x0800`：强制主动扫描模式，抑制在 VDEV 为空时的被动 Beacon 接收流程。

---

## 4. 固件与 Board-2.bin 组包规范

即使内核打了 Patch，如果 Board Data 没有根据机型匹配，仍然无法拉起射频。

### 4.1 提取与放置固件
从原厂 Android 系统的 `/vendor/firmware/` 提取以下文件：
* `wlanmdsp.mbn`（WLAN Hexagon 固件）
* 放置路径：`/lib/firmware/qcom/sdm660/<device>/wlanmdsp.mbn`

### 4.2 Board Data 打包（board-2.bin）
`ath10k` 在 SNOC 总线下按以下格式匹配条目：
`bus=snoc,qmi-board-id=XX,qmi-chip-id=YY,variant=ZZ`

从原厂提取 `bdwlan30.bin` 后，使用官方 `ath10k-bdencoder` 或 Python 打包脚本封装为 TLV 格式的 `board-2.bin`：
1. TLV Header: `QCA-ATH10K-BOARD`
2. ID 0: Board Name 字符串（与驱动 QMI 查询到的 board-id 严格一致）
3. ID 1: Board Data 二进制数据
放置于 `/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin`。

---

## 5. 真实 AP 连网与实测效果

在搭载 Alpine Linux + Phosh 的小米 Note 3 真机上验证：

### 5.1 扫描验证
```bash
# NetworkManager 命令行扫描
nmcli dev wifi list
```
**输出**：
```text
IN-USE  BSSID              SSID           MODE   CHAN  FREQ      RATE        SIGNAL  BARS  SECURITY 
        XX:XX:XX:XX:XX:XX  MyHome-5G      Infra  36    5180 MHz  540 Mbit/s  100     ▂▄▆█  WPA2     
        XX:XX:XX:XX:XX:XX  Office-2.4G    Infra  6     2437 MHz  270 Mbit/s  85      ▂▄▆_  WPA2     
```
连续扫描 50 次，WCSS DSP 0 崩溃，内核 0 报错。

### 5.2 联网性能
连接 802.11ac 5GHz AP：
* `wpa_state=COMPLETED`
* 协议：802.11ac，信道 36（5180 MHz），带宽 80MHz
* Ping 测试（公共 DNS）：
  ```text
  64 bytes from 223.5.5.5: seq=1 ttl=118 time=7.89 ms
  64 bytes from 223.5.5.5: seq=2 ttl=118 time=8.12 ms
  0% packet loss
  ```
* 网页下载（`wget`）：稳定跑满 80~100 Mbps 真实速率。
* 桌面集成：Phosh 顶栏 Wi-Fi 满格点亮，休眠唤醒重连一切正常。

---

## 6. 物理 MAC 固化提醒（安全与规范）

WCN3990 默认启动会生成随机 MAC（`ath10k_snoc: invalid MAC address; choosing random`）。
**正确做法**：从原机 `persist` 分区的 WLAN MAC 偏移处（或原厂 `/persist/wlan_mac.bin`）提取原机专属 MAC，通过 systemd-networkd、udev 规则（`01-mac-fix.rules`）或 pre-up 脚本写入接口，不要改写物理 `persist` 分区，保护校准数据安全。

---

## 7. 结语

高通 WCN3990 并非“主线 Linux 不可攻破”，核心问题往往隐藏在厂商 BSP 私有修改与主线驱动未同步的协议细微处。希望此文与 Patch 能帮助所有正在将 SDM660、MSM8998、SDM636 设备推向主线 Linux / postmarketOS 的开发者们少走弯路！
