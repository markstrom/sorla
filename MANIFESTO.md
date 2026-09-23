# The Sorla Manifesto

**Hold a key. Speak. Let go. Your words appear.**

That is the whole product. Everything in Sorla exists to make that moment faster, more accurate, more private, or more invisible. Anything else belongs somewhere else.

---

## What Sorla is

### Sorla does one thing
Sorla puts your spoken words where your cursor is. Sorla is not a note-taking app, a meeting recorder, a file transcriber, an AI assistant or a writing coach.

### Sorla never sends your voice anywhere
Your voice never leaves your Mac. Sorla has no account, no cloud, no analytics and no telemetry. Out of the box Sorla goes online exactly once: to download the speech model it needs. After that it is silent. Sorla checks for a newer model only when you press *Check Now*, or automatically if you turn that on.

### Sorla is fast enough to disappear
The text is there before you think about waiting for it. Sorla starts instantly and uses no CPU while idle.

### Sorla only shows up while you speak
A menu bar icon, a small indicator while you speak, a soft sound when it starts and stops. Sorla never steals focus and never interrupts.

### Sorla works right out of the box
Install, grant two permissions, hold Right ⌘. The defaults are the product; every setting is optional.

### Sorla runs the best model for your language
Sorla ships the most accurate on-device model available for the language it serves, and keeps it up to date. One excellent model beats a menu of mediocre ones.

### Sorla leaves your words alone
Sorla writes what you said. It never rewrites, summarizes, "improves" or reformats your words, and it puts your clipboard back the way it found it.

### Sorla is native and light
Sorla is built for the Mac with the Mac's own tools: small, few dependencies, no background services, no helper apps.

### Sorla credits what it stands on
Every model and library Sorla uses is credited, with its license, where users can see it.

---

## What Sorla never does

- AI rewriting, "modes", prompts or tone adjustment
- Per-app profiles or context awareness
- Transcription history or a library of recordings
- Transcribing audio or video files
- Meetings, speaker detection or summaries
- Cloud models, accounts, subscriptions or sync
- Voice commands, plugins or scripting
- Analytics of any kind

Every one of these exists in other apps, and every one of them makes those apps harder to understand.

---

## The feature test

Before anything is added to Sorla, it must pass all six questions. One "no" means it is not built — or something smaller that passes is built instead.

1. **Core loop** — Does it make *hold, speak, let go* better for most people who use Sorla?
2. **No new knob** — Can it work without a new setting? If it needs one, does a real person need a different default for a real reason?
3. **Stays on the Mac** — Does every word stay on the device?
4. **Stays fast and quiet** — Do dictation latency, launch time and idle CPU stay where they are?
5. **One sentence** — Can a new user understand it from one sentence?
6. **Worth keeping** — If it were removed in a year, would people miss it?

---

## Budgets

| | Limit |
|---|---|
| Release-to-text for a 10-second dictation | under 0.5 s |
| CPU while idle | 0 % |
| Settings | at most 10 |
| Items in the menu | at most 8 |
| Network traffic | the first model download; after that only when the user asks (or opts in to automatic update checks) |
| Steps from install to first dictation | install, two permissions, speak |

A change that would break a budget waits until it doesn't.
