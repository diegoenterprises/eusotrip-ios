# Backend Endpoint ↔ Screen Map

**Source of truth for endpoints:** `EusoTrip/Services/EusoTripAPI.swift` (confirmed, live, Azure backend at `eusotrip-app.azurewebsites.net`).
**Cross-reference:** `_WAVE3_AUDIT/_MASTER_ROADMAP.md` (286 tRPC routers across web + iOS; iOS currently consumes ~25).

---

## 1. tRPC client surface (iOS-consumed endpoints)

These are all implemented in `EusoTripAPI.swift` and callable today.

| Router | Procedure | File line | Consumed by screen(s) |
|---|---|---|---|
| auth | login, me, logout, forgotPassword, resetPassword | 540, 553, 558, 564, 570 | 001_SignIn, 003_ForgotPassword, 004_ResetPassword |
| auth | register{Driver,Shipper,Catalyst,Broker,Dispatch,Escort}, verifyEmail, resendVerification | 608–705 | 002_CreateAccount |
| loads | search, getById | 393, 411 | 010_DriverHome (active load) |
| hos | getStatus, getCurrentStatus, changeStatus, getDailyLog, getLogHistory, certifyLog, addRemark, getViolations | 423–527 | 019_HosDutyStatus, HOSLiveStore |
| inspections | getTemplate, submit, getHistory, getPrevious, getOpenDefects, createDVIR, getDVIRHistory, getDVIRCategories | 718–801 | 011_PretripDVIR, 012_DvirSubmitted (partial) |
| esangAIv2 | chat, clearHistory | 855, 876 | DriverConversationView, ESANG coach (partial) |
| wallet | createPlaidLinkToken, exchangePlaidPublicToken, createStripeSetupIntent, attachStripePaymentMethod, getBalance, getInstantPayoutEligibility | 923–1017 | AddPaymentAccountSheet (Plaid+Stripe), DriverWalletPane (partial) |
| loadLifecycle | executeTransition | 1069 | Trip lifecycle 013–050 (partial) |
| loadWizard | start, advanceStep, recordEvidence, complete, abort, getSession | 1154–1216 | Pickup/Delivery wizards 014–025 (not fully wired) |
| notifications | updatePreferences, getPushSettings | 1242, 1270 | MeNotificationsView |
| loadsDriver | acceptLoad, declineLoad, getPendingLoads, getActiveTender, counterOffer, getRateConURL | 1294–1430 | 052_RateconTender, pending-load flows |
| news | getArticles, cacheStatus, getTrending, getMorningBrief, getBreakingNews, saveArticle, unsaveArticle, getSavedArticles | 1457–1511 | MeNewsView |
| messaging | getConversations, getMessages, sendMessage, markAsRead, getUnreadCount, search, searchUsers, createConversation, delete, archive, uploadAttachment, sendPayment, unsendMessage, getUserPhone | 1546–1743 | MessageHub (partial — inbox thread list still seeded in places) |
| hotZones | getRateFeed | 1906 | HotZonesWidget, HotZonesDetailSheet |
| eld | getAllProviders, getConnectionStatus, getProviderConfig, connectProvider, disconnectProvider | 2068–2128 | ELDIntegrationView |

Plus HERE Maps (not tRPC): `Services/HereMaps/{HereGeocodingClient, HereRoutingClient, HereMatrixClient, HERAuthService, HereTileOverlay}` — all live against HERE Developer API.

---

## 2. Screens and where they stand

Grouped by wire status. Mobile screen count per `_WAVE3_AUDIT/_MASTER_ROADMAP.md`: 121 driver figmas, 44 ported to SwiftUI today.

### A. Fully live (backend + UI wired)

| Screen | File | Endpoint(s) |
|---|---|---|
| 001 Sign In | Views/Auth/001_SignIn.swift | auth.login |
| 002 Create Account | Views/Auth/002_CreateAccount.swift | auth.register{Role} |
| 003 Forgot Password | Views/Auth/003_ForgotPassword.swift | auth.forgotPassword |
| 004 Reset Password | Views/Auth/004_ResetPassword.swift | auth.resetPassword |
| 005/006 Terms / Privacy | Views/Auth/005/006 | static text — no endpoint needed |
| 010 Driver Home | Views/Driver/010_DriverHome.swift | loads.search, hos.getStatus, loads.getById (active load + HOS) |
| 011 Pretrip DVIR | Views/Driver/011_PretripDVIR.swift | inspections.getTemplate, inspections.createDVIR |
| 012 DVIR Submitted | Views/Driver/012_DvirSubmitted.swift | inspections.submit |
| 019 HOS Duty Status | Views/Driver/019_HosDutyStatus.swift | hos.getCurrentStatus, hos.changeStatus, hos.getDailyLog, hos.certifyLog |
| HotZones widget | Views/Driver/HotZonesWidget.swift | hotZones.getRateFeed |
| MeNewsView | Views/Driver/MeNewsView.swift | news.* (articles, saved, morning brief) |
| MeNotificationsView | Views/Driver/MeNotificationsView.swift | notifications.*, push.getSettings |
| AddPaymentAccountSheet | Views/Driver/AddPaymentAccountSheet.swift | wallet.createPlaidLinkToken, wallet.createStripeSetupIntent |
| ELDIntegrationView | Views/Driver/ELDIntegrationView.swift | eld.* |
| WeatherCard | Views/Components/WeatherCard.swift | weather (via WeatherService) |
| 052 Ratecon Tender | Views/Driver/052_RateconTender.swift | loadsDriver.getActiveTender, acceptLoad, declineLoad |

### B. Endpoint exists, UI still on seeded arrays — Phase 1 rewire candidates

| Screen / Surface | File | Endpoint(s) ready | Notes |
|---|---|---|---|
| Eusoboards loads board | DriverTabPanes.swift:96 | loads.search | Swap `board` → `@StateObject LoadBoardStore` |
| My Loads sheet (all 3 buckets) | DriverTabPanes.swift:1296,1673 | loads.search(status:) | Duplicated in 2 places — consolidate |
| Driver Home suggested-loads carousel | 010_DriverHome.swift:67 | loads.search | Use the same live board feed |
| EusoWallet hero balance | DriverTabPanes.swift:2021 | wallet.getBalance | `$4,118.22` → live amount |
| EusoWallet payment methods | DriverTabPanes.swift:2078 | wallet list (via Plaid/Stripe attach records) | Needs a `wallet.listPaymentMethods` aggregator — near-close; tag as P2 |
| MeZeun DVIR entries | MeDetailScreens.swift:1954 | inspections.getHistory | Direct swap |
| MeTax inspection-ish entries | MeDetailScreens.swift:384 | inspections.getHistory | Rework when tax surface lands |
| Dispatch / Driver-lobby chat | MeDetailScreens.swift:3052 | messaging.getMessages | Needs a room_id contract |
| Inbox thread list | DriverTabPanes.swift:3131 | messaging.getConversations | Structure already aligned |
| ESANG coach transcript | DriverTabPanes.swift:3733 | esangAIv2.chat | Chips' canned replies become server responses |
| Pretrip checks (028) | 028_LoadLockedPrehaul.swift:60 | loadWizard.start / getSession | Shape of `checks` already matches wizard step |
| Pickup steps (029) | 029_PickupArrival.swift:78 | loadLifecycle.executeTransition | Same |
| BOL metrics (033) | 033_BolSignoff.swift:84 | loadWizard.recordEvidence | Same |
| 017 driver name | 017_PickupBolSigning.swift:35 | auth.me | One-line swap |

### C. Endpoint MISSING — Phase 2 (small server-side tweaks expected to ship soon per Wave 4)

| Screen / Surface | Needed endpoint | Status |
|---|---|---|
| Wallet transactions list | `wallet.getTransactions({filter, cursor})` | Missing — design simple paginated router |
| Wallet weekly history / YTD | `wallet.getEarningsSummary` | Missing |
| Settlement preview | `wallet.getSettlementPreview` | Missing |
| Factoring offer | `factoring.getOffer(loadId)` | Missing |
| Rewards catalog | `rewards.getCatalog`, `rewards.redeem` | Missing — small lift |
| Missions / achievements (iOS) | `achievements.*` | **Routers exist** in `_WAVE4_BUILD/server/routers/achievements.ts` — only the Swift adapter is missing |
| Tax / 1099 summary | `tax.getSummary`, `tax.get1099` | Missing — `_WAVE4_BUILD/server/routers/taxReporting.append.ts` drafted |
| Fuel card status | `fuelCard.getStatus`, `fuelCard.getReceipts` | Missing |
| Leaderboard | `leaderboard.getSeason` | Missing |
| Fleet assets | `fleet.listAssets`, `fleet.getMaintenance` | Missing |

### D. Endpoint MISSING — Phase 3 (sizeable backend work per _WAVE3_AUDIT §§2.1–2.4)

| Screen / Surface | Needed endpoint family | Status |
|---|---|---|
| ESANG coach-copy (static callouts across ~60 screens) | `esangAI.getCoachCopy({screen, context})` | Not started — Wave 3 §2.1 |
| Tanker/discharge/disconnect wizards (030, 032, 040, 042–044, 048) | `bayOps/{discharge,disconnectWizard,connectWizard,backingAssist}` | Not started — Wave 3 §2.3 |
| Telemetry (trailer, tank, scale) | `telemetry/{trailerTelemetry, tankMonitor, fuel.getTankStatus, scales.recordWeigh}` | Not started — Wave 3 §2.4 |
| Availability grid & blocks | `availability.*` | Not started |
| Spectra match verdict (031) | `spectra.getVerdict` | Not started |
| Smart-stop amenities (036) | `smartStops.getAmenities` | Not started |
| The Haul gamification presence | `rooms.getPresence` + socket | Not started |

---

## 3. Gap list (consumer-side)

Screens with **zero** backend consumption today, by iOS file:

- All of `MeDetailScreens.swift` except MeZeun (which can quickly wire `inspections.getHistory`).
- All trip-lifecycle screens 013 – 051 except the ones already wired (019, 011, 012).
- `DriverConversationView.swift` (partial — uses esangAIv2.chat for the LLM side but lobby/group chat uses mocked roster).
- Wallet sections §§4–8 in `DriverTabPanes.swift`.

---

## 4. What the roadmap says (from `_WAVE3_AUDIT/_MASTER_ROADMAP.md`)

- Bucket 00 (screens 010–022): 13/13 ported, ~72% backend coverage → this is the "parity reference" where we should treat mocks as bugs.
- Buckets 01–09: 0/108 ported; backend coverage 14%–74%.
- Weighted mobile parity today: **10.7%** (13 of 121 screens) with ~62% backend readiness.
- Bucket 09 (routing/reroute/price-lock/tank-status) is the lowest-coverage band — explicitly earmarked for Phase 3 empty states.

---

## 5. Recommended API abstraction

`EusoTripAPI.swift` exposes everything as methods on a sharded singleton — cleaner than a rewrite. To prevent view files from pulling mocks while wiring: introduce thin `Store` classes (mirroring `HOSLiveStore`, `NewsFeedStore`, `HotZonesStore`) per domain — `LoadsStore`, `WalletStore`, `MessagingStore`, `FleetStore`, `RewardsStore` — each `@MainActor final class … ObservableObject` with `isLoading`, `items`, `lastError`. Views become `@StateObject` consumers with empty-state branches. This pattern already works for News and HotZones.
