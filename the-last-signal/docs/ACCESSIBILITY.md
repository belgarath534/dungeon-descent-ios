# Accessibility testing checklist

Run through this with VoiceOver on an iPhone after each increment. Automated tests check structure (one heading per screen, every button and form control has a label, no duplicate IDs), but only a person can confirm how the game feels.

## Most important to confirm first

- [ ] **After every action, VoiceOver reads the new text without you touching anything.** The game moves focus to the narration block. If VoiceOver only reads the first paragraph, or nothing, note it: the alternative is to send new text straight to the screen reader instead of moving focus, and that is a small change.
- [ ] Swiping right from the narration reaches the options for the next decision in a sensible order.
- [ ] Choices in a conversation are announced with their number, such as "1. Police. Dispatch picked up a signal from this place."

## Navigation

- [ ] The rotor set to Headings jumps between: place name, Actions, Around you, Exits, Menu.
- [ ] Every button says what it does on its own, without needing the text around it. Objects include their position ("Front desk, ahead"), exits include direction ("East: Security office").
- [ ] Opening an object moves focus to its name, and "Back to the room" returns focus to that object.
- [ ] Locked exits say ", locked" after you have tried them once.
- [ ] Nothing is reachable only by sight or only by gesture.

## Sound

- [ ] With headphones, objects and exits on the left and right play in the correct ear as you move between them.
- [ ] Ambience never drowns out VoiceOver. Volume sliders work with swipe up and down and announce percentages.
- [ ] Mono audio puts every sound in both ears.
- [ ] Every sound in the glossary on "How to play" is distinct and easy to learn.
- [ ] "Reduce sudden loud sounds" makes the power and locker sounds clearly softer.

## Speech modes

- [ ] Screen reader mode: no double speech (the game never talks over VoiceOver).
- [ ] Built-in voice mode, with VoiceOver off: new text is read aloud, and each control is read as you tab to it.

## Stealth (Chapter 3)

- [ ] 001's footsteps are clearly in the correct ear, and you can tell one room away from two rooms away.
- [ ] The warning "It is coming toward you" arrives in time to act.
- [ ] Listen always tells you where 001 is in words.
- [ ] Being caught, dying and "Try again from the last checkpoint" are all clear and easy to reach.

## Saving

- [ ] Leave the app mid-conversation, reopen it, choose Continue: the game reminds you of the conversation and offers the same replies.
- [ ] Save slot buttons describe the place, chapter and time of each save.

## Reading and comfort

- [ ] Large and Larger text sizes reflow without cutting anything off.
- [ ] High contrast mode is readable.
- [ ] Documents in the journal read cleanly from top to bottom.

## Known limits of this build

- The game runs in Safari or any browser; it is not yet wrapped as an iOS app (see `ARCHITECTURE.md`).
- On iPhone, the silent switch may mute game sounds in Safari. The app version will fix this.
- Sounds are synthesised placeholders. Voices are text read by your screen reader; there is no recorded voice acting yet.
