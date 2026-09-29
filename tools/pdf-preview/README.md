# PDF layout preview

A Python copy of the PDF layout in `ScaffoldPro-native/main.swift`
(`PDFGenerator`), for checking the letterhead layout against the company's
sample quotation Qt26193 (`docs/reference/`) without a Mac.

```bash
pip install pillow numpy
python3 docs.py      # renders quotation, invoice, delivery note and BOQ pages to out/
python3 compare.py   # sample vs render, side by side, with per-element pixel differences
```

The screenshots and renders are 96 dpi, so 1 pixel = 0.75 pt. The Mac
fonts (Verdana Bold, PingFang, Songti) are replaced by similar Linux fonts, so
letter shapes differ slightly. Positions, sizes and colours are the same as in
the Swift code. If you change the layout in `main.swift`, make the same change
in `render.py`.

## Word export check

```bash
pip install pillow numpy pymupdf   # and LibreOffice Writer (soffice)
python3 word.py      # sample documents → out/word_*.docx, rendered to out/word_*_<page>.png
```

`word.py` turns the sample documents into the layout the app sends to
`js/docx-export.js`, builds the .docx files with it (node), and renders them
with LibreOffice so they can be compared with `docs.py`'s PDF pages.

## BQ sheet check

```bash
python3 sheet.py ../../docs/reference/BQ-CRBC-1635.pdf
```

`sheet.py` is a Python copy of `BQSheet.layout` and `BQSheetRenderer`. It
rebuilds the sample BQ (landscape, and the portrait version without prices),
compares it with the original pixel by pixel (`out/sheet_diff.png`), and
builds and renders the Word copies (`out/word_sheet_*`). Carlito, the app's
bundled stand-in for Calibri, must be installed for LibreOffice to render the
Word copies like Word does (for example `~/.local/share/fonts`).
