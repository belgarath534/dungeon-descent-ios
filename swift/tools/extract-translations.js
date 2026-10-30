// Copies the web version's Portuguese translations into the Swift app's
// String Catalog, so every English line the web version translated shows
// in Portuguese on an iPhone set to Portuguese (or with the game's
// Language setting on Português).
//
//   node swift/tools/extract-translations.js
//
// Reads www/index.html: the T['pt-BR'] table that t() uses and the early
// PT table for the main menu. Writes
// swift/App/DungeonDescent/Localizable.xcstrings, keeping any entries added
// to the catalog by hand (Swift-only text) and replacing the web ones.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..', '..');
const html = fs.readFileSync(path.join(root, 'www', 'index.html'), 'utf8');

// Slices `var NAME = { ... };` out of the page by brace depth (strings skipped).
function slice(marker) {
  const at = html.indexOf(marker);
  if (at < 0) throw new Error('Not found: ' + marker);
  let i = html.indexOf('{', at), depth = 0, quote = null;
  for (; i < html.length; i++) {
    const c = html[i];
    if (quote) {
      if (c === '\\') { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && html[i + 1] === '/') { i = html.indexOf('\n', i); continue; }
    if (c === '/' && html[i + 1] === '*') { i = html.indexOf('*/', i) + 1; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}' && --depth === 0) break;
  }
  return html.slice(html.indexOf('{', at), i + 1);
}

const pairs = {};
function add(table) {
  for (const [en, pt] of Object.entries(table)) {
    if (typeof pt !== 'string' || !en.trim() || en === pt) continue;
    pairs[en] = pt;
  }
}
add(vm.runInNewContext('(' + slice('  var PT = {') + ')'));
add(vm.runInNewContext('(' + slice('var T = {') + ')')['pt-BR']);

const out = path.join(root, 'swift', 'App', 'DungeonDescent', 'Localizable.xcstrings');
let catalog = { sourceLanguage: 'en', strings: {}, version: '1.0' };
if (fs.existsSync(out)) catalog = JSON.parse(fs.readFileSync(out, 'utf8'));
for (const [en, pt] of Object.entries(pairs)) {
  catalog.strings[en] = { extractionState: 'manual', localizations: { 'pt-BR': { stringUnit: { state: 'translated', value: pt } } } };
}
const sorted = {};
for (const k of Object.keys(catalog.strings).sort()) sorted[k] = catalog.strings[k];
catalog.strings = sorted;
fs.writeFileSync(out, JSON.stringify(catalog, null, 2) + '\n');
console.log('Wrote ' + Object.keys(pairs).length + ' translations to ' + path.relative(root, out));
