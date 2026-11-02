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

const keep = (scene, node) => node && scene.nodes.push(node);

// Recorded loop if it has loaded, otherwise the synthesised fallback.
function bed(api, bus, scene, sample, opts, fallback) {
  const node = api.loopSample(sample, opts, bus);
  if (node) keep(scene, node);
  else fallback();
}

function powerHum(api, bus, scene, gain, freq) {
  bed(api, bus, scene, 'amb-generator', { gain, lowpass: 900 }, () =>
    keep(scene, api.loopTone({ freq, gain: 0.012 }, bus)),
  );
}

export const SOUNDSCAPES = {
  // Inside the car the rain is muffled by the roof.
  car_rain({ api, bus, scene }) {
    bed(api, bus, scene, 'amb-rain', { gain: 0.7, lowpass: 1400 }, () => {
      keep(scene, api.loopNoise({ freq: 900, gain: 0.12 }, bus));
      keep(scene, api.loopNoise({ filter: 'bandpass', freq: 2600, Q: 0.8, gain: 0.025 }, bus));
    });
    every(scene, 6000, 14000, () => api.tone(1000, 0.12, { gain: 0.008, bus, pan: 0.6 }));
  },

  outdoor_rain({ api, bus, scene }) {
    bed(api, bus, scene, 'amb-rain', { gain: 0.6 }, () => {
      keep(scene, api.loopNoise({ freq: 3000, gain: 0.06 }, bus));
      keep(scene, api.loopNoise({ filter: 'bandpass', freq: 4500, Q: 2, gain: 0.02, pan: -0.6 }, bus));
    });
    every(scene, 9000, 20000, () =>
      api.tone(38, 2.5, { type: 'sawtooth', lowpass: 120, gain: 0.05, attack: 0.6, bus }),
    );
  },

  lobby({ api, bus, scene, powered }) {
    bed(api, bus, scene, 'amb-facility', { gain: 0.35 }, () =>
      keep(scene, api.loopNoise({ freq: 300, gain: 0.04 }, bus)),
    );
    // Rain still audible through the front doors behind you.
    keep(scene, api.loopSample('amb-rain', { gain: 0.12, lowpass: 700 }, bus));
    if (powered) powerHum(api, bus, scene, 0.15, 60);
    // Dripping water on your left.
    every(scene, 2000, 5000, () =>
      api.tone(1800, 0.05, { slideTo: 1100, gain: 0.02, bus, pan: -0.6 }),
    );
  },

  office({ api, bus, scene, powered }) {
    bed(api, bus, scene, 'amb-facility', { gain: 0.25, lowpass: 2000 }, () =>
      keep(scene, api.loopNoise({ freq: 250, gain: 0.03 }, bus)),
    );
    if (powered) {
      powerHum(api, bus, scene, 0.2, 120);
      keep(scene, api.loopNoise({ filter: 'highpass', freq: 6000, gain: 0.006 }, bus));
    }
  },

  corridor({ api, bus, scene, powered }) {
    bed(api, bus, scene, 'amb-corridor', { gain: 0.45 }, () =>
      keep(scene, api.loopNoise({ freq: 180, gain: 0.045 }, bus)),
    );
    if (powered) powerHum(api, bus, scene, 0.12, 50);
    every(scene, 8000, 16000, () =>
      api.tone(90, 0.7, { slideTo: 70, gain: 0.03, attack: 0.2, bus, pan: Math.random() * 2 - 1 }),
    );
  },

  elevator({ api, bus, scene }) {
    powerHum(api, bus, scene, 0.3, 70);
    keep(scene, api.loopNoise({ freq: 400, gain: 0.03 }, bus));
  },
};
