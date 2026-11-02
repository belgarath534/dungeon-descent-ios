// Looping room ambience. Each room names one of these. Ambience is quiet
// on purpose: it must never cover speech from a screen reader.
// `powered` is true once emergency power is restored, which adds the
// electrical hum players learn to associate with a live building.

function every(scene, minMs, maxMs, fn) {
  let id;
  const schedule = () => {
    id = setTimeout(() => {
      fn();
      schedule();
    }, minMs + Math.random() * (maxMs - minMs));
    scene.timers.push(id);
  };
  schedule();
}

const keep = (scene, node) => scene.nodes.push(node);

export const SOUNDSCAPES = {
  car_rain({ api, bus, scene }) {
    keep(scene, api.loopNoise({ freq: 900, gain: 0.12 }, bus));
    keep(scene, api.loopNoise({ filter: 'bandpass', freq: 2600, Q: 0.8, gain: 0.025 }, bus));
    every(scene, 6000, 14000, () => api.tone(1000, 0.12, { gain: 0.008, bus, pan: 0.6 }));
  },

  outdoor_rain({ api, bus, scene }) {
    keep(scene, api.loopNoise({ freq: 3000, gain: 0.06 }, bus));
    keep(scene, api.loopNoise({ filter: 'bandpass', freq: 4500, Q: 2, gain: 0.02, pan: -0.6 }, bus));
    every(scene, 9000, 20000, () =>
      api.tone(38, 2.5, { type: 'sawtooth', lowpass: 120, gain: 0.05, attack: 0.6, bus }),
    );
  },

  lobby({ api, bus, scene, powered }) {
    keep(scene, api.loopNoise({ freq: 300, gain: 0.04 }, bus));
    if (powered) keep(scene, api.loopTone({ freq: 60, gain: 0.012 }, bus));
    every(scene, 2000, 5000, () =>
      api.tone(1800, 0.05, { slideTo: 1100, gain: 0.02, bus, pan: -0.6 }),
    );
  },

  office({ api, bus, scene, powered }) {
    keep(scene, api.loopNoise({ freq: 250, gain: 0.03 }, bus));
    if (powered) {
      keep(scene, api.loopTone({ freq: 120, gain: 0.01 }, bus));
      keep(scene, api.loopNoise({ filter: 'highpass', freq: 6000, gain: 0.006 }, bus));
    }
  },

  corridor({ api, bus, scene, powered }) {
    keep(scene, api.loopNoise({ freq: 180, gain: 0.045 }, bus));
    if (powered) keep(scene, api.loopTone({ freq: 50, gain: 0.012 }, bus));
    every(scene, 8000, 16000, () =>
      api.tone(90, 0.7, { slideTo: 70, gain: 0.03, attack: 0.2, bus, pan: Math.random() * 2 - 1 }),
    );
  },

  elevator({ api, bus, scene }) {
    keep(scene, api.loopTone({ freq: 70, gain: 0.03 }, bus));
    keep(scene, api.loopNoise({ freq: 400, gain: 0.03 }, bus));
  },
};
