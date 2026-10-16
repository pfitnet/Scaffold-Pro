'use strict';

// Tasks (tasks.html): the page's keys, window.appRefresh, and the quick-add
// bar fixed to the bottom of the window. The list itself: js/tasks.js
// (window.scheduleList). Keys: N the quick-add bar, ⇧N the full task form,
// / search. (The time log is a floating window: js/time-log.js, ⌥⌘T.)

(function () {
  const $ = (id) => document.getElementById(id);

  // The quick-add bar is fixed to the bottom of the window (css/calendar.css):
  // keep it over the list's column.
  function placeBar() {
    const bar = $('tk-quick');
    const col = bar.parentElement.getBoundingClientRect();
    if (!col.width) return;
    bar.style.left = `${col.left}px`;
    bar.style.width = `${col.width}px`;
  }
  const watch = new ResizeObserver(placeBar);
  watch.observe($('content'));
  watch.observe($('tk-quick').parentElement);

  window.appRefresh = () => window.scheduleList.load();
  $('tt-add').addEventListener('click', () => $('new-task-btn').click());

  document.addEventListener('keydown', (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || e.defaultPrevented) return;
    const t = e.target;
    if (t && (t.closest('input, textarea, select, [contenteditable="true"], .modal, .modal-backdrop, dialog, .calc-float') || t.isContentEditable)) return;
    if (document.querySelector('.modal-backdrop:not(.hidden), .modal.open, dialog[open]')) return;
    const k = e.key.toLowerCase();
    if (k === 'n' && e.shiftKey) { e.preventDefault(); $('new-task-btn').click(); }
    else if (k === 'n') { e.preventDefault(); window.scheduleList.focusQuick(); }
    else if (e.key === '/') { e.preventDefault(); window.scheduleList.focusSearch(); }
  });
})();
