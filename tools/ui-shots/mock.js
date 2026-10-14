'use strict';
// Mock replies for the native bridge, by route ('area:action'). Unknown routes get a
// guess from the name: lists → [], everything else → {}. Add realistic data per route.
const D = require('./data.js');

function reply(action, payload) {
  if (Object.prototype.hasOwnProperty.call(D.routes, action)) {
    const r = D.routes[action];
    return typeof r === 'function' ? r(payload || {}) : r;
  }
  if (/:(list|search|people|roster|history|events|activity|recent|all|names|members|leads|items|log)/i.test(action) || /s$/.test(action.split(':')[1] || '')) return [];
  return {};
}
module.exports = { reply };
