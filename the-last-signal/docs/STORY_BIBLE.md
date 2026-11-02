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

## 2b. Details added in Chapter 2: Preservation (placeholders, need approval)

| Detail | Where | Why |
|---|---|---|
| Sublevel 1 has an elevator landing, laboratory corridor, transfer suite, preservation lab, medical ward and storage. The elevator only goes down for now. | Map | Needs a map to explore. |
| Daniel's speakers do not reach the preservation lab ("they made sure of that"). He sends the player for the records there, not knowing what else is inside. | Arrival dialogue | Lets the player discover Emily first and decide what to tell him. |
| Emily is in Capsule 3, preserved for "interference" and "attempted access to sealed Sublevel 2 records". Revival is not authorized. | Preservation log | Matches the brief: captured and preserved so she could not interfere. |
| **The big choice:** tell Daniel she is alive, or lie. A lie is exposed if he hears her loud monitor alarms on the facility radio channel, or if the player sends him the records. | Daniel dialogue | Honesty with consequences, as in the brief. |
| Daniel's reaction to the news never says whether he knew she had been captured. His only line about her: "She was the only one who argued for me." | Dialogue | Leaves open question 6 open. |
| The transfer suite: a restraint chair with "I DID NOT AGREE" scratched into the armrest, and a recording of the transfer ("Board resolution fourteen... Consent is not required." "He's asking for Emily." "The body doesn't matter now.") | Transfer suite | Shows the non-consensual transfer from the brief; hints the body still exists somewhere. |
| An empty case labelled "TRANSFER. SECONDARY." with the destination scratched out. | Transfer suite (secret) | A hint toward the prototype/experiment connection, deliberately vague. |
| A smashed glass wall, broken outward from inside a lab. | Corridor | Unexplained on purpose. |
| A revival protocol: Emily can only be woken with authorization codes from Sublevel 2, and "familiar voices help". | Medical ward (secret) | Sets up a path to the Emily and Daniel radio conversation. |
| Prototype 001 stands under a tarp in storage, crate stencilled "DO NOT ACTIVATE. BOARD ORDER." Daniel asks the player to wake it because "it remembers things I don't. Things they took out of me." The player can agree or refuse for now. | Storage, chapter end | The brief's activation request. 001 is not activated yet; that is Chapter 3. |

### How Emily's care works (my defaults for open questions 7 and 8)

- Her power and condition change with **in-game time only** (time passes when you act, never while you read).
- Power cells (three in Chapter 2) top up her power. Checking on her in the ward restores her condition.
- Warnings always come before anything permanent: a quiet chirp at 50 percent, then loud radio alarms at 25 and 10 percent, then a final alarm. She can die while you are elsewhere, but only after all of those.
- If she dies, the story continues, and it is remembered.

## 2c. Chapter 3: Awakening

### Decisions made (the creator said: you choose)

- **Who sent the signal: Daniel.** "Three short, one long" was Prototype 001's heartbeat, the first sound it made the night its core was switched on (Emily cried). He used it because it was "the only voice I had left that was still mine." Revealed when 001 wakes and makes the sound.
- **Did Daniel know Emily was captured: no.** The board told him she resigned because she did not want to see what he had become. He believed them, and blames himself for that.
- **What happens if 001 catches you:** the first time it hurts you and walks on. Caught again while still hurt, you die and restart from the last checkpoint. The medical ward can patch you up.

### Details added (placeholders)

| Detail | Why |
|---|---|
| Sublevel 2 holds the revival codes, the board's records, "and what's left of me". | Sets up finding Daniel's body there, as in the brief. |
| The only way down is a freight lift in storage that answers only to a key kept inside 001 ("they built it to carry their equipment"). | Gives a reason to wake 001. |
| 001 wakes gentle ("Hello. I am here to help."), then corrects itself: "Intruder detected." | Shows the modified programming from the brief. |
| 001 patrols Sublevel 1 on a fixed route and recharges in storage, when it cannot see you. | Stealth that can be played entirely by ear. |
| Telling 001 "Daniel built you to be kind" makes it hesitate once: "Kindness is not a requirement." | Pays off the whiteboard secret from Chapter 1. |
| 001 stops and stands over Emily's bed on its rounds. | Unexplained on purpose; feeds the prototype mystery. |
| The key's tag says 001's original behavioural layer is archived on Sublevel 2. | A possible way to restore 001 later. |

## 2d. Chapter 4: Remains (placeholders, need approval)

| Detail | Why |
|---|---|
| Sublevel 2 never lost power: freight lift bay, main hall, records, monitoring, containment. | The board's real work lived here. |
| **Daniel's biological body** lies in containment, kept breathing by machines. No neural activity since the transfer. The chart's board note: "leverage". The latest entry, in different handwriting: "still here". | The brief: the player discovers his original body. "Still here" is deliberately unexplained. |
| An empty frame labelled TRANSFER RECIPIENT, RELOCATED. Board minutes: location restricted to Board members. Daniel: "The rest of me is somewhere else. Don't ask me where. Not yet." | Keeps the robotic body's location a mystery, as the brief requires. |
| Board minutes confirm Emily was told Daniel "had taken leave", and preservation was approved if she persisted. | Fits both sides of the lie told to Daniel and Emily. |
| The player can tell Daniel his body is breathing, or lie that it is gone (a lie that can matter later). | Honesty choice with weight. |
| **Emily's care away from the ward:** if Daniel trusts you (20+) and knows about Emily, he offers to watch her through the ward systems (her decline slows a lot). A medical link in monitoring can wire the ward to Sublevel 2's power (power stops draining) and run a partial check (up to 70 percent). After three full checks, her decline slows anyway. | Answers the creator's question about caring for her from far away. |
| **Emily wakes** when the revival codes are entered in the ward. She is too weak to walk. | Ends the care loop and starts her as a character. |
| **The turning point:** Emily and Daniel talk over the radio. He apologises for believing she left; she asks where he is; he will not say, "not even you". Trust +15. Any hidden lie about Emily is exposed during the call. | The brief's major turning point. It does not guarantee lasting trust. |
| 001's original behavioural layer, the one Daniel wrote, is in a humming archive box (found by listening). | A way to restore 001 in a later chapter. |

## 2e. Chapter 5: Relocated (placeholders, need approval)

| Detail | Why |
|---|---|
| Daniel's robotic body was moved to **Isolation**, a sealed room in the east stairwell between the surface and Sublevel 1, behind the chained door from Chapter 1. Restraints on, network limited to facility audio. | The brief: Daniel was isolated somewhere inside the facility. Explains why he can only talk through radios and speakers. |
| The isolation door opens to a rhythm code: three short, one long, his own heartbeat. "Somebody on the Board thought that was funny." | Pays off the signal. |
| Fresh footprints and a padlock dated within the last month: someone from the board still visits. | Sets up Chapter 6 and the "still here" note. |
| Emily knows the way and an elevator maintenance trick. If Emily is dead, the board's isolation order in the records room gives the same information. | Both routes reach the same place. |
| **The romance, kept quiet:** eleven years of building things together; he brought two coffees every morning and pretended one was a mistake; she meant to tell him something the night she was taken, and never did. She sends him her lanyard and asks you not to repeat what she said. | Creator's request for a romantic thread, kept understated so it does not undercut the horror. |
| Daniel tries to stop you at the stairwell. You can be honest, lie, or say Emily sent you. | Honesty choice. |
| The robotic body: tall, steel and grey composite, a face built to look gentle, amber eyes like 001's original ones. First words in person: "You came anyway." | The first face-to-face meeting. |

## 2f. Chapter 6: The Board, and Chapter 7: The Last Signal (decided by Claude at the creator's request; change freely)

- **Marcus Hale**, former secretary to the Project Board, is "M." from the Chapter 1 override note. He signed Resolution 14, hid the override card, keeps Daniel's body breathing, and writes "still here" on the chart. He carries the remote for Daniel's clamps, with a red button that switches Daniel off for good, and he never could press it. The rest of the board scattered.
- **The secret connection** (the brief's possible ending): the secondary transfer put a full copy of Daniel's mind into 001's core, as a backup. The board rewrote 001 so it would never know. That is why 001 stood over Emily's bed. Restoring 001's original core makes it remember: "Two cups. One was always a mistake."
- **Daniel's "incident":** on waking in the robot body he reached for a board member. He did not hurt him. That was enough to have him clamped in isolation with audio access only.
- **Marcus's fate:** arrest him, hear him out and make him help (then arrest him), or let Daniel decide, which leads to the revenge path (a capsule, as was done to Emily).
- **Emily's lanyard:** give it to Daniel. If Emily confided in you, you can keep her secret for her to tell. You can also invent a message she never said, which closes the romantic ending.

### The six endings of Part One

| Ending | How to reach it |
|---|---|
| **Two Coffees** (romantic) | Bring Daniel home with Emily awake and alive, her lanyard given without inventing her words, and trust 50 or more. |
| **Home** (restored) | Bring Daniel home. Needs Emily awake or Marcus helping, 001's copy reachable (001 restored or the copy known about), and trust 30 or more. |
| **Silence** (lost) | Try to bring him home with low trust (he switches himself off), or press the red button. |
| **Code Four** (abandon) | Walk away. Always possible. |
| **Names** (revenge) | Open his clamps with Marcus's remote and let him hunt the board. |
| **The First of Its Kind** (secret connection) | With 001 restored and the copy known, Daniel goes into the body he designed to be kind. |

Most endings close on the signal returning ("three short tones, one long") as a hook for Part Two.

## Plan for the rest of the story (agreed with the creator)

- **Part One** ends at Chapter 7 with all the endings from the brief, plus a **romantic ending** (Daniel restored to his body, walking out with Emily), unlocked only by keeping Emily alive, being honest, and finding the right secrets. Other routes are bittersweet or tragic.
- **Chapter 6: The Board.** Who writes "still here"; facing the people who did this (the revenge path); restoring 001 with Daniel's original core.
- **Chapter 7: The Last Signal.** The finale and the endings.
- **Part Two is a sequel inside the same app,** offered as "Continue to Part Two" after the finale, carrying every choice over. One app means one set of updates and bug fixes.

## Part Two (creator's idea: a trial; details decided by Claude at the creator's request)

The creator's idea: after Part One, the protagonist is put on trial, framed by someone from the organization, and believes their life is over until something turns it around. Part Two continues from whichever Part One ending the player reached, inside the same game.

**Plan:** 1 Summons (the arrest), 2 Investigation, 3 The trial, 4 Who really framed you, 5 The verdict and new endings.

### Part Two, Chapter 1: Summons (built)

| Detail | Why |
|---|---|
| Months later. The opening depends on the Part One ending: **Two Coffees**, dinner where Emily and Daniel finally say "I love you" (creator's request); **Home**, Daniel calls, he walked to the end of the street; **First of Its Kind**, Daniel in 001's body cooks you soup; **Names**, alone, the news; **Silence / Code Four**, alone, the old radio clicks on by itself. | One sequel, six ways in. |
| **Dr. Alan Pryce**, a former board member, is found dead. At the scene: a police radio looping the signal, a note with your badge number, a torn page of the facility visitor log with your name. Your own radio, handed into evidence after the facility call, is missing from the evidence room. | The frame-up. |
| **Detective Ruiz** (your former partner) arrests you. You can ask for a lawyer, tell her everything, or deny ever being at the facility (a lie, caught at once by the dispatch log). | Choices that will matter at the trial. |
| **The anonymous tip** naming you came in at 3:02 AM, hours before the body was found, and the caller played the signal down the phone. | The first crack in the frame. |
| **One phone call:** Emily, Daniel, 001-Daniel, the number Daniel left (revenge ending: "It wasn't me."), or the public defender, **Okafor**. | Who can help you depends on Part One. |
| **The voice in the vent:** "You opened the door. You should have left it closed. Every answer you give, I already have a copy of." | Whoever framed you is close, and knows the signal. |

### Part Two, Chapter 2: Witnesses (built)

| Detail | Why |
|---|---|
| **Sarah Quinn** (creator's idea): ran the facility's audio and radio systems, so every channel Daniel used went through her boxes. She sat two desks from you for a year and had a quiet crush on you; you never noticed her. Emily and Daniel knew her (and knew about the crush). She has watched the facility network since that night, and you. | Creator's request: a new character who knew you when you didn't know her. |
| Sarah knows who you are: you left the last coffee for the night shift, walked Ana to her car when it rained, and were **the only one who quit** when the board took Daniel off his project. | Creator's request: people who knew you defend you. Settles the open question of why the protagonist left. |
| At first Sarah looks suspicious (she knows the signal and the network). You can say so. Emily vouches for her, and laughs that you thanked the wrong person for Sarah's birthday card. | A red herring, then an ally. The "cooked" moment. |
| Sarah's slow romance is optional: "I'm noticing now" or "Thank you, for all of it". | Kept slow, as agreed. |
| **Witnesses** you can win over: Emily, Daniel (human endings), Marcus (if arrested), and the old night shift at the diner: Ana (accounts), Theo (the night guard who wrote "somebody is still talking on the radio"), Priya (labs, terrified; demanding she owes you drives her away). Two at least before Okafor will go on. | The people who knew you, standing up for you. |
| Your lawyer is **Nadia Okafor**. Bail is paid by Emily or Daniel if you called them. Detective Ruiz's initial is now A. | Avoids confusion with Sarah. |
| Pryce was about to testify against the board. The 3 AM tip came through the facility's old phone exchange: **someone is still inside the facility network**, and they just sent the signal **from the courthouse**. | Sets up the trial. |

### Part Two, Chapter 3: The Trial (built)

| Detail | Why |
|---|---|
| **Judge Amara Bell.** **Prosecutor Grant Holloway**, calm and silver-haired. | The courtroom cast. |
| The jury's leaning is a hidden counter. Good cross-examination, honest answers, and the witnesses you recruited raise it; lies (the caught lie to Ruiz comes back) and the prosecution's witness lower it. | Every earlier choice counts in court. |
| Cross-examining **Ruiz**: the tip came eight hours before the body was found; your radio vanished from the police evidence room; you did not resist arrest; she never had a reason to doubt you. | Uses what you learned in Chapter 1. |
| **Victor Lane**, the prosecution's surprise eyewitness, is the board's old private security, the man behind "the number on the board". Only Theo can expose him. | Pays off Chapter 1's security log and recruiting Theo. |
| At recess Sarah traces the courthouse signal to the **courthouse evidence room**. | The frame came from inside. |
| Your witnesses testify in their own voices. You choose whether to take the stand and how to close. | Agency in the courtroom. |
| The jury retires. The lights go out. Over the speakers: "Guilty or not, it doesn't matter. I kept a copy of everything. Including him." | The cliffhanger: "him" is Daniel, a copy of his mind. The verdict comes next chapter. |

## 3. Open questions for the creator

1. **Timeline.** Did the protagonist leave before or after the experiment and the abandonment? Chapter 1 avoids saying.
2. ~~Answered in 2c.~~ **What was the protagonist's job** at the facility, and did they know Daniel or Emily personally?
3. **Names.** Does the facility have a name? Does the protagonist have a name or a fixed gender?
4. **How long has the facility been abandoned?** Chapter 1 only says "dark for a long time".
5. **Who sent the signal?** Daniel implies he has been waiting for someone to pick up the radio. Was it Daniel, Emily's capsule, Prototype 001, or something else?
6. **Does Daniel know Emily is alive** and where she is?
7. **Emily's care loop.** Built with in-game time and staged warnings (see above). Change it if you want it harder or easier.
8. **Emily's death.** Built so she can die while you are elsewhere, but only after several warnings. Is that right?
10. **Who smashed the glass wall** on Sublevel 1, and what was in the empty transfer case?
11. **Where is Daniel's robotic body,** in relation to the facility? Chapter 2 only says he cannot reach storage.
9. **Prototype 001's danger.** If it catches the player, is that death, capture, injury, or a chase? This affects how stealth works for blind players.
