#!/usr/bin/env python3
"""按本机实测格式打 Android boot 镜像（v0，page 4096，内核后追加 DTB）。

本机实测（来自备份的原厂 boot.img）：
  magic ANDROID! / header_version 0 / page_size 4096
  kernel 段 = gzip(Image) + 紧随其后的多个 DTB（ABL 按 qcom,msm-id 选型）
  ramdisk 段独立，second_size = 0
用法:
  python tools/30-mkbootimg.py --kernel Image.gz --dtb jason.dtb \
      --cmdline "console=... panic=15" -o out/probe.img
"""
import argparse
import struct

PAGE = 4096
KERNEL_ADDR = 0x80008000
RAMDISK_ADDR = 0x81000000
SECOND_ADDR = 0x80F00000
TAGS_ADDR = 0x80000100


def pad(data, page=PAGE):
    n = (len(data) + page - 1) // page * page
    return data + b"\x00" * (n - len(data))


def build(kernel, dtb, ramdisk, cmdline, name=b"probe", os_version=0):
    kblob = kernel + (dtb or b"")
    cmd = cmdline.encode()[:511]
    hdr = bytearray(1632)
    hdr[0:8] = b"ANDROID!"
    struct.pack_into("<10I", hdr, 8,
                     len(kblob), KERNEL_ADDR,
                     len(ramdisk), RAMDISK_ADDR,
                     0, SECOND_ADDR,
                     TAGS_ADDR, PAGE, 0, os_version)
    hdr[48:48 + len(name)] = name
    hdr[64:64 + len(cmd)] = cmd
    return pad(bytes(hdr)) + pad(kblob) + (pad(ramdisk) if ramdisk else b"")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--dtb")
    ap.add_argument("--ramdisk")
    ap.add_argument("--cmdline", required=True)
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()
    kernel = open(a.kernel, "rb").read()
    dtb = open(a.dtb, "rb").read() if a.dtb else b""
    ramdisk = open(a.ramdisk, "rb").read() if a.ramdisk else b""
    img = build(kernel, dtb, ramdisk, a.cmdline)
    open(a.out, "wb").write(img)
    print(f"写入 {a.out}: {len(img)} B  (kernel {len(kernel)} + dtb {len(dtb)}, ramdisk {len(ramdisk)})")
    # 回读自检
    b = open(a.out, "rb").read()
    ks, _, rs, _, _, _, _, ps, hv, _ = struct.unpack_from("<10I", b, 8)
    print(f"回读: magic={b[:8]!r} kernel_size={ks} ramdisk_size={rs} page={ps} hv={hv}")
    print("cmdline=" + b[64:64+len(a.cmdline)].decode())


if __name__ == "__main__":
    main()
