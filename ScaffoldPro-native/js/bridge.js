'use strict';
/**
 * Replaces Electron's preload.js + contextBridge. There's no separate
 * preload process here — main.swift injects this file's contents as a
 * WKUserScript at document-start, so `window.api` exists before any page
 * script runs.
 *
 * Native calls go out via window.webkit.messageHandlers.native.postMessage
 * and come back via window.__nativeCallback(id, ok, resultJson, error),
 * which main.swift invokes with webView.evaluateJavaScript(...). Every
 * dashboard.js / clients.js / sites.js / projects.js / project-detail.js /
 * price-lists.js file is untouched from the Electron version — they only
 * ever call window.api.*, never anything Electron-specific.
 */
(function () {
  const pending = new Map();
  let nextId = 1;

  function callNative(action, payload) {
    return new Promise((resolve, reject) => {
      const id = String(nextId++);
      pending.set(id, { resolve, reject });
      try {
        window.webkit.messageHandlers.native.postMessage({ id: id, action: action, payload: payload || {} });
      } catch (err) {
        pending.delete(id);
        reject(err);
      }
    });
  }

  window.__nativeCallback = function (id, ok, resultJson, errorMessage) {
    const entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    if (ok) {
      entry.resolve(resultJson === null || resultJson === undefined || resultJson === '' ? null : JSON.parse(resultJson));
    } else {
      entry.reject(new Error(errorMessage || 'Native call failed'));
    }
  };

  window.api = {
    clients: {
      list: (includeArchived) => callNative('clients:list', { includeArchived: !!includeArchived }),
      create: (input) => callNative('clients:create', input),
      update: (id, input) => callNative('clients:update', Object.assign({ id: id }, input)),
      setArchived: (id, archived) => callNative('clients:setArchived', { id: id, archived: archived }),
      detail: (id) => callNative('clients:detail', { id: id }),
    },
    sites: {
      list: (includeArchived) => callNative('sites:list', { includeArchived: !!includeArchived }),
      create: (input) => callNative('sites:create', input),
      update: (id, input) => callNative('sites:update', Object.assign({ id: id }, input)),
      setArchived: (id, archived) => callNative('sites:setArchived', { id: id, archived: archived }),
      detail: (id) => callNative('sites:detail', { id: id }),
    },
    // Clients or sites ('clients' / 'sites') to and from Excel.
    parties: {
      exportXLSX: (kind, includeArchived) => callNative('parties:exportXLSX', { kind: kind, includeArchived: !!includeArchived }),
      importPreview: (kind) => callNative('parties:importPreview', { kind: kind }),
      importApply: (token) => callNative('parties:importApply', { token: token }),
    },
    dashboard: {
      summary: () => callNative('dashboard:summary'),
    },
    search: {
      query: (query) => callNative('search:query', { query: query }),
    },
    activity: {
      listForProject: (projectId) => callNative('activity:listForProject', { projectId: projectId }),
    },
    priceLists: {
      list: () => callNative('priceLists:list'),
      searchItems: (params) => callNative('priceListItems:search', params),
      updateItem: (id, changes) => callNative('priceListItems:update', Object.assign({ id: id }, changes)),
      createItem: (sourceKey, input) => callNative('priceListItems:create', Object.assign({ sourceKey: sourceKey }, input)),
      archiveItem: (id) => callNative('priceListItems:archive', { id: id }),
      duplicateItem: (id) => callNative('priceListItems:duplicate', { id: id }),
      // One category's item ids in their new order (dragged in the Material List).
      reorderItems: (ids) => callNative('priceListItems:reorder', { ids: ids }),
      // Pinned items come first when picking items for a document.
      setPinned: (id, pinned) => callNative('priceListItems:setPinned', { id: id, pinned: !!pinned }),
      reorderPinned: (ids) => callNative('priceListItems:reorderPinned', { ids: ids }),
      importPreview: (sourceKey) => callNative('priceLists:importPreview', { sourceKey: sourceKey }),
      importApply: (token) => callNative('priceLists:importApply', { token: token }),
      exportCSV: (sourceKey) => callNative('priceLists:exportCSV', { sourceKey: sourceKey }),
      // "Unit Rates" PDF for a client: { itemIds, clientId, clientName, markupPercent, subject, notes }.
      // How the list is kept the same on every Mac → { mode: 'team' | 'icloud' | 'off', folder, otherMacs }.
      syncStatus: () => callNative('priceLists:syncStatus'),
      unitRatesPDF: (input) => callNative('priceLists:unitRatesPDF', input),
    },
    projects: {
      list: () => callNative('projects:list'),
      proposeNumber: () => callNative('projects:proposeNumber'),
      create: (input) => callNative('projects:create', input),
      get: (projectNumber) => callNative('projects:get', { projectNumber: projectNumber }),
      update: (id, input) => callNative('projects:update', Object.assign({ id: id }, input)),
      // A new project code: renames its folder and renumbers its draft documents.
      changeNumber: (id, projectNumber) => callNative('projects:changeNumber', { id: id, projectNumber: projectNumber }),
      updateStatus: (id, status) => callNative('projects:updateStatus', { id: id, status: status }),
      revealFolder: (projectNumber) => callNative('projects:revealFolder', { projectNumber: projectNumber }),
      uploadDrawing: (projectNumber, link) => callNative('projects:uploadDrawing', Object.assign({ projectNumber: projectNumber }, link || {})),
      // What a project holds (asked before deleting), and deleting it.
      contents: (id) => callNative('projects:contents', { id: id }),
      // Every project's documents and what each was made from (the Overview).
      overview: () => callNative('projects:overview'),
      remove: (id, confirm) => callNative('projects:delete', { id: id, confirm: confirm || null }),
    },
    drawings: {
      listForProject: (projectId) => callNative('drawings:listForProject', { projectId: projectId }),
      listForDocument: (linkedKind, linkedId) => callNative('drawings:listForDocument', { linkedKind: linkedKind, linkedId: linkedId }),
      setLink: (id, linkedKind, linkedId) => callNative('drawings:setLink', { id: id, linkedKind: linkedKind || null, linkedId: linkedId || null }),
      updateDescription: (id, description) => callNative('drawings:updateDescription', { id: id, description: description }),
      rename: (id, newName) => callNative('drawings:rename', { id: id, newName: newName }),
      archive: (id) => callNative('drawings:archive', { id: id }),
      removeReference: (id) => callNative('drawings:removeReference', { id: id }),
      relink: (id) => callNative('drawings:relink', { id: id }),
      replace: (id) => callNative('drawings:replace', { id: id }),
      open: (id) => callNative('drawings:open', { id: id }),
      reveal: (id) => callNative('drawings:reveal', { id: id }),
    },
    documents: {
      listForProject: (projectId) => callNative('documents:listForProject', { projectId: projectId }),
      // Filed with one of the project's BOQs / quotations (kind 'BOQ' | 'Quotation'), or not (null).
      setLink: (id, linkedKind, linkedId) => callNative('documents:setLink', { id: id, linkedKind: linkedKind || null, linkedId: linkedId || null }),
      upload: (projectNumber, category) => callNative('documents:upload', { projectNumber: projectNumber, category: category }),
      updateDescription: (id, description) => callNative('documents:updateDescription', { id: id, description: description }),
      rename: (id, newName) => callNative('documents:rename', { id: id, newName: newName }),
      archive: (id) => callNative('documents:archive', { id: id }),
      removeReference: (id) => callNative('documents:removeReference', { id: id }),
      relink: (id) => callNative('documents:relink', { id: id }),
      replace: (id) => callNative('documents:replace', { id: id }),
      open: (id) => callNative('documents:open', { id: id }),
      reveal: (id) => callNative('documents:reveal', { id: id }),
    },
    boq: {
      // How items are listed: 'code' | 'description' | 'manual' (as arranged).
      setLineSort: (id, mode) => callNative('boq:setLineSort', { id: id, mode: mode }),
      // The BOQ's own delivery schedule (Day 1, Day 2…); a quotation can copy it.
      deliverySchedule: (id) => callNative('quotations:deliverySchedule', { id: id }),
      // The schedule on its own, as the landscape sheet printed after the BOQ → { ok, error, path }.
      // (internal: with the days' internal notes.)
      deliverySchedulePDF: (id, internal, opts) => callNative('quotations:deliverySchedulePDF', Object.assign({ id: id, kind: 'BOQ', internal: !!internal }, opts || {})),
      addDeliveryDay: (id) => callNative('quotations:addDeliveryDay', { id: id }),
      updateDeliveryDay: (dayId, changes) => callNative('quotations:updateDeliveryDay', Object.assign({ id: dayId }, changes)),
      deleteDeliveryDay: (dayId) => callNative('quotations:deleteDeliveryDay', { id: dayId }),
      // Item names on the PDF in 'English' or 'Chinese' (null = Settings' choice).
      setLanguage: (id, language) => callNative('boq:setLanguage', { id: id, language: language || null }),
      // Several BOQs added together into one new Draft BOQ → { ok, error, id }.
      combine: (ids) => callNative('boq:combine', { ids: ids }),
      // The landscape sheet's Terms box: { terms? }.
      updateSheetExtras: (id, changes) => callNative('boq:updateSheetExtras', Object.assign({ id: id }, changes)),
      listForProject: (projectId) => callNative('boq:listForProject', { projectId: projectId }),
      setOrientation: (id, orientation) => callNative('boq:setOrientation', { id: id, orientation: orientation }),
      // A discount on an item's unit rate: 'None' | 'Percent' | 'Amount' (off each unit).
      updateLineDiscount: (id, discountType, discountValue) => callNative('boq:updateLineDiscount', { id: id, discountType: discountType, discountValue: discountValue }),
      // Rates listed after the total ({ title, rates: [{ name, rate, unit }], note }), or null to remove.
      setRatesSection: (id, section) => callNative('boq:setRatesSection', { id: id, section: section }),
      setCharges: (id, charges) => callNative('boq:setCharges', { id: id, charges: charges }),
      standardRates: () => callNative('boq:standardRates'),
      create: (projectId, projectNumber, pricingMode) =>
        callNative('boq:create', { projectId: projectId, projectNumber: projectNumber, pricingMode: pricingMode }),
      get: (id) => callNative('boq:get', { id: id }),
      addLineItem: (input) => callNative('boq:addLineItem', input),
      updateLineItem: (id, changes) => callNative('boq:updateLineItem', Object.assign({ id: id }, changes)),
      removeLineItem: (id) => callNative('boq:removeLineItem', { id: id }),
      updateStatus: (id, status) => callNative('boq:updateStatus', { id: id, status: status }),
      updateNotes: (id, notes) => callNative('boq:updateNotes', { id: id, notes: notes }),
      // force: also an issued one (after the page has asked twice).
      remove: (id, force) => callNative('boq:delete', { id: id, force: !!force }),
      // opts: { preview: true } → the PDF comes back to show (js/doc-preview.js) before it's saved.
      exportPDF: (id, opts) => callNative('boq:exportPDF', Object.assign({ id: id }, opts || {})),
      exportWord: (id) => callNative('boq:exportWord', { id: id }),
      updateDetails: (id, changes) => callNative('boq:updateDetails', Object.assign({ id: id }, changes)),
      moveLineItem: (id, direction) => callNative('boq:moveLineItem', { id: id, direction: direction }),
      // The BOQ's line ids in their new order (dragged in the editor).
      reorderLineItems: (boqId, ids) => callNative('boq:reorderLineItems', { boqId: boqId, ids: ids }),
      duplicateLineItem: (id) => callNative('boq:duplicateLineItem', { id: id }),
      updateLineNotes: (id, notes) => callNative('boq:updateLineNotes', { id: id, notes: notes }),
      print: (id) => callNative('boq:print', { id: id }),
    },
    quotations: {
      // Delivery schedule: how many of each material go to site on Day 1, Day 2… (not tied to stock).
      deliverySchedule: (id) => callNative('quotations:deliverySchedule', { id: id }),
      // The schedule on its own, as the landscape sheet printed after the quotation → { ok, error, path }.
      deliverySchedulePDF: (id, internal, opts) => callNative('quotations:deliverySchedulePDF', Object.assign({ id: id, kind: 'Quotation', internal: !!internal }, opts || {})),
      addDeliveryDay: (id) => callNative('quotations:addDeliveryDay', { id: id }),
      // changes: { date?, sent?, note?, internalNote?, quantities?: { lineId: qty } }
      updateDeliveryDay: (dayId, changes) => callNative('quotations:updateDeliveryDay', Object.assign({ id: dayId }, changes)),
      deleteDeliveryDay: (dayId) => callNative('quotations:deleteDeliveryDay', { id: dayId }),
      // The BOQ's delivery schedule onto this quotation (replacing its own) → { ok, error, skipped }.
      copyScheduleFromBOQ: (quotationId, boqId) => callNative('quotations:copyScheduleFromBOQ', { quotationId: quotationId, boqId: boqId }),
      // Kept in step with a BOQ both ways (its items become the BOQ's), or not.
      linkBOQ: (quotationId, boqId) => callNative('quotations:linkBOQ', { quotationId: quotationId, boqId: boqId }),
      unlinkBOQ: (id) => callNative('quotations:unlinkBOQ', { id: id }),
      // Item names on the PDF in 'English' or 'Chinese' (null = Settings' choice).
      setLanguage: (id, language) => callNative('quotations:setLanguage', { id: id, language: language || null }),
      // 'Portrait' (the letterhead) or 'Landscape' (the BQ sheet with terms and signatures).
      setOrientation: (id, orientation) => callNative('quotations:setOrientation', { id: id, orientation: orientation }),
      listForProject: (projectId) => callNative('quotations:listForProject', { projectId: projectId }),
      create: (projectId, projectNumber, boqId, pricingMode) =>
        callNative('quotations:create', { projectId: projectId, projectNumber: projectNumber, boqId: boqId || null, pricingMode: pricingMode || 'Rental' }),
      get: (id) => callNative('quotations:get', { id: id }),
      addLineItem: (input) => callNative('quotations:addLineItem', input),
      updateLineItem: (id, changes) => callNative('quotations:updateLineItem', Object.assign({ id: id }, changes)),
      removeLineItem: (id) => callNative('quotations:removeLineItem', { id: id }),
      updateLineDiscount: (id, discountType, discountValue) => callNative('quotations:updateLineDiscount', { id: id, discountType: discountType, discountValue: discountValue }),
      // Extra sections: kind 'Priced' | 'Rates' | 'Note'.
      addBlock: (quotationId, kind) => callNative('quotations:addBlock', { quotationId: quotationId, kind: kind }),
      updateBlock: (id, changes) => callNative('quotations:updateBlock', Object.assign({ id: id }, changes)),
      moveBlock: (id, up) => callNative('quotations:moveBlock', { id: id, up: !!up }),
      setLineSort: (id, mode) => callNative('quotations:setLineSort', { id: id, mode: mode }),
      // The quotation's item ids in their new order (dragged) — linked, its BOQ follows.
      reorderLineItems: (quotationId, ids) => callNative('quotations:reorderLineItems', { quotationId: quotationId, ids: ids }),
      reorderBlocks: (quotationId, ids) => callNative('quotations:reorderBlocks', { quotationId: quotationId, ids: ids }),
      removeBlock: (id) => callNative('quotations:removeBlock', { id: id }),
      // Moves these lines and sections to a new quotation, listed under this one: { ok, error, id, number }.
      split: (id, lineIds, blockIds) => callNative('quotations:split', { id: id, lineIds: lineIds, blockIds: blockIds }),
      // A subsidiary's lines and sections back onto its parent; the subsidiary is deleted: { ok, error, id (the parent) }.
      revertSplit: (id) => callNative('quotations:revertSplit', { id: id }),
      addBlockLine: (blockId, line) => callNative('quotations:addBlockLine', Object.assign({ blockId: blockId }, line)),
      // The standard manpower rates (Settings), into a rates section — or a new one if blockId is null.
      addStandardRates: (quotationId, blockId) => callNative('quotations:addStandardRates', { quotationId: quotationId, blockId: blockId || null }),
      updateHeader: (id, header) => callNative('quotations:updateHeader', Object.assign({ id: id }, header)),
      updateLetterFields: (id, changes) => callNative('quotations:updateLetterFields', Object.assign({ id: id }, changes)),
      importFromBOQ: (quotationId, boqId, replaceExisting) =>
        callNative('quotations:importFromBOQ', { quotationId: quotationId, boqId: boqId, replaceExisting: !!replaceExisting }),
      updateStatus: (id, status) => callNative('quotations:updateStatus', { id: id, status: status }),
      // force: also an issued one (after the page has asked twice).
      remove: (id, force) => callNative('quotations:delete', { id: id, force: !!force }),
      // opts: { preview: true } → the PDF comes back to show (js/doc-preview.js) before it's saved, withSubsidiaries.
      exportPDF: (id, opts) => callNative('quotations:exportPDF', Object.assign({ id: id }, opts || {})),
      // One linked line taken out of the link (linked false), or linked again
      // with prevail 'boq' | 'quotation' — whose figures are kept.
      setLineLink: (id, linked, prevail) => callNative('quotations:setLineLink', { id: id, linked: !!linked, prevail: prevail || null }),
      exportWord: (id) => callNative('quotations:exportWord', { id: id }),
      // opts: { withSubsidiaries } — its subsidiaries printed after it.
      print: (id, opts) => callNative('quotations:print', Object.assign({ id: id }, opts || {})),
      // Several quotations in one PDF (in the order given), optionally each with its drawings.
      combinePDF: (ids, includeDrawings, opts) => callNative('quotations:combinePDF', Object.assign({ ids: ids, includeDrawings: !!includeDrawings }, opts || {})),
      // The client's signed copy (PDF or photo/scan), kept in the project's Quotations folder.
      uploadSigned: (id) => callNative('quotations:uploadSigned', { id: id }),
      saveSignedFile: (id, fileName, base64) => callNative('quotations:saveSignedFile', { id: id, fileName: fileName, base64: base64 }),
      // action: 'open' | 'reveal' | 'remove' (the file stays in the folder).
      signedCopy: (id, action) => callNative('quotations:signedCopy', { id: id, action: action }),
      setSignedNotNeeded: (id, notNeeded) => callNative('quotations:setSignedNotNeeded', { id: id, notNeeded: !!notNeeded }),
    },
    invoices: {
      listForProject: (projectId) => callNative('invoices:listForProject', { projectId: projectId }),
      create: (projectId, projectNumber, quotationId, options) =>
        callNative('invoices:create', Object.assign({ projectId: projectId, projectNumber: projectNumber, quotationId: quotationId || null }, options || {})),
      updateRental: (id, changes) => callNative('invoices:updateRental', Object.assign({ id: id }, changes)),
      get: (id) => callNative('invoices:get', { id: id }),
      addLineItem: (input) => callNative('invoices:addLineItem', input),
      updateLineItem: (id, changes) => callNative('invoices:updateLineItem', Object.assign({ id: id }, changes)),
      removeLineItem: (id) => callNative('invoices:removeLineItem', { id: id }),
      updateLineDiscount: (id, discountType, discountValue) => callNative('invoices:updateLineDiscount', { id: id, discountType: discountType, discountValue: discountValue }),
      updateHeader: (id, header) => callNative('invoices:updateHeader', Object.assign({ id: id }, header)),
      updateStatus: (id, status) => callNative('invoices:updateStatus', { id: id, status: status }),
      recordPayment: (id, amount, details) => callNative('invoices:recordPayment', Object.assign({ id: id, amount: amount }, details || {})),
      // force: also an issued one (after the page has asked twice).
      remove: (id, force) => callNative('invoices:delete', { id: id, force: !!force }),
      // opts: { preview: true } → the PDF comes back to show (js/doc-preview.js) before it's saved.
      exportPDF: (id, opts) => callNative('invoices:exportPDF', Object.assign({ id: id }, opts || {})),
      exportWord: (id) => callNative('invoices:exportWord', { id: id }),
      print: (id) => callNative('invoices:print', { id: id }),
    },
    // Who made a project or document and who last worked on it → { createdBy, lastEditedBy, lastEditedAt, mine }.
    authors: {
      get: (kind, id, number) => callNative('documents:authors', { kind: kind, id: id || '', number: number || null }),
      // BOQ › Quotation › Delivery Notes › Invoices linked to a document.
      chain: (kind, id) => callNative('documents:chain', { kind: kind, id: id }),
    },
    // Letters on the letterhead (the letter editor).
    letters: {
      list: (projectId) => callNative('letters:list', { projectId: projectId || null }),
      // → { ok, error, id }; addressed to the client (or the project's client).
      create: (input) => callNative('letters:create', input || {}),
      get: (id) => callNative('letters:get', { id: id }),
      // changes: { letterDate?, recipientName?, recipientAddress?, attention?, yourRef?, subject?, projectId?, clientId?, bodyHTML? }
      update: (id, changes) => callNative('letters:update', Object.assign({ id: id }, changes)),
      updateStatus: (id, status) => callNative('letters:updateStatus', { id: id, status: status }),
      remove: (id, force) => callNative('letters:delete', { id: id, force: !!force }),
      exportPDF: (id, opts) => callNative('letters:exportPDF', Object.assign({ id: id }, opts || {})),
      print: (id) => callNative('letters:print', { id: id }),
      // PDFs / pictures chosen and copied for an annexure (a new one when attachmentId is null) → { ok, attachments }.
      addAttachmentFiles: (id, attachmentId) => callNative('letters:addAttachmentFiles', { id: id, attachmentId: attachmentId || null }),
      openAttachmentFile: (path) => callNative('letters:openAttachmentFile', { path: path }),
      // The letterhead and footer as a page-sized PNG → { png (base64), paperSize }.
      letterhead: () => callNative('letters:letterhead'),
    },
    // Several of a document's quantities at once ("Multiply…" and its Undo).
    // kind: 'boq' | 'quotation' | 'invoice' | 'deliveryNote';
    // quantities: { lineId: newQuantity } → { ok, error }.
    lines: {
      setQuantities: (kind, documentId, quantities) => callNative('lines:setQuantities', { kind: kind, documentId: documentId, quantities: quantities }),
    },
    deliveryNotes: {
      // The copy signed on site (a PDF, or a photo or scan): chosen in a panel, or a dropped file.
      // It's kept in the project's Delivery Notes folder and added after the invoice that bills it.
      uploadSigned: (id) => callNative('deliveryNotes:uploadSigned', { id: id }),
      saveSignedFile: (id, fileName, base64) => callNative('deliveryNotes:saveSignedFile', { id: id, fileName: fileName, base64: base64 }),
      // 'open' | 'reveal' | 'remove'
      signedCopy: (id, action) => callNative('deliveryNotes:signedCopy', { id: id, action: action }),
      // Item names on the PDF in 'English' or 'Chinese' (null = Settings' choice).
      setLanguage: (id, language) => callNative('deliveryNotes:setLanguage', { id: id, language: language || null }),
      // Several delivery notes added together into one new Draft note → { ok, error, id }.
      combine: (ids) => callNative('deliveryNotes:combine', { ids: ids }),
      // A quotation's materials into a Draft note (quantities added to items already on it) → { ok, added, error }.
      importQuotation: (id, quotationId, replaceExisting) =>
        callNative('deliveryNotes:importQuotation', { id: id, quotationId: quotationId, replaceExisting: !!replaceExisting }),
      listForProject: (projectId) => callNative('deliveryNotes:listForProject', { projectId: projectId }),
      create: (projectId, projectNumber, quotationId, invoiceId) =>
        callNative('deliveryNotes:create', { projectId: projectId, projectNumber: projectNumber, quotationId: quotationId || null, invoiceId: invoiceId || null }),
      get: (id) => callNative('deliveryNotes:get', { id: id }),
      addLineItem: (input) => callNative('deliveryNotes:addLineItem', input),
      updateLineItem: (id, changes) => callNative('deliveryNotes:updateLineItem', Object.assign({ id: id }, changes)),
      removeLineItem: (id) => callNative('deliveryNotes:removeLineItem', { id: id }),
      updateHeader: (id, header) => callNative('deliveryNotes:updateHeader', Object.assign({ id: id }, header)),
      updateStatus: (id, status) => callNative('deliveryNotes:updateStatus', { id: id, status: status }),
      // force: also an issued one (after the page has asked twice).
      remove: (id, force) => callNative('deliveryNotes:delete', { id: id, force: !!force }),
      // opts: { preview: true } → the PDF comes back to show (js/doc-preview.js) before it's saved.
      exportPDF: (id, opts) => callNative('deliveryNotes:exportPDF', Object.assign({ id: id }, opts || {})),
      exportWord: (id) => callNative('deliveryNotes:exportWord', { id: id }),
      print: (id) => callNative('deliveryNotes:print', { id: id }),
    },
    settings: {
      get: () => callNative('settings:get'),
      update: (input) => callNative('settings:update', input),
      chooseLogo: () => callNative('settings:chooseLogo'),
      removeLogo: () => callNative('settings:removeLogo'),
      logoPreview: () => callNative('settings:logoPreview'),
      numberPreview: (type, template) => callNative('settings:numberPreview', { type: type, template: template }),
    },
    // Word copies built by js/docx-export.js, saved next to the PDFs.
    files: {
      saveWord: (input) => callNative('files:saveWord', input),
      // The PDF shown in the preview (js/doc-preview.js): save it into the project folder, or let it go.
      savePreview: (token) => callNative('files:savePreview', { token: token }),
      discardPreview: (token) => callNative('files:discardPreview', { token: token }),
      // A file just saved: open it, or show it in Finder.
      openSaved: (path, reveal) => callNative('files:openSaved', { path: path, reveal: !!reveal }),
      // Shows a BOQ / quotation / invoice / delivery note's file in Finder.
      // kind: 'BOQ', 'Quotation', 'Invoice' or 'DeliveryNote'.
      locateDocument: (kind, id) => callNative('files:locateDocument', { kind: kind, id: id }),
      // Several at once: one Finder window with all their files selected.
      locateDocuments: (kind, ids) => callNative('files:locateDocuments', { kind: kind, ids: ids }),
      // Several quotations or BOQs ('Quotation' | 'BOQ') in one PDF, optionally each with its drawings.
      combinePDF: (kind, ids, includeDrawings, opts) => callNative('documents:combinePDF', Object.assign({ kind: kind, ids: ids, includeDrawings: !!includeDrawings }, opts || {})),
      // Files dropped onto a project's Drawings or Documents section.
      // target: 'drawing' (options: linkedKind, linkedId) or 'document'
      // (options: category); files: [{ name, base64 }].
      dropIntoProject: (projectNumber, target, options, files) => callNative('files:dropIntoProject',
        Object.assign({ projectNumber: projectNumber, target: target, files: files }, options || {})),
    },
    // Stock list: what's in the yard, on hire and owned; movements.
    stock: {
      data: () => callNative('stock:data'),
      addMovement: (movement) => callNative('stock:addMovement', movement),
      // Many lines at once: { kind, date, reference, notes, projectId, deliveryNoteId (a return answering a signed
      // delivery note), company (RentOut / RentBack), lines: [{ priceListItemId, itemCode, itemDescription, unit, quantity }] }
      addMovements: (batch) => callNative('stock:addMovements', batch),
      // A signed delivery note's items still out: when to ask whether they're back.
      returnCheck: (deliveryNoteId, date) => callNative('stock:returnCheck', { deliveryNoteId: deliveryNoteId, date: date }),
      deleteBatch: (batchId) => callNative('stock:deleteBatch', { batchId: batchId }),
      deleteMovement: (id) => callNative('stock:deleteMovement', { id: id }),
    },
    // Accounts: receivables, payments and expenses.
    accounts: {
      data: () => callNative('accounts:data'),
      saveExpense: (expense) => callNative('accounts:saveExpense', expense),
      deleteExpense: (id) => callNative('accounts:deleteExpense', { id: id }),
      // where: { projectNumber, subfolder } or { adminFolder } — else Administration › Accounts.
      saveCSV: (fileName, csv, where) => callNative('accounts:saveCSV', Object.assign({ fileName: fileName, csv: csv }, where || {})),
      // Liabilities: money the company owes, and payments made towards it.
      saveLiability: (liability) => callNative('accounts:saveLiability', liability),
      deleteLiability: (id) => callNative('accounts:deleteLiability', { id: id }),
      addLiabilityPayment: (payment) => callNative('accounts:addLiabilityPayment', payment),
      deleteLiabilityPayment: (id) => callNative('accounts:deleteLiabilityPayment', { id: id }),
    },
    employees: {
      list: () => callNative('employees:list'),
      // Adds (no id) or changes an employee → { ok, error, id }.
      save: (employee) => callNative('employees:save', employee),
      remove: (id) => callNative('employees:delete', { id: id }),
      // A month's pay into Expenses: { month: 'yyyy-mm', date, lines: [{ employeeId, pay, mpf }] } → { ok, error, recorded, skipped }.
      recordPayroll: (input) => callNative('employees:recordPayroll', input),
    },
    // Automatic backup into the shared iCloud folder (Proficiency › William's Work).
    cloudBackup: {
      status: () => callNative('cloudBackup:status'),
      setEnabled: (enabled) => callNative('cloudBackup:setEnabled', { enabled: !!enabled }),
      backUpNow: () => callNative('cloudBackup:backUpNow'),
      chooseFolder: () => callNative('cloudBackup:chooseFolder'),
      useDefaultFolder: () => callNative('cloudBackup:useDefaultFolder'),
      reveal: () => callNative('cloudBackup:reveal'),
    },
    // Settings › Google Sheets: the who / when / what overview sheet, kept in step both ways.
    sheets: {
      status: () => callNative('sheets:status'),
      // Checks them with the sheet first → { ok, error }
      link: (url, secret) => callNative('sheets:link', { url: url, secret: secret }),
      unlink: () => callNative('sheets:unlink'),
      syncNow: () => callNative('sheets:syncNow'),
      // The Apps Script for the sheet, onto the clipboard.
      copyScript: () => callNative('sheets:copyScript'),
      openSheet: () => callNative('sheets:openSheet'),
    },
    // Sharing the data with other Macs through a shared (iCloud Drive) folder.
    // Scaffold inspections (Form 5 register): each project's records, and what's due.
    inspections: {
      list: (projectId) => callNative('inspections:list', { projectId: projectId }),
      // { id?, projectId, structure, location, inspectedOn, inspector, result, remarks, actionTaken, nextDue, dismantled } → { ok, error, id }
      save: (record) => callNative('inspections:save', record),
      remove: (id) => callNative('inspections:delete', { id: id }),
      due: (withinDays) => callNative('inspections:due', withinDays == null ? {} : { withinDays: withinDays }),
    },
    // The team's to-dos.
    tasks: {
      list: (projectId) => callNative('tasks:list', projectId ? { projectId: projectId } : {}),
      // { id?, title, notes, projectId, assignee, dueDate, priority } → { ok, error, id }
      save: (task) => callNative('tasks:save', task),
      setDone: (id, done) => callNative('tasks:setDone', { id: id, done: done }),
      remove: (id) => callNative('tasks:delete', { id: id }),
      people: () => callNative('tasks:people'),
    },
    // Everything dated between two days (yyyy-MM-dd).
    calendar: {
      events: (from, to) => callNative('calendar:events', { from: from, to: to }),
    },
    // Settings › Updates: { automatic: true|false } and/or { check: true } → { automatic }.
    updates: {
      get: () => callNative('app:updates', {}),
      set: (changes) => callNative('app:updates', changes),
    },
    // Marketing: the overview / follow-ups / references, and leads.
    marketing: {
      summary: () => callNative('marketing:summary'),
      leads: () => callNative('marketing:leads'),
      // { id? (to change one), company, contactPerson, phone, email, source, status, estimatedValue, nextFollowUp, owner, notes } → { ok, error, id }
      saveLead: (lead) => callNative('marketing:saveLead', lead),
      deleteLead: (id) => callNative('marketing:deleteLead', { id: id }),
      // Makes a client from the lead → { ok, error, id: the client's id }
      convertLead: (id) => callNative('marketing:convertLead', { id: id }),
      // Quotations issued to a client (null: everyone) from–to (yyyy-MM-dd) → { rows, total, wonCount, wonValue, … }
      clientReport: (clientId, from, to) => callNative('marketing:clientReport', { clientId: clientId || null, from: from, to: to }),
      // The same as a PDF on the letterhead — shown in the preview first.
      clientReportPDF: (clientId, from, to) => callNative('marketing:clientReportPDF', { clientId: clientId || null, from: from, to: to, preview: true }),
    },
    // Marketing › Promotions: campaigns, their targets, and their letters.
    promotions: {
      list: () => callNative('promotions:list'),
      save: (promotion) => callNative('promotions:save', { promotion: promotion }),
      remove: (id) => callNative('promotions:delete', { id: id }),
      // A draft letter for each target given that hasn't one → { ok, promotion }
      writeLetters: (id, targetIds) => callNative('promotions:writeLetters', { id: id, targetIds: targetIds }),
    },
    // This Mac's user: their page, and everyone's name colours.
    users: {
      page: () => callNative('users:page'),
      profiles: () => callNative('users:profiles'),
      // '#RRGGBB', or '' for the automatic colour.
      setColor: (color) => callNative('users:setColor', { color: color }),
      setName: (name) => callNative('users:setName', { name: name }),
      setTeam: (team) => callNative('users:setTeam', { team: team }),
    },
    // Undo / Redo the last action (js/undo.js): { ok, label, canUndo, canRedo, error }.
    history: {
      undo: () => callNative('history:undo'),
      redo: () => callNative('history:redo'),
    },
    // ScaffoldPro Web: this Mac serving the pages to browsers.
    web: {
      status: () => callNative('web:status'),
      configure: (input) => callNative('web:configure', input),
      endSession: (token) => callNative('web:endSession', { token }),
    },
    // Chat: Everyone, your team, and direct messages.
    chat: {
      page: () => callNative('chat:page'),
      messages: (conversation) => callNative('chat:messages', { conversation }),
      send: (input) => callNative('chat:send', input),
      edit: (id, text, del) => callNative('chat:edit', { id, text, delete: !!del }),
      react: (id, emoji) => callNative('chat:react', { id, emoji }),
      typing: (conversation) => callNative('chat:typing', { conversation }),
      attach: (conversation) => callNative('chat:attach', { conversation }),
      file: (file) => callNative('chat:file', { file }),
      setGifKey: (key) => callNative('chat:setGifKey', { key }),
    },
    // Asking a director to sign and chop a quotation.
    signatures: {
      page: () => callNative('signatures:page'),
      request: (quotationId, signer, note) => callNative('signatures:request', { quotationId, signer, note }),
      withdraw: (id) => callNative('signatures:withdraw', { id }),
      decline: (id, reply) => callNative('signatures:decline', { id, reply }),
      sign: (id) => callNative('signatures:sign', { id }),
      openFile: (path) => callNative('signatures:openFile', { path }),
      // The saved signed copy, for the preview → { ok, pages, fileName }
      previewSigned: (path) => callNative('signatures:previewSigned', { path }),
      // Takes back the signature and chop (the signed PDF goes to the Trash).
      unsign: (quotationId) => callNative('signatures:unsign', { quotationId }),
      chooseImage: (which) => callNative('signatures:chooseImage', { which }),
      removeImage: (which) => callNative('signatures:removeImage', { which }),
      image: (which) => callNative('signatures:image', { which }),
    },
    // Messages for everyone, or for one team, shown at the top of the Dashboard.
    // Costs › Manpower Rates: the workers, what we charge, and what each
    // rate provider charges us → { rates: [{ name, rate, unit, costs: { provider: rate } }], providers }.
    costs: {
      manpower: () => callNative('costs:manpower'),
      saveManpower: (input) => callNative('costs:saveManpower', input),
    },
    announcements: {
      page: () => callNative('announcements:page'),
      post: (input) => callNative('announcements:post', input),
      dismiss: (id) => callNative('announcements:dismiss', { id: id }),
      remove: (id) => callNative('announcements:delete', { id: id }),
    },
    team: {
      // The Team page: people, their devices, team, title and who signs.
      page: () => callNative('team:page'),
      setPerson: (input) => callNative('team:setPerson', input),
      status: () => callNative('team:status'),
      // Makes a shared folder from this Mac's data (asks where).
      start: () => callNative('team:start'),
      // Uses a shared folder set up on another Mac (asks for it).
      join: () => callNative('team:join'),
      // Back to this Mac's own data (after the app restarts).
      leave: () => callNative('team:leave'),
      setName: (name) => callNative('team:setName', { name: name }),
      reveal: () => callNative('team:reveal'),
    },
    app: {
      relaunch: () => callNative('app:relaunch'),
    },
    backup: {
      list: () => callNative('backup:list'),
      locations: () => callNative('backup:locations'),
      create: () => callNative('backup:create'),
      restore: (path) => callNative('backup:restore', { path: path }),
      chooseAndRestore: () => callNative('backup:chooseAndRestore'),
      reveal: (path) => callNative('backup:reveal', { path: path || '' }),
      revealDataFolder: () => callNative('backup:revealDataFolder'),
      // The automatic (12:00) backups and, while sharing, the local copy in Documents › ScaffoldPro.
      autoStatus: () => callNative('backup:autoStatus'),
      localCopyNow: () => callNative('backup:localCopyNow'),
      revealLocalCopy: () => callNative('backup:revealLocalCopy'),
    },
    workers: {
      list: (includeArchived) => callNative('workers:list', { includeArchived: !!includeArchived }),
      create: (input) => callNative('workers:create', input),
      update: (id, input) => callNative('workers:update', Object.assign({ id: id }, input)),
      setArchived: (id, archived) => callNative('workers:setArchived', { id: id, archived: archived }),
      revealFolder: (id) => callNative('workers:revealFolder', { id: id }),
    },
    workerDocuments: {
      list: (workerId) => callNative('workerDocuments:list', { workerId: workerId }),
      upload: (workerId, category, expiryDate) => callNative('workerDocuments:upload', { workerId: workerId, category: category, expiryDate: expiryDate || null }),
      update: (id, changes) => callNative('workerDocuments:update', Object.assign({ id: id }, changes)),
      archive: (id) => callNative('workerDocuments:archive', { id: id }),
      removeReference: (id) => callNative('workerDocuments:removeReference', { id: id }),
      relink: (id) => callNative('workerDocuments:relink', { id: id }),
      open: (id) => callNative('workerDocuments:open', { id: id }),
      reveal: (id) => callNative('workerDocuments:reveal', { id: id }),
    },
    adminDocuments: {
      list: () => callNative('adminDocuments:list'),
      upload: (category, expiryDate) => callNative('adminDocuments:upload', { category: category, expiryDate: expiryDate || null }),
      update: (id, changes) => callNative('adminDocuments:update', Object.assign({ id: id }, changes)),
      archive: (id) => callNative('adminDocuments:archive', { id: id }),
      removeReference: (id) => callNative('adminDocuments:removeReference', { id: id }),
      relink: (id) => callNative('adminDocuments:relink', { id: id }),
      open: (id) => callNative('adminDocuments:open', { id: id }),
      reveal: (id) => callNative('adminDocuments:reveal', { id: id }),
      expiring: (days) => callNative('adminDocuments:expiring', { days: days || 30 }),
    },
  };

  // ---- The Delete key never leaves the page ----
  //
  // In a web view, Delete (Backspace) pressed outside a text box goes back
  // to the previous page — easily done by accident, e.g. right after a
  // table is redrawn and the cursor has left the box. Only text boxes
  // get it.
  window.addEventListener('keydown', (e) => {
    if (e.key !== 'Backspace') return;
    const t = e.target;
    const editable = t && (t.isContentEditable || t.tagName === 'TEXTAREA' ||
      (t.tagName === 'INPUT' && !t.readOnly && !['button', 'checkbox', 'radio', 'submit', 'reset', 'file', 'image', 'range', 'color'].includes(t.type)));
    if (!editable) e.preventDefault();
  }, true);

  // ---- Changes from other Macs (team sharing) ----
  //
  // main.swift calls window.__sharedDataChanged({ stores, names }) when
  // another Mac's changes have been merged in. The page then refreshes to
  // show them: straight away, or — so nothing being typed is lost — once
  // no field has focus, no dialog is open and nothing is being dragged.
  // A page can handle it itself by setting window.onSharedDataChanged.

  const SCROLL_KEY = 'scaffoldpro.sharedRefresh';
  let waiting = null;

  function busy() {
    const a = document.activeElement;
    if (a && (a.isContentEditable || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT' ||
        (a.tagName === 'INPUT' && !['button', 'submit', 'checkbox', 'radio', 'file'].includes(a.type)))) return true;
    if (document.querySelector('.modal-backdrop:not(.hidden), .search-overlay:not(.hidden)')) return true;
    return !!(document.body && document.body.classList.contains('reordering'));
  }

  function toast(text) {
    if (!document.body) return;
    const el = document.createElement('div');
    el.className = 'sync-toast';
    el.textContent = text;
    document.body.appendChild(el);
    requestAnimationFrame(() => el.classList.add('show'));
    setTimeout(() => { el.classList.remove('show'); setTimeout(() => el.remove(), 400); }, 3800);
  }

  function refresh(change) {
    const who = (change.names || []).join(', ') || 'another Mac';
    if (typeof window.onSharedDataChanged === 'function') {
      window.onSharedDataChanged(change);
      toast(`Updated with changes from ${who}`);
      return;
    }
    const content = document.getElementById('content');
    try {
      sessionStorage.setItem(SCROLL_KEY, JSON.stringify({
        url: location.href, y: window.scrollY, content: content ? content.scrollTop : 0, who: who,
      }));
    } catch (e) { /* the page still refreshes */ }
    location.reload();
  }

  window.__sharedDataChanged = function (change) {
    const merged = waiting || { stores: [], names: [] };
    for (const key of ['stores', 'names']) {
      for (const v of (change && change[key]) || []) if (!merged[key].includes(v)) merged[key].push(v);
    }
    if (waiting) return; // already waiting for a quiet moment
    waiting = merged;
    const tryNow = () => {
      if (busy()) { setTimeout(tryNow, 1000); return; }
      // A field that was just left may still be saving.
      setTimeout(() => {
        if (busy()) { setTimeout(tryNow, 1000); return; }
        const c = waiting;
        waiting = null;
        refresh(c);
      }, 700);
    };
    tryNow();
  };

  // After such a refresh: back to the same place, and say what happened.
  window.addEventListener('load', () => {
    let saved = null;
    try {
      saved = JSON.parse(sessionStorage.getItem(SCROLL_KEY) || 'null');
      sessionStorage.removeItem(SCROLL_KEY);
    } catch (e) { saved = null; }
    if (!saved || saved.url !== location.href) return;
    const restore = () => {
      window.scrollTo(0, saved.y || 0);
      const content = document.getElementById('content');
      if (content) content.scrollTop = saved.content || 0;
    };
    // The page fills in its lists after loading; restore as they arrive.
    for (const ms of [0, 150, 400, 900]) setTimeout(restore, ms);
    toast(`Updated with changes from ${saved.who}`);
  });
})();
