# Wave-3 Agent 07 Audit — Bucket 07 (090–102)

Scope: 13 Driver-app Figma screens (light + dark pairs).
Backend root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`
Schema root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/schema.ts`
Swift root: `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/`

Global note: the Swift Driver folder currently contains only files `010_DriverHome.swift` through `022_DockAssigned.swift`. **None of the 13 screens in this bucket (090–102) have Swift ports yet** — this is the universal Swift-port gap for this bucket and is not re-listed per screen.

---

## 090 Team Chat.png
**Swift port:** GAP — no matching Swift file in `EusoTrip/Views/Driver/` (files stop at 022).
**Purpose:** Group-channel messaging screen for a driver crew ("PA Tank Crew"), showing a threaded conversation, read receipts, a composer, and a bottom tab bar (Home / Trips / Wallet / Me with central action button).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Channel header (name, online count, "7 members") | Channel metadata | `channels.getById` (channels.ts:279), `channels.getMembers` (channels.ts:308) | `groupChannels` + `channelMembers` tables exist (schema.ts:3538, 3561). |
| Presence dot "ONLINE" | Member presence | GAP | No presence router found; only last-seen heuristics. |
| Overflow icons (chat / settings top-right) | Open settings / mute | `channels.updateChannel` (channels.ts:385), `channels.toggleMute` (channels.ts:426) | |
| Date divider "FRI · APR 17" | Client-side grouping | n/a | Derived from message timestamps. |
| Message bubbles (incoming, outgoing) | Thread messages | `channels.getMessages` (channels.ts:101) | Backed by `messages` table (schema.ts:817). |
| Avatar + name + timestamp per message | User lookup | `users` relation via `messages.senderId` | No dedicated procedure; joined in `channels.getMessages`. |
| Read receipt ("Read" + count) | Read state | `channels.markRead` (channels.ts:338); table `messageReadReceipts` (schema.ts:3578) | |
| Reaction count ("• 3") under message | Reactions | GAP in channels router; `messageReactions` table exists (schema.ts:2552) | No `channels.addReaction` / `getReactions` procedure. |
| EsangAI contextual prompt card ("Reggie's radar matches…") | AI assistant suggestion | `esangAI.*` / `esangAIv2.*` exists | No clear "chat-context suggestion" procedure wired; treat as GAP for this exact surface. |
| Message composer input | Draft text | n/a | Client state. |
| Send button (paper plane) | Send message | `channels.sendMessage` (channels.ts:153) | |
| Attachment icon (+) | Attach media | `channels.uploadAttachment` (channels.ts:534) | `messageAttachments` table (schema.ts:2570). |
| Voice-note / mic icon | Record audio | GAP | No voice-message procedure in channels.ts. |
| Bottom tab bar (Home / Trips / Wallet / Me / center +) | Navigation | n/a (client nav) | |

### Backend GAPS (numbered)
1. No presence/online-status procedure for channel members.
2. No reaction add/remove/list procedure in `channels.ts` despite `messageReactions` table.
3. No voice-note send/upload procedure (only generic attachment upload).
4. No "AI chat suggestion" procedure that ingests channel context to produce the inline EsangAI card.
5. No typing indicator / ephemeral presence channel.

### User-journey entry points
- Tap "Team Chat" deep-link from a notification (`notifications.list` item) → requires active `channelMembers` row for current user.
- Tap crew row in a Chats index (channels.list) → `channels.list` must return the crew.
- Push from CommunicationHub broadcast (`communicationHub.sendBroadcast`) that targets this channel.
Required backend state: `groupChannels` row + `channelMembers` row for `ctx.user.id`; prior `messages` for history; unread counts via `channels.getSummary`.

---

## 091 Load Offer Detail.png
**Swift port:** GAP.
**Purpose:** Driver-facing load offer card with pickup/drop, elevation graph, pay breakdown, load specs, lane-vs-market indicator, shipper card, AI rationale, and Decline / Book-it-now CTAs. Includes a countdown chip ("1H 33M TO PICKUP" / "17H 03M OPEN").

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| "SPOT OFFER · SPT-44790" header | Load reference | `loads.getById` (loads.ts:1012) | |
| Countdown chip (time to pickup / time open) | Derived from `loads.pickupWindowEnd` | n/a | Computed client-side. |
| Pickup / Drop city cards | Stops | `loads.getById` returns stops; `loadStops` table (schema.ts:413) | |
| Elevation chart (miles vs grade) | Route elevation | GAP | No procedure returns terrain/elevation; `routing.calculateRoute` returns distance/time only. |
| Miles / Drive / Deadhead tiles | Route metrics | `routing.calculateRoute` (routing.ts:70) | Deadhead requires current driver location join — partial. |
| Pay breakdown (line-haul, fuel surcharge, quick-turn premium, total) | Settlement calc | `loads.calculateRate` (loads.ts:1676) | Quick-turn premium is not an explicit field — likely computed via `contextualPricing` or ad-hoc. |
| Load specs (weight, commodity, equip, hazmat) | Load attributes | `loads.getById` (loads.ts:1012) | Hazmat flag via `adr.*`. |
| "Lane rate vs market" gauge (+$125 / +20%) | Market comparison | `loads.getRateHistory` (loads.ts:1752) partial; `rateSheet.*` | GAP for explicit "vs lane average delta" metric. |
| Shipper card (name, rating 4.6) | Shipper profile | `ratings.getForEntity` (ratings.ts:36); `customers.*` | |
| EsangAI rationale card ("$1.42/mi above…") | AI explanation | `esangAIv2.*` | GAP — no load-offer-specific explainer procedure surfaced. |
| Decline button | Reject offer | `drivers.declineLoad` (drivers.ts:1130) | |
| Book it now button | Accept offer | `drivers.acceptLoad` (drivers.ts:1122) or `loads.book` (loads.ts:1897) | Two competing paths; canonical flow unclear. |
| Bottom tab bar | Navigation | n/a | |

### Backend GAPS (numbered)
1. No elevation/terrain profile procedure feeding the chart.
2. No explicit "lane-vs-market delta" procedure; must be composed from `rateSheet`/`loads.getRateHistory`.
3. "Quick-turn premium" pay line has no dedicated config/procedure.
4. Ambiguity: `drivers.acceptLoad` vs `loads.book` — audit needed to pick canonical accept path.
5. No procedure returning the AI rationale text block for a specific offer.

### User-journey entry points
- Push notification → load offer → `notifications.list` item with `loadId` deep link.
- Load-board tap (`loadBoard.*` / `loads.getMarketplaceLoads` loads.ts:2866).
- Dispatch assignment (`drivers.assignLoad` drivers.ts:597) pushes offer to driver inbox.
Required backend state: `loads` row with status=`available`/`offered`, optional `bids` row, driver HOS availability via `drivers.getMyHOS`.

---

## 092 Settlement Detail.png
**Swift port:** GAP.
**Purpose:** Driver pay-stub / settlement detail. Header with net paid + gross + miles + RPM, load-breakdown line items (line-haul, fuel surcharge, short-haul premium, driver lease deduction, platform fee), a documents section (rate confirmation / BOL / detention proof), and a timeline.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| "SETTLEMENT · STL-90487" + Pending/Paid status pill | Settlement record | `settlementBatching.getBatchDetail` (settlementBatching.ts:205); `earnings.list` (earnings.ts:178) | Table `settlements` (schema.ts:720). |
| Net paid / Gross / Miles / RPM tiles | Aggregates | `earnings.getSummary` (earnings.ts:24); `settlementBatching.getDriverBatchView` (settlementBatching.ts:576) | |
| Associated load card ("Load SH-2047 …") | Load ref | `loads.getById` (loads.ts:1012) | |
| Line items (line-haul, FSC, short-haul premium, driver lease, platform fee) | Pay breakdown | GAP | `earnings.list` returns totals; no itemized settlement-line procedure. `leaseAgreements` (schema.ts:5264) and `platformRevenue` (schema.ts:2061) exist but not surfaced by a single line-item endpoint. |
| Documents rows with status (cleared / pending) | Linked docs | `settlementBatching.generateBatchPDF` (settlementBatching.ts:621); `documents.list` (documents.ts:135); table `settlementDocuments` (schema.ts:761) | |
| Rate confirmation entry | Doc | `agreements.*` or `documents.getById` | |
| BOL + scale ticket entry | Doc | `bol.list` (bol.ts:305) | |
| Detention proof entry | Doc | `detentionAccessorials.*` evidence attach | GAP — no explicit "settlement evidence link" join table in schema. |
| Timeline (load delivered / settlement posted) | Event log | GAP | No settlement-timeline procedure; `auditLogs` table exists but not surfaced. |
| Bottom tab bar | Navigation | n/a | |

### Backend GAPS (numbered)
1. No line-item-level settlement procedure returning individual deductions and premiums.
2. No settlement↔evidence linking procedure (document status "cleared/pending" vs the settlement).
3. No settlement timeline/history procedure.
4. `earnings.getSummary` returns only aggregates; the PDF-level breakdown shown must be assembled client-side.

### User-journey entry points
- Tap settlement row in Wallet tab → `settlementBatching.getDriverBatchView`.
- Notification "Settlement posted $516 net" (seen on 095) → deep link.
- From Trip Wrap "Submit & finish" success → new settlement row.
Required backend state: `settlements` row with driver's user_id, `payments` row(s), linked `loads`, optional `settlementDocuments`.

---

## 093 Tax Vault.png
**Swift port:** GAP.
**Purpose:** Driver year-to-date tax dashboard. Header with YTD taxable net, miles, estimated tax owed, set aside. Document list (2026 YTD summary, Q1 estimate filed, IFTA Q1 summary, 2025 1099-NEC, DOT medical certificate). Monthly receipts grid with quick-add. Next-quarterly estimate card. EsangAI tax tip. Request form / Export vault CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| YTD net / miles / est. tax / set-aside tiles | Tax aggregates | `taxReporting.getContractorSummary` (taxReporting.ts:24); `taxReporting.getDashboard` (taxReporting.ts:287) | |
| Year selector (2026) | Scope filter | Input param to taxReporting | |
| "7 FILED · 2 LIVE" docs counter | Derived | n/a | |
| 2026 YTD summary row | Report doc | `reports.*` | GAP — no "YTD summary" specific procedure. |
| Q1 2026 estimate filed | 1040-ES | GAP | Not in routers; `taxReporting` focuses on 1099. |
| IFTA Q1 2026 summary | IFTA report | `iftaCalculator.*` | Router exists; exact "quarterly summary" procedure not verified. |
| 2025 1099-NEC | 1099 issuance | `taxReporting.list1099s` (taxReporting.ts:157); `taxReporting.get1099Detail` (taxReporting.ts:209); `taxReporting.generate1099s` (taxReporting.ts:84) | |
| DOT medical certificate | Driver doc | `documents.getDriverDocuments` (documents.ts:372) | |
| Receipts-this-month tiles with "+ Add" | Receipts | `driverMobile.submitExpense` (driverMobile.ts:648); `driverMobile.scanReceipt` (driverMobile.ts:677); `driverMobile.getExpenseHistory` (driverMobile.ts:707) | |
| Next-quarterly-estimate card + due date | Projection | GAP | No quarterly-estimate projection procedure. |
| EsangAI tax tip card | AI suggestion | `esangAI.*` | GAP — no tax-specific explainer endpoint. |
| Request form button | Request tax doc | GAP | No "request a new form" procedure in taxReporting. |
| Export vault button | Bulk export | `exports.*` | Generic export router; no "tax vault export" specific. |

### Backend GAPS (numbered)
1. No 1040-ES / estimated-tax-filing procedure.
2. No quarterly-estimate projection procedure feeding the "DUE JUN 16 $1,930" card.
3. No "request tax form" procedure.
4. No tax-specific export procedure (needs `exports.create` wiring + template).
5. No persisted year selector / multi-year browsing (`year` input param only).

### User-journey entry points
- Profile → Tax Vault tab → `taxReporting.getContractorSummary`.
- Notification "Q1 estimate filed" → deep link.
- Push from January 1099 generation job (`taxReporting.generate1099s`).
Required backend state: driver role, `payments`/`earnings` aggregates for fiscal year, at least one generated `documents` row of type `1099_NEC`.

---

## 094 Driver Profile.png
**Swift port:** GAP.
**Purpose:** Driver resume/scorecard. Header with avatar, name, role (CDL-A · HAZMAT · TANKER · food-grade specialist), rating 4.92, on-time % 99.4%, streak 14 days. KPI tiles (loads, miles, years, safety). Badges grid, Top corridors list with loads count, Shipper spotlight with rating, EsangAI tip, Edit profile / Share card CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Avatar + name + role line | Profile | `profile.getMyProfile` (profile.ts:27); `profile.getDriverProfile` (profile.ts:110) | |
| Endorsements row (CDL-A/HAZMAT/TANKER) | Certifications | `profile.getCertifications` (profile.ts:164); `certifications` table (schema.ts:1609) | |
| Rating 4.92 | Aggregate rating | `ratings.getMySummary` (ratings.ts:232) | |
| On-time % | Performance metric | `drivers.getPerformanceMetrics` (drivers.ts:544); `drivers.getScorecard` (drivers.ts:1402) | |
| 14-day streak pill | Gamification streak | `gamification.getStats` (gamification.ts:631); `gamificationProfiles` table (schema.ts:2343) | |
| KPI tiles (Loads / Miles / Years / Safety "0 inc.") | Aggregates | `drivers.getDashboardStats` (drivers.ts:129); `safetyIncidents` table (schema.ts:1545) | |
| Badges grid "12 of 24" | Earned badges | `gamification.getBadges` (gamification.ts:528); `userBadges` table (schema.ts:2304) | |
| Top corridors list | Lane stats | `drivers.getPreferredLanes` (drivers.ts:2077) | |
| Shipper spotlight (Wawa review quote) | Recent review | `ratings.getReviews` (ratings.ts:112) | |
| EsangAI "New 5.0 review" card | AI summary | GAP | No profile-specific AI summarizer. |
| Edit profile | Mutate | `profile.updateProfile` (profile.ts:59); `profile.updateAvatar` (profile.ts:90) | |
| Share card | Share | GAP | No "share profile card" / short-link generator procedure. |
| Bottom tab bar | Navigation | n/a | |

### Backend GAPS (numbered)
1. No shareable-profile-card / short-link procedure.
2. No AI profile-summary generator for the EsangAI card.
3. No "featured review" selection / pinning procedure on ratings router.
4. "Haz Safe" / "Iridium 5 YR" / "100K MI 2026" / "200 LOADS" badges appear to be trucking-specific — verify seeded `badges` rows exist (`badges` table schema.ts:2265) — GAP if not seeded.

### User-journey entry points
- Bottom tab "Me" → `profile.getMyProfile`.
- Deep link from shipper/dispatcher viewing driver (`profile.getDriverProfile` with driverId).
- Share-card URL → public profile view (currently no public procedure).
Required backend state: `users` + `drivers` row; optional `certifications`, `userBadges`, `ratings`, `gamificationProfiles` rows.

---

## 095 Notifications.png
**Swift port:** GAP.
**Purpose:** Notifications inbox with unread counter, filter tabs (All / Loads / Money / Safety / Crew), today + earlier sections, action pills on specific items, EsangAI contextual summary at bottom, Preferences + Mark-all-read CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header unread chip ("5 unread") | Counter | `notifications.getUnreadCount` (notifications.ts:443); `notifications.getSummary` (notifications.ts:22) | |
| "PREFS SYNCED" chip | Pref sync state | `notifications.getPreferences` (notifications.ts:277) | |
| Filter tabs (All / Loads / Money / Safety / Crew) | Category filter | `notifications.getCategoryCounts` (notifications.ts:140); `notifications.list` with `category` (notifications.ts:51) | |
| Notification row (review, offer, settlement, FSC bump, crew chat) | List items | `notifications.list` (notifications.ts:51) | Backed by `notifications` table (schema.ts:937). |
| "Pin to profile" / "14:22m to Harrisburg" / "View detail" inline CTAs | Deep-link actions | GAP | No "notification inline action" payload schema in `notifications.ts`. |
| Swipe-to-archive (not shown but implied) | Archive | `notifications.archive` (notifications.ts:226) | |
| EsangAI bottom summary bar | AI digest | GAP | No notification-summarizer procedure. |
| Preferences button | Navigate | `notifications.updatePreferences` (notifications.ts:337) | |
| Mark all read button | Bulk action | `notifications.markAllAsRead` (notifications.ts:198) | |

### Backend GAPS (numbered)
1. No structured inline-action payload on notification rows.
2. No AI notification-digest procedure.
3. No per-category mute/preference schema explicitly surfaced (general prefs only).
4. No realtime subscription procedure (WS/SSE) — client must poll `list`.

### User-journey entry points
- Bell icon → `notifications.list`.
- Push notification tap → deep link by `notifications.getById` (not present — GAP).
- From preferences-update confirmation → `notifications.updatePreferences`.
Required backend state: `notifications` rows for `ctx.user.id`, `notificationPreferences` row (schema.ts:2471).

---

## 096 Detention.png
**Swift port:** GAP.
**Purpose:** Detention claim screen with big clock (0:18 over / 2:47 over), status pills (Pending Review / Approved $62.50), load card, dock-time-vs-free-time progress bar, claim breakdown rows, owed amount, Evidence-attached grid (dock photo / GPS pings / BOL scan + "Add"), EsangAI context, optional dispute/submit flows (implicit from status).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header with claim id + filed time + status pill | Claim | `detentionAccessorials.getDetentionDashboard` (detentionAccessorials.ts:129); `detentionAccessorials.getActiveDetentions` (detentionAccessorials.ts:256); table `detentionClaims` (schema.ts:5121) + `detentionRecords` (schema.ts:5745) | |
| Countdown "X:YY OVER" | Derived | n/a | Computed from free-time + dock arrival. |
| Yara Lancaster ops · Trip TR-08512 card | Load/facility | `loads.getById`; `facilities.*` | |
| Dock-time-vs-free-time progress | Visualization | `detentionAccessorials.calculateDetention` (detentionAccessorials.ts:355) | |
| Claim breakdown rows (Dock arrival / Free-time expired / BOL released / Over free @ $50/hr) | Line items | `detentionAccessorials.calculateDetention` (detentionAccessorials.ts:355) | |
| Owed amount | Total | calc procedure | |
| Evidence cards (dock photo / GPS pings / BOL scan / Add) | Attached evidence | GAP | No explicit "detention evidence attach" procedure; `documents.upload` could be reused but no linking schema. |
| Add evidence CTA | Upload | `documents.upload` (documents.ts:176) partial | |
| Status pill "Pending Review" / "Approved" | State | `detentionAccessorials.disputeDetention` (detentionAccessorials.ts:511); `detentionAccessorials.invoiceDetentionCharge` (detentionAccessorials.ts:1431) | No explicit "approve claim" procedure — likely covered by batch approval. |
| EsangAI note ("dock has been clean lately…") | AI context | GAP | No detention-specific AI procedure. |

### Backend GAPS (numbered)
1. No evidence-to-detention linking schema / procedure (photo/GPS/BOL bundle).
2. No driver-initiated "approve/submit detention claim" mutation (only `disputeDetention`).
3. GPS-ping evidence must draw from `gpsTracking` (schema.ts:906); no procedure extracts the relevant window automatically.
4. No AI-context procedure for detention narrative.
5. Status enum for `detentionClaims` not surfaced as a controlled vocabulary in the router.

### User-journey entry points
- Notification "Detention auto-filed at BOL clear" → deep link.
- Home screen "Active detention" tile → `detentionAccessorials.getActiveDetentions`.
- Post-delivery auto-generation after BOL capture (needs wiring).
Required backend state: `detentionClaims` row linked to `loads.id` + `users.id`, facility row, BOL/dock arrival timestamps.

---

## 097 Accessorial.png
**Swift port:** GAP.
**Purpose:** Accessorial submission screen. Draft card with status + amount. Shipper/load card. Type selector grid (Layover / Extra stop / Lumper / Weight / Assist / Other). Amount rows (Quantity / Rate / Request total). Note-to-ops text. Receipts attachments ("OCR matched 2 of 2"). Submit flow implicit.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "NEW ACCESSORIAL" + status pill (DRAFT / APPROVED) + amount | Accessorial record | `detentionAccessorials.getAccessorialCatalog` (detentionAccessorials.ts:660); `detentionAccessorials.applyAccessorial` (detentionAccessorials.ts:712); `accessorial.submitClaim` (accessorial.ts:141) | Two overlapping routers. |
| "Net-15 policy. OCR prefilled from receipt" subtext | OCR + policy | `accessorial.submitClaim`; `documents.digitize` (documents.ts:244) | |
| Shipper/load card | Ref | `loads.getById`; `customers.*` | |
| Type selector (Layover / Extra stop / Lumper / Weight / Assist / Other) | Type enum | `detentionAccessorials.getAccessorialCatalog` (detentionAccessorials.ts:660) | Must be driven by `accessorialCatalog` data; schema table not explicit. |
| Quantity input | Input | n/a | |
| Rate input | Input | `detentionAccessorials.configureAccessorialRate` (detentionAccessorials.ts:690) provides rate; per-type rate lookup | |
| Request total | Derived | Computed client-side | |
| Note to ops textarea | Comment | `accessorial.submitClaim` input | |
| Receipts grid (Lumper receipt / Dock mgr sig / +) | Attachments | `documents.upload` (documents.ts:176); no dedicated accessorial-receipt schema — GAP for link table. |
| Approved amount (in dark/approved variant) | Approval result | `accessorial.updateClaimStatus` (accessorial.ts:295) | |
| OCR match badge "OCR matched 2 of 2" | OCR confidence | `documents.digitize` (documents.ts:244) | No surfaced confidence field on receipt row. |

### Backend GAPS (numbered)
1. Two competing routers (`accessorial.ts` and `detentionAccessorials.ts`) — canonical submission path ambiguous.
2. No explicit driver-facing `accessorial.submit` with Layover/Lumper/Weight/Assist/Other type enum (catalog-driven only).
3. No receipt-to-accessorial link schema; attachments reuse generic `documents`.
4. OCR confidence / match count field not exposed in a procedure.
5. No per-shipper accessorial policy lookup (Net-15 text is static).

### User-journey entry points
- Trip detail → "Add accessorial" → new draft.
- BOL capture completes → auto-prefill draft (notification triggers).
- Dispatch assignment includes lumper line → driver confirms.
Required backend state: `loads` row in progress, `customers`/shipper policy, at least one receipt in `documents`.

---

## 098 BOL Capture.png
**Swift port:** GAP.
**Purpose:** Live camera BOL capture. Status pills (Live Capture / Closed). Live preview frame. Lighting/Focus/Edges quality bars. OCR fields (BOL #, trip, shipper/cnsg, pieces/weight) with "Pre-fill ready". EsangAI tip ("Edges locked at 88%… shutter will fire auto"). Retake / Capture & attach CTAs. Dark variant shows "Download PDF" (post-capture).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Live capture / Closed status pills | State | `bol.generate` (bol.ts:374); `bol.list` (bol.ts:305) | |
| Shipper ribbon ("Wawa Inc - Food-grade") | Context | `loads.getById`; `customers.*` | |
| Live preview image area | Camera | n/a | Client-only. |
| Lighting / Focus / Edges quality bars | On-device metrics | GAP | No backend; client-side ML (CoreML/Vision). |
| OCR field readout (BOL #, trip, shipper, pieces/weight) | OCR result | `documents.digitize` (documents.ts:244) | Returns text; dedicated BOL OCR schema GAP. |
| "Pre-fill ready" / "Confirmed" / "OCR confidence 99.4%" chip | Confidence | GAP | Confidence field not surfaced. |
| EsangAI auto-shutter guidance | AI | GAP | No "capture guidance" procedure. |
| Retake button | Client action | n/a | |
| Capture & attach button | Upload + link | `bol.generateBOLFromLoad` (bol.ts:1067) or `documents.upload` (documents.ts:176) | |
| Download PDF (dark variant, post-capture) | Get PDF | `documents.getFileData` (documents.ts:299); `bol.generate` | |
| Archive chip ("BOL ARCHIVED") | Storage state | `documents.*` | |

### Backend GAPS (numbered)
1. No BOL-specific OCR procedure returning structured fields (bol#, shipper, pieces, weight).
2. No OCR confidence field in response.
3. No "attach BOL to load" linking procedure (document↔load link is implicit through metadata).
4. No archive-and-hash procedure for BOL (document hashing exists `documentHashes` schema.ts:1006 — not wired via router).

### User-journey entry points
- Post-pickup flow from 017 PickupBolSigning → BOL capture.
- From accessorial/detention "Need BOL evidence" deep link.
- From Trip Wrap "Missing BOL" warning.
Required backend state: active `loads` with status=picked-up; driver on-duty; camera permission.

---

## 099 Trip Wrap.png
**Swift port:** GAP.
**Purpose:** End-of-trip wrap screen. Draft/Submitted/Archived pills. Trip header (Tampa FL → Lancaster PA). Tiles (miles, drive time, gross, RPM). Shipper rating stars (Dock / Ops comms / Pay terms / Safety). Comment textarea. Gamification earned pills (+72 XP earned / 13 day streak / food-grade 50). Pay card ("Marcus Hook reload - $740"). EsangAI "50-load food-grade milestone" card. Skip rating / Submit & finish CTAs. Archived variant shows "Done" + "Submitted" timestamp.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Draft / Submitted / Archived pill | State | `loadLifecycle.transitionState` (loadLifecycle.ts:3021) | |
| Trip header | Load meta | `loads.getById` (loads.ts:1012) | |
| Miles / Drive / Gross / RPM tiles | Aggregates | `loads.getTimeline` (loads.ts:1507); `earnings.list` | |
| 5-star rating sliders (Dock / Ops comms / Pay terms / Safety) | Rating submit | `ratings.submit` (ratings.ts:155) | 4-dimension rating fields not explicit in schema — GAP. |
| Comment textarea | Text | `ratings.submit` | |
| XP/streak/specialty chips | Gamification events | `gamification.getStats`; `gamification.getMissions` (gamification.ts:679); `missionProgress` table (schema.ts:2236) | |
| "Marcus Hook reload $740" next-load card | Next offer | `loads.getMarketplaceLoads` (loads.ts:2866); `drivers.getPendingLoads` (drivers.ts:1141) | |
| EsangAI milestone card | AI context | GAP — no milestone-detection procedure. |
| Skip rating | Skip | No-op (no procedure call) | |
| Submit & finish | Submit | `ratings.submit` + `loadLifecycle.executeTransition` (loadLifecycle.ts:2247) | Two mutations needed in sequence. |
| Done (archived) | Close | n/a | |

### Backend GAPS (numbered)
1. `ratings.submit` schema likely lacks the 4 distinct dimension fields shown (dock/ops comms/pay terms/safety).
2. No single atomic "wrap trip" procedure bundling rating + lifecycle transition + mission-progress fire.
3. Milestone-detection for EsangAI card has no procedure.
4. No next-best-load recommender procedure tied to trip-wrap context (uses generic marketplace).

### User-journey entry points
- From 021 At Receiver Gate → delivered → wrap.
- Push notification "Trip ready to wrap" 12 hrs post-delivery.
- Wallet/Trip history tap on unwrapped trip.
Required backend state: `loads` status=delivered, no existing `ratings` row from this user on this load.

---

## 100 Itinerary.png
**Swift port:** GAP.
**Purpose:** Multi-stop itinerary view. Active/Archived pill. Trip header (multi-leg). Map/line visualization. Ordered stop list with status (Wawa Tampa-pickup / Wawa Lancaster-drop / Pilot Carlisle-fuel / Yara North America-reload). Aggregates (miles, drive, stops, ETA last). EsangAI tip ("skip the truck wash…"). Re-optimize / Mark-fuel-stop-done CTAs. Archived variant → Open trip log.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Active/Archived pill | State | `loadLifecycle.getStateMachine` (loadLifecycle.ts:2127) | |
| Trip header "Fri haul — Tampa → Lancaster → M.Hook" | Load/leg meta | `loads.getById` (loads.ts:1012); `loadRelayLegs` (schema.ts:498) | |
| Map / route line | Geometry | `routing.calculateRoute` (routing.ts:70); `loadRoutes` (schema.ts:5704) | |
| Stops list with origin/drop/fuel/reload | Stops | `loads.getTimeline` (loads.ts:1507); `loadStops` (schema.ts:413); `routeWaypoints` (schema.ts:2932) | |
| Per-stop ETA and leg metrics | Routing | `routing.getHOSRoutePlan` (routing.ts:201) | |
| Fuel stop with gal/price | Fuel plan | `routing.getFuelStops` (routing.ts:328) | |
| Aggregates (miles / drive / stops / ETA last) | Derived | `routing.calculateRoute` | |
| EsangAI suggestion | AI | GAP — no itinerary-specific AI. |
| Re-optimize button | Re-route | `routing.optimizeRoute` (routing.ts:276) | |
| Mark fuel stop done | Stop completion | GAP — no explicit "markStopComplete" procedure (only lifecycle transitions). |
| Open trip log (archived) | Nav | `loads.getTimeline` (loads.ts:1507) | |

### Backend GAPS (numbered)
1. No `markStopComplete` / `completeStop` procedure — must use generic `loadLifecycle.executeTransition`.
2. No itinerary-scoped AI advisory procedure.
3. No persistence of user re-optimization preferences.
4. Multi-drop schema mix: `loadStops` + `routeWaypoints` + `loadRelayLegs` — canonical source unclear.

### User-journey entry points
- Trip card → Itinerary tab.
- Dispatch push "Itinerary updated".
- From 013 ActiveEnroute → "View itinerary".
Required backend state: `loads` with ≥2 stops, `routes`/`loadRoutes` row, driver assigned.

---

## 101 Weigh Bypass.png
**Swift port:** GAP.
**Purpose:** Real-time weigh-station approach screen. Big status card (BYPASS / PREPASS GREEN / distance to scale). Verdict line. PA-283 W Lancaster scale card. Carrier-fitness card (FMCSA SMS score 96 · Satisfactory · Qualified / Clean for 23 months). Today's stations-cleared list. Next trip station preview. EsangAI tip. Ack / Log pass CTAs. Trip-summary variant shows "7 bypass / 1 pulled" + History / View receipts CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Big verdict card (BYPASS / PULL-IN) + distance | PrePass status | `driverMobile.getPrePassStatus` (driverMobile.ts:1035); `driverMobile.getWeighStationAlerts` (driverMobile.ts:990) | |
| Scale card (PA-283 W Lancaster) | Scale meta | `scales.list` (scales.ts:64); `scales.getNearby` (scales.ts:72) | |
| Carrier fitness (FMCSA SMS 96 · Satisfactory + Qualified chip) | FMCSA pull | `fmcsa.*`; `hzCarrierSafety` table (schema.ts:6232) | |
| Today's stations cleared list | History | GAP — no "today's scale events cleared" procedure. |
| Next-trip-station preview | Prediction | GAP — no forward-looking scale-prediction procedure. |
| EsangAI driving tip | AI | GAP. |
| Ack button | Acknowledge | GAP — no `scales.ackBypass` procedure. |
| Log pass button | Record pass | GAP — no `scales.logBypass` / `scales.logPass` procedure. |
| Trip summary "7 bypass / 1 pulled" | Aggregate | GAP. |
| History / View receipts | Nav | GAP — no PrePass receipts procedure. |

### Backend GAPS (numbered)
1. No scale-event log procedure (bypass vs pull-in vs cleared).
2. No trip-level weigh-pass aggregate procedure.
3. No per-station historical "streak" / clean-months metric.
4. No PrePass receipts procedure / storage.
5. FMCSA `SMS score` live-pull not a dedicated driver-facing procedure (admin-only via `fmcsa.*`).

### User-journey entry points
- Geofence approach alert (within N miles of scale).
- From active-enroute screen → "Weigh bypass" card.
- Notification "PrePass status changed".
Required backend state: active `loads`, driver HOS on-duty, `hzCarrierSafety` record, integration connection to PrePass/Drivewyze in `integrationConnections` (schema.ts:3802).

---

## 102 ELD Duty Log.png
**Swift port:** GAP.
**Purpose:** ELD duty-status dashboard. Header HOS status + timestamp (DRIVING · LIVE / SLEEPER BERTH). Current-duty card with time left / target. 11hr drive / 14hr on-duty / 8 since break / 70hr cycle progress bars (color-coded). Grid graph (0–24h with OFF/SLB/DRIV/OD rows). Last 4 status changes list. 70hr · 8-day cycle card. EsangAI tip ("Break clock is the binding limit…"). Archived variant shows restart target + "RESTART IN PROGRESS" / post-34hr reset.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Current duty status header (DRIVING / SLEEPER BERTH) + since time | HOS | `hos.getCurrentStatus` (hos.ts:50); `drivers.getMyHOSStatus` (drivers.ts:822); `eld.getDriverStatus` (eld.ts:232) | |
| "Heading to…" subtext | Current load | `drivers.getCurrentLoad` (drivers.ts:215) | |
| Time-left / target chip | Countdown | Derived from HOS | |
| 11hr / 14hr / 8 since break / 70hr cycle progress bars | Clock state | `hos.getCurrentStatus`; `hos.getDailyLog` (hos.ts:114) | Granular fields (since-last-break) not explicit. |
| Grid graph (24h x 4 duty statuses) | Daily log | `hos.getDailyLog` (hos.ts:114); `eld.getLogs` (eld.ts:163) | |
| Last 4 status changes list | Event log | `hos.getLogHistory` (hos.ts:146) | |
| 70hr · 8-day cycle progress card (Healthy/Warning) | Cycle metric | `hos.getCurrentStatus` | |
| EsangAI tip | AI | GAP — no HOS-specific AI suggestion procedure. |
| Archived / restart-in-progress variant | Restart state | GAP — no explicit 34-hr restart tracker procedure. |
| Status-change CTA (implicit - tap to edit) | Mutation | `hos.changeStatus` (hos.ts:93); `drivers.changeHOSStatus` (drivers.ts:1537) | Two overlapping paths. |
| Certify log (end of day) | Sign | `hos.certifyLog` (hos.ts:185) | |
| Add remark | Annotate | `hos.addRemark` (hos.ts:194) | |
| Violations (not shown if none, but implied) | Alerts | `hos.getViolations` (hos.ts:203); `drivers.getHOSViolations` (drivers.ts:1532) | |

### Backend GAPS (numbered)
1. No 34-hr restart tracker procedure (target time, in-progress state).
2. "Since last break" (8hr) calculation not a surfaced field on `hos.getCurrentStatus`.
3. AI HOS-coaching procedure not wired.
4. Two duplicated status-change paths (`hos.changeStatus` vs `drivers.changeHOSStatus`) — canonical choice unclear.
5. Per-trip HOS plan vs live log comparison (planned vs actual) not present.

### User-journey entry points
- Bottom tab → HOS / ELD.
- Geofence (pickup/drop) triggers auto status-change (e.g., On-duty when entering gate).
- Notification "HOS: 30 min left until break".
- From 019 HosDutyStatus.
Required backend state: `drivers` row, connected ELD provider (`integrationConnections`), today's HOS rows via `eld.getLogs`, current `loads` assignment optional.

---

## Summary
- **Screens audited:** 13 (090–102).
- **Swift ports present:** 0 / 13 (0%) — all 13 are GAP; Driver folder ends at 022.
- **Fully backed (every element maps cleanly):** 0.
- **Mostly backed (≥70% elements map, isolated gaps):** 8 — 090, 091, 092, 094, 095, 097, 099, 102.
- **Partially backed (significant holes):** 3 — 093 (tax), 098 (BOL OCR), 100 (itinerary stop-complete).
- **Largely unbacked:** 2 — 096 (detention evidence linking), 101 (weigh bypass events).
- **Approximate element-level coverage:** ~62% of enumerated UI elements map to a concrete procedure; ~38% are GAP or rely on generic reuse.

### Top 3 systemic gaps
1. **EsangAI contextual cards**: 12 of 13 screens surface an in-context AI tip/explanation; no router exposes a screen-scoped advisor procedure (`esangAI.*`/`esangAIv2.*` exist but don't match these UI surfaces). Implement per-surface AI context procedures or a single `esangAI.getContext({screen, entityId})`.
2. **Evidence/receipt↔claim linking**: Detention (096), Accessorial (097), BOL Capture (098), and Settlement (092) all show photo/receipt/GPS evidence tied to a parent claim/settlement, but there is no link schema or join procedure. Generic `documents.upload` is the only path; need a typed `claimEvidence` schema + CRUD procedures.
3. **Weigh-bypass / scale-event logging (101)**: Entire screen has no backend coverage for pass/pull logging, streak metrics, PrePass receipts, or per-trip aggregation. `scales.ts` is read-only (`list`/`getNearby`).

### Top 3 mid-tier gaps
4. **34-hr restart tracker + per-break counters** missing on `hos.ts` (102).
5. **Duplicated driver-action routers** (`drivers.acceptLoad` vs `loads.book`; `hos.changeStatus` vs `drivers.changeHOSStatus`; `accessorial.ts` vs `detentionAccessorials.ts`) need canonical-path decisions.
6. **Shareable assets** (driver profile card share, tax vault export, trip-wrap atomic submit) all lack dedicated procedures.

### Required backend state (common)
All 13 screens require: authenticated `users` row with role `DRIVER` via `auditedOperationsProcedure` / `isolatedProcedure` context; a current `drivers` row; and an `integrationConnections` row for the ELD provider to avoid stubbed HOS data (`eld.getDriverStatus`).
