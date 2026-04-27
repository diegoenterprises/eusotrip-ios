/**
 * Wave-4 · Theme 2.8 · `achievements` router tests.
 *
 * Path in the web repo: `server/routers/__tests__/achievements.test.ts`.
 */

import { describe, expect, it, beforeEach } from 'vitest';
import { appRouter } from '../../routers';
import { deriveRarity } from '../achievements';

const {
  makeCtx,
  seedUser,
  seedBadge,
  seedUserBadge,
  resetDb,
} = require('./helpers');

describe('deriveRarity (unit)', () => {
  it('maps legendary category → legendary', () => {
    expect(
      deriveRarity({ category: 'legendary', tier: 'bronze', isRare: false } as any)
    ).toBe('legendary');
  });
  it('maps epic category → epic', () => {
    expect(
      deriveRarity({ category: 'epic', tier: 'bronze', isRare: false } as any)
    ).toBe('epic');
  });
  it('maps isRare=true → epic regardless of category', () => {
    expect(
      deriveRarity({
        category: 'milestone',
        tier: 'bronze',
        isRare: true,
      } as any)
    ).toBe('epic');
  });
  it('maps platinum/diamond → rare', () => {
    expect(
      deriveRarity({ category: 'performance', tier: 'platinum', isRare: false } as any)
    ).toBe('rare');
    expect(
      deriveRarity({ category: 'performance', tier: 'diamond', isRare: false } as any)
    ).toBe('rare');
  });
  it('maps gold tier → uncommon', () => {
    expect(
      deriveRarity({ category: 'milestone', tier: 'gold', isRare: false } as any)
    ).toBe('uncommon');
  });
  it('defaults to common', () => {
    expect(
      deriveRarity({ category: 'milestone', tier: 'silver', isRare: false } as any)
    ).toBe('common');
  });
});

describe('achievements.listMine', () => {
  beforeEach(async () => await resetDb());

  it('returns only my earned badges', async () => {
    const me = await seedUser();
    const other = await seedUser();
    const b1 = await seedBadge({ category: 'milestone', tier: 'gold' });
    const b2 = await seedBadge({ category: 'legendary', tier: 'diamond' });
    await seedUserBadge({ userId: me.id, badgeId: b1.id });
    await seedUserBadge({ userId: me.id, badgeId: b2.id });
    await seedUserBadge({ userId: other.id, badgeId: b1.id });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.listMine();
    expect(res.achievements).toHaveLength(2);
  });

  it('filters by rarity', async () => {
    const me = await seedUser();
    const gold = await seedBadge({ category: 'milestone', tier: 'gold' });
    const legendary = await seedBadge({ category: 'legendary', tier: 'diamond' });
    await seedUserBadge({ userId: me.id, badgeId: gold.id });
    await seedUserBadge({ userId: me.id, badgeId: legendary.id });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.listMine({ rarity: 'legendary' });
    expect(res.achievements).toHaveLength(1);
    expect(res.achievements[0].badge.id).toBe(legendary.id);
  });
});

describe('achievements.getById', () => {
  beforeEach(async () => await resetDb());

  it('returns isEarned=true when I have the badge', async () => {
    const me = await seedUser();
    const b = await seedBadge({});
    await seedUserBadge({ userId: me.id, badgeId: b.id });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.getById({ achievementId: b.id });
    expect(res.isEarned).toBe(true);
  });

  it('returns isEarned=false for a locked badge', async () => {
    const me = await seedUser();
    const b = await seedBadge({});

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.getById({ achievementId: b.id });
    expect(res.isEarned).toBe(false);
  });

  it('NOT_FOUND on unknown badge id', async () => {
    const me = await seedUser();
    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.achievements.getById({ achievementId: 999999 })
    ).rejects.toThrow(/not found/i);
  });
});

describe('achievements.share', () => {
  beforeEach(async () => await resetDb());

  it('returns a signed URL for a badge I\'ve earned', async () => {
    const me = await seedUser();
    const b = await seedBadge({});
    await seedUserBadge({ userId: me.id, badgeId: b.id });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.share({ achievementId: b.id });
    expect(res.url).toMatch(/^https?:\/\//);
    expect(res.token.split('.')).toHaveLength(3); // body.mac.nonce
    expect(res.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  it('FORBIDDEN when I haven\'t earned the badge', async () => {
    const me = await seedUser();
    const b = await seedBadge({});
    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.achievements.share({ achievementId: b.id })
    ).rejects.toThrow(/have not earned/i);
  });

  it('produces a distinct nonce per call (cache-busting)', async () => {
    const me = await seedUser();
    const b = await seedBadge({});
    await seedUserBadge({ userId: me.id, badgeId: b.id });
    const caller = appRouter.createCaller(makeCtx(me));

    const a = await caller.achievements.share({ achievementId: b.id });
    const c = await caller.achievements.share({ achievementId: b.id });
    expect(a.token).not.toBe(c.token);
  });
});

describe('achievements.getRarityCounts', () => {
  beforeEach(async () => await resetDb());

  it('returns all five buckets even when empty', async () => {
    const me = await seedUser();
    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.getRarityCounts();
    expect(res).toEqual({
      common: 0,
      uncommon: 0,
      rare: 0,
      epic: 0,
      legendary: 0,
    });
  });

  it('counts correctly across the rarity buckets', async () => {
    const me = await seedUser();
    const common = await seedBadge({ category: 'milestone', tier: 'silver' });
    const uncommon = await seedBadge({ category: 'milestone', tier: 'gold' });
    const rare = await seedBadge({ category: 'performance', tier: 'platinum' });
    const epic = await seedBadge({ category: 'epic', tier: 'gold' });
    const legendary = await seedBadge({ category: 'legendary', tier: 'diamond' });
    for (const b of [common, uncommon, rare, epic, legendary]) {
      await seedUserBadge({ userId: me.id, badgeId: b.id });
    }

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.achievements.getRarityCounts();
    expect(res).toEqual({
      common: 1,
      uncommon: 1,
      rare: 1,
      epic: 1,
      legendary: 1,
    });
  });
});
