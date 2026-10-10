// Replaces files inside node_modules with our fixed copies after every npm
// install. Right now that's one fix: @capacitor-community/speech-recognition
// 7.0.1 can crash the iPhone app when voice listening restarts quickly (the
// old session cleared the new one's request) or when the microphone reports
// a 0 Hz format. The fixed Plugin.swift lives in native-patches/.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const pkgDir = path.join(root, 'node_modules', '@capacitor-community', 'speech-recognition');
const pkgJson = path.join(pkgDir, 'package.json');

if (!fs.existsSync(pkgJson)) {
  console.log('[native-patches] speech-recognition not installed, nothing to patch');
  process.exit(0);
}
const version = JSON.parse(fs.readFileSync(pkgJson, 'utf8')).version;
const fixed = path.join(root, 'native-patches', 'speech-recognition-' + version, 'Plugin.swift');
if (!fs.existsSync(fixed)) {
  console.error('[native-patches] no fix for speech-recognition ' + version + '; check the crash fix still applies, then add native-patches/speech-recognition-' + version + '/Plugin.swift');
  process.exit(1);
}
fs.copyFileSync(fixed, path.join(pkgDir, 'ios', 'Plugin', 'Plugin.swift'));
console.log('[native-patches] applied speech-recognition ' + version + ' crash fix');
