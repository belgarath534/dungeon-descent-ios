// Copies the game's data tables (enemies, loot, shops, traps, room text,
// floor names) out of the web version into one JSON file the Swift version
// reads, so the numbers can't drift from the web game.
//
//   node swift/tools/extract-game-data.js
//
// Reads www/index.html, writes swift/DungeonCore/Sources/DungeonCore/Resources/gamedata.json.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const src = fs.readFileSync(path.join(root, 'www', 'index.html'), 'utf8');

// Finds `var NAME = [...]` or `var NAME = {...}` and evaluates just that literal.
function grab(name) {
  const m = new RegExp('var ' + name + ' = ').exec(src);
  if (!m) return undefined;
  const start = m.index + m[0].length;
  const open = src[start], close = open === '[' ? ']' : '}';
  let depth = 0, quote = null, j = start;
  for (; j < src.length; j++) {
    const c = src[j];
    if (quote) {
      if (c === '\\') { j++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && src[j + 1] === '/') { j = src.indexOf('\n', j); continue; }
    if (c === '/' && src[j + 1] === '*') { j = src.indexOf('*/', j) + 1; continue; }
    if (c === "'" || c === '"' || c === '`') { quote = c; continue; }
    if (c === open) depth++;
    else if (c === close && --depth === 0) break;
  }
  return eval('(' + src.slice(start, j + 1) + ')');
}

// Floor names are a list starting with an empty entry, or (Sunken, Hollow)
// an object keyed by floor number; both become the list form.
function floorList(v) {
  if (!v || Array.isArray(v)) return v;
  const list = [''];
  Object.keys(v).map(Number).sort((a, b) => a - b).forEach(k => { list[k] = v[k]; });
  return Array.from(list, x => x || '');
}

// Audio tables call _audioUrl('file.mp3'); here that just returns the file name.
// eslint-disable-next-line no-unused-vars
function _audioUrl(f) { return f; }

// Keeps only plain data: functions (e.g. RUNE_DEFS.apply) are dropped.
function plain(v) { return JSON.parse(JSON.stringify(v)); }

const eliteTable = grab('ELITE_ENEMIES');

// eliteKey: the ELITE_ENEMIES entry for this table (a dungeon name or 'Nightmare').
function enemies(prefix, eliteKey) {
  const e = grab(prefix + 'ENEMIES');
  if (!e) return undefined;
  return plain({
    t1: e.t1 || [], t2: e.t2 || [], t3: e.t3 || [],
    bosses: e.bossPool || (e.boss ? [e.boss] : []),
    elites: (eliteTable[eliteKey] || []).concat(e.elites || [])
      .concat(eliteKey === 'The Whispering Forest' ? grab('WHISPER_ELITES') || [] : []),
  });
}

// Which tables each dungeon uses. A dungeon without its own table of some
// kind falls back to the Crypt's, as the web version does.
const dungeons = {
  'Crypt of Malachar':     '',
  'The Ashbound Wastes':   'ASH_',
  'Frosthold Abyss':       'FROST_',
  'The Sunken Archives':   'SUNKEN_',
  'The Hollow':            'HOLLOW_',
  'The Whispering Forest': 'WHISPER_',
  'The Infernal Descent':  'INFERNAL_',
  'The Abyssal Deep':      'ABYSSAL_',
};

// Starting skill per class, from initSkillPool().
function startingSkills() {
  const m = /var startingSkills = (\{[^}]*\})/.exec(src);
  return m ? JSON.parse(m[1]) : {};
}

// Turns an achievement's check function into a data condition Swift can test:
//   { stat, min }   achievement stat (dd_ach_stats) at least min (true counts as 1)
//   { key, min }    a number saved under a store key at least min
//   { listKey, min } a JSON list saved under a store key with at least min entries
//   { equalsKey, value }, { gold, min }, { trophies, min }
function achievementCondition(fn) {
  const c = fn ? fn.toString().replace(/\s+/g, ' ') : '';
  let m;
  if ((m = /s(?:\.(\w+)|\['([^']+)'\])\s*\|\|\s*0\)?\s*>=\s*(\d+)/.exec(c))) return { stat: m[1] || m[2], min: +m[3] };
  if ((m = /s\.(\w+)\s*>=\s*(\d+)/.exec(c))) return { stat: m[1], min: +m[2] };
  if ((m = /parseInt\(DDStore\.getItem\('(\w+)'\)\s*\|\|\s*'0'\)\s*>=\s*(\d+)/.exec(c))) return { key: m[1], min: +m[2] };
  if ((m = /_jsonParseSafe\(DDStore\.getItem\('(\w+)'\)[^)]*\)\.length\s*>=\s*(\d+)/.exec(c))) return { listKey: m[1], min: +m[2] };
  if ((m = /DDStore\.getItem\('(\w+)'\)\s*===\s*'([^']*)'/.exec(c))) return { equalsKey: m[1], value: m[2] };
  if ((m = /getGlobalGold\(\)\s*>=\s*(\d+)/.exec(c))) return { gold: +m[1] };
  if ((m = /getTrophies\(\)\s*>=\s*(\d+)/.exec(c))) return { trophies: +m[1] };
  if ((m = /return\s*!*s\.(\w+)\s*;?\s*\}/.exec(c))) return { stat: m[1], min: 1 };
  return {};
}

function achievements() {
  global.DDStore = { getItem: () => null };
  return grab('ACHIEVEMENTS').map(a => ({
    id: a.id, name: a.name, icon: a.icon, desc: a.desc, hint: a.hint,
    gold: a.gold || 50, trophies: a.trophies || 1, gcId: a.gcId || null,
    condition: achievementCondition(a.check),
  }));
}

const out = {
  dungeons: {},
  nightmareEnemies: enemies('NIGHTMARE_', 'Nightmare'),
  enemySpecials: plain(grab('ENEMY_SPECIALS')),
  achievements: achievements(),
  dailyQuests: plain(grab('DAILY_QUESTS')),
  traps: plain(grab('TRAP_TYPES')),
  classSkills: plain(grab('CLASS_SKILLS')),
  startingSkills: startingSkills(),
  audio: {
    tracks: plain(grab('TRACK_FILES')),
    ambient: plain(grab('AMBIENT_FILES')),
    enemySfx: plain(grab('DUNGEON_ENEMY_SFX')),
    bossSfx: plain(grab('DUNGEON_BOSS_SFX')),
  },
};
const crypt = { loot: grab('LOOT'), shop: grab('SHOP_STOCK'), rooms: grab('ROOM_DESCS'), floors: grab('FLOOR_NAMES') };
for (const [name, p] of Object.entries(dungeons)) {
  out.dungeons[name] = {
    enemies: enemies(p, name),
    loot: plain(grab(p + 'LOOT') || crypt.loot),
    shop: plain(grab(p + 'SHOP_STOCK') || crypt.shop),
    rooms: plain(grab(p + 'ROOM_DESCS') || crypt.rooms),
    floors: plain(floorList(grab(p + 'FLOOR_NAMES')) || crypt.floors),
  };
}

const file = path.join(root, 'swift', 'DungeonCore', 'Sources', 'DungeonCore', 'Resources', 'gamedata.json');
fs.writeFileSync(file, JSON.stringify(out, null, 1) + '\n');
const count = Object.values(out.dungeons).reduce((n, d) => n + d.enemies.t1.length + d.enemies.t2.length + d.enemies.t3.length + d.enemies.bosses.length, 0);
console.log('Wrote ' + path.relative(root, file) + ': ' + Object.keys(out.dungeons).length + ' dungeons, ' + count + ' enemies and bosses.');

// Text the dungeon screen shows: the death cinematic lines, defeat quotes and
// the victory closing line for each dungeon and class.
const ui = {
  deathLines: plain(grab('DEATH_LINES')),
  defeatQuotes: plain(grab('DEFEAT_QUOTES')),
  nightmareDefeatQuotes: plain(grab('NIGHTMARE_DEFEAT_QUOTES')),
  closingLines: plain(grab('CLOSING_LINES')),
};
const uiFile = path.join(root, 'swift', 'App', 'DungeonDescent', 'uitext.json');
fs.writeFileSync(uiFile, JSON.stringify(ui, null, 1) + '\n');
console.log('Wrote ' + path.relative(root, uiFile) + ': ' + Object.keys(ui.deathLines || {}).length + ' dungeons of death lines, ' + Object.keys(ui.closingLines || {}).length + ' of closing lines.');

// The Bestiary: every entry, the enemy-name-to-entry map recordKill() uses,
// and the kill milestones.
{
  const nameToId = (() => {
    const i = src.indexOf('var nameToId = {', src.indexOf('function recordKill('));
    const j = src.indexOf('};', i);
    return eval('(' + src.slice(i + 'var nameToId = '.length, j + 1) + ')');
  })();
  const bestiary = {
    entries: plain(grab('BESTIARY_DATA')),
    nameToId,
    milestones: plain(grab('BESTIARY_MILESTONES')),
  };
  const f = path.join(root, 'swift', 'App', 'DungeonDescent', 'bestiary.json');
  fs.writeFileSync(f, JSON.stringify(bestiary, null, 1) + '\n');
  console.log('Wrote ' + path.relative(root, f) + ': ' + bestiary.entries.length + ' entries, ' + Object.keys(nameToId).length + ' names, ' + Object.keys(bestiary.milestones).length + ' milestones.');
}
