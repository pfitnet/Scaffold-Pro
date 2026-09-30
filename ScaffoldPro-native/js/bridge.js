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
      // Item names on the PDF in 'English' or 'Chinese' (null = Settings' choice).
      setLanguage: (id, language) => callNative('boq:setLanguage', { id: id, language: language || null }),
      // Several BOQs added together into one new Draft BOQ → { ok, error, id }.
      combine: (ids) => callNative('boq:combine', { ids: ids }),
      // The landscape sheet's Terms box and signature box: { terms?, signatureSection? }.
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
      exportPDF: (id) => callNative('boq:exportPDF', { id: id }),
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
      addDeliveryDay: (id) => callNative('quotations:addDeliveryDay', { id: id }),
      // changes: { date?, sent?, note?, quantities?: { lineId: qty } }
      updateDeliveryDay: (dayId, changes) => callNative('quotations:updateDeliveryDay', Object.assign({ id: dayId }, changes)),
      deleteDeliveryDay: (dayId) => callNative('quotations:deleteDeliveryDay', { id: dayId }),
      // Item names on the PDF in 'English' or 'Chinese' (null = Settings' choice).
      setLanguage: (id, language) => callNative('quotations:setLanguage', { id: id, language: language || null }),
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
      reorderBlocks: (quotationId, ids) => callNative('quotations:reorderBlocks', { quotationId: quotationId, ids: ids }),
      removeBlock: (id) => callNative('quotations:removeBlock', { id: id }),
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
      exportPDF: (id) => callNative('quotations:exportPDF', { id: id }),
      exportWord: (id) => callNative('quotations:exportWord', { id: id }),
      print: (id) => callNative('quotations:print', { id: id }),
      // Several quotations in one PDF (in the order given), optionally each with its drawings.
      combinePDF: (ids, includeDrawings) => callNative('quotations:combinePDF', { ids: ids, includeDrawings: !!includeDrawings }),
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
      exportPDF: (id) => callNative('invoices:exportPDF', { id: id }),
      exportWord: (id) => callNative('invoices:exportWord', { id: id }),
      print: (id) => callNative('invoices:print', { id: id }),
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
      exportPDF: (id) => callNative('letters:exportPDF', { id: id }),
      print: (id) => callNative('letters:print', { id: id }),
      // The letterhead and footer as a page-sized PNG → { png (base64), paperSize }.
      letterhead: () => callNative('letters:letterhead'),
    },
    deliveryNotes: {
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
      exportPDF: (id) => callNative('deliveryNotes:exportPDF', { id: id }),
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
      // Shows a BOQ / quotation / invoice / delivery note's file in Finder.
      // kind: 'BOQ', 'Quotation', 'Invoice' or 'DeliveryNote'.
      locateDocument: (kind, id) => callNative('files:locateDocument', { kind: kind, id: id }),
      // Several at once: one Finder window with all their files selected.
      locateDocuments: (kind, ids) => callNative('files:locateDocuments', { kind: kind, ids: ids }),
      // Several quotations or BOQs ('Quotation' | 'BOQ') in one PDF, optionally each with its drawings.
      combinePDF: (kind, ids, includeDrawings) => callNative('documents:combinePDF', { kind: kind, ids: ids, includeDrawings: !!includeDrawings }),
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
    // Sharing the data with other Macs through a shared (iCloud Drive) folder.
    team: {
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
