"""Read-only work progress image, 44 × 18 points at Retina resolution."""
from pathlib import Path
from progress_ring import write_png


def progress_image(percent, color, directory=None):
    percent = min(100, max(0, int(percent)))
    rgb = int(color, 16) & 0xffffff
    directory = directory or Path.home() / '.cache/sketchybar/work-progress'
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f'v1-{percent}-{rgb:06x}.png'
    if path.exists():
        return str(path)
    width, height = 88, 36
    track = (56, 69, 52)
    fill = ((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
    buf = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            # Capsule track, 10 points high; sample edges for smooth antialiasing.
            dx = max(abs(x + .5 - 44) - 34, 0)
            dy = abs(y + .5 - 18)
            alpha = min(1, max(0, 10.5 - (dx * dx + dy * dy) ** .5))
            chosen = fill if x + .5 < width * percent / 100 else track
            i = (y * width + x) * 4
            buf[i:i+4] = bytes((*chosen, round(alpha * 255)))
    temporary = path.with_suffix('.tmp')
    write_png(temporary, width, height, buf)
    temporary.replace(path)
    return str(path)
