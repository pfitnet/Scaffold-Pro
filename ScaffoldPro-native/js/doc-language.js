'use strict';

// "Items in: English / 中文" on the delivery note, quotation and BOQ
// editors: the language the item names are printed in on the PDF and Word
// copy (materials' Chinese names from the Material List). "Default" follows
// Settings › BOQ Defaults.
//
//   window.docLanguage.init((language) => window.api.boq.setLanguage(id, language));
//   window.docLanguage.show(detail);   // { language, defaultLanguage }

(function () {
  const NAMES = { English: 'English', Chinese: '中文 Chinese' };
  let save = null;

  function select() { return document.getElementById('language-select'); }

  window.docLanguage = {
    init(setLanguage) {
      save = setLanguage;
      const el = select();
      if (!el) return;
      el.addEventListener('change', async () => {
        const r = await save(el.value || null);
        if (r && r.ok === false) alert(r.error);
      });
    },
    show(detail) {
      const el = select();
      if (!el || !detail) return;
      const fallback = detail.defaultLanguage === 'Chinese' ? 'Chinese' : 'English';
      el.innerHTML = `<option value="">Default (${NAMES[fallback]})</option>` +
        '<option value="English">English</option><option value="Chinese">中文 Chinese</option>';
      if (document.activeElement !== el) el.value = detail.language || '';
    },
  };
})();
