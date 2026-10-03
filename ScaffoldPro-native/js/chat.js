'use strict';

// Chat: Everyone, your team, and a direct message with each person.
// Messages travel like the rest of the shared data; "typing…" and new
// messages are checked every second or two. Emoji (picker and reactions),
// GIFs (GIPHY search, with a key) and pictures from the Mac, replies, and
// editing or deleting your own messages.

(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  const EMOJI = {
    'Smileys': '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 😉 😊 😇 🥰 😍 🤩 😘 😋 😛 😜 🤪 😝 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 😌 😔 😪 😴 😷 🤒 🤕 🥵 🥶 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬',
    'Gestures': '👍 👎 👌 🤌 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤝 🙏 👏 🙌 👐 🤲 💪 🫡 🫶 ✍️',
    'Site': '🏗️ 🧱 🪜 🔩 🔧 🔨 🪛 ⚒️ 🛠️ ⛏️ 🪚 📐 📏 🦺 ⛑️ 👷 🚧 🚚 🚛 🏢 🏭 🏠 🌧️ ☀️ 🌪️ ⏰ 📅 📦 🧾 💰 💵 📄 📝 📎 ✅ ❌ ⚠️ 🔥',
    'Hearts': '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ⭐ 🌟 ✨ ⚡ 🎉 🎊 🎈 🏆 🥇 🍻 🥂 🍰 ☕ 🍜 🍱',
  };
  const QUICK = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

  let page = null;
  let current = null;          // conversation id
  let messages = [];
  let shownIds = new Set();
  let replyTo = null;
  let editing = null;
  const fileCache = new Map();
  let lastTypingSent = 0;
  let readMarks = {};

  const me = () => (page ? page.me : '');
  const key = () => `chat.read:${me().toLowerCase()}`;
  function loadReads() { try { readMarks = JSON.parse(localStorage.getItem(key()) || '{}'); } catch (e) { readMarks = {}; } }
  function markRead(id, at) {
    if (!at || (readMarks[id] && readMarks[id] >= at)) return;
    readMarks[id] = at;
    try { localStorage.setItem(key(), JSON.stringify(readMarks)); } catch (e) { /* ignore */ }
    if (window.refreshChatBadge) window.refreshChatBadge();
  }

  const initials = (n) => String(n).trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase();
  const colour = (n) => (window.personColor ? window.personColor(n) : '#8a8f98');
  const time = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  function dayLabel(iso) {
    const d = new Date(iso);
    const t = new Date();
    const y = new Date(); y.setDate(y.getDate() - 1);
    if (d.toDateString() === t.toDateString()) return 'Today';
    if (d.toDateString() === y.toDateString()) return 'Yesterday';
    return d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
  }
  function ago(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    const mins = Math.round((Date.now() - d.getTime()) / 60000);
    if (mins < 1) return 'now';
    if (mins < 60) return `${mins}m`;
    if (mins < 60 * 24) return time(iso);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }).replace('Sept', 'Sep');
  }
  // Only emoji (1–3 of them): shown large.
  const emojiOnly = (t) => /^(\p{Extended_Pictographic}(️|‍\p{Extended_Pictographic})*\s*){1,3}$/u.test(t.trim());

  function linkify(text) {
    let html = esc(text);
    html = html.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>');
    if (page) {
      for (const n of [page.me].concat(page.people)) {
        const re = new RegExp(`@${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi');
        html = html.replace(re, (m) => `<span class="mention${n.toLowerCase() === page.me.toLowerCase() ? ' me' : ''}">${m}</span>`);
      }
    }
    return html;
  }

  // ---- conversations ----

  function convAvatar(c) {
    if (c.kind === 'everyone') return '<span class="conv-avatar group">👥</span>';
    if (c.kind === 'team') return '<span class="conv-avatar group">🏷️</span>';
    return `<span class="conv-avatar" style="background:${colour(c.with)}">${esc(initials(c.with))}</span>`;
  }

  function renderConversations() {
    const q = $('chat-search').value.trim().toLowerCase();
    const list = page.conversations.filter((c) => !q || c.title.toLowerCase().includes(q));
    $('chat-convs').innerHTML = list.map((c) => {
      const unread = c.lastAt && c.lastAuthor && c.lastAuthor.toLowerCase() !== page.me.toLowerCase() && (!readMarks[c.id] || readMarks[c.id] < c.lastAt) && c.id !== current;
      return `<button class="conv${c.id === current ? ' active' : ''}${unread ? ' unread' : ''}" data-id="${esc(c.id)}" data-no-icon>
        ${convAvatar(c)}
        <span class="conv-text"><span class="conv-title">${esc(c.title)}</span>
          <span class="conv-last">${c.lastText ? `${c.lastAuthor && c.lastAuthor.toLowerCase() === page.me.toLowerCase() ? 'You: ' : c.kind === 'dm' ? '' : `${esc(c.lastAuthor)}: `}${esc(c.lastText)}` : '<i>No messages yet</i>'}</span></span>
        <span class="conv-meta"><span class="conv-time">${ago(c.lastAt)}</span>${unread ? '<span class="conv-dot"></span>' : ''}</span>
      </button>`;
    }).join('') || '<div class="empty-inline" style="padding:12px">No one matches.</div>';
    for (const b of $('chat-convs').querySelectorAll('.conv')) b.addEventListener('click', () => open(b.dataset.id));
  }

  function renderHead() {
    const c = page.conversations.find((x) => x.id === current);
    if (!c) { $('chat-head').innerHTML = ''; return; }
    const sub = c.kind === 'everyone' ? `Everyone using ScaffoldPro · ${page.people.length + 1} people`
      : c.kind === 'team' ? `Your team (${esc(page.myTeam)})` : 'Direct message';
    $('chat-head').innerHTML = `${convAvatar(c)}<div><div class="chat-title">${esc(c.title)}</div><div class="chat-sub">${sub}</div></div>`;
  }

  async function open(id) {
    current = id;
    messages = [];
    shownIds = new Set();
    replyTo = null; editing = null;
    $('chat-messages').innerHTML = '';
    renderReply();
    try { localStorage.setItem('chat.current', id); } catch (e) { /* ignore */ }
    renderConversations();
    renderHead();
    await poll(true);
    $('chat-input').focus();
  }

  // ---- messages ----

  async function fileURL(name) {
    if (fileCache.has(name)) return fileCache.get(name);
    const r = await window.api.chat.file(name);
    const url = (r && r.dataURL) || '';
    fileCache.set(name, url);
    return url;
  }

  function reactionsHTML(m) {
    const entries = Object.entries(m.reactions || {}).filter(([, who]) => who.length);
    if (!entries.length) return '';
    return `<div class="reactions">${entries.map(([e, who]) => `<button class="reaction${who.includes(page.me.toLowerCase()) ? ' mine' : ''}" data-emoji="${esc(e)}" data-no-icon title="${esc(who.join(', '))}">${esc(e)}<span>${who.length}</span></button>`).join('')}</div>`;
  }

  function bodyHTML(m) {
    if (m.deleted) return '<div class="bubble deleted">This message was deleted</div>';
    const quoted = m.replyTo ? messages.find((x) => x.id === m.replyTo) : null;
    const quote = quoted ? `<div class="quote"><b>${esc(quoted.author)}</b> ${esc(quoted.deleted ? 'Deleted message' : quoted.text || (quoted.gifURL ? 'GIF' : 'Picture'))}</div>` : '';
    const media = m.gifURL ? `<img class="chat-media" src="${esc(m.gifURL)}" alt="GIF" loading="lazy" />`
      : m.file ? `<img class="chat-media" data-file="${esc(m.file)}" ${fileCache.get(m.file) ? `src="${fileCache.get(m.file)}"` : ''} alt="${esc(m.fileName || 'Picture')}" />` : '';
    const big = !media && !quote && m.text && emojiOnly(m.text);
    const text = m.text ? `<div class="text">${linkify(m.text)}${m.editedAt ? ' <span class="edited">(edited)</span>' : ''}</div>` : '';
    if (big) return `<div class="big-emoji">${esc(m.text)}</div>`;
    return `<div class="bubble${media && !m.text ? ' media-only' : ''}">${quote}${media}${text}</div>`;
  }

  function messageHTML(m, prev) {
    const mine = m.author.toLowerCase() === page.me.toLowerCase();
    const grouped = prev && prev.author === m.author && (new Date(m.createdAt) - new Date(prev.createdAt)) < 5 * 60000 && dayLabel(prev.createdAt) === dayLabel(m.createdAt);
    const day = !prev || dayLabel(prev.createdAt) !== dayLabel(m.createdAt) ? `<div class="day-sep"><span>${dayLabel(m.createdAt)}</span></div>` : '';
    return `${day}<div class="msg${mine ? ' mine' : ''}${grouped ? ' grouped' : ''}" data-id="${esc(m.id)}">
      ${mine ? '' : `<span class="msg-avatar" style="background:${colour(m.author)}">${grouped ? '' : esc(initials(m.author))}</span>`}
      <div class="msg-col">
        ${grouped || mine ? '' : `<div class="msg-author" style="color:${colour(m.author)}">${esc(m.author)}</div>`}
        <div class="msg-row">${bodyHTML(m)}
          ${m.deleted ? '' : `<div class="msg-tools">
            ${QUICK.slice(0, 3).map((e) => `<button class="tool-react" data-emoji="${e}" data-no-icon>${e}</button>`).join('')}
            <button class="tool-more-react" data-no-icon title="React">＋</button>
            <button class="tool-reply" data-no-icon title="Reply">↩</button>
            ${mine && !m.gifURL && !m.file ? '<button class="tool-edit" data-no-icon title="Edit">✎</button>' : ''}
            ${mine ? '<button class="tool-delete" data-no-icon title="Delete">🗑</button>' : ''}
          </div>`}
        </div>
        ${reactionsHTML(m)}
        <div class="msg-time">${time(m.createdAt)}</div>
      </div>
    </div>`;
  }

  function render(fresh) {
    const scroll = $('chat-scroll');
    const atBottom = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 80;
    if (!messages.length) {
      const c = page.conversations.find((x) => x.id === current);
      $('chat-messages').innerHTML = `<div class="chat-empty"><div class="wave">👋</div><div>Say hello${c && c.kind === 'dm' ? ` to ${esc(c.title)}` : ''}!</div></div>`;
      return;
    }
    $('chat-messages').innerHTML = messages.map((m, i) => messageHTML(m, messages[i - 1])).join('');
    // The new ones slide in.
    for (const m of messages) {
      const el = $('chat-messages').querySelector(`.msg[data-id="${CSS.escape(m.id)}"]`);
      if (el && !shownIds.has(m.id) && !fresh) el.classList.add('enter');
    }
    const newOnes = messages.filter((m) => !shownIds.has(m.id));
    messages.forEach((m) => shownIds.add(m.id));
    for (const img of $('chat-messages').querySelectorAll('img[data-file]:not([src])')) {
      fileURL(img.dataset.file).then((u) => { if (u) img.src = u; });
    }
    for (const img of $('chat-messages').querySelectorAll('img.chat-media')) {
      img.addEventListener('load', () => { if (atBottom || fresh) scroll.scrollTop = scroll.scrollHeight; }, { once: true });
    }
    wireMessages();
    const fromOthers = newOnes.some((m) => m.author.toLowerCase() !== page.me.toLowerCase());
    if (fresh || atBottom || newOnes.some((m) => m.author.toLowerCase() === page.me.toLowerCase())) {
      scroll.scrollTop = scroll.scrollHeight;
      $('chat-new-pill').classList.add('hidden');
    } else if (fromOthers) {
      $('chat-new-pill').classList.remove('hidden');
    }
    const last = messages[messages.length - 1];
    if (last && document.hasFocus()) markRead(current, last.createdAt);
  }

  function wireMessages() {
    for (const el of $('chat-messages').querySelectorAll('.msg')) {
      const m = messages.find((x) => x.id === el.dataset.id);
      if (!m) continue;
      const on = (sel, fn) => { for (const b of el.querySelectorAll(sel)) b.addEventListener('click', (e) => { e.stopPropagation(); fn(b, e); }); };
      on('.tool-react, .reaction', (b) => react(m, b.dataset.emoji, b));
      on('.tool-more-react', (b) => openEmoji(b, (e) => react(m, e)));
      on('.tool-reply', () => { replyTo = m; editing = null; renderReply(); $('chat-input').focus(); });
      on('.tool-edit', () => { editing = m; replyTo = null; $('chat-input').value = m.text; renderReply(); grow(); $('chat-input').focus(); });
      on('.tool-delete', async () => {
        if (!await window.appConfirm('Delete this message?\n\nIt’s removed for everyone.', { ok: 'Delete' })) return;
        const r = await window.api.chat.edit(m.id, null, true);
        if (r && r.ok === false) { await window.appAlert(r.error); return; }
        poll();
      });
    }
  }

  async function react(m, emoji, button) {
    if (button) { button.classList.remove('pop'); void button.offsetWidth; button.classList.add('pop'); }
    rememberEmoji(emoji);
    const r = await window.api.chat.react(m.id, emoji);
    if (r && r.ok === false) { await window.appAlert(r.error); return; }
    poll();
  }

  function renderReply() {
    const box = $('chat-reply');
    const m = editing || replyTo;
    box.classList.toggle('hidden', !m);
    if (!m) return;
    box.innerHTML = `<span class="reply-bar"></span><div class="reply-text"><b>${editing ? 'Editing' : `Replying to ${esc(m.author)}`}</b>
      <span>${esc(m.text || (m.gifURL ? 'GIF' : 'Picture'))}</span></div><button class="reply-x" data-no-icon aria-label="Cancel">✕</button>`;
    box.querySelector('.reply-x').addEventListener('click', () => {
      if (editing) $('chat-input').value = '';
      replyTo = null; editing = null; renderReply(); grow();
    });
  }

  // ---- sending ----

  function grow() {
    const t = $('chat-input');
    t.style.height = 'auto';
    t.style.height = `${Math.min(140, t.scrollHeight)}px`;
    $('chat-send').classList.toggle('ready', !!t.value.trim());
  }

  async function send(extra = {}) {
    const input = $('chat-input');
    const text = input.value;
    if (editing && !extra.gifURL) {
      const r = await window.api.chat.edit(editing.id, text, false);
      if (r && r.ok === false) { await window.appAlert(r.error); return; }
      editing = null; input.value = ''; renderReply(); grow(); poll();
      return;
    }
    if (!text.trim() && !extra.gifURL) return;
    const payload = Object.assign({ conversation: current, text: extra.gifURL ? '' : text, replyTo: replyTo ? replyTo.id : null }, extra);
    if (!extra.gifURL) { input.value = ''; grow(); }
    $('chat-send').classList.remove('sent'); void $('chat-send').offsetWidth; $('chat-send').classList.add('sent');
    const r = await window.api.chat.send(payload);
    if (!r || r.ok === false) { await window.appAlert((r && r.error) || 'It couldn’t be sent.'); if (!extra.gifURL) input.value = text; return; }
    replyTo = null; renderReply();
    lastTypingSent = 0;
    await poll();
  }

  function typing() {
    const now = Date.now();
    if (!$('chat-input').value.trim()) return;
    if (now - lastTypingSent < 2500) return;
    lastTypingSent = now;
    window.api.chat.typing(current);
  }

  // ---- emoji and GIFs ----

  function recentEmoji() { try { return JSON.parse(localStorage.getItem('chat.recentEmoji') || '[]'); } catch (e) { return []; } }
  function rememberEmoji(e) {
    const list = [e].concat(recentEmoji().filter((x) => x !== e)).slice(0, 16);
    try { localStorage.setItem('chat.recentEmoji', JSON.stringify(list)); } catch (err) { /* ignore */ }
  }

  let emojiTarget = null;
  function openEmoji(anchor, pick) {
    const pop = $('emoji-pop');
    closePops();
    emojiTarget = pick;
    const recent = recentEmoji();
    const groups = (recent.length ? [['Recent', recent]] : []).concat(Object.entries(EMOJI).map(([k, v]) => [k, v.split(' ')]));
    pop.innerHTML = `<div class="pop-tabs">${groups.map(([k], i) => `<button data-i="${i}" class="${i === 0 ? 'on' : ''}" data-no-icon>${esc(k)}</button>`).join('')}</div>
      <div class="emoji-grid">${groups.map(([k, list], i) => `<div class="emoji-group" data-i="${i}"><div class="emoji-group-title">${esc(k)}</div>${list.map((e) => `<button class="emoji" data-no-icon>${e}</button>`).join('')}</div>`).join('')}</div>`;
    for (const b of pop.querySelectorAll('.pop-tabs button')) {
      b.addEventListener('click', () => {
        pop.querySelector(`.emoji-group[data-i="${b.dataset.i}"]`).scrollIntoView({ block: 'start', behavior: 'smooth' });
        for (const x of pop.querySelectorAll('.pop-tabs button')) x.classList.toggle('on', x === b);
      });
    }
    for (const b of pop.querySelectorAll('.emoji')) {
      b.addEventListener('click', () => {
        const e = b.textContent;
        rememberEmoji(e);
        const fn = emojiTarget;
        if (fn) { closePops(); fn(e); }
      });
    }
    place(pop, anchor);
    pop.classList.remove('hidden');
  }

  function insertAtCursor(text) {
    const t = $('chat-input');
    const s = t.selectionStart ?? t.value.length;
    t.value = t.value.slice(0, s) + text + t.value.slice(t.selectionEnd ?? s);
    t.selectionStart = t.selectionEnd = s + text.length;
    grow();
    t.focus();
  }

  function place(pop, anchor) {
    const main = document.querySelector('.chat-main').getBoundingClientRect();
    const a = anchor.getBoundingClientRect();
    pop.style.left = `${Math.max(8, Math.min(a.left - main.left, main.width - 360))}px`;
    pop.style.bottom = `${main.bottom - a.top + 8}px`;
  }

  function closePops() {
    $('emoji-pop').classList.add('hidden');
    $('gif-pop').classList.add('hidden');
  }

  let gifTimer = 0;
  async function openGifs() {
    const pop = $('gif-pop');
    closePops();
    if (!page.gifKey) {
      pop.innerHTML = `<div class="gif-setup"><div class="gif-setup-title">GIF search</div>
        <p>GIF search uses GIPHY. Get a free API key at <b>developers.giphy.com</b> (Create an App › API), paste it here once, and everyone can search GIFs.</p>
        <div class="gif-key-row"><input type="text" id="gif-key" placeholder="GIPHY API key" /><button class="primary" id="gif-key-save" data-no-icon>Save</button></div>
        <p class="small-note">Or send a GIF from this Mac with the picture button.</p></div>`;
      $('gif-key-save').addEventListener('click', async () => {
        const k = $('gif-key').value.trim();
        if (!k) return;
        await window.api.chat.setGifKey(k);
        page.gifKey = k;
        openGifs();
      });
    } else {
      pop.innerHTML = '<input type="search" id="gif-search" placeholder="Search GIPHY" autocomplete="off" /><div class="gif-grid" id="gif-grid"><div class="gif-loading">Loading…</div></div><div class="gif-credit">Powered by GIPHY</div>';
      $('gif-search').addEventListener('input', () => { clearTimeout(gifTimer); gifTimer = setTimeout(() => loadGifs($('gif-search').value.trim()), 300); });
      loadGifs('');
      setTimeout(() => $('gif-search').focus(), 0);
    }
    place(pop, $('chat-gif-btn'));
    pop.classList.remove('hidden');
  }

  async function loadGifs(q) {
    const grid = $('gif-grid');
    if (!grid) return;
    const url = q ? `https://api.giphy.com/v1/gifs/search?api_key=${encodeURIComponent(page.gifKey)}&q=${encodeURIComponent(q)}&limit=24&rating=pg-13`
      : `https://api.giphy.com/v1/gifs/trending?api_key=${encodeURIComponent(page.gifKey)}&limit=24&rating=pg-13`;
    try {
      const res = await fetch(url);
      const body = await res.json();
      if (!res.ok) throw new Error((body && body.message) || 'GIPHY said no');
      const list = (body.data || []).map((g) => ({ preview: g.images.fixed_width_downsampled?.url || g.images.fixed_width.url, full: g.images.downsized_medium?.url || g.images.original.url, title: g.title }));
      grid.innerHTML = list.length ? list.map((g) => `<button class="gif-item" data-full="${esc(g.full)}" data-no-icon title="${esc(g.title)}"><img src="${esc(g.preview)}" alt="" loading="lazy" /></button>`).join('') : '<div class="gif-loading">No GIFs found.</div>';
      for (const b of grid.querySelectorAll('.gif-item')) b.addEventListener('click', () => { closePops(); send({ gifURL: b.dataset.full }); });
    } catch (e) {
      grid.innerHTML = `<div class="gif-loading">GIFs couldn’t be loaded (${esc(e.message)}). Check the internet connection or the GIPHY key.</div>`;
    }
  }

  // ---- polling ----

  let polling = false;
  async function poll(fresh) {
    if (!current || polling) return;
    polling = true;
    try {
      const r = await window.api.chat.messages(current);
      if (!r) return;
      const before = JSON.stringify(messages);
      messages = r.messages || [];
      if (fresh || JSON.stringify(messages) !== before) render(fresh);
      const typingNow = (r.typing || []);
      $('chat-typing').classList.toggle('hidden', !typingNow.length);
      $('chat-typing-text').textContent = typingNow.length ? `${typingNow.join(', ')} ${typingNow.length === 1 ? 'is' : 'are'} typing…` : '';
    } finally { polling = false; }
  }

  async function refreshList() {
    const fresh = await window.api.chat.page();
    if (!fresh) return;
    page = fresh;
    renderConversations();
  }

  (async function init() {
    page = await window.api.chat.page();
    await window.loadPersonColors();
    loadReads();
    let start = null;
    try { start = localStorage.getItem('chat.current'); } catch (e) { /* ignore */ }
    const wanted = new URLSearchParams(location.search).get('with');
    if (wanted) start = page.conversations.find((c) => c.kind === 'dm' && c.with.toLowerCase() === wanted.toLowerCase())?.id || start;
    if (!page.conversations.some((c) => c.id === start)) start = 'everyone';
    $('chat-search').addEventListener('input', renderConversations);
    const input = $('chat-input');
    input.addEventListener('input', () => { grow(); typing(); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); }
      if (e.key === 'Escape' && (replyTo || editing)) { if (editing) input.value = ''; replyTo = null; editing = null; renderReply(); grow(); }
      if (e.key === 'ArrowUp' && !input.value) {
        const mine = [...messages].reverse().find((m) => m.author.toLowerCase() === page.me.toLowerCase() && !m.deleted && !m.gifURL && !m.file);
        if (mine) { e.preventDefault(); editing = mine; input.value = mine.text; renderReply(); grow(); }
      }
    });
    input.addEventListener('blur', () => window.api.chat.typing(null));
    $('chat-send').addEventListener('click', () => send());
    $('chat-emoji-btn').addEventListener('click', (e) => { e.stopPropagation(); if (!$('emoji-pop').classList.contains('hidden')) { closePops(); return; } openEmoji($('chat-emoji-btn'), insertAtCursor); });
    $('chat-gif-btn').addEventListener('click', (e) => { e.stopPropagation(); if (!$('gif-pop').classList.contains('hidden')) { closePops(); return; } openGifs(); });
    $('chat-attach-btn').addEventListener('click', async () => {
      const r = await window.api.chat.attach(current);
      if (r && r.ok === false) { await window.appAlert(r.error); return; }
      poll();
    });
    $('chat-new-pill').addEventListener('click', () => { $('chat-scroll').scrollTo({ top: $('chat-scroll').scrollHeight, behavior: 'smooth' }); $('chat-new-pill').classList.add('hidden'); });
    $('chat-scroll').addEventListener('scroll', () => {
      const s = $('chat-scroll');
      if (s.scrollHeight - s.scrollTop - s.clientHeight < 60) {
        $('chat-new-pill').classList.add('hidden');
        const last = messages[messages.length - 1];
        if (last) markRead(current, last.createdAt);
      }
    });
    document.addEventListener('click', (e) => { if (!e.target.closest('.chat-pop')) closePops(); });
    window.addEventListener('focus', () => { const last = messages[messages.length - 1]; if (last) markRead(current, last.createdAt); });
    await open(start);
    setInterval(poll, 1500);
    setInterval(refreshList, 5000);
  })();
})();
