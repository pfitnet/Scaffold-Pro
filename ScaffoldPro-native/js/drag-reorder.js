'use strict';

// Drag-and-drop reordering, shared by the editors.
//
// Grab an item by its handle (⋮⋮) and drag it up or down: it follows the
// pointer, the others slide out of its way, and letting go saves the new
// order. The page scrolls when you drag near its top or bottom edge. With
// the handle focused, ↑ / ↓ move the item one place too.
//
// Pointer events rather than HTML5 drag and drop, so it behaves the same in
// the app's web view (and works on table rows).
//
//   container.innerHTML = … `<tr data-id="…"><td>${window.dragHandleHTML()}</td>…`
//   window.makeReorderable(tbody, { item: 'tr', onReorder: (ids) => save(ids) });

(function () {
  const GRIP = '<svg viewBox="0 0 10 16" width="10" height="16" aria-hidden="true" fill="currentColor">' +
    '<circle cx="3" cy="3" r="1.3"/><circle cx="7" cy="3" r="1.3"/><circle cx="3" cy="8" r="1.3"/>' +
    '<circle cx="7" cy="8" r="1.3"/><circle cx="3" cy="13" r="1.3"/><circle cx="7" cy="13" r="1.3"/></svg>';

  window.dragHandleHTML = function (title) {
    const label = title || 'Drag to reorder (or focus and press ↑ / ↓)';
    return `<span class="drag-handle" role="button" tabindex="0" title="${label}" aria-label="${label}">${GRIP}</span>`;
  };

  function scrollerOf(node) {
    for (let n = node.parentElement; n && n !== document.body; n = n.parentElement) {
      const overflow = getComputedStyle(n).overflowY;
      if ((overflow === 'auto' || overflow === 'scroll') && n.scrollHeight > n.clientHeight) return n;
    }
    return document.scrollingElement || document.documentElement;
  }

  /**
   * @param container  the element whose direct children are the items
   * @param options.item       selector for an item (a direct child), e.g. 'tr'
   * @param options.handle     selector for the handle inside an item ('.drag-handle')
   * @param options.onReorder  called with the items' ids (data-id) in their new order
   */
  window.makeReorderable = function (container, options) {
    const itemSel = options.item;
    const handleSel = options.handle || '.drag-handle';
    const items = () => [...container.children].filter((el) => el.matches(itemSel) && el.dataset.id);
    const ids = () => items().map((el) => el.dataset.id);

    const finish = (before, movedId) => {
      const after = ids();
      if (after.join('\n') === before.join('\n')) return;
      Promise.resolve(options.onReorder(after)).then(() => {
        // The editor re-renders; keep the moved item's handle focused for the keyboard.
        if (!movedId) return;
        const again = document.querySelector(`[data-id="${CSS.escape(movedId)}"] ${handleSel}`);
        if (again) again.focus();
      });
    };

    // Slides the other items from where they were to where they are now.
    const animateOthers = (el, move) => {
      const others = items().filter((x) => x !== el);
      const before = new Map(others.map((x) => [x, x.getBoundingClientRect().top]));
      move();
      for (const x of others) {
        const dy = before.get(x) - x.getBoundingClientRect().top;
        if (!dy) continue;
        x.style.transition = 'none';
        x.style.transform = `translateY(${dy}px)`;
        requestAnimationFrame(() => {
          x.style.transition = 'transform 140ms ease';
          x.style.transform = '';
        });
      }
    };

    container.addEventListener('pointerdown', (e) => {
      const handle = e.target.closest(handleSel);
      if (!handle || e.button !== 0) return;
      const el = handle.closest(itemSel);
      if (!el || el.parentElement !== container || !el.dataset.id) return;
      e.preventDefault();

      const startOrder = ids();
      const scroller = scrollerOf(container);
      const grabOffset = e.clientY - el.getBoundingClientRect().top;
      let pointerY = e.clientY;
      let dragging = true;
      el.classList.add('dragging');
      document.body.classList.add('reordering');

      // Where the item would be without its transform.
      const naturalTop = () => {
        const saved = el.style.transform;
        el.style.transform = '';
        const top = el.getBoundingClientRect().top;
        el.style.transform = saved;
        return top;
      };
      const follow = () => { el.style.transform = `translateY(${pointerY - grabOffset - naturalTop()}px)`; };

      // Moves the item to the place under the pointer (by the others'
      // resting midpoints, so their slide animations don't cause jitter).
      const place = () => {
        const others = items().filter((x) => x !== el);
        const centre = pointerY - grabOffset + el.offsetHeight / 2;
        const restingMid = (x) => {
          const t = getComputedStyle(x).transform;
          const dy = t && t !== 'none' ? new DOMMatrixReadOnly(t).m42 : 0;
          return x.getBoundingClientRect().top - dy + x.offsetHeight / 2;
        };
        const next = others.find((x) => centre < restingMid(x));
        const current = el.nextElementSibling;
        if (next) {
          if (current !== next) animateOthers(el, () => container.insertBefore(el, next));
        } else {
          const last = others[others.length - 1];
          if (last && last.nextElementSibling !== el) animateOthers(el, () => last.after(el));
        }
        follow();
      };

      // Scrolls while the pointer is near the top or bottom of the view.
      const edgeScroll = () => {
        if (!dragging) return;
        const box = scroller === document.scrollingElement || scroller === document.documentElement
          ? { top: 0, bottom: window.innerHeight } : scroller.getBoundingClientRect();
        const zone = 48;
        let step = 0;
        if (pointerY < box.top + zone) step = -Math.ceil((box.top + zone - pointerY) / 4);
        else if (pointerY > box.bottom - zone) step = Math.ceil((pointerY - (box.bottom - zone)) / 4);
        if (step) {
          scroller.scrollTop += step;
          place();
        }
        requestAnimationFrame(edgeScroll);
      };
      requestAnimationFrame(edgeScroll);

      // Followed on the window (moving the item in the page would drop a
      // pointer capture), and ended however the pointer is released.
      const onMove = (ev) => {
        if (ev.pointerId !== e.pointerId) return;
        pointerY = ev.clientY;
        place();
      };
      const onUp = (ev) => {
        if (!dragging || (ev && ev.pointerId !== undefined && ev.pointerId !== e.pointerId)) return;
        dragging = false;
        window.removeEventListener('pointermove', onMove, true);
        window.removeEventListener('pointerup', onUp, true);
        window.removeEventListener('pointercancel', onUp, true);
        window.removeEventListener('blur', onUp);
        document.body.classList.remove('reordering');
        // Settle into place, then save.
        el.style.transition = 'transform 120ms ease';
        el.style.transform = '';
        setTimeout(() => {
          el.classList.remove('dragging');
          el.style.transition = '';
          finish(startOrder, null);
        }, 130);
      };
      window.addEventListener('pointermove', onMove, true);
      window.addEventListener('pointerup', onUp, true);
      window.addEventListener('pointercancel', onUp, true);
      window.addEventListener('blur', onUp);
    });

    container.addEventListener('keydown', (e) => {
      const handle = e.target.closest(handleSel);
      if (!handle || (e.key !== 'ArrowUp' && e.key !== 'ArrowDown')) return;
      const el = handle.closest(itemSel);
      if (!el || el.parentElement !== container) return;
      e.preventDefault();
      const startOrder = ids();
      const list = items();
      const at = list.indexOf(el);
      if (e.key === 'ArrowUp' && at > 0) animateOthers(el, () => container.insertBefore(el, list[at - 1]));
      else if (e.key === 'ArrowDown' && at < list.length - 1) animateOthers(el, () => list[at + 1].after(el));
      finish(startOrder, el.dataset.id);
    });
  };
})();
