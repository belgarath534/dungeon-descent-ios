// Procedural audio: every sound is synthesised with the Web Audio API,
// so the game has a complete, consistent sound language before any
// recorded assets exist. Recorded files can later replace any cue by
// name (see registerSample) without touching game code.
//
// Spatial rule used everywhere: things on your left play in the left ear,
// things on your right in the right ear, things ahead in the centre.
// "Mono audio" setting collapses everything to the centre.

import { CUES } from './cues.js';
import { SOUNDSCAPES } from './soundscapes.js';

export function createAudio({ settings }) {
  let ac = null;
  let master, sfxBus, ambBus;
  let noiseBuffer = null;
  let current = null; // { id, powered, nodes: [], timers: [], gain }
  const samples = new Map();

  function ensure() {
    if (ac) return ac;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ac = new AC();
    master = ac.createGain();
    sfxBus = ac.createGain();
    ambBus = ac.createGain();
    sfxBus.connect(master);
    ambBus.connect(master);
    master.connect(ac.destination);
    noiseBuffer = makeNoise(ac, 3);
    applyVolumes();
    return ac;
  }

  function makeNoise(ctx, seconds) {
    const buf = ctx.createBuffer(1, ctx.sampleRate * seconds, ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    return buf;
  }

  function applyVolumes() {
    if (!ac) return;
    master.gain.value = settings.get('masterVolume');
    sfxBus.gain.value = settings.get('effectsVolume');
    ambBus.gain.value = settings.get('ambienceVolume');
  }

  function panner(pan = 0) {
    const p = settings.get('monoAudio') ? 0 : pan;
    if (ac.createStereoPanner) {
      const node = ac.createStereoPanner();
      node.pan.value = Math.max(-1, Math.min(1, p));
      return node;
    }
    return ac.createGain();
  }

  // ---- building blocks shared by cues and soundscapes -------------------
  const api = {
    get ctx() {
      return ac;
    },
    get now() {
      return ac.currentTime;
    },
    reduceStartles: () => settings.get('reduceStartles'),

    tone(freq, dur, o = {}) {
      const t = ac.currentTime + (o.at || 0);
      const osc = ac.createOscillator();
      osc.type = o.type || 'sine';
      osc.frequency.setValueAtTime(freq, t);
      if (o.slideTo) osc.frequency.exponentialRampToValueAtTime(o.slideTo, t + dur);
      const env = envelope(t, dur, o);
      let out = osc;
      if (o.lowpass) {
        const f = ac.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = o.lowpass;
        osc.connect(f);
        out = f;
      }
      out.connect(env.input);
      env.output.connect(o.bus || sfxBus);
      osc.start(t);
      osc.stop(t + dur + 0.05);
      return osc;
    },

    noise(dur, o = {}) {
      const t = ac.currentTime + (o.at || 0);
      const src = ac.createBufferSource();
      src.buffer = noiseBuffer;
      src.loop = true;
      const f = ac.createBiquadFilter();
      f.type = o.filter || 'lowpass';
      f.frequency.setValueAtTime(o.freq || 1000, t);
      if (o.sweepTo) f.frequency.exponentialRampToValueAtTime(o.sweepTo, t + dur);
      f.Q.value = o.Q || 0.7;
      const env = envelope(t, dur, o);
      src.connect(f);
      f.connect(env.input);
      env.output.connect(o.bus || sfxBus);
      src.start(t, Math.random() * 2);
      src.stop(t + dur + 0.05);
      return src;
    },

    // Continuous layers for ambience; returned nodes are stopped on fade-out.
    loopNoise(o, bus) {
      const src = ac.createBufferSource();
      src.buffer = noiseBuffer;
      src.loop = true;
      const f = ac.createBiquadFilter();
      f.type = o.filter || 'lowpass';
      f.frequency.value = o.freq || 500;
      f.Q.value = o.Q || 0.7;
      const g = ac.createGain();
      g.gain.value = o.gain || 0.05;
      const p = panner(o.pan || 0);
      src.connect(f);
      f.connect(g);
      g.connect(p);
      p.connect(bus);
      src.start(0, Math.random() * 2);
      return src;
    },

    loopTone(o, bus) {
      const osc = ac.createOscillator();
      osc.type = o.type || 'sine';
      osc.frequency.value = o.freq;
      const g = ac.createGain();
      g.gain.value = o.gain || 0.02;
      osc.connect(g);
      g.connect(bus);
      osc.start();
      return osc;
    },
  };

  function envelope(t, dur, o) {
    const g = ac.createGain();
    const peak = o.gain ?? 0.2;
    const attack = o.attack ?? 0.005;
    const release = o.release ?? Math.min(0.1, dur / 2);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0002), t + attack);
    g.gain.setValueAtTime(Math.max(peak, 0.0002), t + Math.max(attack, dur - release));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    if (o.pan !== undefined) {
      const p = panner(o.pan);
      g.connect(p);
      return { input: g, output: p };
    }
    return { input: g, output: g };
  }

  function playSample(name, o) {
    const buf = samples.get(name);
    const src = ac.createBufferSource();
    src.buffer = buf;
    const p = panner(o.pan || 0);
    src.connect(p);
    p.connect(sfxBus);
    src.start();
  }

  // ---- ambience -------------------------------------------------------------
  function stopCurrent(fade = 1.2) {
    if (!current) return;
    const old = current;
    current = null;
    old.timers.forEach(clearInterval);
    old.timers.forEach(clearTimeout);
    const t = ac.currentTime;
    old.gain.gain.setValueAtTime(old.gain.gain.value, t);
    old.gain.gain.linearRampToValueAtTime(0, t + fade);
    setTimeout(() => {
      old.nodes.forEach((n) => {
        try {
          n.stop();
        } catch {
          /* already stopped */
        }
      });
      old.gain.disconnect();
    }, fade * 1000 + 100);
  }

  return {
    unlock() {
      const ctx = ensure();
      if (ctx && ctx.state === 'suspended') ctx.resume();
    },

    applyVolumes,

    cue(name, opts = {}) {
      if (!ensure()) return;
      if (samples.has(name)) return playSample(name, opts);
      const fn = CUES[name];
      if (!fn) return;
      try {
        fn(api, opts);
      } catch (err) {
        console.warn(`[audio] cue ${name} failed`, err);
      }
    },

    setSoundscape(id, { powered = false } = {}) {
      if (!ensure()) return;
      if (current && current.id === id && current.powered === powered) return;
      stopCurrent();
      const profile = SOUNDSCAPES[id];
      if (!profile) return;
      const gain = ac.createGain();
      gain.gain.value = 0;
      gain.connect(ambBus);
      gain.gain.linearRampToValueAtTime(1, ac.currentTime + 1.5);
      const scene = { id, powered, nodes: [], timers: [], gain };
      profile({ api, bus: gain, scene, powered, panner });
      current = scene;
    },

    stopAmbience: () => ac && stopCurrent(0.5),

    // Replace a synthesised cue with a recorded file later on.
    async registerSample(name, url) {
      if (!ensure()) return;
      const res = await fetch(url);
      samples.set(name, await ac.decodeAudioData(await res.arrayBuffer()));
    },

    suspend: () => ac?.suspend(),
    resume: () => ac?.resume(),
  };
}
