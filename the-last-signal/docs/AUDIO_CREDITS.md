# Audio sources

Every recording in `www/audio/` is **CC0 (public domain)**: free for commercial use, no credit required. The licence was checked on each source page on OpenGameArt on 2 November 2026. Crediting the authors anyway is a nice gesture.

Files were converted to MP3 and loudness-normalised so nothing jumps out over a screen reader. Sounds that are not listed here (interface clicks, trust changes, objectives, the three-short-one-long signal motif, footsteps, power-up) are still synthesised in code by `www/js/audio/cues.js`.

| File in game | Used for | Original | Author | Source |
|---|---|---|---|---|
| amb-rain.mp3 | Rain at the car, gate and lobby doors | Rain (loopable), file 1 | Ylmir | https://opengameart.org/content/rain-loopable |
| amb-corridor.mp3 | Main corridor bed | Abandoned passages (horror ambience loop) | congusbongus | https://opengameart.org/content/abandoned-passages-horror-ambience-loop |
| amb-facility.mp3 | Lobby and office room tone | Ambient horror | techiew | https://opengameart.org/content/ambient-horror |
| amb-generator.mp3 | Electrical hum once emergency power is on | Generator (loop) | YCbCr | https://opengameart.org/content/generator-loop |
| music-title.mp3 | Main menu music | Insistent: background loop | yd | https://opengameart.org/content/insistent-background-loop |
| music-descent.mp3 | End of Chapter 1, the elevator going down | Descent | cinameng | https://opengameart.org/content/descent |
| music-sublevel.mp3 | Reserved for the sublevels (not used yet) | The Depths of Hell (Ambience Pack 1) | Joth | https://opengameart.org/content/ambience-pack-1-sci-fi-horror |
| sfx-radio-static.mp3 | Radio transmissions | Frequency Static, static3 (0.8 s excerpt) | bretbernhoft | https://opengameart.org/content/frequency-static-sound-effects |
| sfx-elevator.mp3 | Elevator doors | Elevator_Door | PagDev | https://opengameart.org/content/elevatordoor |
| sfx-door.mp3 | Doors | door_open_01 (100 CC0 metal and wood SFX) | rubberduck | https://opengameart.org/content/100-cc0-metal-and-wood-sfx |
| sfx-locker.mp3 | Forcing the locker | metal_open_01 (same pack) | rubberduck | same |
| sfx-latch.mp3 | Glovebox latch | lock_open_01 (same pack) | rubberduck | same |
| sfx-car-door.mp3 | Car door | metal_slam_01 (same pack) | rubberduck | same |
| sfx-locked.mp3 | Locked or blocked way | metal_hit_01 (same pack) | rubberduck | same |
| sfx-stinger.mp3 | Chapter end hit | Very Bassy 1 (Horror Hit Soundpack 1) | psychhead_ | https://opengameart.org/content/horror-hit-soundpack-1 |

Effects were matched to their use by file name and length; they need a listen on headphones to confirm each one fits. Swapping one is a one-line change in `www/js/audio/library.js`.

## Good places to look for more

- OpenGameArt, filtered to CC0: more in the packs above (Ambience Pack 1 has four more sci-fi horror loops; Horror Hit Soundpack 1 has 55 hits).
- Sound effects can also be generated to order with ElevenLabs, which is connected to this workspace, but generating uses credits and its free plan requires attribution.
