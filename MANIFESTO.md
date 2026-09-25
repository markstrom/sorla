# The Sorla Manifesto

**Speech becomes text. Nothing more.**

This manifesto is the yardstick for every decision about Sorla. A feature, a setting, a screen or a line of copy that doesn't serve these principles doesn't belong in Sorla — however useful it would be somewhere else.

---

## The principles

### 1. One purpose
Sorla turns speech into text where the user is already working. Every feature must improve that flow or make it more reliable. Features that create a different use case don't belong in Sorla.

### 2. Local processing
Audio and transcription are processed on the device and never sent anywhere. Sorla must not require an account or collect user behaviour. The network may be used for the first model download and for updates the user has explicitly requested or enabled. After that, dictation must work without the internet.

### 3. Fast to usable text
Minimise the time from activation to correctly pasted text. Judge speed and accuracy together: a faster transcription is no improvement if it creates more correction work. Launch, dictation and pasting must stay within their performance budgets.

### 4. Calm, with clear feedback
Sorla must not steal focus or demand attention outside the dictation flow. The user must be able to tell when the app is listening, processing and done. Errors that block or put the result at risk must be visible and recoverable. Discretion must not become ambiguity.

A narrow exception: when an explicit attempt to use the core function — a dictation or a paste — is blocked by a known problem that needs a concrete action from the user, Sorla may open an in-app recovery window that explains the problem and offers that action. It opens only after the attempt (for push-to-talk, on release), one at a time, never over a recording, and not again for the same problem in the same run once the user has said "Not now". The welcome window at launch remains allowed. Ordinary success, update offers, silence, empty recognition, a single failed transcription and the deliberate clipboard fallback after switching apps do not qualify. Sorla never uses macOS notifications or asks for notification permission.

### 5. Defaults before settings
Solve problems with well-considered default behaviour before introducing new choices. A setting should exist when real user needs call for different behaviours that can't be reconciled in one good default. Don't expose technical decisions the product can make itself.

### 6. The user's words
Sorla transcribes; it does not edit. Punctuation and capitalisation may make speech readable, but features must not change the user's meaning, tone or choice of words. Rewriting, summarising, translating and added content are outside its job.

### 7. Preserve the work and enable recovery
Preserve the clipboard and focus. Existing text may only be replaced as the user intends, for example through an active selection. If pasting fails, the latest transcription must be reusable without dictating again through Paste Last Transcription, unless the user has turned off keeping it or Sorla must restart. Limit storage and recovery to what the current flow needs.

### 8. Depth before breadth
Prioritise accuracy, reliability and accessibility over more features, models and languages. An addition must solve a demonstrated problem, not just widen the offering. The benefit doesn't have to reach the majority: making the core function accessible to a smaller group can weigh heavily.

### 9. Small, native, honest
Use the platform's own tools and established behaviours. Keep resource use, dependencies and background work to what the task requires. Make limitations and technical dependencies clear. Separate measured results from ambitions, and document significant trade-offs.

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
