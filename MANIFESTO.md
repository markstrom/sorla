# The Sorla Manifesto

**Speech becomes text. Nothing more.**

This manifesto is the yardstick for every decision about Sorla. A feature, a setting, a screen or a line of copy that doesn't serve these principles doesn't belong in Sorla — however useful it would be somewhere else.

---

## The principles

### 1. One purpose
Sorla exists to turn speech into text where the user is already working. Every part of it serves that purpose, or it goes.

### 2. Nothing leaves the Mac
Voice, text and behaviour stay on the device. Sorla never needs an account, a server or permission to phone home. The network is used only for what the user explicitly needs or asks for.

### 3. Never make the user wait
Speed is the feature. Dictation must feel instant, starting must feel instant, and nothing may slow down the moment between speaking and seeing the words.

### 4. Calm by default
Sorla appears when it is used and disappears when it isn't. It never takes focus, never interrupts, never asks for attention it doesn't need.

### 5. Defaults over settings
Sorla must be complete without anyone opening Settings. A setting is a decision the product failed to make; each one must exist because real people genuinely need different answers.

### 6. The user's words, untouched
Sorla writes what was said. It does not interpret, rewrite, summarise or improve.

### 7. Leave everything as it was found
The user's clipboard, focus, files and habits are theirs. Sorla borrows only what it needs, for as short a time as possible, and puts it back.

### 8. Depth over breadth
One excellent solution beats several average ones — for models, for options, for languages. Sorla gets better by being better, not by growing.

### 9. Small, native, honest
Sorla is built with the platform's own tools, stays small, runs nothing in the background it doesn't need, and is open about what it does and what it builds on.

---

## Out of scope, by principle

- Anything that changes the user's words — rewriting, summaries, tone, "AI modes" *(principle 6)*
- Anything that needs an account, a server, sync or tracking *(principle 2)*
- Anything that works on recordings after the fact — files, meetings, history *(principle 1)*
- Anything that watches what the user is doing to adapt itself *(principles 2 and 4)*
- Anything the user must learn or remember to use Sorla well — modes, commands, profiles *(principles 4 and 5)*

---

## The feature test

A proposal must pass all six. One "no" means it is not built — or something smaller that passes is built instead.

1. **Purpose** — Does it make *speech to text, where you are* better for most people who use Sorla?
2. **Default** — Can it work without a new setting? If not, do real people truly need different answers?
3. **Privacy** — Does every word and every behaviour stay on the Mac?
4. **Speed and calm** — Do dictation, start-up and idle cost stay the same, and does Sorla stay as quiet?
5. **Clarity** — Can a new user understand it from one sentence?
6. **Value** — If it were removed a year later, would people miss it?

---

## Budgets

Principles become measurable here. A change that breaks a budget waits until it doesn't.

| | Limit |
|---|---|
| From letting go to seeing the text (10 s of speech) | under 0.5 s |
| CPU while not in use | 0 % |
| Settings | at most 10 |
| Menu items | at most 8 |
| Network use | the first model download; after that only when the user asks or opts in |
| Steps from install to first dictation | install, grant permissions, speak |
