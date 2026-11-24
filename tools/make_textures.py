#!/usr/bin/env python3
"""
SON DİLİM — Prosedürel Doku Üretimi
===============================================================================
Çalıştırma:
    python tools/make_textures.py

Üretilen dokular (res/assets/textures/):
    asphalt_albedo.png    → yol zemini (albedo)
    asphalt_normal.png    → yol zemini (normal map)
    pavement_albedo.png   → kaldırım (albedo)
    pavement_normal.png   → kaldırım (normal map)
    box_diffuse.png       → pasta kutusu (karton)
    facade_albedo.png     → bina cephesi (sıva)

Yöntem: Tileable Value Noise → yükseklikten normal türetme → PNG (zlib).
Bağımlılık: yalnızca Python standart kütüphanesi (PIL gereksiz).
===============================================================================
"""

import math
import os
import struct
import zlib

PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(PROJ, "res", "assets", "textures")
os.makedirs(OUT, exist_ok=True)

W = H = 512


# ── PNG YAZICI ───────────────────────────────────────────────────────────────
def png(path, w, h, pixels):
    """pixels: bytearray, w*h*3 (RGB)."""
    raw = b''
    for y in range(h):
        raw += b'\x00' + bytes(pixels[y * w * 3:(y + 1) * w * 3])

    def chunk(tag, data):
        c = tag + data
        return (struct.pack('>I', len(data)) + c +
                struct.pack('>I', zlib.crc32(c) & 0xffffffff))

    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    out += chunk(b'IDAT', zlib.compress(raw, 9))
    out += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(out)
    print(f"  ✓ {os.path.basename(path)}  {os.path.getsize(path) // 1024} KB")


# ── TILEABLE VALUE NOISE ────────────────────────────────────────────────────
def value_noise(w, h, cells, seed, octaves=4):
    """Tileable value noise. Aynı seed → aynı doku."""
    import random
    random.seed(seed)
    acc = [[0.0] * w for _ in range(h)]
    amp_total = 0.0
    for o in range(octaves):
        freq = cells * (2 ** o)
        amp = 1.0 / (2 ** o)
        amp_total += amp
        grid = [[random.random() for _ in range(freq + 1)]
                for _ in range(freq + 1)]
        for y in range(h):
            fy = y / h * freq
            iy = int(fy)
            ty = fy - iy
            ty = ty * ty * (3 - 2 * ty)
            for x in range(w):
                fx = x / w * freq
                ix = int(fx)
                tx = fx - ix
                tx = tx * tx * (3 - 2 * tx)
                v = (grid[iy][ix] * (1 - tx) + grid[iy][ix + 1] * tx) * (1 - ty) + \
                    (grid[iy + 1][ix] * (1 - tx) +
                     grid[iy + 1][ix + 1] * tx) * ty
                acc[y][x] += v * amp
    for y in range(h):
        for x in range(w):
            acc[y][x] /= amp_total
    return acc


def height_to_normal(hgt, strength=2.2):
    """Yükseklik alanından normal haritası üretir (OpenGL konvansiyonu)."""
    px = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 3
            left = hgt[y][(x - 1) % W]
            right = hgt[y][(x + 1) % W]
            up = hgt[(y - 1) % H][x]
            down = hgt[(y + 1) % H][x]
            nx = (left - right) * strength
            ny = (up - down) * strength
            nz = 1.0
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            px[i] = int((nx / ln * 0.5 + 0.5) * 255)
            px[i + 1] = int((ny / ln * 0.5 + 0.5) * 255)
            px[i + 2] = int((nz / ln * 0.5 + 0.5) * 255)
    return px


# ── 1) ASFALT ────────────────────────────────────────────────────────────────
def make_asphalt():
    print("Asfalt üretiliyor...")
    n1 = value_noise(W, H, 8, 11, 5)
    n2 = value_noise(W, H, 32, 22, 3)

    px = bytearray(W * H * 3)
    hgt = [[0.0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 3
            g = n1[y][x] * 0.6 + n2[y][x] * 0.4
            # Islak leke (albedo'da koyu, çukur hissi)
            wet = 0.0
            if n2[y][x] < 0.42:
                wet = (0.42 - n2[y][x]) * 1.6
            base = 26 + g * 26
            px[i] = int(min(255, base + wet * 4))
            px[i + 1] = int(min(255, base + wet * 2))
            px[i + 2] = int(min(255, base * 1.28 + wet * 14))
            hgt[y][x] = g * 0.7 + n2[y][x] * 0.3
    png(os.path.join(OUT, "asphalt_albedo.png"), W, H, px)
    png(os.path.join(OUT, "asphalt_normal.png"), W, H,
        height_to_normal(hgt, 2.2))


# ── 2) KALDIRIM ──────────────────────────────────────────────────────────────
def make_pavement():
    print("Kaldırım üretiliyor...")
    n3 = value_noise(W, H, 16, 33, 4)
    n4 = value_noise(W, H, 64, 44, 2)
    TILE = 64  # bir plaka 64px

    px = bytearray(W * H * 3)
    hgt = [[0.0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 3
            gx, gy = x % TILE, y % TILE
            joint = (gx < 3 or gx > TILE - 4 or
                     gy < 3 or gy > TILE - 4)
            g = n3[y][x] * 0.7 + n4[y][x] * 0.3
            v = 88 + g * 44
            if joint:
                v *= 0.55
            px[i] = int(v * 1.0)
            px[i + 1] = int(v * 0.98)
            px[i + 2] = int(v * 1.06)
            hgt[y][x] = (0.0 if joint else 1.0) + n4[y][x] * 0.06
    png(os.path.join(OUT, "pavement_albedo.png"), W, H, px)
    png(os.path.join(OUT, "pavement_normal.png"), W, H,
        height_to_normal(hgt, 3.5))


# ── 3) KUTU (karton) ────────────────────────────────────────────────────────
def make_box():
    print("Pasta kutusu (karton) üretiliyor...")
    n5 = value_noise(W, H, 48, 77, 3)
    n6 = value_noise(W, H, 6, 88, 3)
    px = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 3
            g = n5[y][x] * 0.55 + n6[y][x] * 0.45
            flute = 0.06 * math.sin(y * 0.55)   # oluklu karton
            v = 132 + g * 54 + flute * 255
            px[i] = int(min(255, v * 1.0))
            px[i + 1] = int(min(255, v * 0.74))
            px[i + 2] = int(min(255, v * 0.44))
    png(os.path.join(OUT, "box_diffuse.png"), W, H, px)


# ── 4) BİNA SIVASI ──────────────────────────────────────────────────────────
def make_facade():
    print("Bina cephesi üretiliyor...")
    n7 = value_noise(W, H, 10, 99, 5)
    n8 = value_noise(W, H, 40, 111, 3)
    px = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 3
            g = n7[y][x] * 0.7 + n8[y][x] * 0.3
            crack = 0.0
            if n8[y][x] < 0.30:
                crack = (0.30 - n8[y][x]) * 2.2   # çatlaklar
            v = 96 + g * 52
            px[i] = int(v * 1.02 * (1 - crack))
            px[i + 1] = int(v * 0.97 * (1 - crack))
            px[i + 2] = int(v * 1.05 * (1 - crack))
    png(os.path.join(OUT, "facade_albedo.png"), W, H, px)


# ── ANA ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("\n=== SON DİLİM — DOKU ÜRETİMİ ===\n")
    make_asphalt()
    make_pavement()
    make_box()
    make_facade()
    print(f"\nToplam {len(os.listdir(OUT))} doku → {OUT}\n")
