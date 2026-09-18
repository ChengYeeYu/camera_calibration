"""Generate a printable checkerboard PNG.

Usage: python3 make_checkerboard.py [cols] [rows] [square_mm] [out_dir]
  cols/rows = number of INNER corners (what you pass to --size), default 8x6.
  out_dir defaults to the repo's calib/ folder (host-mounted, so it survives the container).
Prints at 300 dpi; measure a square after printing and use that for --square.
"""
import os
import sys
import numpy as np
import cv2

cols = int(sys.argv[1]) if len(sys.argv) > 1 else 8
rows = int(sys.argv[2]) if len(sys.argv) > 2 else 6
square_mm = float(sys.argv[3]) if len(sys.argv) > 3 else 25.0
out_dir = sys.argv[4] if len(sys.argv) > 4 else os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "calib")

dpi = 300
px = int(square_mm / 25.4 * dpi)
nx, ny = cols + 1, rows + 1          # squares = inner corners + 1
margin = px
img = np.full(((ny * px) + 2 * margin, (nx * px) + 2 * margin), 255, np.uint8)
for j in range(ny):
    for i in range(nx):
        if (i + j) % 2 == 0:
            y0, x0 = margin + j * px, margin + i * px
            img[y0:y0 + px, x0:x0 + px] = 0

os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"checkerboard_{cols}x{rows}_{int(square_mm)}mm.png")
if not cv2.imwrite(out, img):
    sys.exit(f"failed to write {out}")
w_mm, h_mm = img.shape[1] / dpi * 25.4, img.shape[0] / dpi * 25.4
print(f"wrote {out}  ({nx}x{ny} squares, {cols}x{rows} inner corners, {square_mm} mm squares @ {dpi} dpi)")
print(f"print size: {w_mm:.0f} x {h_mm:.0f} mm  -> fits A4 landscape at 100% scale")
print(f"-> calibrate with: --size {cols}x{rows} --square {square_mm/1000:.4f}")
