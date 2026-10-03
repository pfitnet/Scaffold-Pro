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
//     items: () => [{ label, sub, value, current, disabled, items } | { group: 'Heading' }],
//       (an item with its own `items` opens them beside it — to the left, or
//       the right where there's no room — on resting on it, a click, or →/←)
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
//     Word (or Excel, with data-excel="…" in place of data-word). The real
//     buttons stay on the page, hidden, with their own code.

(function () {
  if (window.hoverMenu) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const CHECK = '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5l3 3 6-7"/></svg>';
  let open = null; // { trigger, menu, close }
  const CHEVRON = '<svg viewBox="0 0 10 10" width="9" height="9" aria-hidden="true"><path d="M6.5 1.5 3 5l3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const itemHTML = (it, i, role, aria) => `<button type="button" class="hm-item${it.current ? ' current' : ''}${it.items ? ' hm-has-sub' : ''}" role="${role}" ${aria} data-i="${i}" ${it.disabled ? 'disabled' : ''} data-no-icon tabindex="-1"${it.items ? ' aria-haspopup="menu"' : ''}>
          ${it.items ? `<span class="hm-chev">${CHEVRON}</span>` : `<span class="hm-check">${it.current ? CHECK : ''}</span>`}
          <span class="hm-text"><span class="hm-label">${esc(it.label)}</span>${it.sub ? `<span class="hm-sub">${esc(it.sub)}</span>` : ''}</span></button>`;

  function attach(trigger, options) {
    const press = options.openOn === 'press';
    let menu = null;
    let submenu = null; // { el, of: the item button }
    let subTimer = null;
    let leaveTimer = null;
    let enterTimer = null;
    let typed = '';
    let typedTimer = null;
    trigger.setAttribute('aria-haspopup', press ? 'listbox' : 'menu');
    trigger.setAttribute('aria-expanded', 'false');
    const isDisabled = () => trigger.disabled || trigger.getAttribute('aria-disabled') === 'true';

    const onOutside = (e) => {
      if (!menu || menu.contains(e.target) || trigger.contains(e.target) || (submenu && submenu.el.contains(e.target))) return;
      close(false);
    };
    const closeSub = () => {
      clearTimeout(subTimer);
      if (!submenu) return;
      const { el, of } = submenu;
      submenu = null;
      of.classList.remove('hm-sub-open');
      of.setAttribute('aria-expanded', 'false');
      el.classList.remove('open');
      setTimeout(() => el.remove(), 120);
    };
    // An item's own list, beside the menu: to the left (or the right without room).
    const openSub = (button, it, focus) => {
      if (submenu && submenu.of === button) { if (focus) { const f = submenu.el.querySelector('.hm-item:not([disabled])'); if (f) f.focus(); } return; }
      closeSub();
      const el = document.createElement('div');
      el.className = 'hm-menu hm-submenu';
      el.setAttribute('role', 'menu');
      el.setAttribute('data-no-icon', '');
      el.innerHTML = it.items.map((child, i) => itemHTML(child, i, 'menuitem', '')).join('');
      document.body.appendChild(el);
      submenu = { el, of: button };
      button.classList.add('hm-sub-open');
      button.setAttribute('aria-expanded', 'true');
      el.style.minWidth = '200px';
      const r = button.getBoundingClientRect(), m = menu.getBoundingClientRect();
      const w = el.offsetWidth, h = el.offsetHeight;
      let left = m.left - w + 2;
      if (left < 8) left = Math.min(m.right - 2, window.innerWidth - w - 8);
      const top = Math.max(8, Math.min(r.top - 6, window.innerHeight - h - 8));
      el.style.left = `${left}px`;
      el.style.top = `${top}px`;
      el.classList.toggle('to-right', left > m.left);
      requestAnimationFrame(() => el.classList.add('open'));
      el.addEventListener('pointerenter', () => { clearTimeout(leaveTimer); clearTimeout(subTimer); });
      if (!press) el.addEventListener('pointerleave', scheduleClose);
      el.addEventListener('pointerdown', (e) => e.preventDefault());
      el.addEventListener('click', (e) => {
        const b = e.target.closest('.hm-item');
        if (!b || b.disabled) return;
        const child = it.items[Number(b.dataset.i)];
        close(true);
        options.onPick(child.value);
      });
      el.addEventListener('keydown', (e) => {
        const all = [...el.querySelectorAll('.hm-item:not([disabled])')];
        const at = all.indexOf(document.activeElement);
        const back = el.classList.contains('to-right') ? 'ArrowLeft' : 'ArrowRight';
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          const next = e.key === 'ArrowDown' ? Math.min(all.length - 1, at + 1) : Math.max(0, at - 1);
          if (all[next]) all[next].focus();
        } else if (e.key === 'Escape' || e.key === back) {
          e.preventDefault(); e.stopPropagation();
          closeSub();
          button.focus();
        } else if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          if (all[at]) all[at].click();
        } else if (e.key === 'Tab') close(false);
      });
      el.addEventListener('focusout', (e) => {
        if (submenu && submenu.el === el && !el.contains(e.relatedTarget) && !(menu && menu.contains(e.relatedTarget))) close(false);
      });
      if (focus) { const f = el.querySelector('.hm-item:not([disabled])'); if (f) f.focus(); }
    };

    const close = (refocus) => {
      clearTimeout(leaveTimer);
      clearTimeout(enterTimer);
      closeSub();
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
          : itemHTML(it, i, press ? 'option' : (it.items ? 'menuitem' : 'menuitemradio'),
            it.items ? '' : `aria-${press ? 'selected' : 'checked'}="${it.current ? 'true' : 'false'}"`)).join('');
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
        if (it.items) { openSub(b, it, true); return; }
        close(true);
        options.onPick(it.value);
      });
      // Resting on an item with its own list opens it; on another, closes it.
      menu.addEventListener('pointerover', (e) => {
        const b = e.target.closest('.hm-item');
        if (!b) return;
        clearTimeout(subTimer);
        const it = items[Number(b.dataset.i)];
        if (it && it.items && !b.disabled) subTimer = setTimeout(() => menu && openSub(b, it, false), 90);
        else if (submenu && submenu.of !== b) subTimer = setTimeout(closeSub, 160);
      });
      menu.addEventListener('keydown', (e) => {
        const all = [...menu.querySelectorAll('.hm-item:not([disabled])')];
        const at = all.indexOf(document.activeElement);
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          const next = e.key === 'ArrowDown' ? Math.min(all.length - 1, at + 1) : Math.max(0, at - 1);
          if (all[next]) all[next].focus();
        } else if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.key === 'Enter' || e.key === ' ') && all[at] && all[at].classList.contains('hm-has-sub')) {
          // ← (or →, Return): the item's own list.
          e.preventDefault(); e.stopPropagation();
          openSub(all[at], items[Number(all[at].dataset.i)], true);
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
        if (menu && !menu.contains(e.relatedTarget) && e.relatedTarget !== trigger && !(submenu && submenu.el.contains(e.relatedTarget))) close(false);
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
        if (menu && (menu.contains(document.activeElement) || (submenu && submenu.el.contains(document.activeElement)))) return;
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

  // Export: PDF by default, or Word (or Excel) from its list.
  function exportMenu(button) {
    const pdf = document.getElementById(button.dataset.pdf || 'export-pdf-btn');
    const excel = button.dataset.excel ? document.getElementById(button.dataset.excel) : null;
    const word = excel || document.getElementById(button.dataset.word || 'export-word-btn');
    if (!pdf) return;
    const busy = () => { button.disabled = !!(pdf.disabled || (word && word.disabled)); };
    const watch = new MutationObserver(busy);
    [pdf, word].filter(Boolean).forEach((b) => watch.observe(b, { attributes: true, attributeFilter: ['disabled'] }));
    busy();
    const other = excel ? 'Excel' : 'Word';
    if (!button.title) button.title = word ? `Save a PDF — or rest the pointer here to choose PDF or ${other}` : 'Save a PDF';
    if (!word) { button.addEventListener('click', () => pdf.click()); return; }
    attach(button, {
      heading: 'Export as',
      minWidth: 200,
      onClick: () => pdf.click(),
      // A page can add its own items after these (button.exportExtras =
      // { items: () => [...], pick: (value) => … }), e.g. a quotation's
      // Attach › Subsidiaries.
      items: () => [
        { label: 'PDF', sub: 'The printed copy — the default', value: 'pdf' },
        excel ? { label: 'Excel', sub: 'A workbook (.xlsx) to edit', value: 'other' }
          : { label: 'Word', sub: 'A .docx laid out like the PDF', value: 'other' },
        ...(button.exportExtras ? button.exportExtras.items() : []),
      ],
      onPick: (v) => {
        if (v === 'pdf' || v === 'other') (v === 'other' ? word : pdf).click();
        else if (button.exportExtras) button.exportExtras.pick(v);
      },
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

  // Line Items' ☰: "Multiply quantities…" (greyed out while the page's
  // Multiply button is hidden: an issued document, or no items) and the
  // Sort choices — data-multiply="multiply-btn" data-sort="line-sort".
  function linesMenu(button) {
    const multiply = document.getElementById(button.dataset.multiply || '');
    const sort = document.getElementById(button.dataset.sort || '');
    const refresh = () => {
      button.title = [multiply ? 'Multiply quantities' : '', sort && sort.selectedOptions[0] ? `Sort: ${sort.selectedOptions[0].textContent}` : '']
        .filter(Boolean).join('\n');
    };
    if (sort) sort.addEventListener('change', refresh);
    refresh();
    attach(button, {
      minWidth: 230,
      align: 'right',
      items: () => [
        ...(multiply ? [{ label: 'Multiply quantities…', sub: 'e.g. ×2 for 2 sets of the same scaffold', value: 'multiply', disabled: multiply.classList.contains('hidden') || multiply.disabled }] : []),
        ...(sort ? [{ group: 'Sort' }, ...selectItems(sort).filter((it) => it.group == null).map((it) => ({ ...it, value: `sort:${it.value}` }))] : []),
      ],
      onPick: (v) => {
        if (v === 'multiply') multiply.click();
        else if (v.startsWith('sort:')) { pickInSelect(sort, v.slice(5)); refresh(); }
      },
    });
  }

  // Every icon picker on the page (.tb-pick) works this way, and every Export and ☰ button.
  const setUp = () => {
    document.querySelectorAll('.tb-pick select').forEach((select) => forSelect(select));
    document.querySelectorAll('button.export-menu').forEach(exportMenu);
    document.querySelectorAll('button.group-menu').forEach(groupMenu);
    document.querySelectorAll('button.lines-menu').forEach(linesMenu);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setUp);
  else setUp();
})();
