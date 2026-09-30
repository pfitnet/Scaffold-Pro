'use strict';

// Icon buttons. Buttons whose label is a common action (Locate File,
// Delete, Print, Open, Edit, Duplicate…) show an icon instead of the word;
// the word stays as the tooltip and for VoiceOver. It works on every
// button, including ones added later (table rows), by watching the page.
//
// Buttons meant to keep their words can opt out with data-no-icon.

(function () {
  const svg = (paths) => `<svg class="btn-icon" viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;

  const ICONS = {
    // A folder with a magnifying glass: show the file in Finder.
    locate: svg('<path d="M2.5 6.5V5a1.5 1.5 0 0 1 1.5-1.5h3.2l1.6 1.8H16A1.5 1.5 0 0 1 17.5 6.8v2.2"/><path d="M2.5 6.5v8A1.5 1.5 0 0 0 4 16h5"/><circle cx="14" cy="13.5" r="2.6"/><path d="m16 15.5 1.8 1.8"/>'),
    trash: svg('<path d="M3.5 5.5h13"/><path d="M8 5.5V4a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v1.5"/><path d="M5 5.5l.8 10.6A1.5 1.5 0 0 0 7.3 17.5h5.4a1.5 1.5 0 0 0 1.5-1.4L15 5.5"/><path d="M8.3 8.5v6M11.7 8.5v6"/>'),
    print: svg('<path d="M5.5 7.5V3.5h9v4"/><rect x="2.5" y="7.5" width="15" height="6.5" rx="1.5"/><path d="M5.5 12h9v5h-9z"/><circle cx="14.5" cy="10" r=".6" fill="currentColor"/>'),
    open: svg('<path d="M11 3.5h5.5V9"/><path d="M16.5 3.5 9 11"/><path d="M14 11.5v3.5a1.5 1.5 0 0 1-1.5 1.5h-7.5A1.5 1.5 0 0 1 3.5 15V7.5A1.5 1.5 0 0 1 5 6h3.5"/>'),
    edit: svg('<path d="M13.5 3.5a1.8 1.8 0 0 1 2.5 2.5L7 15l-3.5 1 1-3.5z"/><path d="m12 5 2.5 2.5"/>'),
    duplicate: svg('<rect x="7" y="7" width="10" height="10" rx="1.5"/><path d="M13 7V4.5A1.5 1.5 0 0 0 11.5 3h-7A1.5 1.5 0 0 0 3 4.5v7A1.5 1.5 0 0 0 4.5 13H7"/>'),
    folder: svg('<path d="M2.5 6V5a1.5 1.5 0 0 1 1.5-1.5h3.2l1.6 1.8H16A1.5 1.5 0 0 1 17.5 6.8V15a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 15z"/><path d="M2.5 8h15"/>'),
    archive: svg('<rect x="2.5" y="3.5" width="15" height="4" rx="1"/><path d="M4 7.5v8A1.5 1.5 0 0 0 5.5 17h9a1.5 1.5 0 0 0 1.5-1.5v-8"/><path d="M8 11h4"/>'),
    rename: svg('<path d="M3 16.5h14"/><path d="M12.5 3.5a1.6 1.6 0 0 1 2.3 2.3L8 12.6l-3 .9.9-3z"/>'),
    pdf: svg('<path d="M11.5 2.5H5.5A1.5 1.5 0 0 0 4 4v12a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 16 16V7z"/><path d="M11.5 2.5V7H16"/><path d="M10 10v5M7.8 12.8 10 15l2.2-2.2"/>'),
    select: svg('<rect x="3" y="3" width="14" height="14" rx="3"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>'),
    // A tray with an arrow going in: add a file.
    upload: svg('<path d="M3.5 12.5v2A1.5 1.5 0 0 0 5 16h10a1.5 1.5 0 0 0 1.5-1.5v-2"/><path d="M10 12.5V3.5"/><path d="M6.5 7 10 3.5 13.5 7"/>'),
    // A crossed circle: not needed / take off the list.
    dismiss: svg('<circle cx="10" cy="10" r="6.5"/><path d="m7.5 7.5 5 5M12.5 7.5l-5 5"/>'),
  };
  window.ICONS = ICONS;

  // Label → icon. Only labels that are clear from the icon alone.
  const LABELS = {
    'Locate File': 'locate', 'Locate Files': 'locate',
    'Delete': 'trash', 'Delete…': 'trash', 'Remove': 'trash',
    'Print…': 'print', 'Print': 'print',
    'Open': 'open',
    'Edit': 'edit',
    'Duplicate': 'duplicate',
    'Show in Finder': 'folder', 'Show Folder': 'folder', 'Show Folder in Finder': 'folder', 'Show Backups Folder': 'folder',
    'Archive': 'archive',
    'Rename': 'rename', 'Rename…': 'rename',
    '⧉': 'duplicate',
  };
  // Symbols used as labels, and the word that goes with them.
  const WORDS = { '⧉': 'Duplicate' };

  function iconize(button) {
    if (button.dataset.noIcon !== undefined || button.closest('[data-no-icon]')) return;
    // Already an icon button: its label may have changed (e.g. Archive → Restore).
    const label = (button.dataset.iconLabel && button.querySelector('.btn-icon') ? button.dataset.iconLabel : button.textContent).trim();
    const name = LABELS[label];
    if (!name) {
      if (button.classList.contains('icon-btn') && !button.querySelector('.btn-icon')) button.classList.remove('icon-btn');
      return;
    }
    if (button.querySelector('.btn-icon') && button.dataset.iconLabel === label) return;
    button.dataset.iconLabel = label;
    if (!button.title) button.title = WORDS[label] || label;
    button.setAttribute('aria-label', WORDS[label] || label);
    button.innerHTML = ICONS[name];
    button.classList.add('icon-btn');
    if (name === 'trash') button.classList.add('icon-danger');
  }

  function scan(root) {
    if (root.nodeType !== 1) return;
    if (root.tagName === 'BUTTON') iconize(root);
    for (const b of root.querySelectorAll('button')) iconize(b);
  }

  function start() {
    scan(document.body);
    new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.type === 'characterData') {
          const b = m.target.parentElement && m.target.parentElement.closest('button');
          if (b) iconize(b);
          continue;
        }
        const b = m.target.closest && m.target.closest('button');
        if (b) iconize(b);
        for (const n of m.addedNodes) scan(n);
      }
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
