'use strict';

// Drag files from Finder onto a Drawings or Documents section to add
// them, the same as choosing them with its Upload button.
//
//   window.fileDrop(element, { projectNumber, target: 'drawing' | 'document',
//                              options: () => ({ linkedKind, linkedId } or { category }),
//                              done: async () => {…} })
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

  window.fileDrop = function fileDrop(el, config) {
    if (!el) return;
    el.classList.add('file-drop-zone');
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
})();
