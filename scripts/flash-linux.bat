@echo off
chcp 65001 >nul
echo ===================================================
echo  Xiaomi Mi Note 3 (jason) Mainline Linux v2.0 一键刷入工具
echo ===================================================
echo.
echo 请确保手机已进入 Fastboot 模式（长按「音量下 + 电源键」），并使用 USB 数据线连接电脑。
echo.
pause

echo.
echo [*] 正在检测 Fastboot 设备...
fastboot devices
if errorlevel 1 (
    echo [!] 未检测到 Fastboot 设备，请检查数据线连接与驱动！
    pause
    exit /b 1
)

echo.
echo [*] 正在刷入 boot 引导分区（v2.0 Debian + Phosh 内核）...
fastboot flash boot boot-xiaomi-jason-debian-phosh-v2.0.img
if errorlevel 1 (
    echo [!] 写入 boot 分区失败！
    pause
    exit /b 1
)

echo.
echo [*] boot 分区写入成功！
echo.
echo 提示：
echo 1. 若您手机的 eMMC p71 分区已经安装了 Debian 12 根文件系统，可以直接重启进入系统。
echo 2. 若需要全新部署 rootfs，请参考 RELEASE_NOTES.md 将 rootfs-debian12-phosh-jason-v2.0.tar.gz 解压至 /dev/mmcblk1p71。
echo.
set /p reboot_choice="是否立即重启手机？(Y/N): "
if /i "%reboot_choice%"=="Y" (
    echo [*] 正在重启...
    fastboot reboot
    echo [*] 重启完成，系统将在约 20 秒内启动至 Phosh 桌面！
)

pause
