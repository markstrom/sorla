# The Prata Manifesto

**Hold a key. Speak. Let go. Your words appear.**

That is the whole product. Everything in Prata exists to make that moment faster, more accurate, more private, or more invisible. Anything that doesn't belong somewhere else.

---

## What we believe

### 1. One job, done perfectly
Prata puts your spoken words where your cursor is. It is not a note-taking app, a meeting recorder, a file transcriber, an AI assistant or a writing coach. Other apps do many things; Prata does one thing better than any of them.

### 2. Private by construction
Your voice never leaves your Mac. No account, no cloud, no analytics, no telemetry. The only network traffic Prata ever makes is fetching the speech model and checking for a newer one — and you can switch that off. Privacy is not a setting; it is how the app is built.

### 3. Fast enough to disappear
The text is there before you think about waiting for it. Prata starts instantly, uses no CPU while idle, and never makes you choose between speed and quality.

### 4. Invisible until needed
A menu bar icon, a small island while you speak, a soft sound when it starts and stops. Prata never steals focus, never interrupts, never asks for attention it doesn't need.

### 5. Right out of the box
Install, grant two permissions, hold Right ⌘. The defaults are the product. Every setting is optional, and the app is complete without touching any of them.

### 6. The best model for your language, not the most models
We ship the most accurate on-device model we can find for the language we serve, and we keep it up to date. Quality beats choice.

### 7. Your words, untouched
Prata writes what you said. It does not rewrite, summarize, "improve" or reformat your words, and it puts your clipboard back the way it found it.

### 8. Native and light
Built for the Mac with the Mac's own tools. Small, few dependencies, no background services, no helper apps.

### 9. Honest about where things come from
Every model and library Prata stands on is credited, with its license, where users can see it.

---

## What Prata will not do

- AI rewriting, "modes", prompts or tone adjustment
- Per-app profiles or context awareness
- Transcription history or a library of recordings
- Transcribing audio or video files
- Meetings, speaker detection or summaries
- Cloud models, accounts, subscriptions or sync
- Voice commands, plugins or scripting
- Analytics of any kind

Saying no to these is a feature. Every one of them exists in other apps, and every one of them makes those apps harder to understand.

---

## The feature test

Before anything is added, it must pass all six questions. One "no" means we don't build it — or we build something smaller that passes.

1. **Core loop** — Does it make *hold, speak, let go* better for most people who use Prata?
2. **No new knob** — Can it work without a new setting? If it needs one, does a real person need a different default for a real reason?
3. **Stays on the Mac** — Does it keep every word on the device?
4. **Stays fast and quiet** — Does it keep dictation latency, launch time and idle CPU where they are?
5. **One sentence** — Can a new user understand it from one sentence?
6. **Worth keeping** — If we had to remove it in a year, would people miss it?

---

## Budgets we keep

| | Limit |
|---|---|
| Release-to-text for a 10-second dictation | under 0.5 s |
| CPU while idle | 0 % |
| Settings | at most 10 |
| Items in the menu | at most 8 |
| Network traffic | model download and update check only |
| Steps from install to first dictation | install, two permissions, speak |

If a change would break a budget, it waits until it doesn't.
