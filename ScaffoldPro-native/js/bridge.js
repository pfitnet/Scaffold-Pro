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
      importPreview: (sourceKey) => callNative('priceLists:importPreview', { sourceKey: sourceKey }),
      importApply: (token) => callNative('priceLists:importApply', { token: token }),
      exportCSV: (sourceKey) => callNative('priceLists:exportCSV', { sourceKey: sourceKey }),
    },
    projects: {
      list: () => callNative('projects:list'),
      proposeNumber: () => callNative('projects:proposeNumber'),
      create: (input) => callNative('projects:create', input),
      get: (projectNumber) => callNative('projects:get', { projectNumber: projectNumber }),
      update: (id, input) => callNative('projects:update', Object.assign({ id: id }, input)),
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
      remove: (id) => callNative('boq:delete', { id: id }),
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
      remove: (id) => callNative('quotations:delete', { id: id }),
      exportPDF: (id) => callNative('quotations:exportPDF', { id: id }),
      exportWord: (id) => callNative('quotations:exportWord', { id: id }),
      print: (id) => callNative('quotations:print', { id: id }),
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
      remove: (id) => callNative('invoices:delete', { id: id }),
      exportPDF: (id) => callNative('invoices:exportPDF', { id: id }),
      exportWord: (id) => callNative('invoices:exportWord', { id: id }),
      print: (id) => callNative('invoices:print', { id: id }),
    },
    deliveryNotes: {
      listForProject: (projectId) => callNative('deliveryNotes:listForProject', { projectId: projectId }),
      create: (projectId, projectNumber, quotationId, invoiceId) =>
        callNative('deliveryNotes:create', { projectId: projectId, projectNumber: projectNumber, quotationId: quotationId || null, invoiceId: invoiceId || null }),
      get: (id) => callNative('deliveryNotes:get', { id: id }),
      addLineItem: (input) => callNative('deliveryNotes:addLineItem', input),
      updateLineItem: (id, changes) => callNative('deliveryNotes:updateLineItem', Object.assign({ id: id }, changes)),
      removeLineItem: (id) => callNative('deliveryNotes:removeLineItem', { id: id }),
      updateHeader: (id, header) => callNative('deliveryNotes:updateHeader', Object.assign({ id: id }, header)),
      updateStatus: (id, status) => callNative('deliveryNotes:updateStatus', { id: id, status: status }),
      remove: (id) => callNative('deliveryNotes:delete', { id: id }),
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
      saveCSV: (fileName, csv) => callNative('accounts:saveCSV', { fileName: fileName, csv: csv }),
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
})();
