#!/usr/bin/env python3
"""Optimize Xiaohongshu poster: gradient background + typography."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = Path(
    "/Users/daniel/.cursor/projects/Users-daniel-Projects-cursor-agent-status/assets/"
    "_____-b2a2b154-3bfb-4c38-a02e-7550e04aa5ff.png"
)
OUT = Path(__file__).resolve().parents[1] / "assets" / "xiaohongshu-poster-optimized.png"

W, H = 1080, 1440


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            index = 1 if bold and path.endswith(".ttc") else 0
            return ImageFont.truetype(path, size, index=index)
    return ImageFont.load_default()


def make_background() -> Image.Image:
    img = Image.new("RGB", (W, H), "#0a0c12")
    px = img.load()
    for y in range(H):
        t = y / H
        r = int(8 + 14 * t + 6 * math.sin(t * math.pi))
        g = int(10 + 18 * t + 8 * math.sin(t * math.pi * 0.9))
        b = int(22 + 28 * t + 12 * math.sin(t * math.pi * 1.1))
        for x in range(W):
            cx = (x - W * 0.5) / W
            vignette = 1.0 - 0.22 * (cx * cx + ((y / H) - 0.42) ** 2)
            px[x, y] = (
                max(0, min(255, int(r * vignette))),
                max(0, min(255, int(g * vignette))),
                max(0, min(255, int(b * vignette))),
            )

    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((140, 620, 940, 1180), fill=(32, 72, 160, 42))
    od.ellipse((220, 700, 860, 1080), fill=(18, 48, 96, 30))
    od.ellipse((-120, -180, 620, 320), fill=(255, 255, 255, 10))
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

    noise = Image.new("RGBA", (W, H))
    nd = ImageDraw.Draw(noise)
    rng = random.Random(42)
    for _ in range(1800):
        x, y = rng.randint(0, W - 1), rng.randint(0, H - 1)
        a = rng.randint(4, 14)
        nd.point((x, y), fill=(255, 255, 255, a))
    noise = noise.filter(ImageFilter.GaussianBlur(radius=0.6))
    return Image.blend(img, noise.convert("RGB"), 0.035)


def draw_header(base: Image.Image) -> None:
    draw = ImageDraw.Draw(base)
    title_font = load_font(54, bold=True)
    sub_font = load_font(26)
    label_font = load_font(22, bold=True)
    feat_font = load_font(30, bold=True)

    draw.text((72, 76), "CURSOR AGENT STATUS", fill="#6b8cff", font=label_font)
    draw.text((72, 122), "Agent 在干嘛", fill="#f4f6fb", font=title_font)
    draw.text((72, 188), "一眼就知道", fill="#f4f6fb", font=title_font)
    draw.rounded_rectangle((72, 276, 168, 280), radius=2, fill="#3d5afe")

    features = [
        ("菜单栏常驻", "随时看 RUN/PND/DONE", "#3d7bf5"),
        ("Dock 悬浮 HUD", "名称 + 状态 + 耗时", "#22a06b"),
        ("不侵入 Cursor", "官方 Hooks 桥接", "#7c6cf0"),
        ("不占 Dock", "纯菜单栏应用", "#e8913a"),
    ]
    x0, y0 = 72, 308
    col_w, row_h = 468, 112
    gap_x, gap_y = 20, 14

    for i, (title, sub, color) in enumerate(features):
        col = i % 2
        row = i // 2
        x = x0 + col * (col_w + gap_x)
        y = y0 + row * (row_h + gap_y)
        draw.rounded_rectangle(
            (x, y, x + col_w, y + row_h),
            radius=16,
            fill="#141824",
            outline="#2a3144",
            width=1,
        )
        draw.ellipse((x + 18, y + 20, x + 30, y + 32), fill=color)
        draw.text((x + 40, y + 14), title, fill="#eef1f8", font=feat_font)
        draw.text((x + 40, y + 54), sub, fill="#8b95aa", font=sub_font)


def extract_ui_layers(src: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Split HUD cards and Dock from source screenshot."""
    # HUD white cards region (exclude top text + black gap)
    hud = src.crop((24, 528, src.width - 24, 698)).convert("RGBA")
    dock = src.crop((0, 692, src.width, src.height)).convert("RGBA")
    return hud, dock


def paste_centered(
    base: Image.Image,
    layer: Image.Image,
    y: int,
    max_width: int,
    shadow: bool = True,
) -> int:
    scale = max_width / layer.width
    new_h = int(layer.height * scale)
    resized = layer.resize((max_width, new_h), Image.Resampling.LANCZOS)
    x = (W - max_width) // 2

    if shadow:
        sh = Image.new("RGBA", (max_width + 64, new_h + 64), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        sd.rounded_rectangle((32, 32, max_width + 32, new_h + 32), radius=20, fill=(0, 0, 0, 80))
        sh = sh.filter(ImageFilter.GaussianBlur(radius=18))
        base.paste(sh, (x - 32, y - 12), sh)

    base.paste(resized, (x, y), resized)
    return y + new_h


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    hud, dock = extract_ui_layers(src)

    canvas = make_background()
    draw_header(canvas)

    y = 560
    y = paste_centered(canvas, hud, y, max_width=W - 120, shadow=True)
    y += 28
    paste_centered(canvas, dock, y, max_width=W - 48, shadow=False)

    draw = ImageDraw.Draw(canvas)
    tag_font = load_font(26)
    draw.text((W // 2, H - 52), "开源免费 · macOS 14+ · MIT", fill="#8b95aa", font=tag_font, anchor="mm")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT, quality=95, optimize=True)
    print(f"Saved: {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
