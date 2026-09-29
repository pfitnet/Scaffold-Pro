'use strict';

// Word (.docx) export of any document, laid out like its PDF.
//
// The native side (main.swift, PDFGenerator.wordLayout) sends the document
// with everything the PDF worked out: each table cell's lines as wrapped on
// the PDF, row heights, where the text of hanging paragraphs starts, which
// sections start a new page, the letterhead and footer as a page-sized
// picture, and the EB Garamond font files. This file turns that into a
// .docx: the letterhead picture sits behind the text on every page (in the
// page header), the page number is a live field, the fonts are embedded (so
// the document looks the same on a Mac without EB Garamond), and the table,
// terms and signatures are ordinary, editable Word content.
//
//   window.buildLetterDocx(layout) → Uint8Array (the .docx file)
//   window.exportWord(fetchLayout) → asks the native side for the layout,
//     builds the file, and saves it into the project folder (then opens it)

(function (root) {
  const TW = (pt) => Math.round(pt * 20); // twentieths of a point
  const HP = (pt) => Math.round(pt * 2); // half-points
  const EMU = (pt) => Math.round(pt * 12700);
  const BODY_FONT = 'EB Garamond';
  const SIGN_FONT = 'Times New Roman';
  const GREY = '999999';
  const DARK_GREY = '666666';
  const LINK = '2854C5';

  // Vertical placement. Word and LibreOffice put a line's baseline about
  // this far below the top of an exactly-spaced line (as a fraction of the
  // line height), so "before" spacing is worked out from the PDF's
  // baseline positions. Measured by rendering with LibreOffice.
  const BASELINE_AT = 0.8;

  function xml(s) {
    return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  // ---------- runs and paragraphs ----------

  function rPr(o) {
    let s = '';
    if (o.font) s += `<w:rFonts w:ascii="${o.font}" w:hAnsi="${o.font}" w:cs="${o.font}"/>`;
    if (o.bold) s += '<w:b/><w:bCs/>';
    if (o.italic) s += '<w:i/><w:iCs/>';
    if (o.color) s += `<w:color w:val="${o.color}"/>`;
    // Pair kerning, as the PDF (and Google Sheets) have it; Word only kerns when asked.
    s += '<w:kern w:val="2"/>';
    if (o.size) s += `<w:sz w:val="${HP(o.size)}"/><w:szCs w:val="${HP(o.size)}"/>`;
    if (o.underline) s += '<w:u w:val="single"/>';
    return s ? `<w:rPr>${s}</w:rPr>` : '';
  }

  // "\t" and "\n" in the text become a tab and a line break.
  function run(text, o = {}) {
    let inner = '';
    for (const part of String(text ?? '').split(/(\t|\n)/)) {
      if (part === '\t') inner += '<w:tab/>';
      else if (part === '\n') inner += '<w:br/>';
      else if (part) inner += `<w:t xml:space="preserve">${xml(part)}</w:t>`;
    }
    return inner ? `<w:r>${rPr(o)}${inner}</w:r>` : '';
  }

  function para(runs, o = {}) {
    let p = '';
    if (o.keepNext) p += '<w:keepNext/>';
    if (o.keepLines) p += '<w:keepLines/>';
    if (o.pageBreakBefore) p += '<w:pageBreakBefore/>';
    if (o.tabs && o.tabs.length) {
      p += `<w:tabs>${o.tabs.map((t) => `<w:tab w:val="${t.val || 'left'}" w:pos="${TW(t.pos)}"/>`).join('')}</w:tabs>`;
    }
    p += `<w:spacing w:before="${TW(Math.max(0, o.before || 0))}" w:after="0" w:line="${TW(o.line || 16.5)}" w:lineRule="exact"/>`;
    if (o.indLeft || o.hanging) p += `<w:ind w:left="${TW(o.indLeft || 0)}"${o.hanging ? ` w:hanging="${TW(o.hanging)}"` : ''}/>`;
    if (o.align) p += `<w:jc w:val="${o.align}"/>`;
    if (o.mark) p += rPr(o.mark);
    return `<w:p><w:pPr>${p}</w:pPr>${runs}</w:p>`;
  }

  // "before" spacing so that this paragraph's first baseline is `gap`
  // points below the previous baseline.
  function gapBefore(gap, prevLine, line) {
    return gap - (prevLine * (1 - BASELINE_AT)) - line * BASELINE_AT;
  }

  // ---------- tables ----------

  function border(side, pt, color) {
    return `<w:${side} w:val="single" w:sz="${Math.round(pt * 8)}" w:space="0" w:color="${color || '000000'}"/>`;
  }
  const NO_BORDER = (side) => `<w:${side} w:val="nil"/>`;

  function tc(width, content, o = {}) {
    let pr = `<w:tcW w:w="${TW(width)}" w:type="dxa"/>`;
    if (o.span > 1) pr += `<w:gridSpan w:val="${o.span}"/>`;
    if (o.borders) pr += `<w:tcBorders>${o.borders}</w:tcBorders>`;
    if (o.mar) {
      const m = o.mar;
      pr += `<w:tcMar><w:top w:w="${TW(m.top || 0)}" w:type="dxa"/><w:left w:w="${TW(m.left || 0)}" w:type="dxa"/>` +
        `<w:bottom w:w="${TW(m.bottom || 0)}" w:type="dxa"/><w:right w:w="${TW(m.right || 0)}" w:type="dxa"/></w:tcMar>`;
    }
    pr += `<w:vAlign w:val="${o.vAlign || 'center'}"/>`;
    return `<w:tc><w:tcPr>${pr}</w:tcPr>${content || '<w:p/>'}</w:tc>`;
  }

  function tr(cells, o = {}) {
    let pr = '<w:cantSplit/>';
    if (o.height) pr += `<w:trHeight w:val="${TW(o.height)}" w:hRule="${o.exact ? 'exact' : 'atLeast'}"/>`;
    if (o.header) pr += '<w:tblHeader/>';
    return `<w:tr><w:trPr>${pr}</w:trPr>${cells.join('')}</w:tr>`;
  }

  function tbl(widths, rows, o = {}) {
    const total = widths.reduce((a, b) => a + b, 0);
    const sides = ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'];
    const borders = o.borders
      ? sides.map((s) => border(s, 0.75)).join('')
      : sides.map(NO_BORDER).join('');
    const m = o.cellMar || { top: 0, left: 0, bottom: 0, right: 0 };
    return `<w:tbl><w:tblPr><w:tblW w:w="${TW(total)}" w:type="dxa"/><w:tblInd w:w="${TW(o.indent || 0)}" w:type="dxa"/>` +
      `<w:tblBorders>${borders}</w:tblBorders><w:tblLayout w:type="fixed"/>` +
      `<w:tblCellMar><w:top w:w="${TW(m.top)}" w:type="dxa"/><w:left w:w="${TW(m.left)}" w:type="dxa"/>` +
      `<w:bottom w:w="${TW(m.bottom)}" w:type="dxa"/><w:right w:w="${TW(m.right)}" w:type="dxa"/></w:tblCellMar>` +
      `<w:tblLook w:val="0000" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/></w:tblPr>` +
      `<w:tblGrid>${widths.map((w) => `<w:gridCol w:w="${TW(w)}"/>`).join('')}</w:tblGrid>${rows.join('')}</w:tbl>`;
  }

  // ---------- the document ----------

  // Cell insets, as on the PDF: text 5pt in from the left rule, 3.4pt in
  // from the right; one line of text centred in a 24.1pt row.
  const CELL = { top: 0, left: 5.0, bottom: 0, right: 3.4 };
  const CELL_LINE = 14.25;

  function cellParagraph(lines, column, width, o = {}) {
    const size = o.size || 11;
    const style = { size, bold: o.bold };
    const inner = width - CELL.left - CELL.right;
    if (column.kind === 'money') {
      if (!lines.length || !lines[0]) return para('', { line: CELL_LINE });
      const text = `${o.currency}\t${lines[0]}${lines.slice(1).map((l) => `\n\t${l}`).join('')}`;
      return para(run(text, style), { line: CELL_LINE, tabs: [{ val: 'right', pos: inner }] });
    }
    if (column.kind === 'weight') {
      // The figure, then "kg" at the right of the cell (as drawWeight on the PDF).
      if (!lines.length || !lines[0]) return para('', { line: CELL_LINE });
      const suffix = KG_WIDTH * size / 11 + 8.4;
      const text = `\t${lines[0]}\tkg${lines.slice(1).map((l) => `\n\t${l}`).join('')}`;
      return para(run(text, style), { line: CELL_LINE, tabs: [{ val: 'right', pos: inner - suffix }, { val: 'right', pos: inner }] });
    }
    const align = { center: 'center', right: 'right', left: 'left' }[column.kind] || 'left';
    return para(run(lines.join('\n'), style), { line: CELL_LINE, align });
  }
  // "kg" in 11pt EB Garamond.
  const KG_WIDTH = 9.94;

  function mainTable(d) {
    const cols = d.columns;
    const widths = cols.map((c) => c.width);
    const n = cols.length;
    const sum = (from, to) => widths.slice(from, to).reduce((a, b) => a + b, 0);
    const rows = [];
    rows.push(tr(cols.map((c, i) => tc(widths[i], para(run(c.title, { bold: true }), { line: CELL_LINE, align: 'center' }))),
      { height: d.headerHeight || 24.1, header: true }));
    for (const r of d.rows) {
      if (r.type === 'item') {
        rows.push(tr(cols.map((c, i) => tc(widths[i], cellParagraph(r.cells[i] || [], c, widths[i], { currency: d.currencySymbol }))),
          { height: r.height }));
      } else if (r.type === 'section') {
        rows.push(tr([tc(sum(0, n), para(run(r.text, { bold: true, size: 12 }), { line: CELL_LINE, align: 'center' }), { span: n })],
          { height: r.height }));
      } else if (r.type === 'summary') {
        const size = r.emphasized ? 12 : 11;
        const label = tc(sum(0, n - 1), para(run(r.label, { bold: true, size }), { line: CELL_LINE, align: 'right' }),
          { span: n - 1, mar: { left: CELL.left, right: 4.25 } });
        const value = tc(widths[n - 1], cellParagraph([r.value], cols[n - 1], widths[n - 1], { currency: d.currencySymbol, bold: true, size }));
        rows.push(tr([label, value], { height: r.height }));
      } else if (r.type === 'partial') {
        const count = Math.min(r.cells.length, n - 1);
        const cells = [];
        for (let i = 0; i < count; i++) cells.push(tc(widths[i], cellParagraph(r.cells[i] || [], cols[i], widths[i], { currency: d.currencySymbol })));
        cells.push(tc(sum(count, n), para(run(r.text), { line: CELL_LINE, align: 'center' }), { span: n - count }));
        rows.push(tr(cells, { height: r.height }));
      } else if (r.type === 'note') {
        rows.push(tr([tc(sum(0, n), para(run(r.text, { italic: true, size: 9.5, color: DARK_GREY }), { line: 13 }),
          { span: n, mar: { left: 6, right: 6 } })], { height: r.height }));
      }
    }
    // The PDF's table starts 0.75pt left of the text.
    return tbl(widths, rows, { borders: true, indent: -0.75, cellMar: CELL });
  }

  function opening(d, L) {
    const out = [];
    // Client (left) and references (right), side by side as on the PDF:
    // client from 47.75pt, labels from 401.25pt, colons at 478.5pt and
    // values ending at 550.5pt; lines 15.75pt apart.
    const pitch = 15.75;
    const leftCol = 401.25 - 5 - L.textLeft;
    const rightCol = L.textRight - (L.textLeft + leftCol);
    const left = [para(run(d.clientName, { bold: true, size: 12 }), { line: pitch })]
      .concat(d.clientLines.map((l) => para(run(l, { size: 12 }), { line: pitch })));
    const right = d.refRows.map((r) => {
      const colon = 478.5 - 401.25;
      if (r.wraps) {
        return para(run(`${r.label}\t:\t${r.value}`), { line: pitch, tabs: [{ pos: colon }], indLeft: 484.5 - 401.25, hanging: 484.5 - 401.25 });
      }
      return para(run(`${r.label}\t:\t${r.value}`), { line: pitch, tabs: [{ pos: colon }, { val: 'right', pos: 550.5 - 401.25 }] });
    });
    // "BY EMAIL ONLY" goes under the references (beside the client's last
    // line when the address is longer), the title under both.
    const clientCount = String(d.clientName).split('\n').length + d.clientLines.length;
    const refCount = d.refRows.reduce((a, r) => a + (r.wraps ? 2 : 1), 0);
    const clientLast = (Math.max(clientCount, 1) - 1) * pitch;
    const refLast = (Math.max(refCount, 1) - 1) * pitch;
    const methodAt = refLast + 19.5;
    if (d.deliveryMethod) {
      right.push(para(run(d.deliveryMethod, { bold: true, size: 13, underline: true }),
        { line: 19.5, before: gapBefore(19.5, pitch, 19.5), align: 'right', tabs: [] }));
    }
    out.push(tbl([leftCol, rightCol], [tr([
      tc(leftCol, left.join(''), { vAlign: 'top', mar: { left: 5 } }),
      tc(rightCol, right.join('') || para(''), { vAlign: 'top', mar: { left: 5, right: L.textRight - 550.5 } }),
    ])], { indent: 0 }));

    const blockLines = Math.max(1 + d.clientLines.length, d.refRows.reduce((a, r) => a + (r.wraps ? 2 : 1), 0), 1);
    let prevLine = pitch;
    // Extra space above and below the title, as on the PDF (titlePadding).
    const TITLE_PADDING = 6.0;
    let titleGap = 40.5 + TITLE_PADDING;
    if (d.deliveryMethod) {
      // Measured from the lower of the two columns' last lines.
      const blockLast = Math.max(clientLast, methodAt);
      if (methodAt >= clientLast) prevLine = 19.5;
      titleGap = Math.max(methodAt + 21.0, clientLast + 24.0) + TITLE_PADDING - blockLast;
    }
    const center = L.pageWidth / 2 - L.textLeft;
    const titleRuns = run('\t') + run(d.title, { bold: true, size: 15, underline: true }) +
      (d.status !== 'Issued' ? run('\t') + run(String(d.status).toUpperCase(), { bold: true, color: GREY }) : '');
    out.push(para(titleRuns, { line: 18, before: gapBefore(titleGap, prevLine, 18),
      tabs: [{ val: 'center', pos: center }, { val: 'right', pos: L.textRight - L.textLeft }] }));
    prevLine = 18;
    let gap = 18.0 + TITLE_PADDING;
    const bodyLine = 16.5;
    const add = (runs) => {
      out.push(para(runs, { line: bodyLine, before: gapBefore(gap, prevLine, bodyLine) }));
      prevLine = bodyLine;
      gap = bodyLine;
    };
    if (d.salutation) add(run(d.salutation));
    if (d.subject) add(run(d.subject, { bold: true, underline: true }));
    if (d.intro) add(run(d.intro));
    // Labelled lines (the delivery note): bold label, ": value" at 100.5pt,
    // 17.35pt apart; the first 24pt (plus padding) under the title.
    const infoRows = d.infoRows || [];
    if (infoRows.length) {
      if (prevLine === 18) gap = 24.0 + TITLE_PADDING;
      else gap = 17.35;
      const colonAt = 100.5, valueAt = colonAt + COLON_SPACE;
      for (const r of infoRows) {
        const runs = run(r.label, { bold: true }) + run('\t: ') +
          run((r.lines || []).join('\n'), { bold: r.bold });
        out.push(para(runs, { line: bodyLine, before: gapBefore(gap, prevLine, bodyLine), indLeft: valueAt, hanging: valueAt - 1.5,
          tabs: [{ pos: colonAt }] }));
        prevLine = bodyLine;
        gap = 17.35;
      }
    }
    // The table starts 15pt below the last line (17.6pt under labelled
    // lines): a spacer paragraph.
    const spacer = (infoRows.length ? 17.6 : 15) - prevLine * (1 - BASELINE_AT);
    if (spacer > 0.5) out.push(para('', { line: spacer }));
    return { xml: out.join(''), blockLines };
  }

  // Justified paragraph; the web address (if any) blue and underlined.
  function textRuns(text, link) {
    if (!link || !text.includes(link)) return run(text);
    const i = text.indexOf(link);
    return run(text.slice(0, i)) + run(link, { color: LINK, underline: true }) + run(text.slice(i + link.length));
  }

  function sections(d) {
    const out = [];
    let first = true;
    for (const s of d.sections) {
      // After the table: 27pt to the first baseline; between sections 33pt.
      let gap = first ? 27 : 33;
      let prevLine = first ? 0 : 16.5;
      first = false;
      let breakNext = !!s.pageBreakBefore;
      if (s.heading) {
        out.push(para(run(s.heading, { bold: true, underline: true }),
          { line: 16.5, before: breakNext ? 0 : gapBefore(gap, prevLine, 16.5), pageBreakBefore: breakNext, keepNext: true }));
        breakNext = false;
        prevLine = 16.5;
        gap = 26.25;
      }
      let previousWasTerm = false;
      s.paragraphs.forEach((p, index) => {
        if (index > 0) gap = p.type === 'text' ? (previousWasTerm ? 33 : 26.25) : (previousWasTerm ? 16.5 : 26.25);
        const before = breakNext ? 0 : gapBefore(gap, prevLine, 16.5);
        if (p.type === 'text') {
          out.push(para(textRuns(p.text, p.link), { line: 16.5, before, align: 'both', pageBreakBefore: breakNext }));
          previousWasTerm = false;
        } else {
          const lines = (p.lines || []).join('\n');
          const marker = p.marker || '';
          const hanging = p.textX - p.left;
          let runs;
          const tabs = [];
          if (!marker) {
            runs = run(lines);
          } else if (p.colon) {
            tabs.push({ pos: p.textX - 3.75 });
            runs = run(`${marker}\t:\t${lines}`);
          } else {
            runs = run(`${marker}\t${lines}`);
          }
          out.push(para(runs, { line: 16.5, before, indLeft: p.textX, hanging: marker ? hanging : 0, tabs,
            pageBreakBefore: breakNext, align: 'left' }));
          previousWasTerm = true;
        }
        breakNext = false;
        prevLine = 16.5;
      });
    }
    return out.join('');
  }

  // "For and on Behalf of", 75.75pt to the signing rule, then the lines
  // under it (Times New Roman, bold italic, 10.5pt), kept on one page.
  function signatures(d, L) {
    if (!d.signatures.length) return '';
    const style = { font: SIGN_FONT, bold: true, italic: true, size: 10.5 };
    const colW = [225.75, 326.25 - (43.5 + 225.75), 225.75];
    const indent = 43.5 - L.textLeft;
    const inset = 5.25;
    const gap = d.sections.length ? 32.25 : 30.0;
    const cells = (fn) => [0, 1, 2].map((i) => {
      if (i === 1) return tc(colW[1], para('', { line: 1 }), { vAlign: 'top' });
      const sig = d.signatures[i === 0 ? 0 : 1];
      return tc(colW[i], sig ? fn(sig) : para('', { line: 1 }), { vAlign: 'top', mar: { left: inset }, borders: fn.borders && sig ? fn.borders : '' });
    });
    const heading = (sig) => para(run(sig.heading, style), { line: 13.5, keepNext: true });
    // The rule is 75.75pt below the heading's baseline.
    const spacer = () => para('', { line: 75.75 - 13.5 * (1 - BASELINE_AT), keepNext: true });
    const linesFn = (sig) => sig.lines.map((l, j) => {
      const text = l.colon ? `${l.text}\t:\t${l.value || ''}` : l.text;
      const gapTo = j === 0 ? 11.25 : j < 3 ? [11.25, 24.75, 39.0][j] - [11.25, 24.75, 39.0][j - 1] : 14.0;
      return para(run(text, style), { line: 13.5, before: j === 0 ? 0 : gapTo - 13.5, tabs: [{ pos: 72 }, { pos: 80 }], keepNext: j < sig.lines.length - 1 });
    }).join('');
    linesFn.borders = border('top', 0.75);
    const rows = [
      tr(cells(heading)),
      tr(cells(spacer)),
      tr(cells(linesFn)),
    ];
    const lead = para('', { line: Math.max(1, gap - 16.5 * (1 - BASELINE_AT) - 13.5 * BASELINE_AT), keepNext: true });
    return lead + tbl(colW, rows, { indent });
  }

  // "Received By : ____  Date : ____": bold labels, a line to write on
  // 6.68pt under the baseline, rows 34.5pt apart; on a page of its own
  // (under "Ref.: <number>") when the PDF has it there.
  const COLON_SPACE = 4.92; // ": " in 11pt EB Garamond
  function receipt(d, L) {
    const rows = d.receiptRows || [];
    if (!rows.length) return '';
    const out = [];
    const RULE_BELOW = 6.68, ROW = 34.5;
    const rowTop = ROW - RULE_BELOW; // from a row's top to its baseline
    let spacer;
    if (d.receiptNewPage) {
      out.push(para(run(`Ref.: ${d.number}`), { line: 16.5, pageBreakBefore: true, keepNext: true }));
      spacer = 32.9 - 16.5 * (1 - BASELINE_AT) - rowTop;
    } else {
      // 33pt under the table, or under the last line of text above.
      spacer = d.sections.length || d.signatures.length ? 33 - 16.5 * (1 - BASELINE_AT) - rowTop : 33 - rowTop;
    }
    out.push(para('', { line: Math.max(1, spacer), keepNext: true }));
    const width = L.textRight + 1 - L.textLeft;
    const widths = [81.65, 5.85, 168.0, 81.15, 5.85, width - 342.5];
    const style = { bold: true };
    const textCell = (w, text, left, keep) => tc(w, para(run(text, style), { line: 13.5, keepNext: keep }),
      { vAlign: 'bottom', mar: { left, bottom: RULE_BELOW - 13.5 * (1 - BASELINE_AT) } });
    const ruleCell = (w, keep) => tc(w, para('', { line: 1, keepNext: keep }), { vAlign: 'bottom', borders: border('bottom', 0.75) });
    const trs = rows.map((r, i) => {
      const keep = i < rows.length - 1;
      return tr([textCell(widths[0], r[0], 9.65, keep), textCell(widths[1], ':', 0, keep), ruleCell(widths[2], keep),
        textCell(widths[3], r[1], 9.15, keep), textCell(widths[4], ':', 0, keep), ruleCell(widths[5], keep)], { height: ROW, exact: true });
    });
    out.push(tbl(widths, trs, { indent: 0 }));
    return out.join('');
  }

  function closing(d) {
    if (!d.closingLine) return '';
    return para(run(d.closingLine, { font: SIGN_FONT, italic: true, size: 10.5 }),
      { line: 13.5, before: gapBefore(69, 13.5, 13.5), align: 'center' });
  }

  function documentXML(d) {
    const L = d;
    // The body starts where continuation pages do on the PDF (first baseline
    // 95.25pt); the first page's opening starts 9pt lower (104.25pt).
    const top = 82.0;
    const body = [para('', { line: 9.75 })];
    const open = opening(d, L);
    body.push(open.xml);
    if (d.columns.length) body.push(mainTable(d));
    body.push(sections(d));
    body.push(signatures(d, L));
    body.push(receipt(d, L));
    body.push(closing(d));
    body.push(para('', { line: 1 })); // Word expects the body to end with a paragraph
    const letter = d.paperSize === 'Letter';
    const pageW = letter ? 12240 : 11906;
    const pageH = letter ? 15840 : 16838;
    const sect = `<w:sectPr><w:headerReference w:type="default" r:id="rIdHeader"/><w:footerReference w:type="default" r:id="rIdFooter"/>` +
      `<w:pgSz w:w="${pageW}" w:h="${pageH}"/>` +
      `<w:pgMar w:top="${TW(top)}" w:right="${TW(L.pageWidth - L.textRight)}" w:bottom="${TW(L.pageHeight - L.contentBottom - 4)}" ` +
      `w:left="${TW(L.textLeft)}" w:header="0" w:footer="${TW(12.4)}" w:gutter="0"/></w:sectPr>`;
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:document ${NS}><w:body>${body.join('')}${sect}</w:body></w:document>`;
  }

  const NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' +
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" ' +
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' +
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

  function headerXML(d) {
    const cx = EMU(d.pageWidth);
    const cy = EMU(d.pageHeight);
    const pic = `<w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="0" behindDoc="1" locked="1" layoutInCell="1" allowOverlap="1">` +
      `<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionH>` +
      `<wp:positionV relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx="${cx}" cy="${cy}"/>` +
      `<wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/><wp:docPr id="1" name="Letterhead"/><wp:cNvGraphicFramePr/>` +
      `<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>` +
      `<pic:nvPicPr><pic:cNvPr id="1" name="letterhead.png"/><pic:cNvPicPr/></pic:nvPicPr>` +
      `<pic:blipFill><a:blip r:embed="rIdLetterhead"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>` +
      `<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>` +
      `</pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing>`;
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:hdr ${NS}>` +
      `<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr><w:r>${pic}</w:r></w:p></w:hdr>`;
  }

  function footerXML(d) {
    const style = { font: SIGN_FONT, italic: true, size: 9, color: GREY };
    const field = `<w:r>${rPr(style)}<w:fldChar w:fldCharType="begin"/></w:r><w:r>${rPr(style)}<w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>` +
      `<w:r>${rPr(style)}<w:fldChar w:fldCharType="separate"/></w:r>${run('1', style)}<w:r>${rPr(style)}<w:fldChar w:fldCharType="end"/></w:r>`;
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:ftr ${NS}>` +
      para(run('Page ', style) + field, { line: 10.5, align: 'right' }) + '</w:ftr>';
  }

  function stylesXML() {
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">` +
      `<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="${BODY_FONT}" w:hAnsi="${BODY_FONT}" w:cs="${BODY_FONT}" w:eastAsia="${BODY_FONT}"/>` +
      `<w:color w:val="000000"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-GB" w:eastAsia="zh-HK"/></w:rPr></w:rPrDefault>` +
      `<w:pPrDefault><w:pPr><w:spacing w:before="0" w:after="0" w:line="330" w:lineRule="exact"/></w:pPr></w:pPrDefault></w:docDefaults>` +
      `<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>` +
      `<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/>` +
      `<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>` +
      `</w:styles>`;
  }

  function settingsXML() {
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">` +
      `<w:embedTrueTypeFonts/><w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/>` +
      `<w:compat><w:doNotExpandShiftReturn/><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>` +
      `</w:settings>`;
  }

  // ---------- embedded fonts (ECMA-376 obfuscation) ----------

  function newGuid() {
    const hex = [];
    for (let i = 0; i < 32; i++) hex.push('0123456789ABCDEF'[Math.floor(Math.random() * 16)]);
    const h = hex.join('');
    return `{${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}}`;
  }

  // The first 32 bytes are XORed with the font key: the GUID's 16 bytes,
  // read from the end of the GUID string backwards.
  function obfuscate(bytes, guid) {
    const hex = guid.replace(/[{}-]/g, '');
    const key = [];
    for (let i = hex.length - 2; i >= 0; i -= 2) key.push(parseInt(hex.slice(i, i + 2), 16));
    const out = new Uint8Array(bytes);
    for (let i = 0; i < 32 && i < out.length; i++) out[i] ^= key[i % 16];
    return out;
  }

  function fontTableXML(embedded) {
    const tag = { regular: 'embedRegular', bold: 'embedBold', italic: 'embedItalic', boldItalic: 'embedBoldItalic' };
    const order = ['regular', 'bold', 'italic', 'boldItalic'];
    const embeds = order.filter((s) => embedded[s]).map((s) => `<w:${tag[s]} r:id="${embedded[s].rid}" w:fontKey="${embedded[s].guid}"/>`).join('');
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` +
      `<w:font w:name="${BODY_FONT}"><w:charset w:val="00"/><w:family w:val="roman"/><w:pitch w:val="variable"/>${embeds}</w:font>` +
      `<w:font w:name="${SIGN_FONT}"><w:charset w:val="00"/><w:family w:val="roman"/><w:pitch w:val="variable"/></w:font></w:fonts>`;
  }

  // ---------- zip (stored, no compression) ----------

  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(bytes) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  function utf8(s) { return new TextEncoder().encode(s); }

  function zip(files) {
    const chunks = [];
    const central = [];
    let offset = 0;
    const now = new Date();
    const dosTime = (now.getHours() << 11) | (now.getMinutes() << 5) | Math.floor(now.getSeconds() / 2);
    const dosDate = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
    for (const f of files) {
      const name = utf8(f.name);
      const data = typeof f.data === 'string' ? utf8(f.data) : f.data;
      const crc = crc32(data);
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, 0x0800, true);
      local.setUint16(8, 0, true);
      local.setUint16(10, dosTime, true);
      local.setUint16(12, dosDate, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, data.length, true);
      local.setUint32(22, data.length, true);
      local.setUint16(26, name.length, true);
      local.setUint16(28, 0, true);
      chunks.push(new Uint8Array(local.buffer), name, data);
      const c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true);
      c.setUint16(4, 20, true);
      c.setUint16(6, 20, true);
      c.setUint16(8, 0x0800, true);
      c.setUint16(10, 0, true);
      c.setUint16(12, dosTime, true);
      c.setUint16(14, dosDate, true);
      c.setUint32(16, crc, true);
      c.setUint32(20, data.length, true);
      c.setUint32(24, data.length, true);
      c.setUint16(28, name.length, true);
      c.setUint16(30, 0, true);
      c.setUint16(32, 0, true);
      c.setUint16(34, 0, true);
      c.setUint16(36, 0, true);
      c.setUint32(38, 0, true);
      c.setUint32(42, offset, true);
      central.push(new Uint8Array(c.buffer), name);
      offset += 30 + name.length + data.length;
    }
    const centralSize = central.reduce((a, b) => a + b.length, 0);
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(8, files.length, true);
    end.setUint16(10, files.length, true);
    end.setUint32(12, centralSize, true);
    end.setUint32(16, offset, true);
    const parts = chunks.concat(central, [new Uint8Array(end.buffer)]);
    const out = new Uint8Array(parts.reduce((a, b) => a + b.length, 0));
    let at = 0;
    for (const p of parts) { out.set(p, at); at += p.length; }
    return out;
  }

  function fromBase64(b64) {
    if (typeof atob === 'function') {
      const s = atob(b64);
      const out = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
      return out;
    }
    return new Uint8Array(Buffer.from(b64, 'base64'));
  }

  function toBase64(bytes) {
    if (typeof btoa === 'function') {
      let s = '';
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      return btoa(s);
    }
    return Buffer.from(bytes).toString('base64');
  }

  // ---------- package ----------

  function buildLetterDocx(d) {
    const files = [];
    const fontRels = [];
    const embedded = {};
    (d.fonts || []).forEach((f, i) => {
      const guid = newGuid();
      const rid = `rIdFont${i + 1}`;
      embedded[f.style] = { rid, guid };
      files.push({ name: `word/fonts/font${i + 1}.odttf`, data: obfuscate(fromBase64(f.data), guid) });
      fontRels.push(`<Relationship Id="${rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/font" Target="fonts/font${i + 1}.odttf"/>`);
    });
    const rels = (items) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${items.join('')}</Relationships>`;
    const created = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    files.unshift(
      { name: '[Content_Types].xml', data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Default Extension="png" ContentType="image/png"/>' +
        '<Default Extension="odttf" ContentType="application/vnd.openxmlformats-officedocument.obfuscatedFont"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
        '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>' +
        '<Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>' +
        '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>' +
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' +
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>' +
        '</Types>' },
      { name: '_rels/.rels', data: rels([
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>',
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>',
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>',
      ]) },
      { name: 'docProps/core.xml', data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">` +
        `<dc:title>${xml(`${d.title} ${d.number}`)}</dc:title><dc:creator>ScaffoldPro</dc:creator>` +
        `<dcterms:created xsi:type="dcterms:W3CDTF">${created}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${created}</dcterms:modified></cp:coreProperties>` },
      { name: 'docProps/app.xml', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>ScaffoldPro</Application></Properties>' },
      { name: 'word/document.xml', data: documentXML(d) },
      { name: 'word/_rels/document.xml.rels', data: rels([
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
        '<Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>',
        '<Relationship Id="rIdFonts" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/>',
        '<Relationship Id="rIdHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>',
        '<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>',
      ]) },
      { name: 'word/styles.xml', data: stylesXML() },
      { name: 'word/settings.xml', data: settingsXML() },
      { name: 'word/fontTable.xml', data: fontTableXML(embedded) },
      { name: 'word/_rels/fontTable.xml.rels', data: rels(fontRels) },
      { name: 'word/header1.xml', data: headerXML(d) },
      { name: 'word/_rels/header1.xml.rels', data: rels([
        '<Relationship Id="rIdLetterhead" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/letterhead.png"/>',
      ]) },
      { name: 'word/footer1.xml', data: footerXML(d) },
      { name: 'word/media/letterhead.png', data: fromBase64(d.letterheadPNG) },
    );
    return zip(files);
  }

  // ---------- BQ sheet ("PROFICIENCY QUOTATION") ----------
  //
  // The native side sends the sheet's rows and cells with their exact
  // positions (main.swift, BQSheet.layout). Here they become one Word table:
  // its grid is every cell edge, rows have their exact heights and fills,
  // text sits 2.625pt in from the rules with its baseline where the PDF has
  // it, and the banner, info and heading rows repeat on every page.

  const CALIBRI_SPACE = 0.2261; // a space, as a fraction of the size (Calibri / Carlito)
  // Line height for sheet text (a little over Calibri's own 1.22, so large
  // text isn't pushed down), and where its baseline falls in the line.
  const SHEET_LINE = 1.25;
  let SHEET_BASELINE_AT = BASELINE_AT;
  // Text inside a cell starts half a rule (0.375pt) in from the rule's centre.
  const HALF_RULE = 0.375;
  // Text ends this much further in on the right than it starts on the left.
  const RIGHT_EXTRA = 0.9;

  function buildSheetDocx(d) {
    // A sheet shrunk to fit one page has thinner rules and less padding.
    const k = d.scale || 1;
    const PAD = 2.625 * k, HALF = HALF_RULE * k, EXTRA = RIGHT_EXTRA * k;
    const edges = [...new Set(d.rows.flatMap((r) => r.cells.flatMap((c) => [c.x0, c.x1])).map((x) => Math.round(x * 1000) / 1000))]
      .sort((a, b) => a - b);
    const widths = edges.slice(1).map((x, i) => x - edges[i]);
    const at = (x) => edges.findIndex((e) => Math.abs(e - x) < 0.01);
    const rows = d.rows.map((row, r) => {
      // Rows joined to the next (the Notes box) have no rule between them.
      const joinedAbove = r > 0 && d.rows[r - 1].joinNext;
      const cells = row.cells.map((c) => {
        const span = at(c.x1) - at(c.x0);
        // A short row (a line of the Notes box) gets a shorter line, so the
        // baseline can still go where the PDF has it.
        const line = Math.min(c.size * SHEET_LINE, (row.height - c.baselineUp - 2 * HALF) / SHEET_BASELINE_AT);
        const font = c.font === 'title' ? 'Arial' : 'Calibri';
        const style = { font, size: c.size, bold: c.font === 'title' };
        const figure = c.align === 'right' || c.align === 'money';
        const inner = c.x1 - c.x0 - (PAD - HALF) * 2 - EXTRA - (figure ? c.size * CALIBRI_SPACE : 0);
        let runs;
        // Placed with space before the paragraph (cell top margins are
        // shared across a row in some Word-compatible apps), so the
        // baseline is where the PDF has it.
        const before = Math.max(0, row.height - c.baselineUp - line * SHEET_BASELINE_AT - 2 * HALF);
        let opts = { line, before, align: { center: 'center', right: 'right' }[c.align] || 'left', keepNext: !!row.joinNext };
        const linkAt = c.link ? c.text.indexOf(c.link) : -1;
        if (c.align === 'money' && c.text) {
          runs = run(`$\t${c.text}`, style);
          opts = { line, before, align: 'left', tabs: [{ val: 'right', pos: inner }] };
        } else if (linkAt >= 0) {
          // A web address: blue and underlined, as in the PDF.
          runs = run(c.text.slice(0, linkAt), style) + run(c.link, { ...style, color: '1155CC', underline: true }) +
            run(c.text.slice(linkAt + c.link.length), style);
        } else {
          runs = run(c.text, style);
        }
        const shade = row.fill ? `<w:shd w:val="clear" w:color="auto" w:fill="${row.fill}"/>` : '';
        // Centred text needs no side padding (and so never wraps).
        const side = c.align === 'center' ? 0 : PAD - HALF;
        const joins = (joinedAbove ? '<w:top w:val="nil"/>' : '') + (row.joinNext ? '<w:bottom w:val="nil"/>' : '');
        const pr = `<w:tcW w:w="${TW(c.x1 - c.x0)}" w:type="dxa"/>${span > 1 ? `<w:gridSpan w:val="${span}"/>` : ''}` +
          `${joins ? `<w:tcBorders>${joins}</w:tcBorders>` : ''}${shade}<w:noWrap/>` +
          `<w:tcMar><w:top w:w="0" w:type="dxa"/><w:left w:w="${TW(side)}" w:type="dxa"/>` +
          '<w:bottom w:w="0" w:type="dxa"/>' +
          `<w:right w:w="${TW(side + EXTRA + (figure ? c.size * CALIBRI_SPACE : 0))}" w:type="dxa"/></w:tcMar><w:vAlign w:val="top"/>`;
        return `<w:tc><w:tcPr>${pr}</w:tcPr>${para(runs, opts)}</w:tc>`;
      });
      return `<w:tr><w:trPr><w:cantSplit/><w:trHeight w:val="${TW(row.height)}" w:hRule="exact"/>${row.repeats ? '<w:tblHeader/>' : ''}</w:trPr>${cells.join('')}</w:tr>`;
    });
    const sides = ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'];
    const table = `<w:tbl><w:tblPr><w:tblW w:w="${TW(d.right - d.left)}" w:type="dxa"/><w:tblInd w:w="0" w:type="dxa"/>` +
      `<w:tblBorders>${sides.map((side) => border(side, 0.75 * k)).join('')}</w:tblBorders><w:tblLayout w:type="fixed"/>` +
      '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar>' +
      '<w:tblLook w:val="0000" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/></w:tblPr>' +
      `<w:tblGrid>${widths.map((w) => `<w:gridCol w:w="${TW(w)}"/>`).join('')}</w:tblGrid>${rows.join('')}</w:tbl>`;
    const sect = `<w:sectPr><w:pgSz w:w="${TW(d.pageWidth)}" w:h="${TW(d.pageHeight)}"${d.landscape ? ' w:orient="landscape"' : ''}/>` +
      `<w:pgMar w:top="${TW(d.top)}" w:right="${TW(Math.max(0, d.pageWidth - d.right))}" w:bottom="${TW(d.pageHeight - d.bottomLimit)}" ` +
      `w:left="${TW(d.left)}" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>`;
    const documentXML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:document ${NS}><w:body>${table}` +
      `${para('', { line: 1 })}${sect}</w:body></w:document>`;
    const rels = (items) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${items.join('')}</Relationships>`;
    const created = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    return zip([
      { name: '[Content_Types].xml', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
        '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>' +
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>' +
        '</Types>' },
      { name: '_rels/.rels', data: rels([
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>',
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>',
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>',
      ]) },
      { name: 'docProps/core.xml', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
        `<dc:title>${xml(`${d.title} ${d.number}`)}</dc:title><dc:creator>ScaffoldPro</dc:creator>` +
        `<dcterms:created xsi:type="dcterms:W3CDTF">${created}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${created}</dcterms:modified></cp:coreProperties>` },
      { name: 'docProps/app.xml', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>ScaffoldPro</Application></Properties>' },
      { name: 'word/document.xml', data: documentXML },
      { name: 'word/_rels/document.xml.rels', data: rels([
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
        '<Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>',
      ]) },
      { name: 'word/styles.xml', data: stylesXML().replace(new RegExp(BODY_FONT, 'g'), 'Calibri') },
      { name: 'word/settings.xml', data: settingsXML().replace('<w:embedTrueTypeFonts/>', '') },
    ]);
  }

  async function exportWord(fetchLayout) {
    const layout = await fetchLayout();
    if (!layout || !layout.ok) return { ok: false, error: (layout && layout.error) || 'The Word document couldn\u2019t be prepared.' };
    const bytes = layout.kind === 'sheet' ? buildSheetDocx(layout) : buildLetterDocx(layout);
    return root.api.files.saveWord({
      projectNumber: layout.projectNumber, subfolder: layout.subfolder, fileName: layout.fileName,
      reference: layout.number, data: toBase64(bytes),
    });
  }

  root.buildLetterDocx = buildLetterDocx;
  root.buildSheetDocx = buildSheetDocx;
  root.__setSheetBaseline = (v) => { SHEET_BASELINE_AT = v; };
  root.exportWord = exportWord;
})(typeof window !== 'undefined' ? window : globalThis);
