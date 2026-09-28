"""ScaffoldPro app icon — rendered with Pillow at 4x and downsampled."""
import math
from PIL import Image, ImageDraw, ImageFilter

NAVY_TOP = (0x1B, 0x35, 0x56)
NAVY_BOTTOM = (0x10, 0x22, 0x3A)
STEEL = (0xE4, 0xE8, 0xEC)
STEEL_SHADE = (0xB4, 0xBD, 0xC7)
YELLOW = (0xF4, 0xB4, 0x00)
YELLOW_EDGE = (0xD9, 0x98, 0x00)
SLOT = (0x4A, 0x5D, 0x76)

def squircle_mask(size, rect, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(rect, radius=radius, fill=255)
    return m

def thick_line(d, p1, p2, width, fill):
    d.line([p1, p2], fill=fill, width=int(width))
    r = width / 2
    for (x, y) in (p1, p2):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

def render(px, simplified=False):
    tiny = px <= 32
    S = 4                       # supersampling
    N = 1024 * S
    k = N / 1024                # 1024-grid → canvas
    g = lambda v: v * k

    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # macOS icon grid: 824×824 body, centred, soft shadow beneath
    body = (g(100), g(100), g(924), g(924))
    radius = g(186)
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((body[0], body[1] + g(10), body[2], body[3] + g(10)), radius=radius, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(g(14)))
    canvas.alpha_composite(shadow)

    # Navy body with a gentle top-to-bottom light falloff
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    for y in range(N):
        t = y / (N - 1)
        c = tuple(int(NAVY_TOP[i] + (NAVY_BOTTOM[i] - NAVY_TOP[i]) * t) for i in range(3))
        gd.line([(0, y), (N, y)], fill=c + (255,))
    mask = squircle_mask(N, body, radius)
    canvas.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(canvas)
    thick = 2.3 if tiny else (1.55 if simplified else 1.0)
    xs = [g(312), g(512), g(712)]
    ys = [g(300), g(512), g(724)]
    top, bottom = g(236), g(792)

    # Ledgers (horizontal tubes)
    for y in ys:
        d.rectangle([xs[0], y - g(12) * thick, xs[2], y + g(12) * thick], fill=STEEL)
        if not simplified:   # underside shade: reads as round tube
            d.rectangle([xs[0], y + g(5), xs[2], y + g(12)], fill=STEEL_SHADE)
    # Standards (vertical tubes) with base plates
    for x in xs:
        d.rectangle([x - g(16) * thick, top, x + g(16) * thick, bottom], fill=STEEL)
        if not simplified:   # right-hand shade
            d.rectangle([x + g(8), top, x + g(16), bottom], fill=STEEL_SHADE)
        if not simplified:
            d.rounded_rectangle([x - g(46), bottom, x + g(46), bottom + g(16)], radius=g(4), fill=STEEL_SHADE)

    # The one bold element: a safety-yellow diagonal brace, rising left → right
    p1, p2 = (xs[0], ys[2]), (xs[2], ys[0])
    thick_line(d, p1, p2, g(38) * thick + g(6), YELLOW_EDGE)
    thick_line(d, p1, p2, g(38) * thick, YELLOW)

    # Rosettes at every joint (the system-scaffold connector) — left out
    # at 16/32 px, where they'd clog into a blob.
    for x in (xs if not tiny else []):
        for y in ys:
            R = g(34) * (1.35 if simplified else 1.0)
            d.ellipse([x - R, y - R, x + R, y + R], fill=STEEL)
            if not simplified:
                d.ellipse([x - R, y - R, x + R, y + R], outline=STEEL_SHADE, width=int(g(3)))
                for a in (45, 135, 225, 315):          # the rosette's slots
                    cx = x + math.cos(math.radians(a)) * g(22)
                    cy = y + math.sin(math.radians(a)) * g(22)
                    r = g(5.5)
                    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SLOT)
                t = g(12)                               # the tube through the centre
                d.ellipse([x - t, y - t, x + t, y + t], fill=STEEL_SHADE)

    # Subtle top sheen, clipped to the body
    sheen = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle(body, radius=radius, outline=(255, 255, 255, 38), width=int(g(3)))
    canvas.alpha_composite(sheen)

    return canvas.resize((px, px), Image.LANCZOS)

if __name__ == "__main__":
    import os
    os.makedirs("AppIcon.iconset", exist_ok=True)
    spec = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    for base, scale in spec:
        px = base * scale
        img = render(px, simplified=px <= 64)
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        img.save(f"AppIcon.iconset/{name}")
    render(1024).save("AppIcon-1024.png")
    print("rendered")
