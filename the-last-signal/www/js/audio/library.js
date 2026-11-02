// Recorded audio used by the game. Every file here is CC0 (public domain):
// free to use commercially, no credit required. Sources, authors and the
// original files are listed in docs/AUDIO_CREDITS.md.
// Files live in www/audio/ and were loudness-normalised so none of them
// jump out over a screen reader.

export const SAMPLE_FILES = {
  // ambience loops
  'amb-rain': 'audio/amb-rain.mp3',
  'amb-corridor': 'audio/amb-corridor.mp3',
  'amb-facility': 'audio/amb-facility.mp3',
  'amb-generator': 'audio/amb-generator.mp3',
  // music
  'music-title': 'audio/music-title.mp3',
  'music-descent': 'audio/music-descent.mp3',
  // one-shot effects
  'sfx-radio-static': 'audio/sfx-radio-static.mp3',
  'sfx-elevator': 'audio/sfx-elevator.mp3',
  'sfx-door': 'audio/sfx-door.mp3',
  'sfx-locker': 'audio/sfx-locker.mp3',
  'sfx-latch': 'audio/sfx-latch.mp3',
  'sfx-car-door': 'audio/sfx-car-door.mp3',
  'sfx-locked': 'audio/sfx-locked.mp3',
  'sfx-stinger': 'audio/sfx-stinger.mp3',
};

// Which game cue each recording replaces. Cues not listed here keep
// their synthesised sound (interface sounds, trust, the signal motif).
export const CUE_SAMPLES = {
  door: 'sfx-door',
  'car.door': 'sfx-car-door',
  locker: 'sfx-locker',
  latch: 'sfx-latch',
  locked: 'sfx-locked',
  'elevator.open': 'sfx-elevator',
  'radio.static': 'sfx-radio-static',
  'radio.on': 'sfx-radio-static',
  'chapter.end': 'sfx-stinger',
};

// Turned down when "Reduce sudden loud sounds" is on.
export const STARTLING = new Set(['sfx-stinger', 'sfx-locker', 'sfx-car-door']);
