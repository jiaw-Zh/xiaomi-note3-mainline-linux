#!/usr/bin/env python3
"""
Xiaomi Note 3 (jason) - Boot Image Packer for Linux
"""
import os
import sys
import subprocess

def main():
    kernel = sys.argv[1] if len(sys.argv) > 1 else "Image.gz"
    dtb = sys.argv[2] if len(sys.argv) > 2 else "sdm660-xiaomi-jason.dtb"
    ramdisk = sys.argv[3] if len(sys.argv) > 3 else "initramfs.cpio.gz"
    output = sys.argv[4] if len(sys.argv) > 4 else "boot.img"
    cmdline = "earlycon=msm_geni_serial,0xc1b0000 console=ttyMSM0,115200n8 panic=15"

    cmd = [
        sys.executable, os.path.join(os.path.dirname(__file__), "30-mkbootimg.py"),
        "--kernel", kernel,
        "--dtb", dtb,
        "--ramdisk", ramdisk,
        "--cmdline", cmdline,
        "-o", output
    ]
    print(f"Packing boot image: {output}")
    res = subprocess.run(cmd)
    if res.returncode == 0:
        print(f"[OK] Boot image generated: {output} ({os.path.getsize(output)} bytes)")
    else:
        sys.exit(res.returncode)

if __name__ == "__main__":
    main()
