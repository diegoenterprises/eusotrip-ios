/**
 * Wave-4 · Build Agent #6 · Theme 2.7
 *
 * Drizzle schema additions for the notifications mutation surface.
 *
 * These additions are NOT to be pasted into the canonical `schema.ts` by this
 * agent — the changelog in agent_06.md lists the exact re-export entries that
 * `schema.ts` needs to pull in from this file, which the schema-owner agent
 * will merge.
 */

import {
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uuid,
  boolean,
  index,
} from 'drizzle-orm/pg-core';
import { users } from './schema'; // existing base table
import { notifications as baseNotifications } from './schema';

// ─── Enums ───────────────────────────────────────────────────────────────────
export const notificationChannelEnum = pgEnum('notification_channel', [
  'dispatch',
  'ops',
  'safety',
  'hos',
  'marketing',
  'ai_coach',
]);

export const notificationDraftStatusEnum = pgEnum('notification_draft_status', [
  'draft',
  'sent',
  'discarded',
]);

// ─── Column additions for `notifications` (declared here for reference; the
//    live `notifications` table in schema.ts needs three new columns added
//    in-place — see changelog) ─────────────────────────────────────────────
export const notificationsColumnAdditions = {
  snoozedUntil: timestamp('snoozed_until', { withTimezone: true }),
  channel: notificationChannelEnum('channel'),
  sourceDraftId: uuid('source_draft_id'),
};

// ─── notification_channel_preferences ────────────────────────────────────────
export const notificationChannelPreferences = pgTable(
  'notification_channel_preferences',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    channel: notificationChannelEnum('channel').notNull(),
    enabled: boolean('enabled').notNull().default(true),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.userId, t.channel] }),
  }),
);

export type NotificationChannelPreference =
  typeof notificationChannelPreferences.$inferSelect;
export type NewNotificationChannelPreference =
  typeof notificationChannelPreferences.$inferInsert;

// ─── notification_drafts ─────────────────────────────────────────────────────
export const notificationDrafts = pgTable(
  'notification_drafts',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    authorUserId: uuid('author_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    toUserId: uuid('to_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    channel: notificationChannelEnum('channel').notNull(),
    body: text('body').notNull(),
    status: notificationDraftStatusEnum('status').notNull().default('draft'),
    createdAt: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => ({
    byAuthorStatusUpdated: index(
      'idx_notification_drafts_author_status_updated',
    ).on(t.authorUserId, t.status, t.updatedAt),
    byToStatus: index('idx_notification_drafts_to_status').on(
      t.toUserId,
      t.status,
    ),
  }),
);

export type NotificationDraft = typeof notificationDrafts.$inferSelect;
export type NewNotificationDraft = typeof notificationDrafts.$inferInsert;

// Re-export the base `notifications` reference so downstream files can pull
// the augmented type from one place.
export { baseNotifications as notifications };
