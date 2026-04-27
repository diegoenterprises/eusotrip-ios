# Wave-4 Build · Agent #9 · Theme 2.8 — Changelog

**Theme:** Split missions + achievements out of `gamification.ts`; add cash
rewards, HOLD rank-lock, share endpoints, referrals.

**Build date:** 2026-04-18
**Audit source:** `_WAVE3_AUDIT/_MASTER_ROADMAP.md` §2.8 (lines 120-126, 185,
224), `_WAVE3_AUDIT/agent_04.md` (067 Mission, 068 Leaderboard, 069
Achievements, 070 Invite).

---

## 1 · Sources read (cite-trail)

| Path | Lines read | Purpose |
| --- | --- | --- |
| `_WAVE3_AUDIT/_MASTER_ROADMAP.md` | §2.8 L120-126, §"Attack order" L185/L224 | Theme 2.8 scope + proposal statement |
| `_WAVE3_AUDIT/agent_04.md` | full (420 L) | Bucket 04 audit for screens 067-070 |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/schema.ts` | L1-40 (imports), L1790-1853 (wallets, walletTransactions), L2152-2341 (missions, missionProgress, badges, userBadges, userTitles), L2442-2465 (leaderboards) | Authoritative names + enums used by the new router + migration |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/_core/trpc.ts` | L1-100, L97/L331/L407 (procedure factories) | Import source for `isolatedProcedure` / router |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/gamification.ts` | L1-70, L670-720 | Confirmed existing `getMissions` / `getBadges` surface we are carving AROUND (unchanged) |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/wallet.ts` | L30-120 | `ensureWallet()` pattern, transactionType enum |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/users.ts` | L755-780 | Existing `getReferralInfo` stub (untouched per brief) |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/feedback.ts` | full (22 L) | Confirmed stub-router pattern we are NOT following (theme 2.9 owns that rewrite) |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/__tests__/users.test.ts` | full (62 L) | vitest + `appRouter.createCaller` test idiom |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/0100_loadlifecycle_tanker_states.sql` | full (59 L) | Sibling migration style |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/drizzle/schema.additions.wave4-8.ts` | full (164 L) | Sibling schema-additions file style/conventions |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/server/routers/notificationsDraft.ts` | full (244 L) | Sibling router style/conventions |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/drizzle/0140_notifications.sql` | full (110 L) | Sibling migration style (PostgreSQL) |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/agent_01.md` | L1-80 | Changelog template |

---

## 2 · Files created

| Path | Purpose | LOC |
| --- | --- | --- |
| `drizzle/0170_missions_achievements_referrals.sql` | PostgreSQL migration: enums (`mission_status`, `mission_kind`, `referral_status`) + tables `driver_missions`, `rank_locks`, `referrals`. Required `(driver_id, status)` index on `driver_missions`. FKs to `users`, `badges`, `leaderboards`. Partial unique index enforces one referrer per referee. | 199 |
| `drizzle/schema.additions.wave4-9.ts` | Staging drizzle schema file exporting `driverMissions`, `rankLocks`, `referrals` tables + string-literal tuples `MISSION_STATUSES`, `MISSION_KINDS`, `REFERRAL_STATUSES`, `ACHIEVEMENT_RARITIES` and inferred types. Central `drizzle/schema.ts` is NOT edited. | 177 |
| `server/routers/missions.ts` | NEW tRPC router: `listForMe({ status? })`, `getById`, `claim` (active → verifying), `redeem` (verified → completed + wallet payout). Supports `cash_reward` (cents → USD wallet credit via `walletTransactions` type=`bonus`) and `badge` (inserts `userBadges` idempotently). FSM guard rejects illegal transitions. | 336 |
| `server/routers/achievements.ts` | NEW tRPC router: `listMine({ rarity? })`, `getById`, `share` (HMAC-signed 7-day share URL + nonce), `getRarityCounts` returning all five buckets. `deriveRarity()` folds `badges.category` + `tier` + `isRare` into the 5-tier rarity. | 252 |
| `server/routers/referrals.ts` | NEW tRPC router: `getMyCode` (durable 3-letter-3-digit code, persisted on first call), `claim({ code })` (self-claim blocked, idempotent, already-attached rejection, normalizes case), `listMyReferrals`. Replaces the email-prefix stub in `users.getReferralInfo`. | 290 |
| `server/routers/__tests__/missions.test.ts` | vitest suite: listForMe scoping + status filtering, getById ownership guard, claim FSM, redeem cash payout + badge grant + idempotence. | 186 |
| `server/routers/__tests__/achievements.test.ts` | vitest suite: `deriveRarity` unit matrix, listMine owner scoping + rarity filter, getById earned-flag, share HMAC URL + FORBIDDEN-if-unearned + nonce uniqueness, getRarityCounts all-buckets aggregate. | 177 |
| `server/routers/__tests__/referrals.test.ts` | vitest suite: getMyCode durability + shape (`/^[A-Z]{3}-\d{3}$/`), claim happy path + self-claim rejection + idempotence + conflict on re-use + case-insensitive + NOT_FOUND + revoked-BAD_REQUEST, listMyReferrals excluding `pending`. | 196 |

**Total new code: ~1,813 LOC across 8 files.**

## 3 · Files modified

**NONE.** Per the STRICT RULES:

- `server/routers/gamification.ts` — NOT modified.
- `server/routers/advancedGamification.ts` — NOT modified.
- `server/routers.ts` — NOT modified.
- `drizzle/schema.ts` — NOT modified.
- `server/routers/users.ts` (`getReferralInfo` at L761) — NOT modified.
- API contract / frontend — NOT modified.

All central-file edits are listed in section 4 for reviewed manual merge.

---

## 4 · Required central-file edits

### 4a · `server/routers.ts` — mount three new routers

```diff
@@ server/routers.ts (import block) @@
 import { gamificationRouter } from "./routers/gamification";
+import { missionsRouter } from "./routers/missions";
+import { achievementsRouter } from "./routers/achievements";
+import { referralsRouter } from "./routers/referrals";

@@ server/routers.ts (appRouter map) @@
   gamification: gamificationRouter,
+  missions: missionsRouter,
+  achievements: achievementsRouter,
+  referrals: referralsRouter,
```

If `server/routers 2.ts` exists as a parallel index, apply the same two deltas there.

### 4b · `drizzle/schema.ts` — re-export the three new tables

The routers currently import from `../../drizzle/schema.additions.wave4-9`.
When the next wave re-unifies the schema, migrate the three `export const`
blocks plus the four string-literal tuples from
`drizzle/schema.additions.wave4-9.ts` into `drizzle/schema.ts` and:

```diff
@@ drizzle/schema.ts (anywhere after line 2465) @@
+// ============================================================================
+// MISSIONS / ACHIEVEMENTS / REFERRALS — Wave-4 Theme 2.8
+// Source migration: drizzle/0170_missions_achievements_referrals.sql
+// ============================================================================
+export { driverMissions, rankLocks, referrals } from "./schema.additions.wave4-9";
+export { MISSION_STATUSES, MISSION_KINDS, REFERRAL_STATUSES, ACHIEVEMENT_RARITIES }
+  from "./schema.additions.wave4-9";
+export type {
+  DriverMission, InsertDriverMission, DriverMissionProgress,
+  RankLock, InsertRankLock,
+  Referral, InsertReferral,
+  MissionStatus, MissionKind, ReferralStatus, AchievementRarity,
+} from "./schema.additions.wave4-9";
```

Then switch the three new routers to `from "../../drizzle/schema"` and delete
`schema.additions.wave4-9.ts`.

### 4c · `server/routers/users.ts` (L761 `getReferralInfo`) — deprecation notice

`users.getReferralInfo` is intentionally left in place (used by existing
clients). The recommended deprecation path:

1. Add a JSDoc `@deprecated Use `referrals.getMyCode` + `referrals.listMyReferrals`` tag on the procedure.
2. Change the body to proxy to the new router when a DB is available, falling back to the current email-prefix stub otherwise. This avoids behavior breakage for callers we haven't migrated yet.
3. In a follow-up wave: remove callers, then remove the procedure.

No edit is required now — the stub and the new router coexist cleanly.

---

## 5 · Mission behavior that SHOULD eventually migrate out of `gamification.ts`

Not done in this wave — listed per STRICT RULES so the follow-up PR can
batch the moves safely:

| Existing procedure | Reason to migrate | Proposed new home |
| --- | --- | --- |
| `gamification.getMissions` (gamification.ts:679) | Returns template catalog AND per-user state; the per-user state belongs in `missions.listForMe` | split: catalog stays; per-user branch moves |
| `gamification.startMission` (:810) | Instantiates a per-driver mission row | `missions.start({ templateMissionId })` (next wave) |
| `gamification.claimMissionReward` (:880) | Overlaps with `missions.redeem` | deprecate; point UI at `missions.redeem` |
| `gamification.cancelMission` (:1001) | Illegal-transition logic should live next to `assertLegalTransition` | `missions.cancel` (next wave) |
| `gamification.getActiveTripMissions` (:1666) | Redundant with `missions.listForMe({ status: 'active' })` | deprecate |
| `advancedGamification.getWeeklyMissions` (:1387) | Template catalog only — stays | (no move) |
| `advancedGamification.getAchievementProgress` (:1204) | "Next unlock" ETA; belongs in achievements | `achievements.getNextUnlock` (future) |
| `advancedGamification.getRareAchievements` (:1215) | UI already has `rarity` filter via `listMine` — redundant | deprecate |

Rank-lock / HOLD surfacing (screen 068) is intentionally data-only in this
wave: the `rank_locks` table + index exist, and a future `leaderboard.ts`
read endpoint (theme follow-up) will join on `rank_locks.locked_until >
NOW()` to compute the `HOLD` pill. No router code needed today.

---

## 6 · Open questions / follow-ups

1. **Rank-lock writer procedure.** Brief asks for the `rank_locks` table but
   not a write endpoint. Ops will need a `leaderboard.lockRank({ driverId,
   leaderboardId, until, reason })` admin procedure — filed for theme 2.12.
2. **Referral credit worker.** `referrals.claim` attaches the referee but
   does NOT credit either wallet — that's triggered by the `first_haul`
   transition, which needs a load-completion hook. Filed for a separate
   wave-5 worker.
3. **Share-link verifier route.** `achievements.share` emits signed HMAC
   tokens but there is no `/s/:token` edge route yet. Filed for the web
   layer in theme 2.13 (public share pages).
4. **MySQL vs PostgreSQL drift.** The migration is PostgreSQL (to match
   `0140_notifications.sql`, `0160_availability_dvir.sql`). The drizzle
   staging file uses `mysql-core` to match the rest of `drizzle/schema.ts`
   (which is MySQL). When the codebase converges on a single dialect the
   drizzle types will need one uniform rewrite — out of scope here.

---

## 7 · Test-run manifest

| Test file | Describe blocks | it-count |
| --- | --- | --- |
| `missions.test.ts` | listForMe, getById, claim, redeem | 13 |
| `achievements.test.ts` | deriveRarity, listMine, getById, share, getRarityCounts | 15 |
| `referrals.test.ts` | getMyCode, claim, listMyReferrals | 12 |

All tests use `resetDb` + `appRouter.createCaller` helpers following the
pattern established by `__tests__/users.test.ts` and
`_WAVE4_BUILD/server/routers/__tests__/notifications.wave4.test.ts`. The
expected helper additions (`seedDriverMission`, `seedWallet`,
`getDriverMission`, `getWalletBalance`, `seedBadge`, `seedUserBadge`,
`seedReferral`, `getReferralByCode`) are listed below for the helpers
maintainer:

```ts
// server/routers/__tests__/helpers.ts — add to the existing factory set
export async function seedDriverMission(overrides?: Partial<InsertDriverMission>) {...}
export async function getDriverMission(id: string): Promise<DriverMission> {...}
export async function seedWallet(overrides: { userId: number } & Partial<InsertWallet>) {...}
export async function getWalletBalance(userId: number): Promise<Wallet> {...}
export async function seedBadge(overrides?: Partial<InsertBadge>) {...}
export async function seedUserBadge(args: { userId: number; badgeId: number }) {...}
export async function seedReferral(overrides: { referrerUserId: number } & Partial<InsertReferral>) {...}
export async function getReferralByCode(code: string): Promise<Referral> {...}
```

---

## 8 · Deliverables summary

| # | Deliverable | Status |
| --- | --- | --- |
| 1 | `server/routers/missions.ts` — listForMe/getById/claim/redeem with cash + badge support | ✔ |
| 2 | `server/routers/achievements.ts` — listMine/getById/share/getRarityCounts | ✔ |
| 3 | `server/routers/referrals.ts` — getMyCode/claim/listMyReferrals | ✔ |
| 4 | `drizzle/0170_missions_achievements_referrals.sql` migration | ✔ |
| 5 | `drizzle/schema.additions.wave4-9.ts` schema additions | ✔ |
| 6 | `missions.test.ts` | ✔ |
| 7 | `achievements.test.ts` | ✔ |
| 8 | `referrals.test.ts` | ✔ |
| 9 | `gamification.ts` / `advancedGamification.ts` / `routers.ts` / `schema.ts` — NOT edited | ✔ |
| 10 | Migration plan for behavior that should eventually move out of `gamification.ts` | ✔ (see §5) |
