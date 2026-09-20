#!/usr/bin/env python3
"""专注时间热力图（GitHub 贡献图风格），只用标准库直接写 PNG。

用法: focus_heatmap.py <数据目录> <输出 png> <周数> "<色阶阈值小时，如 1 2 4>"
数据目录下每天一个文件（文件名 YYYY-MM-DD，内容为当天专注秒数）。
列 = 周（最右为本周），行 = 周一…周日；今天的格子加描边。
stdout 输出一行摘要：今天 / 本周 / 近 30 天日均。
"""

import datetime as dt
import struct
import sys
import zlib
from pathlib import Path

SCALE = 2          # 按 2x 绘制，sketchybar 里用 image.scale=0.5 显示（Retina 清晰）
CELL = 11 * SCALE
GAP = 3 * SCALE
RADIUS = 2.5 * SCALE

EMPTY = (0x29, 0x2E, 0x42)
LEVELS = [(0x0E, 0x44, 0x29), (0x00, 0x6D, 0x32), (0x26, 0xA6, 0x41), (0x39, 0xD3, 0x53)]
TODAY_RING = (0xC0, 0xCA, 0xF5)


def load(data_dir: Path) -> dict:
    seconds = {}
    for f in data_dir.glob("????-??-??"):
        try:
            seconds[dt.date.fromisoformat(f.name)] = int(f.read_text().strip() or 0)
        except ValueError:
            pass
    return seconds


def level_color(secs: int, thresholds: list) -> tuple:
    if secs <= 0:
        return EMPTY
    level = sum(1 for h in thresholds if secs >= h * 3600)
    return LEVELS[min(level, len(LEVELS) - 1)]


def draw_rounded_rect(buf, width, x0, y0, size, radius, color):
    """抗锯齿圆角方块，src-over 叠加到 RGBA 缓冲区。"""
    half = size / 2
    cx, cy = x0 + half, y0 + half
    for py in range(int(y0), int(y0 + size) + 1):
        for px in range(int(x0), int(x0 + size) + 1):
            qx = abs(px + 0.5 - cx) - (half - radius)
            qy = abs(py + 0.5 - cy) - (half - radius)
            outside = (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** 0.5
            d = outside + min(max(qx, qy), 0) - radius
            a = min(max(0.5 - d, 0.0), 1.0)
            if a <= 0:
                continue
            i = (py * width + px) * 4
            if i < 0 or i + 3 >= len(buf):
                continue
            da = buf[i + 3] / 255
            oa = a + da * (1 - a)
            for c in range(3):
                buf[i + c] = round((color[c] * a + buf[i + c] * da * (1 - a)) / oa)
            buf[i + 3] = round(oa * 255)


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


def fmt(secs: float) -> str:
    m = int(secs // 60)
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


def main():
    data_dir, out, weeks = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
    thresholds = [float(h) for h in sys.argv[4].split()]
    seconds = load(data_dir)

    today = dt.date.today()
    first_monday = today - dt.timedelta(days=today.weekday(), weeks=weeks - 1)

    width = weeks * CELL + (weeks - 1) * GAP
    height = 7 * CELL + 6 * GAP
    buf = bytearray(width * height * 4)

    for w in range(weeks):
        for d in range(7):
            day = first_monday + dt.timedelta(weeks=w, days=d)
            if day > today:
                continue
            x, y = w * (CELL + GAP), d * (CELL + GAP)
            color = level_color(seconds.get(day, 0), thresholds)
            if day == today:
                draw_rounded_rect(buf, width, x, y, CELL, RADIUS, TODAY_RING)
                inset = 2 * SCALE
                draw_rounded_rect(buf, width, x + inset, y + inset, CELL - 2 * inset, max(RADIUS - inset, 1), color)
            else:
                draw_rounded_rect(buf, width, x, y, CELL, RADIUS, color)

    write_png(out, width, height, buf)

    week_start = today - dt.timedelta(days=today.weekday())
    this_week = sum(s for day, s in seconds.items() if week_start <= day <= today)
    last30 = sum(s for day, s in seconds.items() if today - dt.timedelta(days=29) <= day <= today)
    print(f"Today {fmt(seconds.get(today, 0))} · This week {fmt(this_week)} · 30-day avg {fmt(last30 / 30)}/day")


if __name__ == "__main__":
    main()
