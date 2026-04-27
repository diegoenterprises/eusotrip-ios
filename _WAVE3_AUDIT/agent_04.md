# Agent 04 - Wave-3 Driver Screens Audit

Bucket: `_bucket_04` (13 Driver screens, 062-070, two "064" entries).
Swift Driver folder only contains 010-022 → **no Wave-3 screen has a Swift port yet**.
Backend refs cite file paths + line numbers from `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`.

---

## 062 Training and Certs.png
**Swift port:** NONE (folder only contains 010-022)
**Purpose:** Active CEU/ERG training card, in-play modules, annual CEU credits, browse & resume.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Active module header ("ERG 2024 Emergency Response", due/timer) | Featured course card | `trainingLMS.getCourseDetail` (trainingLMS.ts:157), `trainingLMS.getModuleProgress` (:524) | "Due in 7d / 4:00 left" countdown is UI-derived |
| CHAPTER 2 OF 3 DONE progress bar | Course progress | `trainingLMS.getModuleProgress` (trainingLMS.ts:524) | |
| Stats row: CEU earned / Required / Due in | Dashboard counters | `trainingLMS.getLMSDashboard` (trainingLMS.ts:600); `trainingCompliance.getCertificationTracker` (trainingCompliance.ts:307) | |
| Modules list (ERG, NH3, Fit-Test, Spill Response) | Course catalog | `trainingLMS.listCourses` (trainingLMS.ts:96); `trainingCompliance.getTrainingCatalog` (trainingCompliance.ts:154) | |
| Annual CEU credits bar (26.0 / 32.0 hrs) | Aggregate CEU hrs | GAP — no router returns annual CEU hours total | |
| ESANG banner ("Finish ERG at Lancaster dwell") | ESANG voice suggestion | `esangAI.*` / `esangVoice.*` (esangAI.ts, esangVoice.ts) | generic, no specific procedure for module-context prompts |
| Browse button | Open catalog | `trainingLMS.listCourses` (trainingLMS.ts:96) | nav-only |
| Resume ERG button | Resume lesson | `trainingLMS.getLessonContent` (trainingLMS.ts:287) + `completeLesson` (:334) | |

### Backend GAPS
1. No `getAnnualCEUTotal`/`ceuYearBalance` procedure — 26/32 hrs counter is computed client-side.
2. No module-contextual ESANG hint API ties a hint to a specific course/module id.
3. "Due in 7d / 4:00 left" lesson-timer state not exposed by `trainingLMS`.

### User-journey entry points
- `ME` tab → Profile → Training & Certs.
- Deep link from push/notifications inbox ("CEU expiring").
- Required backend state: enrolled course (`trainingLMS.enrollInCourse`, :215), module progress rows, active user session.

---

## 063 Preferences.png
**Swift port:** NONE
**Purpose:** Driver preferences — DND window, theme, voice, notification toggles, units, biometric, PIN, devices.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Current Mode (Day Window / Sleep Window, DND on/off, hours) | DND schedule | `preferences.get` (preferences.ts:27), `preferences.update` (:55); `notifications.getPreferences` (notifications.ts:277), `updatePreferences` (:337) | |
| Theme (LIGHT/DARK) | Theme toggle | `preferences.update` (preferences.ts:55) | |
| Voice (DETAILED/MINIMAL) | Voice verbosity | `preferences.update` (preferences.ts:55) | verbosity key stored in prefs |
| Load tenders toggle | Notification channel pref | `notifications.updatePreferences` (notifications.ts:337), `updateSetting` (:427) | |
| Dispatch chat toggle | Chat notif pref | `notifications.updatePreferences` (notifications.ts:337) | |
| Safety alerts toggle | Safety notif pref | `notifications.updatePreferences` (notifications.ts:337) | |
| Units (Imperial / mi / gal) | UOM | `preferences.update` (preferences.ts:55) | |
| Voice detail (full/female) | Voice persona | GAP — no voice-persona field confirmed in preferences schema |
| Haptics (medium) | Haptics level | GAP — no haptics key in `preferences.update` schema |
| Biometric unlock, last used | Biometric toggle + last-auth | GAP — no preferences/security procedure for biometric status & last-used timestamp |
| Fallback PIN SET button | Set PIN | GAP — no `setFallbackPin` procedure |
| Signed-in devices (3 active) | Device list | `profile.getConnectedDevices` (profile.ts:270), `revokeDevice` (:278); also `users.getSessions` (users.ts:778) | |
| Privacy / TOS links | Legal | `legal.getPrivacyPolicy` (legal.ts:21), `legal.getTermsOfService` (:12) | |
| ESANG banner (day window active etc.) | Suggestion | `esangAI.*` / `esangVoice.*` | |
| Save changes | Persist | `preferences.update` (preferences.ts:55) | |

### Backend GAPS
1. `voiceDetail` (female persona / TTS voice choice) — not in `preferences.update`.
2. `haptics` level — not in preferences schema.
3. Biometric unlock + "Last sign-in 04:02" → no security router procedure.
4. Fallback PIN set/rotate endpoint missing.

### User-journey entry points
- `ME` tab → Settings → Preferences.
- Onboarding flow final step.
- Required state: user session, wallet/auth initialized, notificationPreferences row.

---

## 064 Notifications Inbox.png
**Swift port:** NONE
**Purpose:** Unified driver inbox (tenders, dispatch, safety) with per-item actions.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Inbox list header (LIVE / 3 UNREAD) | Unread count | `notifications.getUnreadCount` (notifications.ts:443), `getSummary` (:22) | |
| ESANG DISPATCH featured row ("Adjacent rebid") | Top load/rebid tender | `loads.*` rebid-specific GAP; closest = `driverMobile.getDriverHomeDashboard` (driverMobile.ts:240); dark variant matches `negotiations.*` | no dedicated "rebid tender" procedure |
| Est. pay / window | Derived tender preview | `loads.*` / `negotiations.*` | |
| PASS / Review rebid button | Decline / open rebid | `negotiations.*` router — specific rebid-decision proc not confirmed; GAP |
| SNOOZE 6h (dark variant) | Snooze notification | GAP — `notifications` has archive/delete but no snooze |
| Tenders & Rebids section rows | Notification items | `notifications.list` (notifications.ts:51) | |
| Dispatch & Safety section rows | Notification items | `notifications.list` (notifications.ts:51) | |
| ESANG banner | Contextual voice hint | `esangAI.*` / `esangVoice.*` | |
| Clear read | Clear read items | GAP — no `clearRead` procedure (only `markAllRead` :462) |
| Mark all read | Bulk ack | `notifications.markAllAsRead` (notifications.ts:198), `markAllRead` (:462) | |

### Backend GAPS
1. `notifications.snooze({id, duration})` missing.
2. `notifications.clearRead` (remove already-read) missing.
3. No rebid-tender-specific schema (load rebid decisions rolled into generic negotiations).
4. No grouping by category for inbox UI — UI groups manually.

### User-journey entry points
- Tab bar bell icon / deep-link from push.
- Wallet PAY / dispatch chat transitions surface here.
- Required state: `notifications` rows for userId, recent load tenders, active rebid negotiations.

---

## 064 Zeun Roadside.png
**Swift port:** NONE
**Purpose:** Roadside diagnostics + ticket for in-cab breakdown; shop-slot booking.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Header "Zeun flagged low oil pressure drift" | Active ticket summary | `zeunMechanics.getBreakdownReport` (zeunMechanics.ts:378); `zeun.getVehicleStatus` (zeun.ts:76) | |
| Rig / Location chips | Vehicle + geo | `vehicle`/`vehicles`, `assetTracking.*` | |
| Severity / detected-by | Enum | `zeunMechanics.reportBreakdown` (zeunMechanics.ts:237) | |
| Sensor reads (oil/coolant/battery) | Telemetry | `zeun.getDiagnosticCodes` (zeun.ts:108); `zeunMechanics.lookupDTC` (:1001); `telemetry.*` | |
| Zeun ticket number + status pills (OPEN/SLOTTED/CONFIRMED/DONE) | Breakdown ticket state | `zeunMechanics.getBreakdownReport` (zeunMechanics.ts:378), `updateBreakdownStatus` (:434) | |
| SLOT HOLD countdown | Held appointment | GAP — no procedure returning slot-hold TTL; partial `zeunMechanics.scheduleMaintenance`/`findProviders` (:471) |
| Nearest qualified shop card | Provider list | `zeunMechanics.findProviders` (zeunMechanics.ts:471), `searchProviders` (:590), `getProvider` (:742) | |
| Distance / slot time / ETA | Route calc | `zeunMechanics.findProviders` returns distance; ETA probably client-side |
| Call shop | Dial provider | GAP — phone action not backed; `getProvider` returns phone only |
| Confirm 07:30 slot | Book slot | `zeunMechanics.scheduleMaintenance`; or `zeun.scheduleMaintenance` (zeun.ts:152) | neither exposes a slot-hold confirm primitive |
| ESANG banner | Hint | `esangAI.*` | |

### Backend GAPS
1. Slot-hold lifecycle (`holdSlot` / `confirmSlotHold` with TTL) missing.
2. `callProvider` / CTI phone-click audit event missing.
3. No `zeunMechanics.getActiveTicketForDriver` — UI must derive from getBreakdownReport by id.
4. Live sensor-drift monitor (auto-flag reason + severity trend) not procedure-backed beyond raw DTC lookups.

### User-journey entry points
- Auto-triggered by Zeun telemetry push → notification inbox → this screen.
- `ME` tab → Maintenance alerts.
- Required state: active breakdown report, provider directory seeded, vehicle bound to driver.

---

## 065 EusoTicket Exception.png
**Swift port:** NONE
**Purpose:** File an observation ticket (hazmat / weather / mechanical / delay) at a specific stop.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Observation header + stop id | Load/stop binding | `loads.*` / `runTickets.*`; `eusoTicket.getRunTicket` (eusoTicket.ts:159) | |
| Category chips (WEATHER / MECHANICAL / HAZMAT / DELAY) | Exception category | `eusoTicket.createRunTicket` (eusoTicket.ts:121) accepts status, but a category exception enum → GAP | partial |
| Ticket detail — Category / Severity / Witnesses | Form fields | GAP — no `exception` / `observation` procedure with these fields |
| Attachments: Photos / Voice / GPS Pin | Upload | `documents.*` / `aiDocProcessor.*`; photo attach GAP for ticket-bound uploads |
| ESANG banner (draft quote) | AI draft | `esangAI.*` | |
| Save draft | Persist draft | GAP — no observation-ticket draft procedure |
| Submit observation | Create exception | GAP — no `eusoTicket.createException` / `safety.createObservation`; closest `safety` incident mutation (safety.ts:24) |

### Backend GAPS
1. `eusoTicket.createException({ category, severity, witnesses, photos, voice, gps })` fully missing.
2. Witness attach (on-site people) — no schema field.
3. Voice attachment (6:22 sample) — upload endpoint GAP.
4. GPS pin attach to ticket — GAP (no `ticket.attachGpsPin`).
5. Draft persistence (auto-save) — GAP.

### User-journey entry points
- During active delivery → "File exception" from EusoTicket screen.
- Home → quick action "Log safety incident" (currently routes to Help & Support).
- Required state: active load + stop id, device camera/mic permissions, GPS fix.

---

## 065 Help and Support.png
**Swift port:** NONE
**Purpose:** Help hub — hotlines, live chat, dispute tools, ops contacts, pinned guides.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Roadside 24/7 hotline (888) 550-HAUL | Dial | `support.getContactInfo` (support.ts:482) | |
| Safety hotline (800) 424-9300 | Dial | `support.getContactInfo` (support.ts:482) | |
| Resume T-8842 / Start support chat | Chat session | `support.startChatSession` (support.ts:542), `sendChatMessage` (:546) | |
| Log safety incident | Report | `safety` incident create (safety.ts:24); `driverMobile.reportSafetyIssue` (driverMobile.ts:1679) | |
| Dispute a load | Ticket / claim | `support.createTicket` (support.ts:228); `freightClaims.*` | |
| Speak a question (voice) | Voice ticket | `esangVoice.*`; GAP — no voice-to-ticket pipeline |
| Your Ops Contacts rows | Team directory | `team.*`; GAP — no per-driver assigned-ops-contact procedure surfaced |
| Contact presence (LIVE/OFF) | Presence | GAP — no presence/activity procedure per user |
| Pinned guides (ESANG guides) | KB articles | `support.getKBArticles` (support.ts:106), `getKBArticle` (:135), `getFAQArticles` (:459) | |
| Tickets button | Open tickets | `support.getMyTickets` (support.ts:326) | |
| Start chat | Chat | `support.startChatSession` (support.ts:542) | |

### Backend GAPS
1. Per-driver "Your Ops Contacts" directory (Lena/Armbrust/Marisol with role) — GAP.
2. Contact presence (LIVE / ON CALL / OFF) — GAP.
3. Voice-question → ticket endpoint (Speak a question) — GAP (only generic voice router).
4. KB bookmark list hardcoded `[]` (support.ts:142) — true persistence GAP.

### User-journey entry points
- Global "Help" link (tab bar ME or contextual).
- Push escalation (e.g., from EusoTicket exception) → support.
- Required state: user session, company/terminal binding for hotlines, active ticket list.

---

## 066 Feedback and Ratings.png
**Swift port:** NONE
**Purpose:** Feedback after a leg — star rating + categorized cards + history.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Rate last leg — star widget | Submit rating | `ratings.submit` (ratings.ts:155); `feedback.list`/`feedback.respond` stubs (feedback.ts:13,18) | feedback table missing |
| Category tiles (App & UI, Kudos to Dispatch, Facility note, Route suggestion) | Categorized review | `ratings.submit` (ratings.ts:155) — free-text only; GAP for typed categories |
| Recent submissions list | History | `ratings.getReviews` (ratings.ts:112); `feedback.list` (feedback.ts:13) returns [] |
| Submission status pills (ACKNOWLEDGED/RESOLVED) | Workflow | GAP — feedback lifecycle not persisted (feedback router is stub) |
| ESANG banner (WAWA OPS acked at 14:19) | Ack event | GAP |
| History button | History view | `ratings.getReviews` (ratings.ts:112) | |
| Submit + accessorial | Rating + claim | `ratings.submit` + `detentionAccessorials.*`/`accessorial.*` | requires linking |

### Backend GAPS
1. `feedback` router is stub (feedback.ts:13-20) — no table, no persistence.
2. No typed category enum for ratings (App/UI, Kudos, Facility, Route).
3. No workflow states (acknowledged/resolved) on feedback.
4. Rating + accessorial combined submit not exposed.

### User-journey entry points
- Post-trip auto-prompt after delivery complete (019/020 pipeline).
- `ME` tab → Feedback.
- Required state: recent completed trip, ratings summary loaded.

---

## 066 P2P Wallet Transfer.png
**Swift port:** NONE
**Purpose:** Instant P2P transfer to another verified driver, optionally tied to a load.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Recipient card (name, tier, last haul, rating) | Lookup recipient | `users.*` / `profile.getDriverProfile` (profile.ts:110); `ratings.getMySummary` (ratings.ts:232) | |
| Amount field + quick chips | Amount | `wallet.transfer.amount` input (wallet.ts:817,820) | |
| USD/Instant toggle | `transferType` | `wallet.transfer` (wallet.ts:817,822) accepts "standard/instant/scheduled" | |
| Memo | Memo | GAP — `wallet.transfer` schema does not include memo field |
| Tied to load (L-2026-88412) | Link to load | GAP — `wallet.transfer` has no `loadId` param |
| EusoWallet impact (balance, after-send) | Balance | `wallet.getBalance` / `ensureWallet`; `paymentsRouter.getBalance` (payments.ts:76) | |
| ESANG banner (no fee Tier-A → Tier-A) | Fee preview | `platformFees.*`; fee logic in `wallet.transfer` (wallet.ts:861) | preview-only endpoint GAP |
| Cancel / Send $X | Execute | `wallet.transfer` (wallet.ts:817) — `auditedProtectedProcedure` | |

### Backend GAPS
1. `memo` field on P2P transfer not persisted (schema p2pTransfers).
2. `loadId` link on P2P transfer (L-2026-88412) — GAP.
3. Pre-send fee-preview procedure (read-only) — only computed inside `transfer` mutation.
4. Recipient lookup by @handle not a dedicated procedure.

### User-journey entry points
- Wallet tab → Send to driver.
- Dispatch chat → "Send payment" inline → this screen.
- Required state: verified recipient, wallet balance ≥ amount, KYC tier.

---

## 067 About and Legal.png
**Swift port:** NONE
**Purpose:** App/driver metadata, carrier of record, legal docs, data export.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| App version / build / STAGING pill | Build info | GAP — no `system.getBuildInfo` procedure; falls back to client bundle |
| Server status "nominal / stable" | Health | `zeunMechanics.health` (zeunMechanics.ts:1893) or aiHealth; no driver-facing single endpoint |
| Carrier of record (Eusotrans, USDOT, MC) | Carrier data | `companies.*`; `authority.*` | |
| Terminal | Terminal | `terminals.*` | |
| CDL state/class | Driver CDL | `drivers.*` / `cdlVerification.*` | |
| Legal: Terms / Privacy / Driver handbook / Open-source | Legal docs | `legal.getTermsOfService` (legal.ts:12), `getPrivacyPolicy` (:21), `getCookiePolicy` (:30) | handbook + OSS licenses GAP |
| Data export ready (download) | Download archive | `legal.requestDataExport` (legal.ts:94); GAP — no download-URL/polling endpoint |
| Download my data request | Kick off export | `legal.requestDataExport` (legal.ts:94) | |
| ESANG banner (privacy policy tap) | Voice hint | `esangAI.*` | |
| Sign out | Session end | `users.*`; `auth` (not in bucket) | |
| Contact support | Open ticket | `support.createTicket` (support.ts:228) | |

### Backend GAPS
1. No `app.getBuildInfo` / `platform.getServerStatus` for driver-facing nominal indicator.
2. Driver handbook / OSS licenses doc endpoints missing from `legal` router.
3. Data export archive download URL + status polling endpoint missing (only `requestDataExport`).
4. "Pending acks" counter (ESANG: no pending acks) — GAP.

### User-journey entry points
- ME → Settings → About.
- Deep link from push "Privacy policy updated".
- Required state: user session, company/terminal binding.

---

## 067 The Haul Mission.png
**Swift port:** NONE
**Purpose:** Active skill mission ("Lancaster Bay Master") with objectives, progress, reward.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Mission name + skill tag + date | Mission meta | `gamification.getMissions` (gamification.ts:679); `advancedGamification.getWeeklyMissions` (advancedGamification.ts:1387) | |
| Time left / Drivers In / Tier | Tier filter | `gamification.getMissions` (gamification.ts:679) — tier filter GAP |
| Objectives list with Cleared/Verifying | Objective state | `gamification.getActiveTripMissions` (gamification.ts:1666); `advancedGamification.getAchievementProgress` (advancedGamification.ts:1204) | per-objective verification GAP |
| Progress bar 60% | Mission progress | `gamification.getActiveTripMissions` (gamification.ts:1666) | |
| On completion rewards: cash +$60, XP +160, Badge Bay Master II | Reward preview | `gamification.getMissions` (:679); `claimMissionReward` (:880) | |
| ESANG banner | Hint | `esangAI.*` | |
| Decline / Continue mission | Cancel / proceed | `gamification.cancelMission` (gamification.ts:1001); `startMission` (:810) | |

### Backend GAPS
1. "Verifying" intermediate objective state — not modeled in `gamification` schema.
2. Tier-A scoped mission filter — GAP.
3. Cash-reward component (missions currently award XP/points, not USD) — schema GAP, needs link to wallet.

### User-journey entry points
- Home "Haul" widget → mission card.
- Push when mission becomes claimable.
- Required: enrolled in mission, current season active (`gamification.getCurrentSeason` :1158).

---

## 068 The Haul Leaderboard.png
**Swift port:** NONE
**Purpose:** Weekly leaderboard (Precision Drops / Hazmat Haulers) with user rank and top 5.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Title + filter (Precision Drops · Week 42) | Leaderboard metadata | `gamification.getLeaderboard` (gamification.ts:294); `driverMobile.getDriverLeaderboard` (driverMobile.ts:1752); `ratings.getLeaderboard` (ratings.ts:267) | week-scoped leaderboard not explicit |
| Filter pills (Closes in 2d, My Tier, Drivers 74) | Filter | `gamification.getLeaderboard` supports filters; tier filter GAP |
| Your rank card (#3 Michael E., HOLD) | Current-user rank | `gamification.getLeaderboard` (gamification.ts:294); HOLD status GAP |
| Top drivers list with points | Top-N | `gamification.getLeaderboard` (:294); `advancedGamification.getLeaderboardHistory` (:1839) | |
| ESANG banner | Hint | `esangAI.*` | |
| Share | Share image/url | GAP — no `leaderboard.share` procedure |
| See full board | Paginate | `gamification.getLeaderboard` (paginated) | |

### Backend GAPS
1. HOLD / PENDING rank-lock state not modeled.
2. Leaderboard categories (Precision Drops, Hazmat Haulers) — no enum in `gamification.getLeaderboard`.
3. `leaderboard.share` shareable deep-link endpoint missing.
4. "74 drivers" total-participant count — GAP (not in response shape).

### User-journey entry points
- Home → Haul widget → Leaderboard.
- Push when rank changes.
- Required: gamification profile, active season.

---

## 069 Achievements Wall.png
**Swift port:** NONE
**Purpose:** Badge case with earned/locked badges and progress to next unlock.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Earned X / Y counter | Badge totals | `gamification.getBadges` (gamification.ts:528); `profile.getAchievements` (profile.ts:172); `driverMobile.getDriverLeaderboard` returns badges (driverMobile.ts:1833) | |
| Legendary count | Rarity aggregate | GAP — no per-rarity aggregate procedure |
| Next Unlock card (Bay Master II - 80%) | Next-badge progress | `advancedGamification.getAchievementProgress` (advancedGamification.ts:1204); `gamification.getAchievements` (:215) | |
| Badge grid (9 tiles, locked/unlocked) | Badge catalog | `gamification.getBadges` (:528); `advancedGamification.getAchievements` (:1166), `getRareAchievements` (:1215) | |
| Badge detail tap → rarity/tier | Detail | GAP — no `gamification.getBadge({id})` detail procedure |
| ESANG banner (Thu Lancaster auto-claim) | Auto-claim projection | GAP — no "projected unlock" projection procedure |
| Share | Share | GAP |
| Explore badges | Browse all | `gamification.getBadges` (:528) | |

### Backend GAPS
1. Per-rarity aggregate (Legendary/Epic/Rare counts) — GAP.
2. `getBadgeDetail({id})` — GAP.
3. "Projected unlock" / ETA badge endpoint — GAP.
4. Badge share to social — GAP.

### User-journey entry points
- Home → Haul → Achievements.
- Claim flow after mission completion.
- Required: gamification profile, earned userBadges rows.

---

## 070 Invite a Driver.png
**Swift port:** NONE
**Purpose:** Driver-to-driver referral code (MEX-742), earnings split, share.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Invites sent / Accepted / Earned counters | Referral stats | `users.getReferralInfo` (users.ts:761) — returns stubbed zeros | referral counts not wired |
| Referral code MEX-742 + expires | Code | `users.getReferralInfo` (users.ts:761) — derives code from email; GAP: no custom persistent code or expiry |
| Copy code | Clipboard | n/a (client) | |
| Payout breakdown (You earn $150, Referee earns $150, Milestone bonus $200) | Reward schedule | GAP — no `referral.getRewardSchedule` procedure; hardcoded UI |
| ESANG banner (Priya Menon · Wawa Lancaster fit) | Suggested invitee | GAP — `invite.lookup` (invite.ts:124) is carrier/FMCSA only, not driver suggestions |
| Text / Share link | Share | `invite.send` (invite.ts:30) — but context enum is carrier-centric (PARTNER_LINK, LOAD_BOARD, etc.); DRIVER_ONBOARD exists (:21) | partial |

### Backend GAPS
1. Persistent, rotating `referralCode` with `expiresAt` — GAP (current code is email-prefix).
2. `referral.getStats` wired to real `referred_by` relations — GAP (returns zeros).
3. `referral.getRewardSchedule` (you/referee/milestone tiers) — GAP.
4. `referral.suggestInvitees` (Priya Menon match) — GAP.
5. No `referrals` table surfaced in driver-facing schema search.
6. Signing-bonus ledger entry after first verified haul — not linked to wallet bonus (`bonus` type exists but no referral creator).

### User-journey entry points
- ME → Invite a driver.
- Home banner when milestone available.
- Required: `users.getReferralInfo`, wallet connected, share-sheet system capability.

---

## Summary

**Totals (Agent 04 bucket)**
- Screens audited: **13** (all 13 light+dark PNGs read).
- Swift ports: **0/13** (Driver folder only contains 010-022 — Wave-3 screens 062-070 unported).
- UI elements audited: ~130.
- Elements fully backed by a tRPC procedure: ~60 → **≈46% backed**.
- Elements partially backed (generic router exists but missing the specific shape/field): ~35 → ≈27%.
- Pure GAPs: ~35 → ≈27%.

**Top-3 gaps (cross-screen, highest impact)**
1. **Feedback + Referral data models are stubs.** `feedback.ts:13-20` returns empty arrays; `users.getReferralInfo` (users.ts:761) derives code from email with no persistence, no `referrals` table. Directly breaks screens 066 Feedback and 070 Invite.
2. **EusoTicket exception pipeline missing.** No `createException/observation` mutation with category/severity/witness/voice/photo/GPS binding — screen 065 EusoTicket Exception has no endpoint; only a generic `safety.createIncident` (safety.ts:24) exists.
3. **Gamification richness gaps.** Cash-reward missions, "Verifying" objective state, HOLD rank-lock, category (Precision/Hazmat) enums, per-rarity badge counts, projected-unlock ETA, and share endpoints are all absent from `gamification` and `advancedGamification`. Affects screens 067/068/069.

**Secondary gaps**
- Preferences router missing voiceDetail, haptics, biometric status, fallback-PIN procedures.
- Notifications router missing `snooze` and `clearRead`.
- P2P transfer missing `memo` and `loadId` binding.
- Zeun roadside missing slot-hold lifecycle.
- About/Legal missing build-info, handbook doc, and data-export download-URL polling.
