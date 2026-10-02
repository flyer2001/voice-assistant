#!/usr/bin/env python3
"""Иконки приватного навыка Алисы: баннер 1024x500 и квадрат 224x224.

Рисуем в 4x и уменьшаем — PIL не умеет сглаживать контуры сам.
Запуск: python3 scripts/alice-icons.py assets/alice
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

BG_TOP = (18, 22, 34)
BG_BOTTOM = (28, 36, 58)
ACCENT = (108, 196, 255)
TEXT = (238, 242, 250)
MUTED = (138, 152, 178)
# Подзаголовок на баннере: MUTED проваливался на тёмном фоне при уменьшении.
SUBTLE = (176, 190, 214)
FONT = "/root/.fonts/Jost.ttf"
S = 4  # supersampling


def backdrop(w, h):
    """Вертикальный градиент плюс мягкое пятно под глифом."""
    img = Image.new("RGB", (w, h), BG_TOP)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line(
            [(0, y), (w, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)),
        )
    return img


def glow(img, cx, cy, r):
    """Пятно света: рисуем на отдельном слое и накладываем с затуханием."""
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 28
    for i in range(steps, 0, -1):
        rr = r * i / steps
        k = (1 - i / steps) ** 2
        d.ellipse(
            [cx - rr, cy - rr, cx + rr, cy + rr],
            fill=tuple(round(c * k * 0.35) for c in ACCENT),
        )
    return ImageChops.add(img, layer)


def mic(d, cx, cy, h):
    """Микрофон: капсула, дуга-держатель, ножка. Пропорции от высоты капсулы."""
    cap_w = h * 0.52
    d.rounded_rectangle(
        [cx - cap_w / 2, cy - h / 2, cx + cap_w / 2, cy + h / 2],
        radius=cap_w / 2,
        fill=ACCENT,
    )
    lw = max(2, round(h * 0.075))
    arc_r = h * 0.44
    # Дуга опущена ниже капсулы: при прежней рамке её низ проходил сквозь
    # корпус, и на 48 px глиф читался как лампочка.
    d.arc(
        [cx - arc_r, cy - arc_r * 0.1, cx + arc_r, cy + arc_r * 1.55],
        start=0,
        end=180,
        fill=ACCENT,
        width=lw,
    )
    stem_top = cy + arc_r * 1.55 - lw / 2
    d.line([(cx, stem_top), (cx, stem_top + h * 0.2)], fill=ACCENT, width=lw)
    base = stem_top + h * 0.2
    # Основание толще ножки — на мелком размере истончалось до пикселя.
    d.line(
        [(cx - h * 0.2, base), (cx + h * 0.2, base)],
        fill=ACCENT,
        width=round(lw * 1.4),
    )


def bars(d, x0, cy, h, n=5, gap=None):
    """Эквалайзер справа от микрофона — признак голосового ввода."""
    gap = gap or h * 0.16
    w = h * 0.1
    scale = [0.34, 0.68, 1.0, 0.58, 0.28]
    for i in range(n):
        bh = h * scale[i % len(scale)]
        x = x0 + i * (w + gap)
        d.rounded_rectangle(
            [x, cy - bh / 2, x + w, cy + bh / 2],
            radius=w / 2,
            fill=ACCENT if i % 2 == 0 else MUTED,
        )


def banner(path):
    w, h = 1024 * S, 500 * S
    img = backdrop(w, h)
    img = glow(img, w * 0.22, h * 0.5, h * 0.62)
    d = ImageDraw.Draw(img)

    mic(d, w * 0.165, h * 0.44, h * 0.34)
    bars(d, w * 0.225, h * 0.47, h * 0.3)

    title = ImageFont.truetype(FONT, round(h * 0.2))
    sub = ImageFont.truetype(FONT, round(h * 0.075))
    # Текст сдвинут от эквалайзера: подзаголовок начинался левее заголовка и
    # липнул к последнему бару.
    tx = w * 0.42
    # Подзаголовок печатается на 0.02w правее: у «к» боковой вынос меньше, чем
    # у «А», и при одном x левый край блока выглядел рваным.
    sx = tx + w * 0.0195
    d.text((sx, h * 0.415), "Ассистент", font=title, fill=TEXT, anchor="ls")
    d.text(
        (sx, h * 0.595),
        "короткая команда голосом —",
        font=sub,
        fill=SUBTLE,
        anchor="ls",
    )
    d.text((sx, h * 0.715), "сразу в рабочую сессию", font=sub, fill=SUBTLE, anchor="ls")

    img.resize((1024, 500), Image.LANCZOS).save(path)


def square(path):
    side = 224 * S
    img = backdrop(side, side)
    img = glow(img, side * 0.5, side * 0.5, side * 0.52)
    d = ImageDraw.Draw(img)
    # Эквалайзер убран: на 224 и ниже бары слипались с дугой держателя и
    # теряли контраст. Остаётся один силуэт.
    # cy сдвинут вверх на 0.09h — глиф уходит вниз ножкой, геометрический
    # центр капсулы это не оптический центр плитки.
    glyph_h = side * 0.42
    mic(d, side * 0.5, side * 0.5 - glyph_h * 0.216, glyph_h)
    img.resize((224, 224), Image.LANCZOS).save(path)


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/alice")
    out.mkdir(parents=True, exist_ok=True)
    banner(out / "alice-banner-1024x500.png")
    square(out / "alice-icon-224x224.png")
    print(f"ok: {out}/alice-banner-1024x500.png, {out}/alice-icon-224x224.png")
