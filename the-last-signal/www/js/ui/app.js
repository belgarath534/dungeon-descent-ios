// The application shell: owns the services, switches screens, manages
// focus, autosaves, and turns engine events into sound and speech.

import { focusEl } from './dom.js';
import { trustLevel } from '../systems/trust.js';

export function createApp({ root, game, saves, settings, announcer, audio, bus, screens }) {
  let current = null; // { name, instance }
  const history = [];
  const pendingNotes = [];
  let gameView = null;

  const app = {
    game,
    saves,
    settings,
    announcer,
    audio,
    bus,
    history,

    show(name, params = {}) {
      const factory = screens[name];
      if (!factory) throw new Error(`Unknown screen ${name}`);
      current?.instance.onHide?.();
      let instance;
      if (name === 'game') {
        // The game screen persists so the last narration survives menus.
        gameView ||= factory(app);
        instance = gameView;
      } else {
        instance = factory(app, params);
      }
      current = { name, instance, params };
      root.replaceChildren(instance.el);
      document.title = instance.title ? `${instance.title} \u2014 The Last Signal` : 'The Last Signal';
      instance.onShow?.(params);
      focusEl(instance.focusTarget?.() || instance.el.querySelector('h1'));
    },

    // Open a screen that returns to the current one when closed.
    open(name, params = {}) {
      audio.cue('ui.select');
      const returnParams = current?.name === 'game' ? {} : current?.params;
      app.show(name, { ...params, returnTo: current?.name, returnParams });
    },

    back() {
      audio.cue('ui.back');
      const p = current?.params;
      if (p?.returnTo) app.show(p.returnTo, p.returnParams || {});
      else app.show(game.state ? 'game' : 'title');
    },

    notify(text, opts) {
      announcer.notify(text, opts);
    },

    recordBeat(lines) {
      if (lines.length) history.push(lines);
      if (history.length > 200) history.shift();
    },

    // Lines produced by event listeners during an action (trust changes)
    // are appended to that action's text so screen readers read them in order.
    takeNotes() {
      return pendingNotes.splice(0);
    },

    autosave() {
      if (!game.state) return;
      saves.save('auto', game.snapshot(), game.saveMeta());
    },

    saveTo(slot) {
      const ok = saves.save(slot, game.snapshot(), game.saveMeta());
      audio.cue(ok ? 'saved' : 'ui.error');
      return ok;
    },

    loadFrom(slot) {
      const data = saves.load(slot);
      if (!data) {
        audio.cue('ui.error');
        app.notify('That save could not be loaded.', { assertive: true });
        return false;
      }
      game.loadState(data.state);
      gameView = null;
      history.length = 0;
      app.show('game', { resume: true });
      return true;
    },

    newGame() {
      gameView = null;
      history.length = 0;
      app.show('game', { newGame: true });
    },

    get currentScreen() {
      return current?.name;
    },

    get currentParams() {
      return current?.params;
    },
  };

  // ---- engine events -> feedback ---------------------------------------
  bus.on('cue', (c) => audio.cue(c.name, c));

  function updateSoundscape() {
    const state = game.state;
    const room = state && game.ctx.content.rooms[state.location];
    if (!room) return;
    const powered = !!state.flags.power_on;
    const w = state.ward || {};
    const key = `${powered}|${w.emilyAlive}|${w.active ? w.location : '-'}`;
    audio.setSoundscape(room.soundscape, { powered, key, state });
  }
  bus.on('room:entered', updateSoundscape);
  bus.on('state:changed', updateSoundscape);

  bus.on('trust:changed', ({ delta, level, levelChanged }) => {
    const mode = settings.get('trustFeedback');
    if (mode === 'off') return;
    audio.cue(delta > 0 ? 'trust.up' : 'trust.down');
    if (mode === 'speech') {
      pendingNotes.push(
        `Daniel’s trust ${delta > 0 ? 'rose' : 'fell'}.` +
          (levelChanged ? ` He now seems ${level.label}.` : ''),
      );
    }
  });

  // ---- global input -------------------------------------------------------
  const unlock = () => audio.unlock();
  window.addEventListener('pointerdown', unlock, { once: false, passive: true });
  window.addEventListener('keydown', unlock, { passive: true });

  document.addEventListener('focusin', (e) => {
    const el = e.target;
    if (el.dataset?.pan !== undefined) audio.cue('ui.move', { pan: Number(el.dataset.pan) });
    if (el.dataset?.quiet !== undefined) return;
    const text = el.getAttribute('aria-label') || el.innerText || el.textContent;
    announcer.focused(text);
  });

  document.addEventListener('keydown', (e) => {
    if (!settings.get('shortcuts')) return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (/^(INPUT|SELECT|TEXTAREA)$/.test(e.target.tagName)) return;
    const handled = current?.instance.onKey?.(e.key);
    if (handled) {
      e.preventDefault();
      return;
    }
    if (e.key === 'Escape' && current?.name !== 'title' && current?.name !== 'game') {
      e.preventDefault();
      app.back();
    }
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      app.autosave();
      audio.suspend();
      announcer.stop();
    } else {
      audio.resume();
    }
  });

  app.trustLevel = () => trustLevel(game.state.trust.daniel.value);
  return app;
}
