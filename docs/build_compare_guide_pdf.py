"""Build the Aryabhangy Compare user guide PDF."""

from pathlib import Path

from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

FONT_DIR = Path(r"C:\Windows\Fonts")
pdfmetrics.registerFont(TTFont("TimesNewRoman", str(FONT_DIR / "times.ttf")))
pdfmetrics.registerFont(TTFont("TimesNewRoman-Bold", str(FONT_DIR / "timesbd.ttf")))
pdfmetrics.registerFontFamily(
    "TimesNewRoman",
    normal="TimesNewRoman",
    bold="TimesNewRoman-Bold",
    italic="TimesNewRoman",
    boldItalic="TimesNewRoman-Bold",
)

OUT = Path(__file__).resolve().parent / "Aryabhangy_Compare_Guide_1.0.1.pdf"

PAGE_W, PAGE_H = A4
LEFT = 20 * mm
RIGHT = 20 * mm
TOP = 18 * mm
BOTTOM = 16 * mm
CONTENT_W = PAGE_W - LEFT - RIGHT


def styles():
    base = dict(fontName="TimesNewRoman", textColor="black", alignment=TA_LEFT)
    return {
        "title": ParagraphStyle(
            "title",
            fontName="TimesNewRoman-Bold",
            fontSize=14,
            leading=18,
            alignment=TA_CENTER,
            textColor="black",
            spaceAfter=2,
        ),
        "version": ParagraphStyle(
            "version",
            fontName="TimesNewRoman",
            fontSize=12,
            leading=16,
            alignment=TA_CENTER,
            textColor="black",
            spaceAfter=12,
        ),
        "body": ParagraphStyle(
            "body",
            **base,
            fontSize=12,
            leading=16,
            spaceAfter=8,
        ),
        "heading": ParagraphStyle(
            "heading",
            fontName="TimesNewRoman-Bold",
            fontSize=14,
            leading=18,
            textColor="black",
            spaceBefore=12,
            spaceAfter=6,
            keepWithNext=True,
        ),
        "subhead": ParagraphStyle(
            "subhead",
            fontName="TimesNewRoman-Bold",
            fontSize=12,
            leading=16,
            textColor="black",
            spaceBefore=8,
            spaceAfter=4,
            keepWithNext=True,
        ),
        "label": ParagraphStyle(
            "label",
            fontName="TimesNewRoman",
            fontSize=12,
            leading=16,
            alignment=TA_RIGHT,
            textColor="black",
            spaceAfter=0,
        ),
        "item": ParagraphStyle(
            "item",
            **base,
            fontSize=12,
            leading=16,
            spaceAfter=0,
        ),
        "after_list": ParagraphStyle(
            "after_list",
            **base,
            fontSize=12,
            leading=16,
            spaceBefore=6,
            spaceAfter=8,
        ),
        "cell": ParagraphStyle(
            "cell",
            **base,
            fontSize=12,
            leading=15,
            spaceAfter=0,
        ),
        "cell_head": ParagraphStyle(
            "cell_head",
            fontName="TimesNewRoman-Bold",
            fontSize=12,
            leading=15,
            textColor="black",
            spaceAfter=0,
        ),
        "footer": ParagraphStyle(
            "footer",
            fontName="TimesNewRoman",
            fontSize=12,
            leading=14,
            alignment=TA_CENTER,
            textColor="black",
        ),
    }


S = styles()


def P(text, style="body"):
    return Paragraph(text, S[style])


def _label_list(pairs, label_width):
    rows = [[P(label, "label"), P(text, "item")] for label, text in pairs]
    table = Table(rows, colWidths=[label_width, CONTENT_W - label_width])
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (0, 0), (0, -1), "RIGHT"),
                ("LEFTPADDING", (0, 0), (0, -1), 0),
                ("RIGHTPADDING", (0, 0), (0, -1), 6),
                ("LEFTPADDING", (1, 0), (1, -1), 0),
                ("RIGHTPADDING", (1, 0), (1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    return [table]


def numbered(items):
    return _label_list([(f"{number}.", text) for number, text in enumerate(items, start=1)], 8 * mm)


def cards(items):
    return _label_list([("•", text) for text in items], 6 * mm)


def reason_table():
    header = [
        P("Reason", "cell_head"),
        P("What it means", "cell_head"),
        P("What to do", "cell_head"),
    ]
    rows_src = [
        (
            "Vehicle number differs",
            "The job card matches, but the vehicle on the sheet and the vehicle in Tally are different.",
            "Check both numbers. If the Tally side is the right vehicle, click <b>Write this card</b>. The write uses the vehicle already on the Tracksheet and the Hirise bill number.",
        ),
        (
            "In Tally, not on the Tracksheet",
            "Tally has this bill, and the demo has no row for it.",
            "There is no <b>Write</b> button. The app does not create a new job card. Check it on the Tracksheet first.",
        ),
        (
            "Service bill not assigned",
            "A service bill could not be joined to one Hirise bill. That day had no single Hirise bill for this vehicle, or it had two.",
            "Look at the bills in Tally. Write all will not pick one.",
        ),
        (
            "Same job card, two vehicles",
            "One job card number is used for different vehicles.",
            "Check which vehicle is correct before writing.",
        ),
        (
            "Duplicate on the Tracksheet",
            "The same job card and vehicle appear more than once on the demo.",
            "Check the duplicate rows before writing.",
        ),
        (
            "Job card incomplete, or Tally bill incomplete",
            "The bill is missing a job card number or a vehicle number.",
            "Nothing is filled until the missing number is clear.",
        ),
    ]
    data = [header]
    for reason, meaning, action in rows_src:
        data.append([P(reason, "cell"), P(meaning, "cell"), P(action, "cell")])

    reason_w = 38 * mm
    meaning_w = 58 * mm
    action_w = CONTENT_W - reason_w - meaning_w
    table = Table(
        data,
        colWidths=[reason_w, meaning_w, action_w],
        repeatRows=1,
    )
    table.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (-1, 0), "TimesNewRoman-Bold"),
                ("FONTNAME", (0, 1), (-1, -1), "TimesNewRoman"),
                ("FONTSIZE", (0, 0), (-1, -1), 12),
                ("BACKGROUND", (0, 0), (-1, 0), "#F2F2F2"),
                ("TEXTCOLOR", (0, 0), (-1, -1), "black"),
                ("ALIGN", (0, 0), (-1, -1), "LEFT"),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("GRID", (0, 0), (-1, -1), 0.4, "black"),
            ]
        )
    )
    return table


def story():
    flow = [
        P("Aryabhangy Compare and the demo Tracksheet", "title"),
        P("Version 1.0.1", "version"),
        P(
            "Do these steps in this order the first time. After that, Tally’s ODBC setting stays. "
            "Each day, start from “Bring the latest job cards into the demo”."
        ),
        P("1. Turn on Tally’s ODBC connection", "heading"),
        P("The app reads bills from Tally on this computer. Tally must allow that connection."),
        *numbered(
            [
                "Open Tally and load the company.",
                "Open <b>Settings</b>, then <b>Connectivity</b>.",
                "Set <b>Tally is acting as</b> to <b>Both</b>.",
                "Set <b>ODBC</b> to <b>Yes</b>.",
                "Note the port number. The usual number is <b>9000</b>. Use the number shown on that screen.",
                "Accept the settings.",
                "Close Tally completely and open it again. Load the same company.",
            ]
        ),
        P("Leave that company open while you compare.", "after_list"),
        P("2. Bring the latest job cards into the demo Tracksheet", "heading"),
        P(
            "The app writes only to the demo Tracksheet. Do this before every compare, so the demo "
            "has the latest job cards from the original Tracksheet."
        ),
        *numbered(
            [
                "Open the demo Tracksheet in the browser: https://aryabhangytracksheetdemo.vercel.app/",
                "Click <b>Get new job cards</b>.",
                "Wait until the new job cards have come in.",
                "Leave the site open if you want to check a card after writing.",
            ]
        ),
        Spacer(1, 6),
        P("3. Set up the app", "heading"),
        P("Open <b>Aryabhangy Compare</b>. Go to <b>Settings</b>."),
        *numbered(
            [
                "<b>Tally port.</b> Type the same port number you set in Tally. If Tally shows 9000, type 9000.",
                "<b>Website.</b> Type the demo Tracksheet address: https://aryabhangytracksheetdemo.vercel.app/",
                "Turn on <b>Allow saving on the Tracksheet</b>. Write stays off until this switch is on. "
                "Saving fills Bill #, Labour, Spares, Total, VAS, and Items on the demo. "
                "The original Tracksheet is left as it is.",
                "Click <b>Check connection</b>. Tally should show online, with the company name that is open. "
                "The website should answer.",
                "Click <b>Select voucher types</b>. Tick <b>Hirise Invoice Service</b>. That is the job-card bill. "
                "Also tick the service bills for this company, then click <b>Save</b>. "
                "The saved names appear under the field.",
            ]
        ),
        P(
            "The port, the website, and Allow saving stay as you set them. The voucher-type list is saved "
            "once for the company that is open. Compare stays off until that list is saved. When you open "
            "another company in Tally, open Settings again and save the list once for that company.",
            "after_list",
        ),
        P("4. Run a compare", "heading"),
        P("Go to the home page. Tally must still be open on the same company."),
        *numbered(
            [
                "<b>Branch.</b> Choose the branch that matches the company open in Tally.",
                "<b>From</b> and <b>To.</b> Choose the date range.",
                "Click <b>Run compare</b>. Wait until it finishes. If Tally shows Not responding, wait. "
                "Do not close Tally, and do not start a second compare.",
            ]
        ),
        P("When it finishes you see four cards:", "after_list"),
        *cards(
            [
                "<b>Added to track.</b> The job card and the vehicle match, and at least one of Bill #, "
                "Labour, Spares, Total, VAS, or Items is different. These rows are ready to write. "
                "The figures shown are from Tally.",
                "<b>No change.</b> Bill #, Labour, Spares, Total, VAS, and Items already match. "
                "Leave these rows as they are.",
                "<b>Removed from sheet.</b> The Tracksheet has that job card in these dates, and Tally "
                "did not return a matching bill. Nothing is deleted.",
                "<b>Check manually.</b> The app will not decide. Open these and look at them.",
            ]
        ),
        P("Click a card to open that list.", "after_list"),
        P("What a written row contains", "subhead"),
        P(
            "Bill # is the last 4 digits of the Hirise bill. Example: bill KL10000126005973 is written as 5973. "
            "A service bill number is not written into Bill #."
        ),
        P(
            "Labour and Spares are the amounts before GST. Total is the amount with GST. A ticked service bill "
            "for the same vehicle on the same day is added into that job: its charge goes into Labour, its name "
            "into VAS, and its total into Total."
        ),
        P("5. Write the result to the demo", "heading"),
        P("Write every Added row", "subhead"),
        P(
            "On the finished compare, click <b>Write all</b>. The number on the button is how many Added rows "
            "will be written. Each of those rows must have a job card, and it must not already say Saved."
        ),
        P("Write all skips No change, Removed from sheet, and Check manually."),
        P("Write one job card", "subhead"),
        P(
            "Open <b>Added to track</b>. Find the job card. Under the job card number, click <b>Write</b>. "
            "That one card is saved on the demo. The row then shows <b>Saved</b>."
        ),
        KeepTogether(
            [
                P("6. Check manually", "heading"),
                P(
                    "Click <b>Review manual checks</b>, or click the <b>Check manually</b> card. Each row shows the "
                    "Tracksheet on one side and the Tally bill on the other, and a short reason."
                ),
                reason_table(),
            ]
        ),
        Spacer(1, 8),
        P(
            "On a Check row that has a job card, <b>Write this card</b> (or <b>Write Tally values to Tracksheet</b>) "
            "saves that one card. A row marked <b>In Tally, not on the Tracksheet</b> stays on Check manually."
        ),
        P("7. Sync from last", "heading"),
        P(
            "The first compare for a branch is always manual: you choose From and To, then <b>Run compare</b>."
        ),
        P(
            "After that compare is saved, <b>Sync from last</b> continues the same company and the same branch. "
            "It sets From to the day after the last saved To date, and To to today, then runs the compare."
        ),
        P(
            "Example: the last saved Angamally compare ended on 31 Oct. Sync from last reads 1 Nov through today. "
            "It only reads. Click <b>Write all</b>, or <b>Write</b> on one job card, when you want those figures on the demo."
        ),
        P("8. One Tally window", "heading"),
        P(
            "While the app is in use, keep one Tally window open, with the company loaded. Close any other "
            "Tally window on this computer before <b>Check connection</b>, <b>Run compare</b>, or <b>Sync from last</b>."
        ),
    ]
    return flow


def draw_page(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColorRGB(0, 0, 0)
    canvas.setLineWidth(0.4)
    y = 11 * mm
    canvas.line(LEFT, y + 4 * mm, PAGE_W - RIGHT, y + 4 * mm)
    canvas.setFont("TimesNewRoman", 12)
    canvas.drawCentredString(PAGE_W / 2, y, f"{doc.page}")
    canvas.restoreState()


def main():
    doc = BaseDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=LEFT,
        rightMargin=RIGHT,
        topMargin=TOP,
        bottomMargin=BOTTOM,
        title="Aryabhangy Compare and the demo Tracksheet",
        author="Arya Bhangy Motors",
    )
    frame = Frame(LEFT, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, showBoundary=0)
    doc.addPageTemplates([PageTemplate(id="guide", frames=[frame], onPage=draw_page)])
    doc.build(story())
    print(OUT)


if __name__ == "__main__":
    main()
