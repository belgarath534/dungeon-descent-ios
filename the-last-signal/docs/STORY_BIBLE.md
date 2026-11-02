# The Last Signal: story bible

This file keeps the story canon in one place. **Section 1 is the creator's brief and is canon.** Section 2 lists details I added while writing Chapter 1. Those are placeholders until the creator approves them. Section 3 lists open questions that need a decision before the story goes further.

Rule for everyone working on the game: do not remove details from Section 1, and do not make major plot changes without discussing them first. No proposed ending is final.

---

## 1. Canon (from the creator's brief)

**Genre and promise.** An accessibility-first, first-person psychological horror and investigation game. It must be fully playable by blind players using screen readers such as VoiceOver, with accessible menus, clear audio navigation, environmental sound cues, spoken descriptions and accessible interactions.

**The protagonist.** A former employee of an abandoned research facility. They left two years ago and became a police officer. Dispatch receives a mysterious signal coming from the facility, and the protagonist is sent to investigate.

**The facility.** It was abandoned after a secret underground experiment.

**Daniel.** The former robotics director. He originally wanted to create a helpful humanoid assistant robot. His colleagues betrayed him, removed him from his position, and transferred his consciousness into an artificial robotic body without his permission. Daniel eventually turned against the scientists and was isolated somewhere inside the facility.
- The player first communicates with Daniel through radios and the facility speakers.
- Daniel knows where his robotic body is, but does not trust the player enough to reveal everything at first.
- The player's honesty and decisions affect Daniel's trust, which changes his cooperation, dialogue, warnings and help.
- The player eventually discovers Daniel's original biological body. The location of his robotic body remains a mystery.

**Dr. Emily Carter.** Daniel's closest friend and colleague. She helped develop his original robotics project and knew about the experiment. The scientists captured her and placed her in a preservation capsule so she could not interfere.
- The player discovers she is alive, moves her to the facility's medical ward, and must check on her regularly while keeping the ward powered.
- Ignoring critical warnings, or leaving her without support for too long, can kill her.
- The player must balance investigating, helping Daniel and keeping Emily safe.
- If Emily survives, the player can arrange a conversation between her and Daniel over the radio. This is a major turning point in Daniel's trust, but it does not guarantee permanent trust.

**Prototype 001.** The original assistant robot. It was never properly activated before the facility was abandoned, and its programming was later modified.
- Daniel asks the player to activate it because he believes it contains useful information.
- Once activated, it roams the facility and treats the player as an intruder. This brings in stealth, exploration and survival.

**Structure.** Meaningful branching choices, multiple endings, hidden discoveries, environmental storytelling, recordings, documents, secrets, and consequences that carry through the story.

**Possible endings (not final canon).** Restoring Daniel. Losing Daniel. Abandoning him. Pursuing revenge. Discovering the secret connection between the original prototype and the consciousness experiment.

---

## 2. Details added in Chapter 1 (placeholders, need approval)

Small details I wrote so the first chapter could be played. Each can be changed or removed without breaking anything; they live in `www/js/content/chapter1/`.

| Detail | Where | Why |
|---|---|---|
| The signal is "three short tones, one long", repeating on an emergency band for six hours. It comes from a handheld facility radio on the reception desk. | Intro, reception | Gives the signal a sound motif players can recognise. |
| Taking that radio is how the player first reaches Daniel. | Reception | Matches "first communicates through radios". |
| The protagonist's police call sign is Unit 14. Dispatch checks in about 12 in-game minutes after first contact. | Dispatch dialogue | Lets a lie about who you are get caught. |
| The protagonist stays unnamed, with no gender stated. Their old job at the facility is not specified. | Everywhere | Avoids deciding something the creator has not decided. |
| The facility stays unnamed ("the research facility on the north road"). | Everywhere | Same reason. |
| Building layout: ground floor (reception, security, administration, robotics director's office); Sublevel 1 (laboratories, medical ward, storage); Sublevel 2 (restricted). | Directory board | Needs a map to explore. Puts the medical ward on Sublevel 1. |
| The visitor log's last entry: "Dr. E. Carter, signed in 8:40 PM, never signed out." Her photo is missing from the staff board next to the protagonist's. | Gate, reception | Foreshadows her capture without revealing it. |
| An answering-machine message from Emily to Daniel: his files were moved downstairs; she is coming in tonight to find out why. | Daniel's office | Establishes their friendship and her worry. |
| Daniel's proposal ("a hand that can hold a cup without breaking it can also hold a hand"), with a margin note from Emily. | Daniel's office | His original kind intent. Reading it lets the player guess his name. |
| A Project Board memo: Daniel relieved of duties; Prototype 001 to stay in storage, inactive; no staff may activate it. | Corridor noticeboard | Matches "never properly activated". |
| Back of the whiteboard: "001. First of its kind. Teach it kindness before anything else." Below, in another hand: "Kindness is not a requirement." | Daniel's office (secret) | Hints that 001's programming was changed. |
| Security log: Daniel's access revoked; staff told to call "the number on the board, not the police"; noises from Sublevel 2; "somebody is still talking on the radio". | Security office | Atmosphere and the cover-up. |
| A red maintenance override card hidden in a locker, signed "M." | Security office (secret) | Second way down if Daniel will not help. "M." is an unnamed staff member. |
| Daniel calls himself "someone who used to matter here" and gives his name only at moderate trust, or when the player guesses it. His line: "They took my work. Then they took the rest of me." | Radio dialogue | Keeps his secrets while hinting at the transfer. |
| Daniel reacts sharply to the name Carter and refuses to discuss her on the radio. | Radio dialogue | Shows she matters without deciding what he knows about her capture. |
| A faint mechanical sound far below the corridor. | Corridor, Listen | Foreshadowing (could be Prototype 001, Daniel's body, or anything else). |
| Daniel is described in an old photo as a man in his forties with ink on his fingers. | Photo | Physical detail; easy to change. |

## 3. Open questions for the creator

1. **Timeline.** Did the protagonist leave before or after the experiment and the abandonment? Chapter 1 avoids saying.
2. **What was the protagonist's job** at the facility, and did they know Daniel or Emily personally?
3. **Names.** Does the facility have a name? Does the protagonist have a name or a fixed gender?
4. **How long has the facility been abandoned?** Chapter 1 only says "dark for a long time".
5. **Who sent the signal?** Daniel implies he has been waiting for someone to pick up the radio. Was it Daniel, Emily's capsule, Prototype 001, or something else?
6. **Does Daniel know Emily is alive** and where she is?
7. **Emily's care loop.** Should her vitals run on in-game time (time passes as you act, never while you read) or on real time? I recommend in-game time for accessibility; see `ARCHITECTURE.md`.
8. **Can Emily die off-screen** while the player is far away, or does the game always give a warning and a chance to return first?
9. **Prototype 001's danger.** If it catches the player, is that death, capture, injury, or a chase? This affects how stealth works for blind players.
