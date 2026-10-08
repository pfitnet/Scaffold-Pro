'use strict';

// ScaffoldPro Web (a page in a browser, served by the office Mac): a
// loading screen while the page and its first data arrive over the network.
// The first page of a visit shows it straight away; later pages only if
// they take more than a moment, so quick ones don't blink. It fades once
// the page has loaded and its lists have had a moment to fill.
//
// Added by main.swift's WebServer to every page it serves, before
// everything else; the Mac window never loads it.

(function () {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) return;
  let first = true;
  try { first = !sessionStorage.getItem('web.loaded'); sessionStorage.setItem('web.loaded', '1'); } catch (e) { first = true; }
  const started = Date.now();

  const css = `
    #web-loading { position: fixed; inset: 0; z-index: 2147483000; display: flex; flex-direction: column; align-items: center; justify-content: center;
      gap: 18px; color: #e9eef8; font: 500 14px -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      background: radial-gradient(120% 90% at 50% 0%, #21407e 0%, #102451 48%, #081330 100%);
      opacity: 0; animation: wl-in .25s ease ${first ? '0s' : '.35s'} forwards; transition: opacity .3s ease; }
    #web-loading.done { opacity: 0 !important; animation: none; pointer-events: none; }
    #web-loading svg { width: 84px; height: 84px; }
    #web-loading .wl-name { font-size: 22px; font-weight: 700; letter-spacing: .01em; }
    #web-loading .wl-name span { color: #f6c445; }
    #web-loading .wl-note { color: rgba(233, 238, 248, .7); font-size: 13px; }
    #web-loading .wl-bar { width: 160px; height: 3px; border-radius: 3px; background: rgba(255, 255, 255, .12); overflow: hidden; }
    #web-loading .wl-bar::after { content: ''; display: block; width: 40%; height: 100%; border-radius: 3px; background: #f6c445;
      animation: wl-sweep 1.1s ease-in-out infinite; }
    @keyframes wl-in { to { opacity: 1; } }
    @keyframes wl-sweep { from { transform: translateX(-100%); } to { transform: translateX(250%); } }
    @media (prefers-reduced-motion: reduce) { #web-loading, #web-loading .wl-bar::after { animation-duration: .01s; } }`;
  const logo = `<svg viewBox="0 0 128 128" aria-hidden="true">
      <rect x="4" y="4" width="120" height="120" rx="28" fill="rgba(255,255,255,.04)" stroke="rgba(255,255,255,.10)"/>
      <g fill="#e9eef8"><rect x="22" y="102" width="16" height="4" rx="1.5"/><rect x="56" y="102" width="16" height="4" rx="1.5"/><rect x="90" y="102" width="16" height="4" rx="1.5"/></g>
      <g fill="none" stroke-linecap="round"><path d="M30 101V22M64 101V22M98 101V22" stroke="#e9eef8" stroke-width="5"/>
      <path d="M30 88H98M30 60H98M30 32H98" stroke="#c9d4ea" stroke-width="4"/><path d="M30 88L98 32" stroke="#f6c445" stroke-width="5.5"/></g>
      <g fill="#102451" stroke="#fff" stroke-width="2.2">${[88, 60, 32].map((y) => [30, 64, 98].map((x) => `<circle cx="${x}" cy="${y}" r="4.2"/>`).join('')).join('')}</g>
    </svg>`;

  const style = document.createElement('style');
  style.textContent = css;
  const screen = document.createElement('div');
  screen.id = 'web-loading';
  screen.setAttribute('role', 'status');
  screen.setAttribute('aria-live', 'polite');
  screen.innerHTML = `${logo}<div class="wl-name">Scaffold<span>Pro</span></div><div class="wl-bar"></div>` +
    `<div class="wl-note">${first ? 'Connecting to the office Mac\u2026' : 'Loading\u2026'}</div>`;
  // Shown before the page's own content is even read.
  document.documentElement.appendChild(style);
  document.documentElement.appendChild(screen);

  function hide() {
    // The first screen of a visit stays long enough to be read, not flashed.
    const wait = Math.max(0, (first ? 700 : 0) - (Date.now() - started));
    setTimeout(() => {
      screen.classList.add('done');
      setTimeout(() => { screen.remove(); style.remove(); }, 350);
    }, wait);
  }
  // Loaded, plus a moment for the page's first lists to arrive.
  window.addEventListener('load', () => setTimeout(hide, 300));
  // Never left up if something on the page fails.
  setTimeout(hide, 12000);
  // Back to a page from the browser's cache: nothing to wait for.
  window.addEventListener('pageshow', (e) => { if (e.persisted) hide(); });
})();
