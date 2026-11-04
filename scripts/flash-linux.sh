#!/usr/bin/env bash
set -e

echo "==================================================="
echo " Xiaomi Mi Note 3 (jason) Mainline Linux v2.0 Flasher"
echo "==================================================="
echo ""
echo "请确保手机已进入 Fastboot 模式，并通过 USB 连接电脑。"
echo ""
read -p "按回车键开始检测设备..."

echo "[*] 检测 Fastboot 设备..."
fastboot devices

echo "[*] 正在刷入 boot 引导分区..."
fastboot flash boot boot-xiaomi-jason-debian-phosh-v2.0.img

echo ""
echo "[*] 引导镜像刷写成功！"
read -p "是否立即重启手机？(y/n) " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "[*] 重启设备..."
    fastboot reboot
    echo "[*] 设备重启中，将在 20 秒内直入 Phosh 移动桌面！"
fi
