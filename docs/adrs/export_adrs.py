#!/usr/bin/env python3
"""
Combine all ADRs (except the 0000 template) into a single PDF.

Dependencies: pip install markdown fpdf2
"""

import glob
import os
import re
import sys

import markdown
from fpdf import FPDF

ADR_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PDF = os.path.join(ADR_DIR, "architecture_decision_records.pdf")

UNICODE_REPLACEMENTS = {
    "\u2014": "--",
    "\u2013": "-",
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2026": "...",
    "\u00a0": " ",
}


class LaTeXStylePDF(FPDF):
    """PDF with a plain, LaTeX-like appearance."""

    MARGIN = 25
    FONT_BODY = ("Times", "", 11)
    FONT_H1 = ("Times", "B", 16)
    FONT_H2 = ("Times", "B", 13)
    FONT_BOLD = ("Times", "B", 11)
    FONT_CODE = ("Courier", "", 9.5)
    LINE_HEIGHT = 5.5

    def header(self):
        pass

    def footer(self):
        self.set_y(-15)
        self.set_font("Times", "", 9)
        self.set_text_color(100, 100, 100)
        self.cell(0, 10, str(self.page_no()), align="C")


def collect_adr_files():
    files = sorted(glob.glob(os.path.join(ADR_DIR, "0*.md")))
    return [f for f in files if "0000_" not in os.path.basename(f)]


def sanitize(text):
    for char, replacement in UNICODE_REPLACEMENTS.items():
        text = text.replace(char, replacement)
    return text


def render_adr(pdf, md_text):
    """Render a single ADR markdown file to the PDF."""
    lines = md_text.strip().split("\n")
    in_list = False

    for line in lines:
        raw = line.rstrip()

        # H1
        if raw.startswith("# "):
            text = sanitize(raw[2:].strip())
            pdf.set_font(*LaTeXStylePDF.FONT_H1)
            pdf.set_text_color(0, 0, 0)
            pdf.ln(2)
            pdf.multi_cell(0, 7.5, text)
            pdf.ln(1)
            # thin rule under title
            y = pdf.get_y()
            pdf.line(pdf.l_margin, y, pdf.w - pdf.r_margin, y)
            pdf.ln(4)
            continue

        # H2
        if raw.startswith("## "):
            text = sanitize(raw[3:].strip())
            if in_list:
                in_list = False
                pdf.ln(2)
            pdf.ln(3)
            pdf.set_font(*LaTeXStylePDF.FONT_H2)
            pdf.set_text_color(0, 0, 0)
            pdf.multi_cell(0, 6.5, text)
            pdf.ln(2)
            continue

        # Blank line
        if not raw.strip():
            if in_list:
                in_list = False
            pdf.ln(2)
            continue

        # List item
        if raw.startswith("- "):
            in_list = True
            text = sanitize(raw[2:].strip())
            render_body_line(pdf, text, indent=True)
            continue

        # Regular paragraph line
        text = sanitize(raw)
        render_body_line(pdf, text, indent=False)


def render_body_line(pdf, text, indent=False):
    """Render a single line, handling **bold** and `code` inline."""
    lh = LaTeXStylePDF.LINE_HEIGHT
    x_start = pdf.l_margin + (8 if indent else 0)

    if indent:
        # bullet
        pdf.set_font(*LaTeXStylePDF.FONT_BODY)
        pdf.set_text_color(0, 0, 0)
        pdf.set_x(x_start - 5)
        pdf.cell(5, lh, chr(8226) if False else "-")  # use dash for latin-1 safety
        pdf.set_x(x_start)

    # Split text into segments: **bold**, `code`, and normal
    parts = re.split(r"(\*\*.*?\*\*|`[^`]+`)", text)
    line_width = pdf.w - pdf.r_margin - x_start

    # Use multi_cell for proper wrapping by building the full line
    # and letting fpdf handle it, but we need inline formatting.
    # Approach: write segments with cell, track x position, wrap manually.
    pdf.set_x(x_start)
    for part in parts:
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            content = part[2:-2]
            pdf.set_font(*LaTeXStylePDF.FONT_BOLD)
        elif part.startswith("`") and part.endswith("`"):
            content = part[1:-1]
            pdf.set_font(*LaTeXStylePDF.FONT_CODE)
        else:
            content = part
            pdf.set_font(*LaTeXStylePDF.FONT_BODY)

        pdf.set_text_color(0, 0, 0)

        # Word-wrap within the segment
        words = content.split(" ")
        for i, word in enumerate(words):
            w_text = word + ("" if i == len(words) - 1 else " ")
            w_width = pdf.get_string_width(w_text)
            remaining = pdf.w - pdf.r_margin - pdf.get_x()
            if w_width > remaining and pdf.get_x() > x_start + 1:
                pdf.ln(lh)
                pdf.set_x(x_start)
            pdf.cell(w_width, lh, w_text)

    pdf.ln(lh)


def main():
    adr_files = collect_adr_files()
    if not adr_files:
        print("No ADR files found.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(adr_files)} ADR(s):")
    for f in adr_files:
        print(f"  - {os.path.basename(f)}")

    pdf = LaTeXStylePDF()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.set_margins(LaTeXStylePDF.MARGIN, LaTeXStylePDF.MARGIN, LaTeXStylePDF.MARGIN)

    for i, path in enumerate(adr_files):
        with open(path, encoding="utf-8") as f:
            md_text = f.read()
        pdf.add_page()
        render_adr(pdf, md_text)

    pdf.output(OUTPUT_PDF)
    print(f"\nExported to: {OUTPUT_PDF}")


if __name__ == "__main__":
    main()
