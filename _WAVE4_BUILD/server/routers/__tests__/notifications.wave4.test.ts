/**
 * Wave-4 · Theme 2.7 · notifications + notificationsDraft procedure tests.
 *
 * Path in web repo: `server/routers/__tests__/notifications.wave4.test.ts`
 *
 * Harness: vitest + the existing `createCallerFactory(appRouter)` pattern used
 * in sibling test files (e.g. `loads.test.ts`). The `makeCtx` / `seedUser`
 * helpers live in `server/routers/__tests__/helpers.ts` — reuse them.
 */

import { describe, expect, it, beforeEach } from 'vitest';
import { appRouter } from '../../routers';
import { createCallerFactory } from '../../trpc';
import {
  makeCtx,
  seedUser,
  seedNotification,
  resetDb,
} from './helpers';

const createCaller = createCallerFactory(appRouter);

describe('notifications · snooze', () => {
  beforeEach(async () => await resetDb());

  it('snoozes a notification the caller owns', async () => {
    const user = await seedUser();
    const notif = await seedNotification({ userId: user.id });
    const caller = createCaller(makeCtx(user));

    const until = new Date(Date.now() + 6 * 60 * 60 * 1000); // 6h
    const res = await caller.notifications.snooze({
      notificationId: notif.id,
      until,
    });
    expect(res.ok).toBe(true);
    expect(res.snoozedUntil?.getTime()).toBe(until.getTime());
  });

  it('rejects a past `until` value', async () => {
    const user = await seedUser();
    const notif = await seedNotification({ userId: user.id });
    const caller = createCaller(makeCtx(user));
    await expect(
      caller.notifications.snooze({
        notificationId: notif.id,
        until: new Date(Date.now() - 1000),
      }),
    ).rejects.toThrow(/future/);
  });

  it('rejects > 30d in the future', async () => {
    const user = await seedUser();
    const notif = await seedNotification({ userId: user.id });
    const caller = createCaller(makeCtx(user));
    await expect(
      caller.notifications.snooze({
        notificationId: notif.id,
        until: new Date(Date.now() + 31 * 24 * 60 * 60 * 1000),
      }),
    ).rejects.toThrow(/30 days/);
  });

  it('refuses to snooze another user\'s notification', async () => {
    const owner = await seedUser();
    const attacker = await seedUser();
    const notif = await seedNotification({ userId: owner.id });
    const caller = createCaller(makeCtx(attacker));
    await expect(
      caller.notifications.snooze({
        notificationId: notif.id,
        until: new Date(Date.now() + 3600_000),
      }),
    ).rejects.toThrow(/not found/);
  });
});

describe('notifications · clearRead', () => {
  beforeEach(async () => await resetDb());

  it('deletes only read notifications older than 7d', async () => {
    const user = await seedUser();
    const tenDaysAgo = new Date(Date.now() - 10 * 24 * 60 * 60 * 1000);
    const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);

    const oldRead = await seedNotification({
      userId: user.id,
      isRead: true,
      readAt: tenDaysAgo,
    });
    const recentRead = await seedNotification({
      userId: user.id,
      isRead: true,
      readAt: threeDaysAgo,
    });
    const oldUnread = await seedNotification({
      userId: user.id,
      isRead: false,
    });

    const caller = createCaller(makeCtx(user));
    const res = await caller.notifications.clearRead();
    expect(res.removed).toBe(1);

    const remaining = await caller.notifications.list();
    const ids = remaining.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(recentRead.id);
    expect(ids).toContain(oldUnread.id);
    expect(ids).not.toContain(oldRead.id);
  });
});

describe('notifications · markAllRead', () => {
  beforeEach(async () => await resetDb());

  it('marks every unread notification read', async () => {
    const user = await seedUser();
    await seedNotification({ userId: user.id, isRead: false });
    await seedNotification({ userId: user.id, isRead: false });
    await seedNotification({ userId: user.id, isRead: true });

    const caller = createCaller(makeCtx(user));
    const res = await caller.notifications.markAllRead();
    expect(res.updated).toBe(2);

    const count = await caller.notifications.getUnreadCount();
    expect(count).toBe(0);
  });

  it('scopes to a single channel when provided', async () => {
    const user = await seedUser();
    await seedNotification({ userId: user.id, isRead: false, channel: 'safety' });
    await seedNotification({ userId: user.id, isRead: false, channel: 'dispatch' });
    const caller = createCaller(makeCtx(user));
    const res = await caller.notifications.markAllRead({ channel: 'safety' });
    expect(res.updated).toBe(1);
  });
});

describe('notifications · channel preferences', () => {
  beforeEach(async () => await resetDb());

  it('upserts a preference and reads it back', async () => {
    const user = await seedUser();
    const caller = createCaller(makeCtx(user));
    await caller.notifications.setChannelPreferences({
      channel: 'marketing',
      enabled: true,
    });
    const prefs = await caller.notifications.getChannelPreferences();
    const mk = prefs.channels.find((c) => c.channel === 'marketing')!;
    expect(mk.enabled).toBe(true);
    expect(mk.isDefault).toBe(false);
  });

  it('returns sensible defaults when no rows exist', async () => {
    const user = await seedUser();
    const caller = createCaller(makeCtx(user));
    const prefs = await caller.notifications.getChannelPreferences();
    expect(prefs.channels).toHaveLength(6);
    const marketing = prefs.channels.find((c) => c.channel === 'marketing')!;
    expect(marketing.enabled).toBe(false);
    expect(marketing.isDefault).toBe(true);
    const dispatch = prefs.channels.find((c) => c.channel === 'dispatch')!;
    expect(dispatch.enabled).toBe(true);
  });

  it('overwrites on repeat writes', async () => {
    const user = await seedUser();
    const caller = createCaller(makeCtx(user));
    await caller.notifications.setChannelPreferences({
      channel: 'ai_coach',
      enabled: false,
    });
    await caller.notifications.setChannelPreferences({
      channel: 'ai_coach',
      enabled: true,
    });
    const prefs = await caller.notifications.getChannelPreferences();
    expect(prefs.channels.find((c) => c.channel === 'ai_coach')!.enabled).toBe(true);
  });
});

describe('notifications.draft · create / update / send / discard', () => {
  beforeEach(async () => await resetDb());

  it('creates a draft to another user', async () => {
    const author = await seedUser();
    const recipient = await seedUser();
    const caller = createCaller(makeCtx(author));
    const res = await caller.notifications.draft.create({
      to: recipient.id,
      channel: 'dispatch',
      body: 'Rolling in 10',
    });
    expect(res.draft.status).toBe('draft');
    expect(res.draft.authorUserId).toBe(author.id);
    expect(res.draft.toUserId).toBe(recipient.id);
  });

  it('refuses a self-addressed draft', async () => {
    const user = await seedUser();
    const caller = createCaller(makeCtx(user));
    await expect(
      caller.notifications.draft.create({
        to: user.id,
        channel: 'dispatch',
        body: 'hi me',
      }),
    ).rejects.toThrow(/yourself/);
  });

  it('updates only while status is draft', async () => {
    const author = await seedUser();
    const recipient = await seedUser();
    const caller = createCaller(makeCtx(author));
    const { draft } = await caller.notifications.draft.create({
      to: recipient.id,
      channel: 'ops',
      body: 'v1',
    });
    await caller.notifications.draft.update({
      draftId: draft.id,
      patch: { body: 'v2' },
    });
    const list1 = await caller.notifications.draft.list();
    expect(list1.drafts[0].body).toBe('v2');

    await caller.notifications.draft.send({ draftId: draft.id });
    await expect(
      caller.notifications.draft.update({
        draftId: draft.id,
        patch: { body: 'v3' },
      }),
    ).rejects.toThrow(/sent/);
  });

  it('send creates a real notification row for the recipient', async () => {
    const author = await seedUser();
    const recipient = await seedUser();
    const authorCaller = createCaller(makeCtx(author));
    const recipientCaller = createCaller(makeCtx(recipient));
    const { draft } = await authorCaller.notifications.draft.create({
      to: recipient.id,
      channel: 'dispatch',
      body: 'Wheels up',
    });
    const sent = await authorCaller.notifications.draft.send({
      draftId: draft.id,
    });
    expect(sent.ok).toBe(true);

    const inbox = await recipientCaller.notifications.list();
    const delivered = inbox.items.find(
      (n: { sourceDraftId: string | null }) => n.sourceDraftId === draft.id,
    );
    expect(delivered).toBeDefined();
    expect(delivered!.body).toBe('Wheels up');
  });

  it('discard marks the draft discarded and blocks further edits', async () => {
    const author = await seedUser();
    const recipient = await seedUser();
    const caller = createCaller(makeCtx(author));
    const { draft } = await caller.notifications.draft.create({
      to: recipient.id,
      channel: 'ai_coach',
      body: 'tip',
    });
    const res = await caller.notifications.draft.discard({ draftId: draft.id });
    expect(res.draft.status).toBe('discarded');
    await expect(
      caller.notifications.draft.update({
        draftId: draft.id,
        patch: { body: 'x' },
      }),
    ).rejects.toThrow();
  });

  it('list filters by status', async () => {
    const author = await seedUser();
    const recipient = await seedUser();
    const caller = createCaller(makeCtx(author));
    const a = await caller.notifications.draft.create({
      to: recipient.id,
      channel: 'ops',
      body: 'a',
    });
    const b = await caller.notifications.draft.create({
      to: recipient.id,
      channel: 'ops',
      body: 'b',
    });
    await caller.notifications.draft.discard({ draftId: b.draft.id });

    const drafts = await caller.notifications.draft.list({ status: 'draft' });
    const discarded = await caller.notifications.draft.list({
      status: 'discarded',
    });
    expect(drafts.drafts.map((d) => d.id)).toEqual([a.draft.id]);
    expect(discarded.drafts.map((d) => d.id)).toEqual([b.draft.id]);
  });
});
