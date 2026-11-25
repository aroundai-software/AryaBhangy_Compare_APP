"""Client confirmation deck: proposed Tracksheet update (not app how-to)."""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path(
    r"C:\Users\admin\.cursor\projects\c-Users-admin-Documents-Manu-Projects-Aryabhabgy-Tracksheet\assets"
)
OUT = ROOT / "docs" / "Aryabhangy_Client_Confirm_VAS_Bill.pptx"
OUT_ALT = ROOT / "docs" / "Aryabhangy_Client_Confirm_VAS_Bill_v2.pptx"

TALLY = ASSETS / (
    "c__Users_admin_AppData_Roaming_Cursor_User_workspaceStorage_"
    "d727a51e1264ad36bc849679045e9279_images_image-ed3c928d-feb4-468c-a3fb-eba8a007038e.png"
)
TRACK_BEFORE = ASSETS / (
    "c__Users_admin_AppData_Roaming_Cursor_User_workspaceStorage_"
    "d727a51e1264ad36bc849679045e9279_images_image-cb8a77e5-4b33-443c-858c-c74889b57fe6.png"
)
TRACK_AFTER = ASSETS / "tracksheet-after-vas-bill.jpg"
if not TRACK_AFTER.exists():
    TRACK_AFTER = ASSETS / "tracksheet-after-007194-v2.jpg"

GREEN = RGBColor(0x1F, 0x4D, 0x3A)
INK = RGBColor(0x1C, 0x19, 0x17)
MUTED = RGBColor(0x57, 0x53, 0x4E)
CREAM = RGBColor(0xF7, 0xF4, 0xEE)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
RED = RGBColor(0x9B, 0x2C, 0x2C)


def _set_run(run, text, size=18, bold=False, color=INK):
    run.text = text
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = "Calibri"


def _fill(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()


def _add_title(slide, text, top=0.35, size=28):
    box = slide.shapes.add_textbox(Inches(0.5), Inches(top), Inches(12.3), Inches(0.65))
    tf = box.text_frame
    tf.clear()
    run = tf.paragraphs[0].add_run()
    _set_run(run, text, size=size, bold=True, color=GREEN)
    return box


def _add_body(slide, text, left, top, width, height, size=16, bold=False, color=INK):
    box = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
    tf = box.text_frame
    tf.word_wrap = True
    tf.clear()
    for i, line in enumerate(text.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        run = p.add_run()
        _set_run(run, line, size=size, bold=bold, color=color)
    return box


def _bg(slide):
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(13.333), Inches(7.5))
    _fill(shape, CREAM)
    sp_tree = slide.shapes._spTree
    sp = shape._element
    sp_tree.remove(sp)
    sp_tree.insert(2, sp)


def build():
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    # 1 — Purpose
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "Please confirm — Tracksheet update from Tally", 2.0, 34)
    _add_body(
        s,
        "Example job: JC 007194  ·  SANEESH KUMAR P V  ·  KL41W6899\n"
        "Hirise voucher: KL10000126006400\n\n"
        "This deck is only to confirm what should be written on the Tracksheet.\n"
        "It is not a product demo of the compare app.",
        0.8,
        3.0,
        11.5,
        2.5,
        size=20,
        color=MUTED,
    )

    # 2 — What we understood
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "What we understood you want")
    _add_body(
        s,
        "When the same job exists in Tally and on the Tracksheet:",
        0.5,
        1.2,
        12,
        0.5,
        size=18,
    )
    items = [
        ("1. VAS field", "Put every item from the Hirise invoice line list into Tracksheet VAS\n"
         "(the 7 parts + Chain Lubrication). Today only “Chain Lube” is there."),
        ("2. BILL # field", "Put the full Hirise voucher number on Tracksheet BILL #\n"
         "(KL10000126006400). Today only the last 4 digits are stored (6400)."),
        ("3. Not changing here", "Labour and Spares amounts are already filled on this example card.\n"
         "We are not proposing to change those on this card."),
    ]
    y = 1.9
    for title, body in items:
        shape = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.5), Inches(y), Inches(12.3), Inches(1.5))
        _fill(shape, WHITE)
        shape.line.color.rgb = RGBColor(0xD6, 0xD3, 0xD1)
        _add_body(s, title, 0.75, y + 0.2, 11.8, 0.4, size=18, bold=True, color=GREEN)
        _add_body(s, body, 0.75, y + 0.65, 11.8, 0.7, size=16)
        y += 1.7

    # 3 — Tally source
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "From Tally (source of truth for the bill)")
    if TALLY.exists():
        s.shapes.add_picture(str(TALLY), Inches(0.35), Inches(1.1), height=Inches(5.95))
    panel = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(8.7), Inches(1.2), Inches(4.2), Inches(5.6))
    _fill(panel, WHITE)
    panel.line.color.rgb = GREEN
    _add_body(s, "On this voucher", 8.9, 1.4, 3.8, 0.4, size=18, bold=True, color=GREEN)
    _add_body(
        s,
        "Full voucher no.\nKL10000126006400\n\n"
        "Items on the bill:\n"
        "1. ENGINE OIL 1\n"
        "2. CONSUMABLES CON-01\n"
        "3. O RING DS-5058\n"
        "4. FILTER COMP ENGINE\n"
        "5. ELEMENT COMP AIR/C\n"
        "6. PLUGSPARK\n"
        "7. WASHER 12MM DRAIN\n"
        "8. CHAIN LUBRICATION\n\n"
        "Linked JC: 007194",
        8.9,
        1.95,
        3.8,
        4.6,
        size=14,
    )

    # 4 — Tracksheet today
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "Tracksheet today (before)")
    if TRACK_BEFORE.exists():
        s.shapes.add_picture(str(TRACK_BEFORE), Inches(0.35), Inches(1.1), width=Inches(12.6))
    badge = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.5), Inches(6.55), Inches(12.3), Inches(0.7))
    _fill(badge, RGBColor(0xFD, 0xEC, 0xEC))
    _add_body(
        s,
        "VAS = Chain Lube only.   BILL # = 6400 only.   The other 7 invoice items are not on the Tracksheet.",
        0.7,
        6.65,
        12,
        0.5,
        size=16,
        bold=True,
        color=RED,
    )

    # 5 — Proposed after
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "Proposed Tracksheet after (for your confirmation)")
    if TRACK_AFTER.exists():
        s.shapes.add_picture(str(TRACK_AFTER), Inches(0.45), Inches(1.05), width=Inches(12.4))
    badge = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.5), Inches(6.55), Inches(12.3), Inches(0.7))
    _fill(badge, RGBColor(0xE7, 0xF5, 0xEE))
    _add_body(
        s,
        "VAS column shows all invoice items.   BILL # column shows full voucher KL10000126006400.",
        0.7,
        6.65,
        12,
        0.5,
        size=16,
        bold=True,
        color=GREEN,
    )

    # 6 — Confirm checklist
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "Please confirm")
    _add_body(
        s,
        "Kindly tick / reply against each point so we build the right behaviour.",
        0.5,
        1.15,
        12,
        0.45,
        size=16,
        color=MUTED,
    )
    checks = [
        "VAS on Tracksheet should list all Hirise invoice items (parts + Chain Lube), not only Chain Lube.",
        "BILL # on Tracksheet should store the full voucher number (KL…6400), not only the last 4 digits.",
        "Last 4 digits can still be used to recognise that Tracksheet 6400 = Tally KL…6400.",
        "Spare part names belong in the VAS field (even though they are inventory lines in Tally).",
        "For this example, Labour / Spares amounts stay as already entered; no change required.",
        "Same rule should apply to other job cards when Tally has items missing on Tracksheet VAS / bill.",
    ]
    y = 1.75
    for text in checks:
        shape = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.5), Inches(y), Inches(12.3), Inches(0.75))
        _fill(shape, WHITE)
        shape.line.color.rgb = RGBColor(0xD6, 0xD3, 0xD1)
        box = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.7), Inches(y + 0.18), Inches(0.4), Inches(0.4))
        _fill(box, CREAM)
        box.line.color.rgb = GREEN
        _add_body(s, text, 1.35, y + 0.15, 11.2, 0.55, size=15)
        y += 0.85

    # 7 — Decision
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _add_title(s, "Decision needed", 2.2, 32)
    _add_body(
        s,
        "Is the “after” picture correct for what should happen on the Tracksheet?\n\n"
        "Yes — proceed with this rule\n"
        "or\n"
        "No — tell us what should differ (e.g. parts stay only in Spares amount,\n"
        "VAS stays services-only, bill stays last 4 only, etc.)",
        0.8,
        3.1,
        11.5,
        3.0,
        size=20,
        color=INK,
    )

    try:
        prs.save(OUT)
        print(OUT)
    except PermissionError:
        prs.save(OUT_ALT)
        print(OUT_ALT)


if __name__ == "__main__":
    build()
