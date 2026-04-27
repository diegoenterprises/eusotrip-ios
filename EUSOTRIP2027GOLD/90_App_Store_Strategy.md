# 90 · App Store Strategy — Single Binary for All Roles

**What this covers.** The EusoTrip App Store strategy — one binary, every role; listing metadata (title, subtitle, promotional, keywords, category); screenshot carousel by role; App Preview video; Apple Watch companion bundle-inside-iOS; review gotchas (WKBackgroundModes audio is iOS-only, watchOS permission strings, Sign in with Apple exemption, encryption export); Privacy Manifest; App Tracking Transparency (not applicable); push entitlement; HealthKit fatigue justification; subscription model (drivers free, broker/fleet paid); carrier-specific apps (NOT building); TestFlight distribution; phased release; release notes + reviewer notes templates; rejection playbook; cross-country listings (en-US/en-CA/fr-CA/es-MX); iPad/Catalyst/Vision Pro (not in scope 1.0); version history strategy; user access; revenue + analytics; launch latency budget; single-app onboarding; dynamic navigation; feature flags + dark launches. Source: wave-1 shard `team_APPSTORE_strategy`.

**When you need this.** Before submission. Before a review rejection. Before a new role launches. When deciding iPad vs iPhone scope. When adding IAP.

**Cross-links.** Launch runbook + phased release: [92_Launch_Runbook_and_Rollback.md](./92_Launch_Runbook_and_Rollback.md). Apple frameworks: [06_Third_Party_Integrations.md §4](./06_Third_Party_Integrations.md). Security manifest: [05_Auth_Security_Compliance.md §11](./05_Auth_Security_Compliance.md).

---

## 1. Single-binary doctrine — one app, every role

EusoTrip ships as exactly **one** iOS application binary. Not one per role. Not one per vertical. Not one per mode. **One.**

Named "EusoTrip" on Home Screen, Spotlight, App Switcher, App Store. When a driver, dispatcher, ocean captain, rail yardmaster, customs broker, and shipper all download EusoTrip, they download the exact same `.ipa` — byte-for-byte identical. What differentiates their experience is not the binary; it is the **role + mode + vertical triple** resolved at sign-in against backend identity service.

**The math of what this single binary must support:**
- **24 roles** — Driver (OTR), Driver (Regional), Driver (Local), Owner-Operator, Dispatcher, Fleet Manager, Safety Officer, Compliance Officer, Broker, Shipper, Receiver, Carrier Admin, Customs Broker, Ocean Captain, First Officer, Ocean Crew, Port Agent, Rail Engineer, Yardmaster, Conductor, Warehouse Manager, Dock Worker, Accountant, Executive.
- **3 modes** — Operator (doing work), Supervisor (managing others), Observer (read-only / stakeholder).
- **9 verticals** — Trucking, Rail, Ocean, Air Cargo, Last-Mile, Warehousing, Customs, Insurance, Finance.

Combinatorial surface: 24 × 3 × 9 = **648 theoretical configurations**. Practically ship curated subset (sparse matrix — rail engineer in "finance mode" is nonsensical and gated off), but there are hundreds of valid experiences inside one app.

**Why not separate apps?** Every argument considered and rejected:
- *"Driver app is simpler, ship it alone."* — No. Same driver often switches to dispatcher mode when running own authority. Same person carries multiple roles. Forcing two apps destroys continuity of single identity.
- *"App Store discoverability."* — Rejected. App Store optimization rewards depth of engagement and review volume on single listing. Splitting fragments ratings, keyword authority, install base.
- *"Separate binaries are smaller."* — Marginally. App Thinning, on-demand resources, asset catalogs already deliver per-device slicing. Full EusoTrip on modern iPhone well under OTA threshold. Role assets lazy-loaded from registry, not bundled per role.
- *"Easier to review."* — No. Each submission is its own review. Multiplying submission count multiplies rejection surface. One binary, one reviewer relationship, one version history.
- *"Carriers want white-label app."* — Not at launch. White-label is Year 3+; when it happens it's a build configuration of the same codebase, not a separate product.

**The binary adapts. The user does not adapt to the binary.** Everything after sign-in — Home tab, Wallet tab, Me tab, Pulse orb behavior, screen registry, notification categories, Watch complications — is a function of `(role, mode, vertical)`.

---

## 2. App Store listing — canonical metadata

**App Name (primary)**: `EusoTrip`
**App Name (secondary, A/B tested)**: `EusoTrip — Freight Operating System`

Short name on icon + primary listing; longer in localized subtitles and promotional text to capture search intent around "freight OS," "trucking software," "logistics platform."

**Subtitle (30 character hard limit)**: `Trucking. Rail. Ocean.`

Exactly 22 characters. Three words, three verticals, three disciplines. No adjectives, no hype, no em-dashes. Must survive truncation on iPhone mini.

**Promotional text (170 characters, changeable without resubmission)**: Rotated seasonally.
Default: `The operating system for moving freight by road, rail, and sea. Built for the 3 AM load, the 2 AM breakdown, and the 1 AM paperwork.`

**Keywords (100 characters, comma-separated, no spaces)**:
`freight,trucking,rail,ocean,CDL,HOS,ELD,DOT,FMCSA,dispatch,broker,shipper,hazmat,reefer,flatbed`

Chosen for intent, not volume. "CDL" converts. "HOS" converts. "ELD" converts. Generic "logistics" covered implicitly by description + category. Revisit quarterly based on App Store Connect Search Ads data.

**Primary category**: Business
**Secondary category**: Navigation

Business is where B2B buyers browse. Navigation gives us foothold in the mapping/routing discovery surface drivers use.

**Age rating**: 4+ (no objectionable content, no UGC exposed to public, no gambling, no simulated violence). Keeps us outside parental restriction filters on company-issued iPhones.

**Required legal URLs**:
- Privacy: `https://eusotrip.com/legal/privacy`
- Terms: `https://eusotrip.com/legal/terms`
- Support: `https://eusotrip.com/support`
- Marketing (optional): `https://eusotrip.com`

All four return 200 OK, served HTTPS, reachable from Apple's reviewer IP ranges. Synthetic check every 15 minutes; 404 on any breaks submission.

---

## 3. Screenshots — role-swapping carousel

Required device sizes per Apple 2026: **6.7", 6.5", 6.1", 5.5"**. Produce 6.7" master and downscale with correct safe areas. 5.5" still required — Apple uses as fallback for older iOS + web App Store.

**Role carousel strategy.** Ten slots, use eight, leaving last two for seasonal (hurricane season ocean routing, ELD compliance deadlines).

- **Slot 1 — "I drive."** — Driver home: next stop, HOS clock, fuel card, gradient background. `Every mile. Every minute. Every dollar.`
- **Slot 2 — "I dispatch."** — Dispatcher board: live map, load queue, chat dock. `Move the board. Move the fleet.`
- **Slot 3 — "I captain."** — Ocean captain bridge: AIS overlay, weather, manifest. `From bridge to berth.`
- **Slot 4 — "I broker."** — Broker desk: load-to-truck matching, margin calculator, rate confirmation. `Every load. Every lane. Every margin.`
- **Slot 5 — Pulse orb.** — Ambient orb on Watch + iPhone. `One glance. Everything.`
- **Slot 6 — Wallet.** — Unified payments: fuel cards, factoring, settlements. `Paid when the wheels stop.`
- **Slot 7 — Me tab.** — Profile + role switcher + credentials. `One identity. Every role.`
- **Slot 8 — Watch companion.** — EusoTrip Pulse on Apple Watch. `On your wrist, on the road.`

Each: 1290 × 2796 (6.7" master), EusoTrip gradient background, SF Pro Display headlines, single clear device frame or bezelless composition. Localized screenshots for en-US, en-CA, fr-CA, es-MX.

---

## 4. App Preview video

One 15–30 second preview per device size (render once at 1080×1920, Apple accepts). **Gradient-heavy, no voiceover, captioned.**

Arc:
1. (0–3s) EusoTrip logo resolves out of gradient.
2. (3–8s) Home tab driver role, swiping to reveal next load.
3. (8–13s) Wallet tab, fuel card lights up, settlement hits.
4. (13–20s) Me tab, role selector sweeps through "Driver → Dispatcher → Captain → Broker," each with own tint.
5. (20–27s) Pulse orb, ambient breathing, glancing at Watch.
6. (27–30s) Wordmark lock-up: `EusoTrip — Freight Operating System`.

Captioned in all four locales. No audio track (App Previews autoplay muted; audio decorative). H.264, AAC stereo, 30fps, under 500MB.

---

## 5. Watch companion — single bundle

EusoTrip Pulse (watchOS) ships **inside iOS app bundle**, not separate listing. User installs EusoTrip on iPhone + has paired Apple Watch → iOS offers to install Pulse automatically. Standard paired-watch-app pattern:

- One App Store Connect record, one review, one version number.
- watchOS binary increments in lockstep with iOS.
- Feature-flagged watch complications roll out same way iOS features do.

**No standalone watchOS app** — Pulse requires paired iPhone running EusoTrip for identity, backend auth, registry resolution. Deliberate constraint; standalone watch apps multiply auth, network, review complexity for glance-layer feature.

---

## 6. App Review gotchas — the ones we've already hit

Battle scars. Do not repeat.

**`WKBackgroundModes` on watchOS.** The `audio` background mode is **iOS-only**. Including in watchOS `Info.plist` causes **error code 90362**, rejected EusoTrip build 51 on first submission. Legal watchOS background modes: `workout-processing`, `location`, `remote-notification`, `self-care`, etc. — **not** `audio`. Pulse uses `workout-processing` for fatigue monitoring only.

**Watch permission strings must all be in Info.plist.** watchOS does not inherit all strings from iOS host; several must be duplicated in watch extension's `Info.plist`. Missing string does not fail build locally — crashes first time API called and fails review. Mandatory set:
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`
- `NSMotionUsageDescription`
- `NSSiriUsageDescription`
- `NSBluetoothAlwaysUsageDescription`
- `NSNearbyInteractionUsageDescription`

Each string plain English, names feature using it, never says "this app needs…" — Apple rejects vague strings. Example: `NSMicrophoneUsageDescription = "EusoTrip uses your microphone for hands-free voice notes and dispatch chat while driving."`

**Sign In with Apple.** Required if we offer any third-party social auth (Google, Facebook). We **do not** ship third-party social auth — only email/phone + SSO for enterprise — **exempt**. If changes, Sign In with Apple must be peer option within same release.

**Encryption export compliance.** `ITSAppUsesNonExemptEncryption = false` in `Info.plist`. We use only Apple-provided TLS, CryptoKit, keychain primitives. No custom crypto, no ship-your-own cipher. Flag removes annual Bureau of Industry and Security paperwork requirement.

---

## 7. Privacy Manifest — `PrivacyInfo.xcprivacy`

Every Apple-mandated privacy manifest must be in main bundle + any first-party framework. Declares:

- **Data collection categories** — Location (precise + coarse), Health, Contact Info, Identifiers, Usage Data, Diagnostics.
- **Linked vs not linked to identity** — all our collection linked (we know who user is).
- **Used for tracking** — **false** across the board. No cross-app or cross-website tracking.
- **Required Reason APIs** — any Apple API on Required Reasons list (`UserDefaults`, `FileManager` creation date, system boot time, disk space, active keyboards) declared with correct reason code (`CA92.1, C617.1`).
- **Third-party SDK manifests** — each SDK we include (Firebase, Sentry, whatever survives vendor cull) must ship own `PrivacyInfo.xcprivacy`; we aggregate theirs into App Privacy report.

Parsed by Apple at upload time; any mismatch with App Privacy questionnaire in App Store Connect triggers Missing Privacy Manifest rejection.

---

## 8. App Tracking Transparency — not applicable

We do not track users across apps or websites owned by other companies. Do not share identifiers with data brokers. Do not fingerprint for advertising. **No ATT prompt.** App Privacy report correctly declares "Data Not Used to Track You." Deliberate product stance, not oversight. Any future integration requiring ATT must be escalated before implementation.

---

## 9. Push notification entitlement

`aps-environment` entitlement required for APNs. Ship `development` in debug builds, `production` in release and TestFlight. Notification categories registered at launch based on user's resolved role — dispatcher gets load-offer + driver-status categories; driver gets dispatch-message + stop-arrival. Categories are Apple-side handle; payload's `category` field must match.

---

## 10. HealthKit usage on Pulse — fatigue justification

Pulse reads heart rate, HRV, wrist movement from HealthKit for **driver fatigue detection**. Regulated sensitive data class; App Review scrutinizes.

Justification filed in review notes verbatim:

> EusoTrip Pulse reads heart rate, HRV, and motion data exclusively on-device to compute a fatigue risk score for commercial drivers. The score is surfaced to the driver only (never to dispatchers, carriers, or third parties) and is used to recommend rest stops in compliance with FMCSA Hours of Service regulations. No HealthKit data leaves the device. The fatigue model runs locally; no health identifiers are transmitted to our servers.

`NSHealthShareUsageDescription` string echoes: `"EusoTrip Pulse uses your heart rate and motion data on your device to detect fatigue and recommend rest stops."`

---

## 11. Subscription model — the plan

Drivers use EusoTrip **free, forever**. Their carriers or brokers pay for them, or they sign on as owner-operators under a broker that pays. **Charging individual drivers for a tool they need to do their job is a doctrinal non-starter.**

Revenue:
- **Broker Pro** — monthly subscription per seat, paid by brokerage, unlocks load-matching intelligence, margin analytics, bulk rate confirmations.
- **Fleet Pro** — per-truck monthly, paid by carrier, unlocks dispatcher board, compliance dashboard, fleet-wide analytics.
- **Carrier Enterprise** — annual contract off App Store, invoiced directly. **No IAP.**

In-App Purchases (StoreKit 2) handle Broker Pro + Fleet Pro when purchased by individual accounts. Enterprise contracts bypass IAP entirely; entitlements enabled via backend flags. Apple takes 15% on small business program revenue for Broker Pro + Fleet Pro; Enterprise sold outside app, not subject to commission per App Store guideline 3.1.3(b).

Even if subscription launch slips past 1.0, **plan is documented now** so App Review is not surprised when IAP appears in later build.

---

## 12. Carrier-specific apps — not building

Receive requests from large carriers for white-label EusoTrip under their brand. **Doctrinal answer for 2027: no.** One app, every carrier, every role. Branded experience surfaces rendered inside EusoTrip based on carrier the user belongs to — carrier colors in Me tab, carrier logo on Home tab, carrier-specific notifications — but **binary, App Store listing, and user-facing product name are always EusoTrip**.

---

## 13. TestFlight distribution

- **Internal testers** — up to 100 App Store Connect users, receive builds automatically on upload, no review required. Engineering, product, design, QA.
- **External testers** — up to **10,000** across groups. External builds require one-time Beta App Review per major version; subsequent builds within 90 days of same version auto-approved.

Tester groups:
- `internal-engineering` (auto-enroll on upload).
- `pilot-carriers-tier-1` (five design-partner carriers).
- `pilot-carriers-tier-2` (next twenty).
- `pilot-brokers`.
- `pilot-ocean`.
- `pilot-rail`.

Each group receives builds tagged for their vertical. Release notes per group role-aware.

---

## 14. Phased release — every production update

Every production release uses Apple's **Phased Release for Automatic Updates**:
- Day 1: 1%.
- Day 2: 2%.
- Day 3: 5%.
- Day 4: 10%.
- Day 5: 20%.
- Day 6: 50%.
- Day 7: 100%.

If crash-free sessions drop below 99.5% OR P0 regression lands, **pause phased release** from App Store Connect + ship hotfix. Phased release applies only to users with Automatic Updates enabled; manual updaters always get latest. Monitoring dashboard watches blended rate.

---

## 15. Release notes template

Each App Store update ships release notes in this structure, 4000 character limit, ours always under 500:

```
What's new in EusoTrip [version]:

• [Headline feature, plain English, role-tagged if relevant]
• [Second feature or improvement]
• [Third feature or improvement]

Reliability:
• [Crash fix or stability improvement, vague is fine]
• [Performance improvement]

Questions? support@eusotrip.com
```

No marketing fluff. No emoji. No "we've been busy!" Read by dispatchers at 4 AM; they need signal, not style.

---

## 16. Reviewer notes template

Filed in App Store Connect with every submission, Review Notes field:

```
Test account (Driver role):
  email: review-driver@eusotrip.com
  password: [rotating, filed per submission]

Test account (Dispatcher role):
  email: review-dispatch@eusotrip.com
  password: [rotating]

Test account (Broker role):
  email: review-broker@eusotrip.com
  password: [rotating]

To switch roles: Me tab → Switch Role. Each account above is
pre-scoped; you do not need to switch roles to review each mode,
but the option exists.

HealthKit usage (Pulse watch app): on-device fatigue detection
for commercial drivers, not transmitted off-device. See privacy
manifest and NSHealthShareUsageDescription.

Background location: used for HOS compliance during active
dispatch. Driver must be on-duty for tracking to activate.

Contact for reviewer questions: appreview@eusotrip.com
  (monitored 24/7 during active submission windows)
```

---

## 17. Review rejection playbook

Common rejections we've hit or expect:

- **Guideline 2.1 — Information Needed.** Reviewer can't reach feature. Response: 30-second Loom showing exact path + updated reviewer credentials with pre-seeded data.
- **Guideline 2.3.10 — Irrelevant metadata.** Keywords or description reference competing platforms. We don't name competitors; response cites keyword list as literal industry terminology (CDL, HOS, ELD are not brand names).
- **Guideline 4.0 — Design / Minimum functionality.** Rare, but if reviewer lands on role with sparse UI, response: explain role adaptation + offer pre-authenticated account with fully populated role.
- **Guideline 5.1.1 — Privacy / Data Collection.** Mismatch between privacy manifest and App Privacy report. Response: fix mismatch in same submission; never argue.
- **Guideline 5.1.2 — Data Use and Sharing.** If challenge HealthKit, respond with justification from §10 verbatim.
- **Metadata rejection (not binary).** Fix in App Store Connect, no resubmission needed, release same day.

Every rejection response sent within 24 hours, signed, with direct contact. We do not appeal in first response; we fix and ship. Appeal only if we believe rejection categorically wrong, and only after second rejection on same basis.

---

## 18. Cross-country listings

- **US (primary)** — en-US. Full metadata, all screenshots, all locales rendered.
- **Canada** — en-CA and fr-CA. Same binary. French-Canadian screenshots rendered from master. Regulatory language adjusted (e.g., "CDL" becomes "Class 1/3" in fr-CA copy, keyword remains CDL for search).
- **Mexico** — es-MX. Same binary. Metadata in Mexican Spanish. Regulatory references to SCT (Secretaría de Comunicaciones y Transportes) added to description.

**One binary. Three countries. Six locales at launch. No geo-forking of the build.**

---

## 19. Mac Catalyst, iPad, Vision Pro — not in scope for 1.0

- **iPad** — runs via iPhone compatibility mode. Native iPad layouts are Year 2. Registry is layout-aware but iPad-specific screens dark-flagged.
- **Mac Catalyst** — Not in scope. Mac users reach via web.
- **Vision Pro** — Not in scope for 2027. Ambient orb + Pulse might translate beautifully; reviewing that is 2028+.

All documented here so team knows answer when asked; App Store Connect correctly declares iPhone + Watch only for 1.0.

---

## 20. Version history strategy

**1.0 lives a long time.** Ship builds as 1.0 (build 52, 53, 54, …) through entire pilot period + first year of GA. Version bump to 1.1 reserved for **significant new role vertical** — e.g., Air Cargo graduating from dark launch to App Store listing. Point bumps (1.0.1, 1.0.2) for bugfix releases only.

**Build numbers always increment monotonically**, never reset. Build 127 follows 126, even across version bumps. Build numbers are internal ground truth; version numbers are marketing.

---

## 21. App Store Connect user access

- **Admin** — two people. Can configure banking, tax, team access.
- **App Manager** — mobile engineering lead + head of product. Can submit, respond to review, release.
- **Developer** — all mobile engineers. Can upload builds + configure TestFlight internal groups.
- **Marketing** — can edit metadata, screenshots, release notes; cannot submit.
- **Finance** — read-only sales + reports.

Release to App Store after approval requires **App Manager or Admin**. No single-person release: doctrine requires second App Manager to click "Release This Version" on production submissions.

---

## 22. Revenue + analytics

- **App Store Connect Analytics** — installs, sessions, retention, crashes. Pulled nightly into BI pipeline.
- **Sales and Trends** — IAP revenue, subscription churn, refund rates. Reconciled monthly against Stripe (enterprise) + StoreKit (IAP).
- **App Store Search Ads** — evaluated quarterly; not core channel — B2B buyers, ads target consumer intent.

Every metric lands in executive dashboard with same retention as backend metrics — 13 months hot, archived forever.

---

## 23. Launch latency budget

Apple enforces:
- **Launch in <10 seconds** from cold start, or watchdog kills process.
- **No main-thread hang >300ms** once launched.

Our internal budget stricter:
- **Cold launch <5 seconds** on oldest supported device (iPhone 12).
- **First meaningful paint <2 seconds.**
- **No main-thread hang >150ms** in any screen.

Enforced in CI with MetricKit hang-detection harness + launch-time regression gate. PR pushing cold launch above 5s on reference device fails CI.

---

## 24. Single-app onboarding

After sign-in, backend returns `(role, mode, vertical, carrier, entitlements)` tuple. App:
1. Persists tuple in keychain-backed identity store.
2. Resolves Home tab configuration from `ContentView.ScreenRegistry.forRole(role, mode, vertical)`.
3. Registers notification categories for role.
4. Requests permissions role actually needs (broker doesn't see Bluetooth ELD prompt; driver does).
5. Hydrates Pulse orb with role's ambient signals.

**Onboarding is three screens maximum after sign-in**: welcome, permissions, role confirmation. If backend tuple unambiguous (single role), role confirmation auto-dismisses after 1.5 seconds.

---

## 25. Dynamic navigation per role

`ContentView.ScreenRegistry.forRole(role, mode, vertical)` is single source of truth for navigation. Returns:
- Ordered list of tab bar entries (Home, Wallet, Me, Pulse).
- Per-tab root screens.
- Per-tab deep-link handlers.
- Per-tab notification category routers.

**No screen references another by hard-coded identifier.** Every navigation transition goes through registry. Role change mid-session (Me → Switch Role) → registry recomputes + tab bar rebuilds; no relaunch.

---

## 26. Feature flags + dark role launches

Every new role ships **dark first**. Role exists in binary, registry can resolve it, screens wired — but backend entitlement flag granting role is off for all accounts except internal dogfood group. Then:
1. Enable for internal (day 0).
2. Enable for one design-partner account (week 1).
3. Enable for pilot tier for that vertical (week 2–4).
4. Enable for all accounts in vertical (month 2+).

**Failed role launch never requires App Store submission to roll back** — flip the flag and role disappears from registry for affected accounts. Binary keeps shipping.

---

## Doctrinal summary

One binary. Twenty-four roles. Three modes. Nine verticals. One App Store listing. One review relationship. One version number progressing slowly + deliberately. Every new role ships dark, proven in production with real users, then graduates into App Store metadata + screenshot carousel when ready to be sold.

The App Store is not the edge of our product; it is the distribution channel for a product that lives in the backend, the registry, and the hands of the people moving freight.

EusoTrip — one app, every role, every vertical, every shift.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
