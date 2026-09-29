# Reference documents

`Qt26193-page1.png` and `Qt26193-page2.png` are screenshots of the company's
standard quotation. Every generated PDF copies its letterhead, footer, colours,
fonts and table style. See `ScaffoldPro-native/AUDIT.md`, "Letterhead layout".

`BQ-CRBC-1635.pdf` is the company's bill of quantities sheet ("PROFICIENCY
QUOTATION", from Google Sheets, A4 landscape). BOQ PDFs and Word copies are
laid out exactly like it; `tools/pdf-preview/sheet.py` rebuilds it and
compares the two pixel by pixel.
