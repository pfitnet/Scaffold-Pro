'use strict';

// A drop-down list drawn by the app (not the system's pop-up menu) that
// opens when the pointer rests on its button, or on a click, Return,
// Space or ↓. ↑ ↓ move, Return picks, Escape closes.
//
//   window.hoverMenu.attach(button, {
//     items: () => [{ label, sub, value, current, disabled }],
//     onPick: (value) => …,
//   });
//   window.hoverMenu.forSelect(select);   // a <select> in a .tb-pick (set up
//     by itself when the page loads): its
//     icon (the <label for=…>) opens the list; picking sets the select's
//     value and fires its "change", so the page's own code runs as before.
//   window.hoverMenu.isOpen()             // a list is showing

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const CHECK = '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5l3 3 6-7"/></svg>';
  let open = null; // { trigger, menu, close }

  function attach(trigger, options) {
    let menu = null;
    let leaveTimer = null;
    let enterTimer = null;
    trigger.setAttribute('aria-haspopup', 'menu');
    trigger.setAttribute('aria-expanded', 'false');

    const close = (refocus) => {
      clearTimeout(leaveTimer);
      clearTimeout(enterTimer);
      if (!menu) return;
      const m = menu;
      menu = null;
      m.classList.remove('open');
      setTimeout(() => m.remove(), 120);
      trigger.setAttribute('aria-expanded', 'false');
      trigger.classList.remove('hm-active');
      if (open && open.trigger === trigger) open = null;
      if (refocus) trigger.focus({ preventScroll: true });
    };

    const place = () => {
      const r = trigger.getBoundingClientRect();
      const w = menu.offsetWidth, h = menu.offsetHeight;
      const gap = 4;
      let left = options.align === 'right' ? r.right - w : r.left;
      left = Math.max(8, Math.min(left, window.innerWidth - w - 8));
      // Below the button, or above it when there's no room underneath.
      let top = r.bottom + gap;
      if (top + h > window.innerHeight - 8 && r.top - gap - h > 8) top = r.top - gap - h;
      menu.style.left = `${left}px`;
      menu.style.top = `${top}px`;
      menu.style.minWidth = `${Math.max(r.width, options.minWidth || 180)}px`;
      menu.classList.toggle('above', top < r.top);
    };

    const show = (focusItem) => {
      clearTimeout(leaveTimer);
      if (menu) { if (focusItem) focusFirst(); return; }
      if (open) open.close();
      const items = options.items() || [];
      if (!items.length) return;
      menu = document.createElement('div');
      menu.className = 'hm-menu';
      menu.setAttribute('role', 'menu');
      menu.setAttribute('data-no-icon', '');
      menu.innerHTML = (options.heading ? `<div class="hm-heading">${esc(options.heading)}</div>` : '') +
        items.map((it, i) => `<button type="button" class="hm-item${it.current ? ' current' : ''}" role="menuitemradio" aria-checked="${it.current ? 'true' : 'false'}" data-i="${i}" ${it.disabled ? 'disabled' : ''} data-no-icon tabindex="-1">
          <span class="hm-check">${it.current ? CHECK : ''}</span>
          <span class="hm-text"><span class="hm-label">${esc(it.label)}</span>${it.sub ? `<span class="hm-sub">${esc(it.sub)}</span>` : ''}</span></button>`).join('');
      document.body.appendChild(menu);
      place();
      requestAnimationFrame(() => menu && menu.classList.add('open'));
      trigger.setAttribute('aria-expanded', 'true');
      trigger.classList.add('hm-active');
      open = { trigger, menu, close };

      menu.addEventListener('pointerenter', () => clearTimeout(leaveTimer));
      menu.addEventListener('pointerleave', scheduleClose);
      menu.addEventListener('click', (e) => {
        const b = e.target.closest('.hm-item');
        if (!b || b.disabled) return;
        const it = items[Number(b.dataset.i)];
        close(true);
        options.onPick(it.value);
      });
      menu.addEventListener('keydown', (e) => {
        const all = [...menu.querySelectorAll('.hm-item:not([disabled])')];
        const at = all.indexOf(document.activeElement);
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          const next = e.key === 'ArrowDown' ? (at + 1) % all.length : (at - 1 + all.length) % all.length;
          if (all[next]) all[next].focus();
        } else if (e.key === 'Escape') {
          e.preventDefault(); e.stopPropagation();
          close(true);
        } else if (e.key === 'Tab') {
          close(false);
        }
      });
      menu.addEventListener('focusout', (e) => {
        if (menu && !menu.contains(e.relatedTarget) && e.relatedTarget !== trigger) close(false);
      });
      if (focusItem) focusFirst();
    };

    function focusFirst() {
      const item = menu.querySelector('.hm-item.current:not([disabled])') || menu.querySelector('.hm-item:not([disabled])');
      if (item) item.focus({ preventScroll: true });
    }
    function scheduleClose() {
      clearTimeout(enterTimer);
      clearTimeout(leaveTimer);
      // A moment's grace, so the pointer can cross from the button to the list.
      leaveTimer = setTimeout(() => {
        if (menu && menu.contains(document.activeElement)) return;
        close(false);
      }, 220);
    }

    trigger.addEventListener('pointerenter', (e) => {
      if (e.pointerType === 'touch' || trigger.disabled) return;
      clearTimeout(leaveTimer);
      clearTimeout(enterTimer);
      enterTimer = setTimeout(() => show(false), 60);
    });
    trigger.addEventListener('pointerleave', scheduleClose);
    trigger.addEventListener('click', (e) => {
      e.preventDefault();
      if (trigger.disabled) return;
      if (menu && menu.contains(document.activeElement)) close(true);
      else show(true);
    });
    trigger.addEventListener('keydown', (e) => {
      if (['ArrowDown', 'Enter', ' '].includes(e.key)) { e.preventDefault(); e.stopPropagation(); show(true); }
      else if (e.key === 'Escape' && menu) { e.preventDefault(); e.stopPropagation(); close(true); }
    });
    return { close: () => close(false) };
  }

  function forSelect(select, options = {}) {
    const box = select.closest('.tb-pick');
    const trigger = (box && box.querySelector(`label[for="${select.id}"]`)) || options.trigger;
    if (!trigger) return null;
    trigger.setAttribute('tabindex', '0');
    trigger.setAttribute('role', 'button');
    return attach(trigger, {
      heading: options.heading || trigger.textContent.trim(),
      minWidth: 220,
      items: () => [...select.options].map((o) => ({
        label: o.textContent, value: o.value, current: o.value === select.value, disabled: select.disabled || o.disabled,
      })),
      onPick: (value) => {
        if (value === select.value) return;
        select.value = value;
        select.dispatchEvent(new Event('change', { bubbles: true }));
      },
    });
  }

  // Scrolling or resizing the window moves the button: the list closes.
  window.addEventListener('resize', () => open && open.close());
  document.addEventListener('scroll', (e) => { if (open && !open.menu.contains(e.target)) open.close(); }, true);

  window.hoverMenu = { attach, forSelect, isOpen: () => !!open };

  // Every icon picker on the page (.tb-pick) works this way.
  const setUp = () => document.querySelectorAll('.tb-pick select').forEach((select) => forSelect(select));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setUp);
  else setUp();
})();
