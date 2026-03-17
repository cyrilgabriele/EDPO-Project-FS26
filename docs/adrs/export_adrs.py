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
    FONT_H3 = ("Times", "B", 11.5)
    FONT_BOLD = ("Times", "B", 11)
    FONT_CODE = ("Courier", "", 9.5)
    FONT_TABLE = ("Times", "", 9.5)
    FONT_TABLE_HDR = ("Times", "B", 9.5)
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


def parse_table_row(raw):
    """Split a markdown table row into cell strings."""
    cells = raw.split("|")
    # strip leading/trailing empty cells from the outer pipes
    if cells and not cells[0].strip():
        cells = cells[1:]
    if cells and not cells[-1].strip():
        cells = cells[:-1]
    return [c.strip() for c in cells]


def is_separator_row(raw):
    """Check if a table row is a --- separator."""
    return bool(re.match(r"^\|[\s\-:|]+\|$", raw.strip()))


def _cell_line_count(pdf, text, col_width):
    """Return how many lines *text* would occupy in a multi_cell of *col_width*."""
    # Account for a small internal padding (1mm each side)
    usable = col_width - 2
    words = text.split(" ")
    lines = 1
    line_len = 0.0
    for word in words:
        w = pdf.get_string_width(word + " ")
        if line_len + w > usable and line_len > 0:
            lines += 1
            line_len = w
        else:
            line_len += w
    return lines


def render_table(pdf, table_lines):
    """Render a markdown table as a simple grid with word-wrapped cells."""
    rows = []
    for line in table_lines:
        if is_separator_row(line):
            continue
        rows.append(parse_table_row(line))
    if not rows:
        return

    num_cols = len(rows[0])
    table_width = pdf.w - pdf.l_margin - pdf.r_margin
    col_widths = [table_width / num_cols] * num_cols
    base_row_height = 5.5

    # --- estimate total table height so we can avoid page breaks ----
    total_height = 4  # top/bottom padding (ln(2) each)
    for row_idx, row in enumerate(rows):
        while len(row) < num_cols:
            row.append("")
        font = LaTeXStylePDF.FONT_TABLE_HDR if row_idx == 0 else LaTeXStylePDF.FONT_TABLE
        pdf.set_font(*font)
        max_lines = 1
        for col_idx, cell in enumerate(row[:num_cols]):
            text = sanitize(cell.replace("`", ""))
            max_lines = max(max_lines, _cell_line_count(pdf, text, col_widths[col_idx]))
        total_height += base_row_height * max_lines

    space_left = pdf.h - pdf.get_y() - pdf.b_margin
    if total_height > space_left:
        pdf.add_page()

    # --- render rows -------------------------------------------------
    pdf.ln(2)
    for row_idx, row in enumerate(rows):
        while len(row) < num_cols:
            row.append("")

        if row_idx == 0:
            pdf.set_font(*LaTeXStylePDF.FONT_TABLE_HDR)
        else:
            pdf.set_font(*LaTeXStylePDF.FONT_TABLE)
        pdf.set_text_color(0, 0, 0)

        # determine row height from tallest cell
        max_lines = 1
        for col_idx, cell in enumerate(row[:num_cols]):
            text = sanitize(cell.replace("`", ""))
            max_lines = max(max_lines, _cell_line_count(pdf, text, col_widths[col_idx]))
        row_h = base_row_height * max_lines

        y_before = pdf.get_y()
        x_start = pdf.l_margin
        for col_idx, cell in enumerate(row[:num_cols]):
            text = sanitize(cell.replace("`", ""))
            x = x_start + sum(col_widths[:col_idx])
            # draw the cell border first
            pdf.rect(x, y_before, col_widths[col_idx], row_h)
            # write text inside with a small left padding
            pdf.set_xy(x + 1, y_before)
            pdf.multi_cell(col_widths[col_idx] - 2, base_row_height, text)

            # restore font after multi_cell (in case it resets)
            if row_idx == 0:
                pdf.set_font(*LaTeXStylePDF.FONT_TABLE_HDR)
            else:
                pdf.set_font(*LaTeXStylePDF.FONT_TABLE)

        pdf.set_y(y_before + row_h)
    pdf.ln(2)


def render_code_block(pdf, code_lines):
    """Render a fenced code block with a light grey background."""
    lh = LaTeXStylePDF.LINE_HEIGHT
    pdf.set_font(*LaTeXStylePDF.FONT_CODE)
    code_indent = 4
    x_start = pdf.l_margin + code_indent
    block_width = pdf.w - pdf.l_margin - pdf.r_margin - code_indent

    pdf.ln(1)
    for line in code_lines:
        text = sanitize(line)
        # draw background
        y = pdf.get_y()
        pdf.set_fill_color(240, 240, 240)
        pdf.rect(x_start - 1, y, block_width + 2, lh, style="F")
        # draw text
        pdf.set_x(x_start)
        pdf.set_text_color(0, 0, 0)
        pdf.cell(block_width, lh, text)
        pdf.ln(lh)
    pdf.ln(1)


def render_adr(pdf, md_text):
    """Render a single ADR markdown file to the PDF."""
    lines = md_text.strip().split("\n")
    in_list = False
    i = 0

    while i < len(lines):
        raw = lines[i].rstrip()

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
            i += 1
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
            i += 1
            continue

        # H3
        if raw.startswith("### "):
            text = sanitize(raw[4:].strip())
            if in_list:
                in_list = False
                pdf.ln(2)
            pdf.ln(2)
            pdf.set_font(*LaTeXStylePDF.FONT_H3)
            pdf.set_text_color(0, 0, 0)
            pdf.multi_cell(0, 6, text)
            pdf.ln(1)
            i += 1
            continue

        # Fenced code block: collect lines between ``` markers
        if raw.startswith("```"):
            i += 1  # skip opening fence
            code_lines = []
            while i < len(lines) and not lines[i].rstrip().startswith("```"):
                code_lines.append(lines[i].rstrip())
                i += 1
            i += 1  # skip closing fence
            render_code_block(pdf, code_lines)
            continue

        # Table: collect consecutive lines starting with |
        if raw.startswith("|"):
            table_lines = []
            while i < len(lines) and lines[i].rstrip().startswith("|"):
                table_lines.append(lines[i].rstrip())
                i += 1
            render_table(pdf, table_lines)
            continue

        # Blank line
        if not raw.strip():
            if in_list:
                in_list = False
            pdf.ln(2)
            i += 1
            continue

        # List item
        if raw.startswith("- "):
            in_list = True
            text = sanitize(raw[2:].strip())
            render_body_line(pdf, text, indent=True)
            i += 1
            continue

        # Regular paragraph line
        text = sanitize(raw)
        render_body_line(pdf, text, indent=False)
        i += 1


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
