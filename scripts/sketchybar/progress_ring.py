#!/usr/bin/env python3
"""项目进度圆环：目标是把环走满（bar 上不再显示 x/y 数字）。

用法: progress_ring.py <已完成数> <总数> <输出 png>
已取消的待办不算在总数里（调用方 day_timeline.sh 已经排除）。
只用标准库直接写 PNG，按 2x 绘制，sketchybar 里用 image.scale=0.5 显示（Retina 清晰）。
环从 12 点方向顺时针走；总数为 0 时画一个空的暗环。
"""

import struct
import sys
import zlib
from math import atan2, pi, sqrt
from pathlib import Path

SCALE = 2
SIZE = 30 * SCALE          # 画布边长
THICK = 4.0 * SCALE        # 环宽
MARGIN = 1.0 * SCALE       # 描边留白，避免贴边被裁
SS = 3                     # 每个像素的超采样倍数（抗锯齿）

TRACK = (0x3B, 0x42, 0x61)     # 未完成部分（和 bar 上其它暗底同色系）
FILL = (0x9E, 0xCE, 0x6A)      # 已完成部分（强调绿）
FULL = (0x9E, 0xCE, 0x6A)      # 闭合时整环同色


def ring_buffer(done: int, total: int) -> bytearray:
    buf = bytearray(SIZE * SIZE * 4)
    r_out = SIZE / 2 - MARGIN
    r_in = r_out - THICK
    cx = cy = SIZE / 2
    frac = 0.0 if total <= 0 else min(max(done / total, 0.0), 1.0)
    closed = total > 0 and done >= total
    step = 1.0 / SS

    for py in range(SIZE):
        for px in range(SIZE):
            # 超采样：统计这个像素里落在环带内的样本，分别累计"已完成"和"未完成"的覆盖率
            cov_fill = cov_track = 0
            for sy in range(SS):
                dy = py + (sy + 0.5) * step - cy
                for sx in range(SS):
                    dx = px + (sx + 0.5) * step - cx
                    d = sqrt(dx * dx + dy * dy)
                    if d < r_in or d > r_out:
                        continue
                    # 12 点方向为 0，顺时针递增
                    ang = (atan2(dx, -dy) + 2 * pi) % (2 * pi) / (2 * pi)
                    if frac > 0 and ang <= frac:
                        cov_fill += 1
                    else:
                        cov_track += 1
            if not cov_fill and not cov_track:
                continue
            n = SS * SS
            color = FULL if closed else FILL
            a_fill, a_track = cov_fill / n, cov_track / n
            a = a_fill + a_track
            i = (py * SIZE + px) * 4
            for c in range(3):
                buf[i + c] = round((color[c] * a_fill + TRACK[c] * a_track) / a)
            buf[i + 3] = round(a * 255)
    return buf


def write_png(path: Path, width: int, height: int, buf: bytearray):
    raw = b"".join(b"\x00" + bytes(buf[y * width * 4:(y + 1) * width * 4]) for y in range(height))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    done, total, out = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
    out.parent.mkdir(parents=True, exist_ok=True)
    write_png(out, SIZE, SIZE, ring_buffer(done, total))


if __name__ == "__main__":
    main()
