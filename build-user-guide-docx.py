"""Render STRATUM-User-Guide.md to a .docx with embedded UI screenshots.

Run:  python build-user-guide-docx.py
Output: STRATUM-User-Guide.docx next to the markdown source.
"""

from __future__ import annotations

import re
import sys
import urllib.parse
from pathlib import Path

import markdown
from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from docx.shared import Cm, Pt, RGBColor
from lxml import html as lxml_html

HERE = Path(__file__).resolve().parent
MD_SRC = HERE / "STRATUM-User-Guide.md"
DOCX_OUT = HERE / "STRATUM-User-Guide.docx"
UI_DIR = (HERE / "UI").resolve()

# python-docx renders unicode fine, but a couple of glyphs still look odd in
# default Word fonts; keep the same fallbacks used by the PDF builder so both
# outputs match.
GLYPH_FALLBACKS: dict[str, str] = {
    "\u22C0": "^",   # logical AND (used as up chevron)
    "\u22C1": "v",   # logical OR  (used as down chevron)
    "\u23F1": "T",   # stopwatch
}

ACCENT = RGBColor(0x0B, 0x3D, 0x59)   # dark navy
CYAN = RGBColor(0x16, 0x7A, 0x9C)     # muted cyan for h3/h4
HEADER_FILL = "0B3D59"                # table header fill
ROW_FILL = "F4F7F9"                   # table zebra fill

MAX_IMG_WIDTH_CM = 15.5               # fits inside A4 with 2 cm margins


def apply_glyph_fallbacks(text: str) -> str:
    for src, dst in GLYPH_FALLBACKS.items():
        text = text.replace(src, dst)
    return text


def resolve_image(src: str) -> Path | None:
    decoded = urllib.parse.unquote(src)
    for candidate in (HERE / decoded, UI_DIR / Path(decoded).name):
        p = candidate.resolve()
        if p.exists():
            return p
    print(f"WARN: image not found for src={src!r}", file=sys.stderr)
    return None


def set_cell_shading(cell, fill_hex: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill_hex)
    tc_pr.append(shd)


def set_cell_text_color(cell, color: RGBColor) -> None:
    for para in cell.paragraphs:
        for run in para.runs:
            run.font.color.rgb = color


# ---------- inline rendering -----------------------------------------------


def add_inline(paragraph, node) -> None:
    """Recursively add inline HTML content to a docx paragraph."""
    tag = node.tag.lower() if isinstance(node.tag, str) else ""

    if tag == "br":
        paragraph.add_run().add_break()
        return

    if tag == "img":
        src = node.get("src", "")
        img_path = resolve_image(src)
        if img_path is not None:
            run = paragraph.add_run()
            run.add_picture(str(img_path), width=Cm(MAX_IMG_WIDTH_CM))
        else:
            paragraph.add_run(f"[missing image: {src}]")
        return

    inherited_bold = tag in ("strong", "b")
    inherited_italic = tag in ("em", "i")
    inherited_code = tag == "code"

    def add_run_text(text: str) -> None:
        if not text:
            return
        run = paragraph.add_run(apply_glyph_fallbacks(text))
        if inherited_bold:
            run.bold = True
        if inherited_italic:
            run.italic = True
        if inherited_code:
            run.font.name = "Consolas"
            run.font.size = Pt(9.5)

    add_run_text(node.text or "")
    for child in node:
        add_inline(paragraph, child)
        add_run_text(child.tail or "")


# ---------- block rendering ------------------------------------------------


def add_heading(doc: Document, node, level: int) -> None:
    text = "".join(node.itertext()).strip()
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12 if level > 1 else 18)
    p.paragraph_format.space_after = Pt(4)
    run = p.add_run(apply_glyph_fallbacks(text))
    run.bold = True
    sizes = {1: 22, 2: 16, 3: 13, 4: 11}
    run.font.size = Pt(sizes.get(level, 11))
    run.font.color.rgb = ACCENT if level <= 2 else CYAN


def add_paragraph_block(doc: Document, node, style: str | None = None) -> None:
    p = doc.add_paragraph(style=style) if style else doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    add_inline(p, node)


def add_list(doc: Document, list_node, ordered: bool) -> None:
    style = "List Number" if ordered else "List Bullet"
    for li in list_node.findall("li"):
        p = doc.add_paragraph(style=style)
        p.paragraph_format.space_after = Pt(2)
        # <li> may contain inline text plus nested <p>, <ul>, <ol>.
        # Flatten first-level inline content into the list paragraph.
        if li.text:
            p.add_run(apply_glyph_fallbacks(li.text))
        for child in li:
            ctag = child.tag.lower()
            if ctag == "p":
                add_inline(p, child)
                if child.tail:
                    p.add_run(apply_glyph_fallbacks(child.tail))
            elif ctag in ("ul", "ol"):
                add_list(doc, child, ordered=(ctag == "ol"))
            else:
                add_inline(p, child)
                if child.tail:
                    p.add_run(apply_glyph_fallbacks(child.tail))


def add_table_block(doc: Document, table_node) -> None:
    header_cells: list[str] = []
    rows: list[list] = []

    thead = table_node.find("thead")
    if thead is not None:
        tr = thead.find("tr")
        if tr is not None:
            header_cells = [c for c in tr.findall("th")]

    tbody = table_node.find("tbody")
    body_rows = tbody.findall("tr") if tbody is not None else []
    for tr in body_rows:
        rows.append(tr.findall("td"))

    if not header_cells and not rows:
        return

    ncols = max(len(header_cells), max((len(r) for r in rows), default=0))
    tbl = doc.add_table(rows=1 + len(rows), cols=ncols)
    tbl.style = "Light Grid Accent 1"
    tbl.autofit = True

    hdr_row = tbl.rows[0]
    for i in range(ncols):
        cell = hdr_row.cells[i]
        cell.text = ""
        if i < len(header_cells):
            p = cell.paragraphs[0]
            add_inline(p, header_cells[i])
        set_cell_shading(cell, HEADER_FILL)
        for para in cell.paragraphs:
            for run in para.runs:
                run.bold = True
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)

    for r, row_cells in enumerate(rows, start=1):
        for i in range(ncols):
            cell = tbl.rows[r].cells[i]
            cell.text = ""
            if i < len(row_cells):
                add_inline(cell.paragraphs[0], row_cells[i])
            cell.vertical_alignment = WD_ALIGN_VERTICAL.TOP
            if r % 2 == 0:
                set_cell_shading(cell, ROW_FILL)


def add_blockquote(doc: Document, node) -> None:
    for child in node:
        if child.tag.lower() == "p":
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.6)
            p.paragraph_format.space_after = Pt(4)
            run_marker = p.add_run("│ ")
            run_marker.font.color.rgb = RGBColor(0x48, 0xD6, 0xFF)
            run_marker.bold = True
            add_inline(p, child)


def add_hr(doc: Document) -> None:
    p = doc.add_paragraph()
    p_pr = p._p.get_or_add_pPr()
    pbdr = OxmlElement("w:pBdr")
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), "6")
    bottom.set(qn("w:space"), "1")
    bottom.set(qn("w:color"), "B8C4CC")
    pbdr.append(bottom)
    p_pr.append(pbdr)


# ---------- driver ---------------------------------------------------------


def walk(doc: Document, root) -> None:
    for node in root:
        tag = node.tag.lower() if isinstance(node.tag, str) else ""
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            add_heading(doc, node, int(tag[1]))
        elif tag == "p":
            # A paragraph that only holds an <img> becomes a figure paragraph.
            imgs = node.findall("img")
            if imgs and not (node.text or "").strip() and len(node) == len(imgs):
                for img in imgs:
                    p = doc.add_paragraph()
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    p.paragraph_format.space_before = Pt(6)
                    p.paragraph_format.space_after = Pt(8)
                    add_inline(p, img)
            else:
                add_paragraph_block(doc, node)
        elif tag == "ul":
            add_list(doc, node, ordered=False)
        elif tag == "ol":
            add_list(doc, node, ordered=True)
        elif tag == "table":
            add_table_block(doc, node)
            # gap after tables
            doc.add_paragraph()
        elif tag == "blockquote":
            add_blockquote(doc, node)
        elif tag == "hr":
            add_hr(doc)
        elif tag == "pre":
            code_text = "".join(node.itertext())
            p = doc.add_paragraph()
            run = p.add_run(code_text)
            run.font.name = "Consolas"
            run.font.size = Pt(9.5)
        else:
            add_paragraph_block(doc, node)


def build(md_text: str) -> Document:
    md_text = apply_glyph_fallbacks(md_text)
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "sane_lists"],
    )
    # Force line-break-free root so lxml can parse cleanly.
    wrapped = f"<div>{html_body}</div>"
    root = lxml_html.fromstring(wrapped)

    doc = Document()

    # A4 with sensible margins.
    section = doc.sections[0]
    section.page_height = Cm(29.7)
    section.page_width = Cm(21.0)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(2.0)
    section.left_margin = Cm(1.8)
    section.right_margin = Cm(1.8)

    # Default body style.
    style = doc.styles["Normal"]
    style.font.name = "Calibri"
    style.font.size = Pt(11)

    # Footer with page number.
    footer_p = section.footer.paragraphs[0]
    footer_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    footer_p.add_run("STRATUM Ground Station — User Guide  |  Page ")
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.text = "PAGE"
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run = footer_p.add_run()
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_end)

    walk(doc, root)
    return doc


def main() -> int:
    if not MD_SRC.exists():
        print(f"ERROR: markdown source not found: {MD_SRC}", file=sys.stderr)
        return 2
    md_text = MD_SRC.read_text(encoding="utf-8")
    doc = build(md_text)
    doc.save(str(DOCX_OUT))
    size_kb = DOCX_OUT.stat().st_size / 1024
    print(f"OK  {DOCX_OUT}  ({size_kb:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
