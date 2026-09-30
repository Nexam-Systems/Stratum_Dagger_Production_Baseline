"""Render STRATUM-User-Guide.md to a PDF with embedded UI screenshots.

Run:  python build-user-guide-pdf.py
Output: STRATUM-User-Guide.pdf next to the markdown source.
"""

from __future__ import annotations

import re
import sys
import urllib.parse
from pathlib import Path

import markdown

# Compat shim: xhtml2pdf imports `get_display` from top-level `bidi`, but the
# pure-Python `python-bidi<0.5` (used here because the native DLL is blocked
# by policy) only exposes it under `bidi.algorithm`. Patch before import.
import bidi  # noqa: E402
import bidi.algorithm  # noqa: E402
if not hasattr(bidi, "get_display"):
    bidi.get_display = bidi.algorithm.get_display  # type: ignore[attr-defined]

from xhtml2pdf import pisa  # noqa: E402

HERE = Path(__file__).resolve().parent
MD_SRC = HERE / "STRATUM-User-Guide.md"
PDF_OUT = HERE / "STRATUM-User-Guide.pdf"
UI_DIR = (HERE / "UI").resolve()

# Helvetica (xhtml2pdf's default) has no glyphs for these — substitute
# readable ASCII so the PDF doesn't show black boxes.
GLYPH_FALLBACKS: dict[str, str] = {
    "\u22C0": "^",   # ⋀  logical AND (used as up chevron)
    "\u22C1": "v",   # ⋁  logical OR  (used as down chevron)
    "\u2264": "<=",  # ≤
    "\u2265": ">=",  # ≥
    "\u2192": "->",  # →
    "\u2190": "<-",  # ←
    "\u2191": "^",   # ↑
    "\u2193": "v",   # ↓
    "\u21B3": "->",  # ↳
    "\u21A5": "^",   # ↥
    "\u23F1": "T",   # ⏱  stopwatch
    "\u2212": "-",   # −  minus sign
    "\u2014": "--",  # — em dash (Helvetica has it but be safe)
}


def apply_glyph_fallbacks(text: str) -> str:
    for src, dst in GLYPH_FALLBACKS.items():
        text = text.replace(src, dst)
    return text


CSS = """
@page {
    size: A4;
    margin: 18mm 16mm 20mm 16mm;
    @frame footer_frame {
        -pdf-frame-content: footer_content;
        left:  16mm;
        right: 16mm;
        bottom: 8mm;
        height: 8mm;
    }
}
body        { font-family: Helvetica, Arial, sans-serif; font-size: 10.5pt;
              color: #1a1f24; line-height: 1.45; }
h1          { font-size: 22pt; color: #0b3d59; margin: 0 0 6pt 0;
              border-bottom: 2pt solid #48D6FF; padding-bottom: 4pt; }
h2          { font-size: 15pt; color: #0b3d59; margin: 18pt 0 6pt 0;
              border-bottom: 0.5pt solid #b8c4cc; padding-bottom: 2pt; }
h3          { font-size: 12pt; color: #14506e; margin: 12pt 0 4pt 0; }
h4          { font-size: 11pt; color: #14506e; margin: 10pt 0 3pt 0; }
p           { margin: 4pt 0; }
ul, ol      { margin: 4pt 0 4pt 14pt; }
li          { margin: 1pt 0; }
code        { font-family: Courier, monospace; font-size: 9.5pt;
              background: #eef2f5; padding: 1pt 3pt; }
blockquote  { border-left: 3pt solid #48D6FF; margin: 6pt 0 6pt 4pt;
              padding: 2pt 8pt; color: #445; background: #f4fbff; }
hr          { border: 0; border-top: 0.5pt solid #b8c4cc; margin: 10pt 0; }
img         { max-width: 100%; }
.figure     { margin: 8pt 0 10pt 0; text-align: center; }
.figure img { border: 0.5pt solid #b8c4cc; }
table       { border-collapse: collapse; width: 100%;
              margin: 6pt 0; font-size: 9.5pt; }
th          { background: #0b3d59; color: #fff;
              padding: 4pt 6pt; text-align: left; }
td          { border: 0.5pt solid #b8c4cc; padding: 4pt 6pt;
              vertical-align: top; }
tr:nth-child(even) td { background: #f4f7f9; }
.footer     { color: #667; font-size: 8pt; text-align: center; }
"""


def resolve_image(src: str) -> str:
    """Rewrite markdown image sources so xhtml2pdf can find them on disk."""
    decoded = urllib.parse.unquote(src)
    candidate = (HERE / decoded).resolve()
    if candidate.exists():
        return candidate.as_uri()
    # try basename in UI dir
    fallback = UI_DIR / Path(decoded).name
    if fallback.exists():
        return fallback.as_uri()
    print(f"WARN: image not found for src={src!r}", file=sys.stderr)
    return src


def md_to_html(md_text: str) -> str:
    md_text = apply_glyph_fallbacks(md_text)
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "sane_lists"],
    )

    # Wrap every <img> in a .figure div so the caption block looks tidy,
    # and rewrite src to a file:// URI xhtml2pdf can load.
    def _img_sub(match: re.Match[str]) -> str:
        attrs = match.group(1)
        src_match = re.search(r'src="([^"]+)"', attrs)
        if not src_match:
            return match.group(0)
        new_src = resolve_image(src_match.group(1))
        attrs = attrs.replace(src_match.group(0), f'src="{new_src}"')
        return f'<div class="figure"><img{attrs} /></div>'

    html_body = re.sub(r"<img([^>]*)/?>", _img_sub, html_body)

    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <style>{CSS}</style>
</head>
<body>
{html_body}
<div id="footer_content" class="footer">
  STRATUM Ground Station — User Guide &nbsp;|&nbsp; Page <pdf:pagenumber />
  of <pdf:pagecount />
</div>
</body>
</html>
"""


def main() -> int:
    if not MD_SRC.exists():
        print(f"ERROR: markdown source not found: {MD_SRC}", file=sys.stderr)
        return 2

    md_text = MD_SRC.read_text(encoding="utf-8")
    html = md_to_html(md_text)

    with PDF_OUT.open("wb") as fh:
        result = pisa.CreatePDF(html, dest=fh, encoding="utf-8")

    if result.err:
        print(f"ERROR: xhtml2pdf reported {result.err} error(s).",
              file=sys.stderr)
        return 1

    size_kb = PDF_OUT.stat().st_size / 1024
    print(f"OK  {PDF_OUT}  ({size_kb:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
