---
name: craft-clear-names
description: How to name any feature, label, button, tab, or menu item in EusoTrip — Apple's WWDC26 "Craft clear names" framework fused with the house copy doctrine. Use before shipping ANY new user-facing string that names a thing.
---

# Craft clear names for features & labels

Source: Apple WWDC26 Session 290 — *"Craft clear names for features and labels in your app."* This is a **naming discipline**, not an API. Run it whenever you name a feature, tab, button, section header, menu item, toggle, or empty-state — on web OR iOS OR watch. It is the naming half of the house [user-facing-copy doctrine]; obey both.

## The bar: a good name is judged on three criteria

1. **Belongs** — it fits the app at every level: matches user expectations, sits coherently beside every *other* name already in the product, and matches the tone of where it lives. A name that's great in isolation but clashes with its neighbors fails.
2. **Sets the right expectation** — the user predicts what they'll find, and the thing delivers exactly that. Predictability *is* trust. A name that overpromises or misdirects is a bug.
3. **Works everywhere** — localizes cleanly (EN/ES for MX lanes, FR for CA), holds up across truck/rail/vessel verticals, and reads the same on a 44mm watch face, a push banner, and a web sidebar.

Not every name must hit all three — **let context decide which dominate.** Financial/compliance surfaces (Wallet, settlements, HOS, hazmat) weight **clarity + trust** hard. Brand/experience surfaces (The Haul, ESANG, missions) may weight **belonging + emotion**. Never sacrifice clarity on a money or safety label to sound clever.

## The process: Think · Feel · Do

1. **Name the audience first.** Which of the 24 roles, in which vertical, at which lifecycle moment? "The escort at a state-line LEO handoff" is a different namer than "the shipper posting a reefer load."
2. **Brainstorm in three buckets** (no filtering yet):
   - **Think** — what should they *think* when they see it? (fast, safe, in-control, official)
   - **Feel** — what should they *feel*? (confident, delighted, protected)
   - **Do** — what should they *do*? (find it, file it, dispatch it, share it)
3. **Group by theme.** Collapse the words into the 2–4 concepts that keep recurring. Those themes are your candidates' backbone.
4. **The natural-language test.** Say the candidate in a sentence a real user would speak: *"File ISF now,"* *"check your Balance,"* *"tap Enhance Dialogue."* If it's awkward out loud, it's wrong on screen.
5. **Score against the three criteria**, weighted for the surface's context. Ship the winner; let it set the pattern for its neighbors.

## Rules that fall out of this (enforce on sight)

- **Name for the user's experience, not the technology.** "Enhance Dialogue" > "Isolate Vocals." "Visited Places" > "Location Cluster Log." → In EusoTrip: never surface the engine. **HERE never appears in user copy** (it's "The Haul / EusoTrip Network"); the AI is **"ESANG AI"** never "Living Codex"; a geofence dwell is "Arrived," not "region-enter event."
- **Use a verb when the user controls the feature.** Verbs put the person in agency: "Enhance Dialogue," "File ISF," "Promote to Booking," "Assign Terminal." Nouns for states they observe: "Balance," "Cutoffs," "Custody."
- **Watch the tone — names can pass judgment.** "Spending Power" sounds like a credit score and quietly judges; "Balance" is neutral and industry-standard. On a driver's earnings or a carrier's score, a smug or scolding label erodes trust.
- **Invent only from clear parts.** "AutoMix" works because Auto+Mix decodes on sight. A coined EusoTrip term must be self-decoding (EusoTicket, EusoWallet pass) — never an opaque codeword.
- **Names accumulate.** Every good name makes the next easier and builds the product's shared vocabulary. Keep the family coherent: if the shipper flow says "Loads," the driver flow doesn't say "Jobs" for the same object. Reuse the established word.
- **No dev-copy, ever.** Enum values, table names, internal flags, and status codes are not names. ("pending_ingate" → "Awaiting gate-in.") This is the hard gate from the copy doctrine.

## Worked reference (Apple's examples, for calibration)

| Feature | Winner | Why the losers lost |
|---|---|---|
| Apple Cash balance | **Balance** | "Spending Power" (vague, judgmental), "Current Funds" (stiff, unspoken) |
| Maps history | **Visited Places** | fits the "places" family, sets ownership, translates |
| Photos grouping | **Memories** | meets users emotionally, not as an algorithm |
| Podcasts audio | **Enhance Dialogue** | "Isolate Vocals" (tech), "Clarify Speech" (incomplete), "Enhance Playback" (generic) |
| Music transitions | **AutoMix** | coined but self-decoding from clear parts |

## When to run this

Before merging any PR that introduces a new named surface — a tab, a CTA, a section header, a toggle, a menu item, an empty-state, a push title. If you added a string that *names a thing*, run Think·Feel·Do and the natural-language test, check it against the three criteria weighted for its context, and confirm it doesn't leak the engine or dev-copy. Cross-reference the house copy doctrine before shipping.
