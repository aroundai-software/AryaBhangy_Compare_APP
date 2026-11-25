"""Professional client confirmation deck — VAS unchanged, new Items column."""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path(
    r"C:\Users\admin\.cursor\projects\c-Users-admin-Documents-Manu-Projects-Aryabhabgy-Tracksheet\assets"
)

OUT = ROOT / "docs" / "Aryabhangy_tracksheet_process.pptx"
OUT_ALT = ROOT / "docs" / "Aryabhangy_tracksheet_process_v2.pptx"

TALLY = ASSETS / (
    "c__Users_admin_AppData_Roaming_Cursor_User_workspaceStorage_"
    "d727a51e1264ad36bc849679045e9279_images_image-ed3c928d-feb4-468c-a3fb-eba8a007038e.png"
)
TRACK_BEFORE = ASSETS / (
    "c__Users_admin_AppData_Roaming_Cursor_User_workspaceStorage_"
    "d727a51e1264ad36bc849679045e9279_images_image-cb8a77e5-4b33-443c-858c-c74889b57fe6.png"
)
TRACK_AFTER = ASSETS / "tracksheet-after-items-column.png"

NAVY = RGBColor(0x14, 0x2A, 0x24)
GREEN = RGBColor(0x1F, 0x4D, 0x3A)
GREEN_SOFT = RGBColor(0xE8, 0xF0, 0xEC)
INK = RGBColor(0x1A, 0x1A, 0x1A)
MUTED = RGBColor(0x5C, 0x5C, 0x5C)
LINE = RGBColor(0xD9, 0xD9, 0xD9)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
SOFT = RGBColor(0xF5, 0xF6, 0xF5)
AMBER_BG = RGBColor(0xFD, 0xF6, 0xEB)
AMBER = RGBColor(0x8A, 0x5A, 0x00)
RED_BG = RGBColor(0xFB, 0xEE, 0xEE)
RED = RGBColor(0x8B, 0x1E, 0x1E)

W = Inches(13.333)
H = Inches(7.5)
MARGIN = Inches(0.7)
TOTAL = 7


def _run(p, text, *, size=14, bold=False, color=INK):
    run = p.add_run()
    run.text = text
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = "Calibri"
    return run


def _fill(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()


def _stroke(shape, color, pt=1):
    shape.line.color.rgb = color
    shape.line.width = Pt(pt)


def _set_text(shape, lines, *, size=14, bold=False, color=INK, align=PP_ALIGN.LEFT):
    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    for i, line in enumerate(lines if isinstance(lines, list) else str(lines).split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        _run(p, line, size=size, bold=bold, color=color)


def _multi(shape, blocks):
    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    first = True
    for text, size, bold, color in blocks:
        for line in str(text).split("\n"):
            p = tf.paragraphs[0] if first else tf.add_paragraph()
            first = False
            p.alignment = PP_ALIGN.LEFT
            _run(p, line, size=size, bold=bold, color=color)


def _bar(slide):
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, Inches(0.08))
    _fill(shape, GREEN)


def _footer(slide, page):
    line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, MARGIN, Inches(7.15), Inches(11.9), Pt(1))
    _fill(line, LINE)
    left = slide.shapes.add_textbox(MARGIN, Inches(7.22), Inches(8), Inches(0.25))
    _set_text(left, ["Aryabhangy Motors  ·  Client confirmation  ·  Confidential"], size=10, color=MUTED)
    right = slide.shapes.add_textbox(Inches(10.5), Inches(7.22), Inches(2.1), Inches(0.25))
    _set_text(right, [f"{page} / {TOTAL}"], size=10, color=MUTED, align=PP_ALIGN.RIGHT)


def _header(slide, eyebrow, title, subtitle=None):
    _bar(slide)
    eye = slide.shapes.add_textbox(MARGIN, Inches(0.28), Inches(12), Inches(0.28))
    _set_text(eye, [eyebrow.upper()], size=11, bold=True, color=GREEN)
    ttl = slide.shapes.add_textbox(MARGIN, Inches(0.55), Inches(12), Inches(0.45))
    _set_text(ttl, [title], size=26, bold=True, color=NAVY)
    if subtitle:
        sub = slide.shapes.add_textbox(MARGIN, Inches(1.05), Inches(12), Inches(0.35))
        _set_text(sub, [subtitle], size=13, color=MUTED)
        return Inches(1.5)
    return Inches(1.2)


def _card(slide, left, top, width, height, *, fill=WHITE, border=LINE):
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    shape.adjustments[0] = 0.06
    _fill(shape, fill)
    _stroke(shape, border, 1)
    return shape


def build():
    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H

    # 1 Cover
    s = prs.slides.add_slide(prs.slide_layouts[6])
    bg = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H)
    _fill(bg, NAVY)
    accent = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(0.18), H)
    _fill(accent, GREEN)
    brand = s.shapes.add_textbox(Inches(0.9), Inches(1.8), Inches(11), Inches(0.4))
    _set_text(brand, ["ARYABHANGY MOTORS"], size=14, bold=True, color=RGBColor(0xA8, 0xC5, 0xB8))
    title = s.shapes.add_textbox(Inches(0.9), Inches(2.3), Inches(11), Inches(1.3))
    _multi(
        title,
        [
            ("Tracksheet update from Tally", 36, True, WHITE),
            ("", 8, False, WHITE),
            ("Confirm VAS, new Items column, and full Bill Number", 18, False, RGBColor(0xC8, 0xD5, 0xCF)),
        ],
    )
    meta = s.shapes.add_textbox(Inches(0.9), Inches(4.5), Inches(11), Inches(1.4))
    _multi(
        meta,
        [
            ("Reference job", 11, True, RGBColor(0xA8, 0xC5, 0xB8)),
            ("JC 007194   ·   SANEESH KUMAR P V   ·   KL41W6899", 16, False, WHITE),
            ("Hirise Invoice Service  KL10000126006400", 16, False, WHITE),
            ("", 8, False, WHITE),
            ("For client review and sign-off", 12, False, RGBColor(0x9A, 0xB0, 0xA8)),
        ],
    )
    page = s.shapes.add_textbox(Inches(11.5), Inches(7.1), Inches(1.2), Inches(0.25))
    _set_text(page, ["1 / 7"], size=10, color=RGBColor(0x8A, 0xA0, 0x98), align=PP_ALIGN.RIGHT)

    # 2 Proposal
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H), SOFT)
    top = _header(
        s,
        "Proposal",
        "What we are asking you to confirm",
        "Three Tracksheet fields — VAS stays services-only; invoice lines go to a new Items column.",
    )
    cards = [
        (
            MARGIN,
            "VAS",
            "Keep as today",
            "Leave VAS as the service value already entered.\n\n"
            "Today / proposed:\nChain Lube\n\n"
            "Do not move spare-part names into VAS.",
        ),
        (
            Inches(4.75),
            "ITEMS  (new)",
            "List all invoice lines",
            "Add a new Items column on Tracksheet.\n\n"
            "ENGINE OIL 1\nCONSUMABLES CON-01\nO RING DS-5058\nFILTER COMP ENGINE\n"
            "ELEMENT COMP AIR/C\nPLUGSPARK\nWASHER 12MM DRAIN\nCHAIN LUBRICATION",
        ),
        (
            Inches(8.85),
            "BILL #",
            "Full voucher number",
            "Store the full Hirise voucher on BILL #.\n\n"
            "Today: 6400\nProposed: KL10000126006400\n\n"
            "Last 4 digits can still be used to match Tally ↔ Tracksheet.",
        ),
    ]
    for left, label, headline, body in cards:
        _card(s, left, top, Inches(3.85), Inches(4.7))
        strip = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, Inches(3.85), Inches(0.1))
        _fill(strip, GREEN)
        box = s.shapes.add_textbox(left + Inches(0.25), top + Inches(0.35), Inches(3.35), Inches(4.15))
        _multi(
            box,
            [
                (label, 12, True, GREEN),
                ("", 6, False, INK),
                (headline, 18, True, NAVY),
                ("", 8, False, INK),
                (body, 13, False, INK),
            ],
        )
    _footer(s, 2)

    # 3 Tally
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H), SOFT)
    _header(s, "Evidence — Tally", "Hirise Invoice Service voucher", "Source of the item list and the full voucher number.")
    if TALLY.exists():
        s.shapes.add_picture(str(TALLY), MARGIN, Inches(1.45), height=Inches(5.35))
    _card(s, Inches(8.55), Inches(1.45), Inches(4.1), Inches(5.35))
    strip = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(8.55), Inches(1.45), Inches(4.1), Inches(0.08))
    _fill(strip, GREEN)
    side = s.shapes.add_textbox(Inches(8.8), Inches(1.75), Inches(3.6), Inches(4.8))
    _multi(
        side,
        [
            ("From this voucher", 11, True, GREEN),
            ("", 6, False, INK),
            ("Voucher", 11, True, MUTED),
            ("KL10000126006400", 14, True, NAVY),
            ("", 8, False, INK),
            ("Job card", 11, True, MUTED),
            ("007194", 14, False, INK),
            ("", 8, False, INK),
            ("Vehicle", 11, True, MUTED),
            ("KL 41W 6899", 14, False, INK),
            ("", 8, False, INK),
            ("Goes to Items column", 11, True, MUTED),
            ("7 inventory lines", 13, False, INK),
            ("+ Chain Lubrication", 13, False, INK),
            ("", 10, False, INK),
            ("Goes to BILL #", 11, True, MUTED),
            ("Full voucher number", 13, False, INK),
            ("", 10, False, INK),
            ("VAS unchanged", 11, True, MUTED),
            ("Chain Lube remains in VAS", 13, False, INK),
        ],
    )
    _footer(s, 3)

    # 4 Before
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H), SOFT)
    _header(s, "Evidence — Tracksheet today", "Current Job Card entry", "No Items column yet. Bill shows last 4 only. VAS already has Chain Lube.")
    if TRACK_BEFORE.exists():
        _card(s, MARGIN, Inches(1.4), Inches(11.95), Inches(4.85))
        s.shapes.add_picture(str(TRACK_BEFORE), Inches(0.85), Inches(1.55), width=Inches(11.65))
    _card(s, MARGIN, Inches(6.35), Inches(11.95), Inches(0.65), fill=RED_BG, border=RGBColor(0xE8, 0xC4, 0xC4))
    note = s.shapes.add_textbox(Inches(0.95), Inches(6.48), Inches(11.4), Inches(0.4))
    _set_text(
        note,
        ["Gap:  No Items column for the 7+ invoice lines.   BILL # = 6400 only.   VAS = Chain Lube (keep)."],
        size=13,
        bold=True,
        color=RED,
    )
    _footer(s, 4)

    # 5 After
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H), SOFT)
    _header(
        s,
        "Proposed result",
        "How the Tracksheet row should look",
        "VAS unchanged. New Items column holds invoice lines. BILL # holds full voucher.",
    )
    if TRACK_AFTER.exists():
        _card(s, MARGIN, Inches(1.4), Inches(11.95), Inches(4.85))
        s.shapes.add_picture(str(TRACK_AFTER), Inches(0.85), Inches(1.55), width=Inches(11.65))
    _card(s, MARGIN, Inches(6.35), Inches(11.95), Inches(0.65), fill=GREEN_SOFT, border=RGBColor(0xC5, 0xD8, 0xCE))
    note = s.shapes.add_textbox(Inches(0.95), Inches(6.48), Inches(11.4), Inches(0.4))
    _set_text(
        note,
        ["Confirm:  VAS = Chain Lube.   ITEMS = all invoice lines.   BILL # = KL10000126006400."],
        size=13,
        bold=True,
        color=GREEN,
    )
    _footer(s, 5)

    # 6 Table
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H), SOFT)
    _header(s, "Rule summary", "Before → After (this job card)", "Please verify each row.")
    headers = ["Field", "Today on Tracksheet", "Proposed value"]
    rows = [
        ("VAS", "Chain Lube", "Chain Lube  (unchanged)"),
        ("ITEMS", "—  (column does not exist)", "All Hirise invoice lines\n(7 parts + Chain Lubrication)"),
        ("BILL #", "6400", "KL10000126006400"),
        ("Labour", "259", "No change"),
        ("Spares", "1,293", "No change"),
    ]
    y0 = Inches(1.5)
    col_x = [MARGIN, Inches(3.0), Inches(7.3)]
    col_w = [Inches(2.2), Inches(4.1), Inches(5.05)]
    head = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, MARGIN, y0, Inches(11.95), Inches(0.48))
    _fill(head, NAVY)
    for i, htxt in enumerate(headers):
        cell = s.shapes.add_textbox(col_x[i] + Inches(0.15), y0 + Inches(0.1), col_w[i] - Inches(0.2), Inches(0.3))
        _set_text(cell, [htxt], size=12, bold=True, color=WHITE)
    y = y0 + Inches(0.48)
    for idx, (a, b, c) in enumerate(rows):
        row_h = Inches(0.9)
        band = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, MARGIN, y, Inches(11.95), row_h)
        _fill(band, WHITE if idx % 2 == 0 else GREEN_SOFT)
        ln = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, MARGIN, y + row_h - Pt(1), Inches(11.95), Pt(1))
        _fill(ln, LINE)
        for i, val in enumerate((a, b, c)):
            cell = s.shapes.add_textbox(
                col_x[i] + Inches(0.15), y + Inches(0.15), col_w[i] - Inches(0.25), row_h - Inches(0.2)
            )
            _set_text(cell, val.split("\n"), size=13, bold=(i == 0), color=NAVY if i == 0 else INK)
        y += row_h
    _footer(s, 6)

    # 7 Sign-off
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, W, H), SOFT)
    _header(s, "Sign-off", "Is this the correct business rule?", "Please choose one option and return this slide.")
    _card(s, MARGIN, Inches(1.55), Inches(5.85), Inches(3.15))
    _card(s, Inches(6.85), Inches(1.55), Inches(5.85), Inches(3.15))
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, MARGIN, Inches(1.55), Inches(5.85), Inches(0.1)), GREEN)
    _fill(s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(6.85), Inches(1.55), Inches(5.85), Inches(0.1)), RED)
    yes = s.shapes.add_textbox(Inches(1.0), Inches(1.9), Inches(5.2), Inches(2.5))
    _multi(
        yes,
        [
            ("YES — proceed", 20, True, GREEN),
            ("", 8, False, INK),
            ("VAS stays as services (e.g. Chain Lube).", 14, False, INK),
            ("New Items column receives all invoice lines.", 14, False, INK),
            ("BILL # stores the full voucher number.", 14, False, INK),
            ("", 10, False, INK),
            ("Approved by: _______________________", 13, False, MUTED),
            ("Date: _______________", 13, False, MUTED),
        ],
    )
    no = s.shapes.add_textbox(Inches(7.15), Inches(1.9), Inches(5.2), Inches(2.5))
    _multi(
        no,
        [
            ("NO — revise", 20, True, RED),
            ("", 8, False, INK),
            ("Tell us what should differ, for example:", 14, False, INK),
            ("• Items should use another field name", 14, False, INK),
            ("• BILL # must stay last 4 only", 14, False, INK),
            ("• Chain Lubrication should not repeat in Items", 14, False, INK),
            ("", 10, False, INK),
            ("Notes: _____________________________", 13, False, MUTED),
        ],
    )
    _card(s, MARGIN, Inches(5.0), Inches(11.95), Inches(1.7), fill=AMBER_BG, border=RGBColor(0xE8, 0xD5, 0xB0))
    tip = s.shapes.add_textbox(Inches(0.95), Inches(5.2), Inches(11.4), Inches(1.35))
    _multi(
        tip,
        [
            ("Clarification already applied in this version", 12, True, AMBER),
            (
                "Spare and consumable names from Tally are proposed for a new Items column — "
                "not for VAS. VAS remains the service field (Chain Lube on this example). "
                "Labour and Spares amounts on this card stay unchanged.",
                14,
                False,
                INK,
            ),
        ],
    )
    _footer(s, 7)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    try:
        prs.save(OUT)
        print(OUT)
    except PermissionError:
        prs.save(OUT_ALT)
        print(OUT_ALT)


if __name__ == "__main__":
    build()
