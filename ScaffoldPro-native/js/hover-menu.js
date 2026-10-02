'use strict';

// A drop-down list drawn by the app (not the system's pop-up menu).
// Two ways to open one:
//   • hover (the default): when the pointer rests on its button, or on a
//     click, Return, Space or ↓ — the Page / Items-in icons, "Start from
//     Others";
//   • press: on a click, Space, Return, ↑ or ↓ — every <select> (js/controls.js).
// In the list ↑ ↓ move, typing jumps to a choice, Return picks, Escape closes.
//
//   window.hoverMenu.attach(button, {
//     items: () => [{ label, sub, value, current, disabled } | { group: 'Heading' }],
//     onPick: (value) => …,
//     openOn: 'hover' | 'press',
//   });
//   window.hoverMenu.forSelect(select);   // a <select> in a .tb-pick (set up
//     by itself when the page loads): its icon (the <label for=…>) opens
//     the list; picking sets the select's value and fires its "change", so
//     the page's own code runs as before.
//   window.hoverMenu.isOpen()             // a list is showing
//   <button class="export-menu" data-pdf="export-pdf-btn" data-word="export-word-btn">Export</button>
//     (set up by itself): a click saves the PDF; resting on it lists PDF and
//     Word. The real buttons stay on the page, hidden, with their own code.

(function () {
  if (window.hoverMenu) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const CHECK = '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5l3 3 6-7"/></svg>';
  let open = null; // { trigger, menu, close }

  function attach(trigger, options) {
    const press = options.openOn === 'press';
    let menu = null;
    let leaveTimer = null;
    let enterTimer = null;
    let typed = '';
    let typedTimer = null;
    trigger.setAttribute('aria-haspopup', press ? 'listbox' : 'menu');
    trigger.setAttribute('aria-expanded', 'false');
    const isDisabled = () => trigger.disabled || trigger.getAttribute('aria-disabled') === 'true';

    const onOutside = (e) => {
      if (!menu || menu.contains(e.target) || trigger.contains(e.target)) return;
      close(false);
    };

    const close = (refocus) => {
      clearTimeout(leaveTimer);
      clearTimeout(enterTimer);
      if (!menu) return;
      const m = menu;
      menu = null;
      m.classList.remove('open');
      setTimeout(() => m.remove(), 120);
      document.removeEventListener('pointerdown', onOutside, true);
      trigger.setAttribute('aria-expanded', 'false');
      trigger.classList.remove('hm-active');
      if (open && open.trigger === trigger) open = null;
      if (refocus) trigger.focus({ preventScroll: true });
    };

    const place = () => {
      const r = trigger.getBoundingClientRect();
      menu.style.minWidth = `${Math.max(r.width, options.minWidth || 180)}px`;
      if (menu.scrollWidth > menu.clientWidth) menu.style.width = `${Math.min(menu.scrollWidth + (menu.offsetWidth - menu.clientWidth), window.innerWidth - 16)}px`;
      const w = menu.offsetWidth, h = menu.offsetHeight;
      const gap = 4;
      let left = options.align === 'right' ? r.right - w : r.left;
      left = Math.max(8, Math.min(left, window.innerWidth - w - 8));
      // Below the button, or above it when there's no room underneath.
      let top = r.bottom + gap;
      if (top + h > window.innerHeight - 8 && r.top - gap - h > 8) top = r.top - gap - h;
      else if (top + h > window.innerHeight - 8) top = Math.max(8, window.innerHeight - 8 - h);
      menu.style.left = `${left}px`;
      menu.style.top = `${top}px`;
      menu.classList.toggle('above', top < r.top);
    };

    const show = (focusItem) => {
      clearTimeout(leaveTimer);
      if (menu) { if (focusItem) focusFirst(); return; }
      if (open) open.close();
      const items = options.items() || [];
      if (!items.some((it) => !it.group)) return;
      menu = document.createElement('div');
      menu.className = `hm-menu${press ? ' hm-list' : ''}`;
      menu.setAttribute('role', press ? 'listbox' : 'menu');
      menu.setAttribute('data-no-icon', '');
      menu.innerHTML = (options.heading ? `<div class="hm-heading">${esc(options.heading)}</div>` : '') +
        items.map((it, i) => it.group != null
          ? `<div class="hm-heading hm-group">${esc(it.group)}</div>`
          : `<button type="button" class="hm-item${it.current ? ' current' : ''}" role="${press ? 'option' : 'menuitemradio'}" aria-${press ? 'selected' : 'checked'}="${it.current ? 'true' : 'false'}" data-i="${i}" ${it.disabled ? 'disabled' : ''} data-no-icon tabindex="-1">
          <span class="hm-check">${it.current ? CHECK : ''}</span>
          <span class="hm-text"><span class="hm-label">${esc(it.label)}</span>${it.sub ? `<span class="hm-sub">${esc(it.sub)}</span>` : ''}</span></button>`).join('');
      document.body.appendChild(menu);
      place();
      // A long list opens at the current choice.
      const current = menu.querySelector('.hm-item.current');
      if (current && menu.scrollHeight > menu.clientHeight) menu.scrollTop = Math.max(0, current.offsetTop - menu.clientHeight / 2 + current.offsetHeight / 2);
      requestAnimationFrame(() => menu && menu.classList.add('open'));
      trigger.setAttribute('aria-expanded', 'true');
      trigger.classList.add('hm-active');
      open = { trigger, menu, close };
      document.addEventListener('pointerdown', onOutside, true);

      if (!press) {
        menu.addEventListener('pointerenter', () => clearTimeout(leaveTimer));
        menu.addEventListener('pointerleave', scheduleClose);
      }
      menu.addEventListener('pointerdown', (e) => e.preventDefault()); // keeps focus where it is
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
          const next = e.key === 'ArrowDown' ? Math.min(all.length - 1, at + 1) : Math.max(0, at - 1);
          if (all[next]) all[next].focus();
        } else if (e.key === 'Home' || e.key === 'End') {
          e.preventDefault();
          const item = e.key === 'Home' ? all[0] : all[all.length - 1];
          if (item) item.focus();
        } else if (e.key === 'Escape') {
          e.preventDefault(); e.stopPropagation();
          close(true);
        } else if (e.key === 'Tab') {
          close(false);
        } else if (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey && e.key !== ' ') {
          // Typing jumps to the first choice that starts with what's typed.
          typed += e.key.toLowerCase();
          clearTimeout(typedTimer);
          typedTimer = setTimeout(() => { typed = ''; }, 700);
          const hit = all.find((b) => b.querySelector('.hm-label').textContent.trim().toLowerCase().startsWith(typed));
          if (hit) hit.focus();
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

    if (press) {
      // A press opens it (not the system's menu); another closes it.
      trigger.addEventListener('mousedown', (e) => {
        if (e.button !== 0) return;
        e.preventDefault();
        if (isDisabled()) return;
        if (menu) { close(true); return; }
        trigger.focus({ preventScroll: true });
        show(true);
      });
      trigger.addEventListener('click', (e) => e.preventDefault());
      trigger.addEventListener('keydown', (e) => {
        if (isDisabled()) return;
        if ([' ', 'Enter', 'ArrowDown', 'ArrowUp'].includes(e.key) && !e.metaKey && !e.ctrlKey) { e.preventDefault(); e.stopPropagation(); show(true); }
        else if (e.key === 'Escape' && menu) { e.preventDefault(); e.stopPropagation(); close(true); }
      });
    } else {
      trigger.addEventListener('pointerenter', (e) => {
        if (e.pointerType === 'touch' || isDisabled()) return;
        clearTimeout(leaveTimer);
        clearTimeout(enterTimer);
        enterTimer = setTimeout(() => show(false), 60);
      });
      trigger.addEventListener('pointerleave', scheduleClose);
      trigger.addEventListener('click', (e) => {
        e.preventDefault();
        if (isDisabled()) return;
        // A button with its own action (Export → PDF): a click does that.
        if (options.onClick) { close(false); options.onClick(); return; }
        if (menu && menu.contains(document.activeElement)) close(true);
        else show(true);
      });
      trigger.addEventListener('keydown', (e) => {
        const opens = options.onClick ? ['ArrowDown'] : ['ArrowDown', 'Enter', ' '];
        if (opens.includes(e.key)) { e.preventDefault(); e.stopPropagation(); show(true); }
        else if (e.key === 'Escape' && menu) { e.preventDefault(); e.stopPropagation(); close(true); }
      });
    }
    return { close: () => close(false), open: () => show(true) };
  }

  // A <select>'s choices as list items (with <optgroup> headings).
  function selectItems(select) {
    const out = [];
    for (const child of select.children) {
      if (child.tagName === 'OPTGROUP') {
        out.push({ group: child.label });
        for (const o of child.children) if (o.tagName === 'OPTION' && !o.hidden) out.push(optionItem(select, o, child.disabled));
      } else if (child.tagName === 'OPTION' && !child.hidden) {
        out.push(optionItem(select, child, false));
      }
    }
    return out;
  }
  const optionItem = (select, o, groupOff) => ({
    label: o.textContent, value: o.value, current: o.selected, disabled: select.disabled || o.disabled || groupOff,
  });
  // Picking sets the select's value and fires its events, as choosing in the system's menu does.
  function pickInSelect(select, value) {
    if (value === select.value) return;
    select.value = value;
    select.dispatchEvent(new Event('input', { bubbles: true }));
    select.dispatchEvent(new Event('change', { bubbles: true }));
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
      items: () => selectItems(select),
      onPick: (value) => pickInSelect(select, value),
    });
  }

  // Scrolling or resizing the window moves the button: the list closes.
  window.addEventListener('resize', () => open && open.close());
  document.addEventListener('scroll', (e) => { if (open && !open.menu.contains(e.target)) open.close(); }, true);

  window.hoverMenu = { attach, forSelect, selectItems, pickInSelect, isOpen: () => !!open };

  // Export: PDF by default, or Word from its list.
  function exportMenu(button) {
    const pdf = document.getElementById(button.dataset.pdf || 'export-pdf-btn');
    const word = document.getElementById(button.dataset.word || 'export-word-btn');
    if (!pdf) return;
    const busy = () => { button.disabled = !!(pdf.disabled || (word && word.disabled)); };
    const watch = new MutationObserver(busy);
    [pdf, word].filter(Boolean).forEach((b) => watch.observe(b, { attributes: true, attributeFilter: ['disabled'] }));
    busy();
    if (!button.title) button.title = word ? 'Save a PDF — or rest the pointer here to choose PDF or Word' : 'Save a PDF';
    if (!word) { button.addEventListener('click', () => pdf.click()); return; }
    attach(button, {
      heading: 'Export as',
      minWidth: 200,
      onClick: () => pdf.click(),
      items: () => [
        { label: 'PDF', sub: 'The printed copy — the default', value: 'pdf' },
        { label: 'Word', sub: 'A .docx laid out like the PDF', value: 'word' },
      ],
      onPick: (v) => (v === 'word' ? word : pdf).click(),
    });
  }

  // One ☰ list for several selects, each under its heading (Add Materials:
  // price list and category): data-selects="source-select:Price list,category-select:Category".
  // A dot on the icon shows a filter (a later select not on its first choice) is on.
  function groupMenu(button) {
    const parts = (button.dataset.selects || '').split(',').map((p) => {
      const [id, heading] = p.split(':');
      return { select: document.getElementById(id.trim()), heading: (heading || '').trim() };
    }).filter((p) => p.select);
    if (!parts.length) return;
    const refresh = () => {
      const filtered = parts.slice(1).some(({ select }) => select.options.length && select.selectedIndex > 0);
      button.classList.toggle('filtered', filtered);
      button.title = parts.map(({ select, heading }) => `${heading}: ${select.selectedOptions[0] ? select.selectedOptions[0].textContent : '—'}`).join('\n');
    };
    const watch = new MutationObserver(refresh);
    parts.forEach(({ select }) => {
      select.addEventListener('change', refresh);
      watch.observe(select, { childList: true, subtree: true });
    });
    refresh();
    attach(button, {
      minWidth: 240,
      align: 'right',
      items: () => parts.flatMap(({ select, heading }, n) => [
        { group: heading },
        ...selectItems(select).filter((it) => it.group == null).map((it) => ({ ...it, value: `${n}\u0000${it.value}` })),
      ]),
      onPick: (v) => {
        const at = v.indexOf('\u0000');
        pickInSelect(parts[Number(v.slice(0, at))].select, v.slice(at + 1));
        refresh();
      },
    });
  }

  // Every icon picker on the page (.tb-pick) works this way, and every Export and ☰ button.
  const setUp = () => {
    document.querySelectorAll('.tb-pick select').forEach((select) => forSelect(select));
    document.querySelectorAll('button.export-menu').forEach(exportMenu);
    document.querySelectorAll('button.group-menu').forEach(groupMenu);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setUp);
  else setUp();
})();
