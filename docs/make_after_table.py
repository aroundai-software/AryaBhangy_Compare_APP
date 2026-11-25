"""Render an accurate after-state Tracksheet row for the client PPT."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(
    r"C:\Users\admin\.cursor\projects\c-Users-admin-Documents-Manu-Projects-Aryabhabgy-Tracksheet"
    r"\assets\tracksheet-after-items-column.png"
)

W, H = 1600, 720
GREEN = (31, 77, 58)
GREEN_SOFT = (232, 240, 236)
HEADER_BG = (245, 246, 245)
LINE = (217, 217, 217)
INK = (26, 26, 26)
MUTED = (92, 92, 92)
WHITE = (255, 255, 255)
NAVY = (20, 42, 36)


def font(size, bold=False):
    candidates = [
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\calibrib.ttf" if bold else r"C:\Windows\Fonts\calibri.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    img = Image.new("RGB", (W, H), WHITE)
    draw = ImageDraw.Draw(img)

    # App chrome
    draw.rectangle((0, 0, W, 72), fill=GREEN)
    draw.text((28, 20), "Arya Bhangy Tracksheet", fill=WHITE, font=font(28, True))
    draw.text((28, 88), "Proposed Job Card after update   ·   JC 007194", fill=MUTED, font=font(16))

    # Table geometry
    left, top = 28, 130
    row_top = top + 52
    row_h = 420
    cols = [
        ("JC", 110, "007194"),
        ("DATE", 110, "09/11/26"),
        ("REG", 150, "KL41W6899"),
        ("VAS", 150, "Chain Lube"),
        ("ITEMS", 520, None),  # multi-line
        ("BILL #", 260, "KL10000126006400"),
        ("LABOUR", 110, "259"),
        ("SPARES", 120, "1,293"),
    ]
    # Fit widths into remaining space
    total_w = W - left * 2
    # Use defined widths scaled if needed
    widths = [c[1] for c in cols]
    scale = total_w / sum(widths)
    widths = [int(w * scale) for w in widths]
    # fix rounding
    widths[-1] += total_w - sum(widths)

    # Header
    x = left
    draw.rectangle((left, top, left + total_w, row_top), fill=HEADER_BG)
    draw.line((left, top, left + total_w, top), fill=LINE, width=1)
    for (name, _, _), width in zip(cols, widths):
        highlight = name in {"ITEMS", "BILL #"}
        if highlight:
            draw.rectangle((x, top, x + width, row_top), fill=GREEN_SOFT)
        draw.text((x + 12, top + 14), name, fill=GREEN if highlight else MUTED, font=font(15, True))
        draw.line((x, top, x, row_top + row_h), fill=LINE, width=1)
        x += width
    draw.line((left + total_w, top, left + total_w, row_top + row_h), fill=LINE, width=1)
    draw.line((left, row_top, left + total_w, row_top), fill=LINE, width=1)

    # Body row background
    draw.rectangle((left, row_top, left + total_w, row_top + row_h), fill=WHITE)

    items = [
        "ENGINE OIL 1",
        "CONSUMABLES CON-01",
        "O RING DS-5058",
        "FILTER COMP ENGINE",
        "ELEMENT COMP AIR/C",
        "PLUGSPARK",
        "WASHER 12MM DRAIN",
        "CHAIN LUBRICATION",
    ]

    x = left
    for (name, _, value), width in zip(cols, widths):
        if name == "ITEMS":
            draw.rectangle((x, row_top, x + width, row_top + row_h), fill=GREEN_SOFT)
            yy = row_top + 18
            for item in items:
                draw.text((x + 14, yy), "•  " + item, fill=INK, font=font(16))
                yy += 36
        elif name == "BILL #":
            draw.rectangle((x, row_top, x + width, row_top + row_h), fill=GREEN_SOFT)
            draw.text((x + 12, row_top + 18), value, fill=NAVY, font=font(15, True))
        elif name == "VAS":
            draw.text((x + 12, row_top + 18), value, fill=INK, font=font(16))
            draw.text((x + 12, row_top + 48), "(unchanged)", fill=MUTED, font=font(13))
        else:
            draw.text((x + 12, row_top + 18), value, fill=INK, font=font(16))
        x += width

    draw.line((left, row_top + row_h, left + total_w, row_top + row_h), fill=LINE, width=1)

    # Caption
    draw.rounded_rectangle((left, row_top + row_h + 24, left + total_w, H - 28), radius=10, fill=GREEN_SOFT)
    draw.text(
        (left + 20, row_top + row_h + 42),
        "VAS stays as before (Chain Lube).   New ITEMS column lists all invoice lines.   BILL # shows full voucher.",
        fill=GREEN,
        font=font(16, True),
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()
