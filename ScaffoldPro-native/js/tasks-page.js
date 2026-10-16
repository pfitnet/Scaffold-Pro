'use strict';

// Tasks & Time (tasks.html): the two tabs, the keys and window.appRefresh.
// The tabs' own parts: js/tasks.js (window.scheduleList) and
// js/time-log.js (window.timeLog).
// Keys: L tasks, G time; N the tab's box (⇧N the full task form);
// / search the tasks; in Time ←/→ a day and T today.

(function () {
  const $ = (id) => document.getElementById(id);
  const TAB_KEY = 'tasks.tab';
  let tab = 'tasks';

  // The entry boxes are fixed to the bottom of the window (css/calendar.css):
  // keep each over its list's column.
  function placeBars() {
    for (const bar of document.querySelectorAll('.cal-page .tk-quick')) {
      const col = bar.parentElement.getBoundingClientRect();
      if (!col.width) continue;
      bar.style.left = `${col.left}px`;
      bar.style.width = `${col.width}px`;
    }
  }
  const watch = new ResizeObserver(placeBars);
  for (const el of [$('content'), ...document.querySelectorAll('.cal-page .tk-main')]) watch.observe(el);

  function show(t) {
    tab = t === 'time' ? 'time' : 'tasks';
    document.body.classList.toggle('tt-time', tab === 'time');
    $('sch-list').classList.toggle('hidden', tab !== 'tasks');
    $('sch-time').classList.toggle('hidden', tab !== 'time');
    for (const b of document.querySelectorAll('#tt-tabs button')) b.classList.toggle('active', b.dataset.tab === tab);
    try { localStorage.setItem(TAB_KEY, tab); } catch (e) { /* not kept */ }
    if (tab === 'time') window.timeLog.shown();
  }

  window.appRefresh = () => Promise.all([window.scheduleList.load(), window.timeLog.load()]);

  for (const b of document.querySelectorAll('#tt-tabs button')) b.addEventListener('click', () => show(b.dataset.tab));
  $('cal-prev').addEventListener('click', () => window.timeLog.go(-1));
  $('cal-next').addEventListener('click', () => window.timeLog.go(1));
  $('cal-today').addEventListener('click', () => window.timeLog.today());
  $('tt-add').addEventListener('click', () => $('new-task-btn').click());

  document.addEventListener('keydown', (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || e.defaultPrevented) return;
    const t = e.target;
    if (t && (t.closest('input, textarea, select, [contenteditable="true"], .modal, .modal-backdrop, dialog') || t.isContentEditable)) return;
    if (document.querySelector('.modal-backdrop:not(.hidden), .modal.open, dialog[open]')) return;
    const k = e.key.toLowerCase();
    const act = (fn) => { e.preventDefault(); fn(); };
    if (k === 'l') return act(() => show('tasks'));
    if (k === 'g') return act(() => show('time'));
    if (k === 'n' && e.shiftKey) return act(() => $('new-task-btn').click());
    if (k === 'n') return act(() => (tab === 'time' ? window.timeLog.focus() : window.scheduleList.focusQuick()));
    if (e.key === '/') return act(() => { show('tasks'); window.scheduleList.focusSearch(); });
    if (tab !== 'time') return;
    if (e.key === 'ArrowLeft') return act(() => window.timeLog.go(-1));
    if (e.key === 'ArrowRight') return act(() => window.timeLog.go(1));
    if (k === 't') act(() => window.timeLog.today());
  });

  // tasks.html?tab=time opens Time; ?task=… (a link to a task) opens Tasks.
  const q = new URLSearchParams(location.search);
  let remembered = null;
  try { remembered = localStorage.getItem(TAB_KEY); } catch (e) { remembered = null; }
  show(q.get('task') ? 'tasks' : q.get('tab') || remembered || 'tasks');
})();
