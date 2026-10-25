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

// Keeps only plain data: functions (e.g. RUNE_DEFS.apply) are dropped.
function plain(v) { return JSON.parse(JSON.stringify(v)); }

function enemies(prefix) {
  const e = grab(prefix + 'ENEMIES');
  if (!e) return undefined;
  return plain({
    t1: e.t1 || [], t2: e.t2 || [], t3: e.t3 || [],
    bosses: e.bossPool || (e.boss ? [e.boss] : []),
    elites: e.elites || [],
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

const out = {
  dungeons: {},
  nightmareEnemies: enemies('NIGHTMARE_'),
  traps: plain(grab('TRAP_TYPES')),
  classSkills: plain(grab('CLASS_SKILLS')),
  startingSkills: startingSkills(),
};
const crypt = { loot: grab('LOOT'), shop: grab('SHOP_STOCK'), rooms: grab('ROOM_DESCS'), floors: grab('FLOOR_NAMES') };
for (const [name, p] of Object.entries(dungeons)) {
  out.dungeons[name] = {
    enemies: enemies(p),
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
