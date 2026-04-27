# Wave-4 Build Agent #6 Report
**Theme:** 2.7 Notifications mutation surface + `notifications.draft` subsurface
**Date:** 2026-04-18
**Scope:** 064 Notifications Inbox · 074 Notification Center · 095 Notifications · 112 Inbox · 113 Thread · 114 Broadcasts

---

## Files produced

Staged under `_WAVE4_BUILD/` so the web-repo owner can drop them into place verbatim.

| Staged path | Target path in web repo | Kind |
|---|---|---|
| `_WAVE4_BUILD/server/routers/notifications.append.ts` | APPEND into `server/routers/notifications.ts` | Code (procedures to merge into existing `createTRPCRouter` literal) |
| `_WAVE4_BUILD/server/routers/notificationsDraft.ts` | `server/routers/notificationsDraft.ts` | New router file |
| `_WAVE4_BUILD/drizzle/0140_notifications.sql` | `drizzle/0140_notifications.sql` | Migration (additive) |
| `_WAVE4_BUILD/drizzle/schema.additions.wave4-6.ts` | Merge into `drizzle/schema.ts` | Drizzle table defs |
| `_WAVE4_BUILD/server/routers/__tests__/notifications.wave4.test.ts` | `server/routers/__tests__/notifications.wave4.test.ts` | Vitest suite |

---

## Procedures added

**In `notifications.ts` (append-only):**
- `snooze({ notificationId, until })` — validates future-only + max +30d, ownership-scoped.
- `clearRead()` — deletes read rows whose `readAt < now-7d` for current user.
- `markAllRead({ channel? })` — bulk mark unread read; optional channel filter.
- `setChannelPreferences({ channel, enabled })` — upsert by `(userId, channel)`.
- `getChannelPreferences()` — returns all six channels with defaults filled (`marketing=false`, everything else `true`).

**In new `notificationsDraft.ts` (mounted as `notifications.draft.*`):**
- `list({ status?, limit? })` — newest-first author-scoped drafts.
- `create({ to, channel, body })` — refuses self-address, checks recipient exists.
- `update({ draftId, patch })` — only while `status='draft'`.
- `send({ draftId })` — transactional: flips draft to `sent` and inserts a real `notifications` row with `source_draft_id` linkage.
- `discard({ draftId })` — soft-closes.

Channel enum (shared): `('dispatch','ops','safety','hos','marketing','ai_coach')`.

---

## Migration `0140_notifications.sql`

- `ALTER TABLE notifications ADD COLUMN snoozed_until TIMESTAMPTZ NULL`.
- `ALTER TABLE notifications ADD COLUMN source_draft_id UUID NULL` (+ FK to `notification_drafts`).
- `ALTER TABLE notifications ADD COLUMN channel notification_channel NULL`.
- New enum `notification_channel` (6 values).
- New enum `notification_draft_status` (`draft`/`sent`/`discarded`).
- New table `notification_channel_preferences` PK `(user_id, channel)` + FK to `users`.
- New table `notification_drafts` with defaulted UUID PK, two FKs to `users`, `CHECK` on non-empty body.
- Indexes: `idx_notifications_user_snoozed` (partial), `idx_notifications_user_channel_created`, `idx_notification_drafts_author_status_updated`, `idx_notification_drafts_to_status`.
- Rollback block kept as a comment.

All statements are `IF NOT EXISTS`/`DO $$` guarded so repeated runs are safe.

---

## Required follow-up edits outside this agent's scope

Per the strict rules, I did **not** edit the master indexes. The schema-owner / router-owner agent needs to apply:

1. **`server/routers/notifications.ts`** (the existing file)
   - Add imports listed in `notifications.append.ts` header (`notificationChannelPreferences` from schema, `NotificationChannelEnum`, `TRPCError`, etc.).
   - Spread `...notificationsWave4Procedures` into the existing `createTRPCRouter({...})` literal.
   - Add `draft: notificationsDraftRouter` key, importing from `./notificationsDraft`.
2. **`server/routers.ts`** (root appRouter) — no change needed; the procedures are reached via the existing `notifications` key.
3. **`drizzle/schema.ts`**
   - Augment the existing `notifications` pgTable with the three columns listed in `notificationsColumnAdditions` (`snoozedUntil`, `channel`, `sourceDraftId`).
   - `export` the two new tables and two new enums from `schema.additions.wave4-6.ts` (either merge or `export * from './schema.additions.wave4-6'`).
4. **`packages/api-contract/src/index.ts`** (tRPC type re-export barrel)
   - Re-export `NotificationChannel` type and the new `notifications.draft.*` router slice. The barrel picks up the rest automatically via `AppRouter`.
5. **Swift client** (`EusoTrip/Services/EusoTripAPI.swift`) — add the six new methods to the `NotificationsService` namespace; not in this agent's scope.

---

## Testing

`notifications.wave4.test.ts` covers 15 cases across snooze (ownership, future-only, 30d cap), clearRead (7d boundary), markAllRead (scoped + global), channel prefs (upsert + defaults + overwrite), and the full draft lifecycle (create / update-guard / send-writes-notification / discard / list-by-status). Assumes the existing `./helpers.ts` factory — no new harness introduced.

---

## Summary (under 300 words)

Theme 2.7 closes the mutation gap the driver inbox has been stuck on. Across six screens (064/074/095/112/113/114) the UI shows SNOOZE, Clear, Mark-all-read, Reply, and channel-pref toggles, but `notifications.ts` only had `list`, `getGroupedByDay`, `archive`, `markAllAsRead`, `updatePreferences`. I added five procedures to the existing router and a new `notifications.draft` subrouter with `list/create/update/send/discard`. The draft `send` is transactional: it flips the draft row to `sent` and, in the same tx, writes a real `notifications` row with a `source_draft_id` back-link so Inbox threads and Ops audits resolve cleanly. Validation is defensive — snooze refuses past timestamps and >30-day futures, drafts refuse self-address, updates/sends/discards all enforce `status='draft'`. A typed `NotificationChannelEnum` (`dispatch|ops|safety|hos|marketing|ai_coach`) replaces the old free-string `category` and is shared between the preferences upsert and the draft composer. Migration `0140_notifications.sql` is fully additive — one partial index on `(user_id, snoozed_until)` to keep the inbox `WHERE snoozed_until IS NULL OR snoozed_until < now()` query hot, plus a composite on `(user_id, channel, created_at DESC)` for the 095 Notifications filter chips. Two new tables: `notification_channel_preferences` (PK `(user_id, channel)`) and `notification_drafts` (UUID PK, dual FKs to `users`, CHECK-nonempty body). Schema types are isolated in `schema.additions.wave4-6.ts` so the schema-owner can merge them without a three-way conflict. I did not edit `routers.ts`, `schema.ts`, or the api-contract barrel — the required edits for those are itemized above. Fifteen vitest cases cover ownership checks, time-window semantics, default preference shape, transactional send, and status-guarded update/discard. Downstream SwiftUI work unblocks screens 064 (SNOOZE + Clear read), 074 / 095 (Mark-all-read + channel chips), 112 (Reply draft), 113 (Draft update + send), and 114 (Snooze broadcast).
