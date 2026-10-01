'use strict';

// The app's own dialogs, in place of the Mac's alert / confirm / prompt
// boxes. Loaded first on every page.
//
//   await appAlert('Saved.');
//   if (!(await appConfirm('Delete this expense?'))) return;
//   const pick = await appChoose('Which pricing?', [{ label: 'Rental', value: 'Rental', primary: true }, { label: 'Sale', value: 'Sale' }]);
//   const name = await appPrompt('New name for this file:', current);
//
// Messages are written "Headline\n\nMore detail": the headline is the
// dialog's title and the rest its text. alert() shows the same dialog
// (without waiting); one dialog shows at a time, the next after it.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const nativeAlert = window.alert ? window.alert.bind(window) : null;
  let queue = Promise.resolve();

  const DESTRUCTIVE = /^(delete|remove|archive|restore|replace|stop sharing|cancel this|take them off)\b/i;

  function split(message) {
    const text = String(message ?? '');
    const parts = text.split('\n\n');
    // "Delete X? This can’t be undone." — the question as the title.
    if (parts.length === 1) {
      const q = text.indexOf('? ');
      if (q > 0 && q < text.length - 2) return { title: text.slice(0, q + 1), body: text.slice(q + 2) };
    }
    return { title: parts[0], body: parts.slice(1).join('\n\n') };
  }

  // The button that does it: "Delete" for "Delete this expense?", etc.
  function actionLabel(title) {
    const t = title.trim();
    const m = /^(Delete|Remove|Archive|Restore|Replace|Link|Share|Change|Return|Create|Use|Combine|Stop sharing|Take them off)\b/i.exec(t);
    if (!m) return 'OK';
    const word = m[1].toLowerCase();
    if (word === 'return') return 'Return to Draft';
    if (word === 'stop sharing') return 'Stop Sharing';
    if (word === 'take them off') return 'Take Off Payroll';
    return m[1][0].toUpperCase() + m[1].slice(1).toLowerCase();
  }

  function ensureStyles() {
    if (document.getElementById('app-dialog-styles')) return;
    const style = document.createElement('style');
    style.id = 'app-dialog-styles';
    style.textContent = `
      .app-dialog-backdrop { position: fixed; inset: 0; z-index: 10000; display: flex; align-items: center; justify-content: center;
        background: rgba(20, 22, 26, 0.32); animation: appDialogFade 0.12s ease-out; padding: 16px; }
      .app-dialog { width: 400px; max-width: 100%; max-height: calc(100vh - 32px); overflow: auto; background: var(--panel, #fff); color: var(--text, #1d1d1f);
        border-radius: 12px; box-shadow: var(--shadow-sheet, 0 18px 50px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.12));
        padding: 20px 20px 16px; animation: appDialogPop 0.14s ease-out; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif; }
      .app-dialog-head { display: flex; gap: 12px; align-items: flex-start; }
      .app-dialog-icon { flex: none; width: 30px; height: 30px; border-radius: 50%; display: flex; align-items: center; justify-content: center;
        background: var(--accent-soft, rgba(36,99,199,0.1)); color: var(--accent, #2463c7); font-weight: 700; font-size: 15px; }
      .app-dialog.danger .app-dialog-icon { background: var(--danger-soft, rgba(201,58,50,0.1)); color: var(--danger, #c93a32); }
      .app-dialog-title { font-size: 14px; font-weight: 650; line-height: 1.35; margin: 5px 0 0; white-space: pre-line; overflow-wrap: anywhere; }
      .app-dialog-body { font-size: 13px; line-height: 1.45; color: var(--text-secondary, #6e6e73); margin: 8px 0 0 42px; white-space: pre-line; overflow-wrap: anywhere; }
      .app-dialog-input { display: block; width: calc(100% - 42px); box-sizing: border-box; margin: 12px 0 0 42px; }
      .app-dialog-buttons { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; margin-top: 18px; }
      .app-dialog-buttons button { min-width: 84px; }
      .app-dialog-buttons button.danger { background: var(--danger, #c93a32); border-color: var(--danger, #c93a32); color: #fff; }
      .app-dialog-buttons button.danger:hover { filter: brightness(0.95); }
      @keyframes appDialogFade { from { opacity: 0; } to { opacity: 1; } }
      @keyframes appDialogPop { from { opacity: 0; transform: translateY(6px) scale(0.98); } to { opacity: 1; transform: none; } }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  // The dialog itself. buttons: [{ label, value, primary?, danger?, cancel? }]
  // — the last is on the right; Return picks the primary one, Escape the
  // cancel one. With `input`, it resolves to the text (or null if cancelled).
  function build(opts, resolve) {
      {
        ensureStyles();
        const { title, body } = split(opts.message);
        const danger = !!opts.danger;
        const backdrop = document.createElement('div');
        backdrop.className = 'app-dialog-backdrop';
        backdrop.innerHTML = `
          <div class="app-dialog${danger ? ' danger' : ''}" data-no-icon role="${opts.buttons.length > 1 ? 'alertdialog' : 'dialog'}" aria-modal="true">
            <div class="app-dialog-head"><div class="app-dialog-icon" aria-hidden="true">${danger ? '!' : opts.buttons.length > 1 ? '?' : 'i'}</div>
              <div class="app-dialog-title">${esc(title)}</div></div>
            ${body ? `<div class="app-dialog-body">${esc(body)}</div>` : ''}
            ${opts.input ? `<input type="text" class="app-dialog-input" value="${esc(opts.input.value || '')}" placeholder="${esc(opts.input.placeholder || '')}" />` : ''}
            <div class="app-dialog-buttons">${opts.buttons.map((b, i) =>
              `<button type="button" data-i="${i}" class="${b.danger ? 'danger' : b.primary ? 'primary' : ''}">${esc(b.label)}</button>`).join('')}</div>
          </div>`;
        const previousFocus = document.activeElement;
        const root = document.body || document.documentElement;
        root.appendChild(backdrop);
        const input = backdrop.querySelector('.app-dialog-input');
        const buttons = [...backdrop.querySelectorAll('.app-dialog-buttons button')];
        const primaryIndex = Math.max(0, opts.buttons.findIndex((b) => b.primary || b.danger));
        const cancelIndex = opts.buttons.findIndex((b) => b.cancel);
        let done = false;
        const finish = (i) => {
          if (done) return;
          done = true;
          document.removeEventListener('keydown', onKey, true);
          backdrop.remove();
          if (previousFocus && previousFocus.focus && document.contains(previousFocus)) { try { previousFocus.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }
          const b = opts.buttons[i];
          resolve(opts.input ? (b && !b.cancel ? input.value : null) : (b ? b.value : undefined));
        };
        const onKey = (e) => {
          if (e.key === 'Escape') {
            e.preventDefault(); e.stopPropagation();
            finish(cancelIndex >= 0 ? cancelIndex : opts.buttons.length === 1 ? 0 : -1);
          } else if (e.key === 'Enter' && !e.isComposing && (document.activeElement === input || !buttons.includes(document.activeElement))) {
            e.preventDefault(); e.stopPropagation();
            finish(primaryIndex);
          } else if (e.key === 'Tab') {
            // Keep focus inside the dialog.
            const items = [input, ...buttons].filter(Boolean);
            const at = items.indexOf(document.activeElement);
            e.preventDefault();
            items[(at + (e.shiftKey ? -1 : 1) + items.length) % items.length].focus();
          }
        };
        document.addEventListener('keydown', onKey, true);
        buttons.forEach((b, i) => b.addEventListener('click', () => finish(i)));
        backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop && cancelIndex >= 0) finish(cancelIndex); });
        if (input) { input.focus(); input.select(); } else buttons[primaryIndex].focus();
      }
  }

  // One dialog at a time; before the page has a body, it waits for it.
  function show(opts) {
    const run = () => new Promise((resolve) => {
      if (document.body) build(opts, resolve);
      else document.addEventListener('DOMContentLoaded', () => build(opts, resolve), { once: true });
    });
    const shown = queue.then(run);
    queue = shown.then(() => undefined, () => undefined);
    return shown;
  }

  window.appDialog = show;

  window.appAlert = function appAlert(message, opts = {}) {
    return show({ message, danger: !!opts.danger, buttons: [{ label: opts.ok || 'OK', value: true, primary: true, cancel: true }] });
  };

  // true / false. opts: { ok, cancel, danger } — worked out from the
  // message when not given ("Delete …?" → a red Delete button).
  window.appConfirm = function appConfirm(message, opts = {}) {
    const { title } = split(message);
    const danger = opts.danger ?? DESTRUCTIVE.test(title.trim());
    return show({ message, danger, buttons: [
      { label: opts.cancel || (/^cancel this/i.test(title.trim()) ? 'Keep It' : 'Cancel'), value: false, cancel: true },
      { label: opts.ok || (/^cancel this/i.test(title.trim()) ? 'Yes, Cancel It' : actionLabel(title)), value: true, primary: !danger, danger },
    ] }).then((v) => v === true);
  };

  // One of several answers: choices [{ label, value, primary?, danger? }];
  // resolves to the chosen value, or null if cancelled (a Cancel button
  // is added unless opts.noCancel).
  window.appChoose = function appChoose(message, choices, opts = {}) {
    const buttons = (opts.noCancel ? [] : [{ label: opts.cancel || 'Cancel', value: null, cancel: true }]).concat(choices);
    return show({ message, danger: !!opts.danger, buttons }).then((v) => (v === undefined ? null : v));
  };

  // The text typed, or null if cancelled.
  window.appPrompt = function appPrompt(message, value, opts = {}) {
    return show({ message, input: { value: value ?? '', placeholder: opts.placeholder }, buttons: [
      { label: opts.cancel || 'Cancel', value: null, cancel: true },
      { label: opts.ok || 'OK', value: true, primary: true },
    ] });
  };

  // Before an automatic update: whatever is being typed is saved (the
  // field loses focus, so it saves as usual; pages that save as they go
  // are told to save now).
  window.saveOpenWork = async function saveOpenWork() {
    const a = document.activeElement;
    if (a && a !== document.body && a.blur) a.blur();
    try { window.dispatchEvent(new Event('beforeunload')); } catch (e) { /* ignore */ }
    // A page with its own Save button saves too.
    if (typeof window.beforeAppUpdate === 'function') { try { await window.beforeAppUpdate(); } catch (e) { /* ignore */ } }
    await new Promise((r) => setTimeout(r, 1200));
  };

  // "A new version is ready — Update Now / Later": resolves 'now' or
  // 'later'. With Update Now, what's open is saved before it resolves.
  window.appUpdatePrompt = function appUpdatePrompt(latest) {
    ensureStyles();
    return new Promise((resolve) => {
      const backdrop = document.createElement('div');
      backdrop.className = 'app-dialog-backdrop';
      backdrop.innerHTML = `<div class="app-dialog" data-no-icon role="alertdialog" aria-modal="true">
        <div class="app-dialog-head"><div class="app-dialog-icon" aria-hidden="true">↻</div><div class="app-dialog-title">A new version of ScaffoldPro is ready</div></div>
        <div class="app-dialog-body">Update now? Your work is saved and backed up first, then ScaffoldPro updates and opens again by itself (about a minute).${latest ? `\n${esc(latest)}` : ''}<span class="update-state"></span></div>
        <div class="app-dialog-buttons"><button type="button" class="later">Later</button><button type="button" class="primary now">Update Now</button></div></div>`;
      (document.body || document.documentElement).appendChild(backdrop);
      let done = false;
      const state = backdrop.querySelector('.update-state');
      const finish = async (answer) => {
        if (done) return;
        done = true;
        document.removeEventListener('keydown', onKey, true);
        if (answer === 'now') {
          for (const b of backdrop.querySelectorAll('button')) b.disabled = true;
          state.textContent = '\n\nSaving your work…';
          await window.saveOpenWork();
          state.textContent = '\n\nBacking up and updating…';
          // The update's own screen takes over; if it can't start, this goes.
          setTimeout(() => backdrop.remove(), 10000);
        } else {
          backdrop.remove();
        }
        resolve(answer);
      };
      const onKey = (e) => {
        if (e.key === 'Escape') { e.preventDefault(); finish('later'); }
        if (e.key === 'Enter') { e.preventDefault(); finish('now'); }
      };
      document.addEventListener('keydown', onKey, true);
      backdrop.querySelector('.later').addEventListener('click', () => finish('later'));
      backdrop.querySelector('.now').addEventListener('click', () => finish('now'));
      backdrop.querySelector('.now').focus();
    });
  };

  // Plain alert() calls show the app's dialog too (without waiting).
  window.alert = function alert(message) { window.appAlert(message); };
  window.alert.native = nativeAlert;
})();
