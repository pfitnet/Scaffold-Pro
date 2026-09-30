'use strict';

// Drag files from Finder onto a Drawings or Documents section to add
// them, the same as choosing them with its Upload button.
//
//   window.fileDrop(element, { projectNumber, target: 'drawing' | 'document',
//                              options: () => ({ linkedKind, linkedId } or { category }),
//                              done: async () => {…},
//                              hint: 'Drop drawings here' })   // adds a big drop box
//
// While files are dragged over the section it's outlined; the files are
// read here and sent to the app, which copies them into the project.

(function () {
  const MAX_BYTES = 60 * 1024 * 1024;

  function base64Of(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result).replace(/^data:[^,]*,/, ''));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  const hasFiles = (e) => !!e.dataTransfer && [...e.dataTransfer.types].includes('Files');

  const DROP_ICON = '<svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 15V4"/><path d="m7.5 8.5 4.5-4.5 4.5 4.5"/><path d="M4 14v3.5A2.5 2.5 0 0 0 6.5 20h11a2.5 2.5 0 0 0 2.5-2.5V14"/></svg>';

  window.fileDrop = function fileDrop(el, config) {
    if (!el) return;
    el.classList.add('file-drop-zone');
    // A big, plain target to drop onto (config.hint), e.g. "Drop drawings here".
    if (config.hint && !el.querySelector(':scope > .drop-box')) {
      const box = document.createElement('div');
      box.className = 'drop-box';
      box.innerHTML = `${DROP_ICON}<div class="drop-box-title"></div><div class="drop-box-sub"></div>`;
      box.querySelector('.drop-box-title').textContent = config.hint;
      box.querySelector('.drop-box-sub').textContent = config.hintSub || 'Drag files here from Finder';
      el.appendChild(box);
    }
    let depth = 0;
    el.addEventListener('dragenter', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth += 1;
      el.classList.add('drop-over');
    });
    el.addEventListener('dragover', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    });
    el.addEventListener('dragleave', () => {
      depth = Math.max(0, depth - 1);
      if (depth === 0) el.classList.remove('drop-over');
    });
    el.addEventListener('drop', async (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      e.stopPropagation();
      depth = 0;
      el.classList.remove('drop-over');
      const files = [...e.dataTransfer.files];
      if (files.length === 0) return;
      const tooBig = files.filter((f) => f.size > MAX_BYTES);
      const ok = files.filter((f) => f.size <= MAX_BYTES && f.size > 0);
      el.classList.add('drop-saving');
      let error = tooBig.length
        ? `Too large to drop (use the Upload button for these):\n${tooBig.map((f) => f.name).join('\n')}` : '';
      try {
        if (ok.length) {
          const payload = [];
          for (const f of ok) payload.push({ name: f.name, base64: await base64Of(f) });
          const r = await window.api.files.dropIntoProject(config.projectNumber, config.target,
            config.options ? config.options() : {}, payload);
          if (r && !r.ok) error = [r.error, error].filter(Boolean).join('\n\n');
        }
      } catch (err) {
        error = [err.message || String(err), error].filter(Boolean).join('\n\n');
      } finally {
        el.classList.remove('drop-saving');
      }
      if (config.done) await config.done();
      if (error) alert(error);
    });
  };

  // A file dropped anywhere else would open in place of the app's page.
  window.addEventListener('dragover', (e) => e.preventDefault());
  window.addEventListener('drop', (e) => e.preventDefault());

  // ---- While files are dragged over the window ----
  // The drop boxes grow and light up, and holding the files near the top
  // or bottom of the page scrolls it (faster the closer to the edge).
  const EDGE = 90;
  let lastY = null;
  let lastOver = 0;
  let frame = null;

  function scroller() {
    const content = document.getElementById('content');
    return content && content.scrollHeight > content.clientHeight ? content : document.scrollingElement;
  }

  function stop() {
    lastY = null;
    document.body.classList.remove('dragging-files');
    if (frame) cancelAnimationFrame(frame);
    frame = null;
  }

  function step() {
    frame = null;
    // No dragover for a moment: the files have left the window.
    if (lastY === null || Date.now() - lastOver > 400) { stop(); return; }
    const el = scroller();
    const rect = el === document.scrollingElement ? { top: 0, bottom: window.innerHeight } : el.getBoundingClientRect();
    let speed = 0;
    if (lastY > rect.bottom - EDGE) speed = Math.min(1, (lastY - (rect.bottom - EDGE)) / EDGE);
    else if (lastY < rect.top + EDGE) speed = -Math.min(1, ((rect.top + EDGE) - lastY) / EDGE);
    if (speed) el.scrollTop += Math.round(speed * speed * Math.sign(speed) * 22) || Math.sign(speed);
    frame = requestAnimationFrame(step);
  }

  window.addEventListener('dragover', (e) => {
    if (!hasFiles(e)) return;
    lastY = e.clientY;
    lastOver = Date.now();
    document.body.classList.add('dragging-files');
    if (!frame) frame = requestAnimationFrame(step);
  }, true);
  window.addEventListener('drop', stop, true);
  window.addEventListener('dragend', stop, true);
})();
