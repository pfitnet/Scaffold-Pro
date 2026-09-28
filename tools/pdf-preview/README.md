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
