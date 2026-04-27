/**
 * Wave-4 · Theme 2.8 · `referrals` router tests.
 *
 * Path in the web repo: `server/routers/__tests__/referrals.test.ts`.
 */

import { describe, expect, it, beforeEach } from 'vitest';
import { appRouter } from '../../routers';

const {
  makeCtx,
  seedUser,
  seedReferral,
  getReferralByCode,
  resetDb,
} = require('./helpers');

describe('referrals.getMyCode', () => {
  beforeEach(async () => await resetDb());

  it('mints a durable code on first call', async () => {
    const me = await seedUser();
    const caller = appRouter.createCaller(makeCtx(me));

    const res = await caller.referrals.getMyCode();
    expect(res.code).toMatch(/^[A-Z]{3}-\d{3}$/);
    expect(res.shareUrl).toContain(res.code);
    expect(res.status).toBe('pending');
  });

  it('returns the SAME code on subsequent calls', async () => {
    const me = await seedUser();
    const caller = appRouter.createCaller(makeCtx(me));

    const a = await caller.referrals.getMyCode();
    const b = await caller.referrals.getMyCode();
    expect(a.code).toBe(b.code);
  });

  it('two different users get two distinct codes', async () => {
    const u1 = await seedUser();
    const u2 = await seedUser();
    const caller1 = appRouter.createCaller(makeCtx(u1));
    const caller2 = appRouter.createCaller(makeCtx(u2));

    const a = await caller1.referrals.getMyCode();
    const b = await caller2.referrals.getMyCode();
    expect(a.code).not.toBe(b.code);
  });
});

describe('referrals.claim', () => {
  beforeEach(async () => await resetDb());

  it('attaches referee on a valid code', async () => {
    const referrer = await seedUser();
    const referee = await seedUser();

    // referrer mints
    const refCaller = appRouter.createCaller(makeCtx(referrer));
    const minted = await refCaller.referrals.getMyCode();

    // referee claims
    const refereeCaller = appRouter.createCaller(makeCtx(referee));
    const res = await refereeCaller.referrals.claim({ code: minted.code });
    expect(res.ok).toBe(true);
    expect(res.status).toBe('claimed');

    const row = await getReferralByCode(minted.code);
    expect(row.referredUserId).toBe(referee.id);
  });

  it('rejects self-claim', async () => {
    const me = await seedUser();
    const caller = appRouter.createCaller(makeCtx(me));
    const minted = await caller.referrals.getMyCode();
    await expect(
      caller.referrals.claim({ code: minted.code })
    ).rejects.toThrow(/self-claim/i);
  });

  it('is idempotent when the same driver re-claims the same code', async () => {
    const referrer = await seedUser();
    const referee = await seedUser();
    const refCaller = appRouter.createCaller(makeCtx(referrer));
    const minted = await refCaller.referrals.getMyCode();

    const refereeCaller = appRouter.createCaller(makeCtx(referee));
    await refereeCaller.referrals.claim({ code: minted.code });
    const second = await refereeCaller.referrals.claim({ code: minted.code });
    expect(second.alreadyAttached).toBe(true);
  });

  it('CONFLICT when code already claimed by someone else', async () => {
    const referrer = await seedUser();
    const referee1 = await seedUser();
    const referee2 = await seedUser();

    const refCaller = appRouter.createCaller(makeCtx(referrer));
    const minted = await refCaller.referrals.getMyCode();

    await appRouter
      .createCaller(makeCtx(referee1))
      .referrals.claim({ code: minted.code });

    await expect(
      appRouter
        .createCaller(makeCtx(referee2))
        .referrals.claim({ code: minted.code })
    ).rejects.toThrow(/already been claimed/i);
  });

  it('CONFLICT when caller is already attached to a different referrer', async () => {
    const refA = await seedUser();
    const refB = await seedUser();
    const newbie = await seedUser();

    const codeA = (
      await appRouter
        .createCaller(makeCtx(refA))
        .referrals.getMyCode()
    ).code;
    const codeB = (
      await appRouter
        .createCaller(makeCtx(refB))
        .referrals.getMyCode()
    ).code;

    await appRouter
      .createCaller(makeCtx(newbie))
      .referrals.claim({ code: codeA });
    await expect(
      appRouter
        .createCaller(makeCtx(newbie))
        .referrals.claim({ code: codeB })
    ).rejects.toThrow(/already attached/i);
  });

  it('NOT_FOUND on garbage code', async () => {
    const me = await seedUser();
    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.referrals.claim({ code: 'ZZZ-999' })
    ).rejects.toThrow(/not found/i);
  });

  it('BAD_REQUEST on revoked code', async () => {
    const referrer = await seedUser();
    const referee = await seedUser();
    const r = await seedReferral({
      referrerUserId: referrer.id,
      status: 'revoked',
      code: 'REV-000',
    });

    const caller = appRouter.createCaller(makeCtx(referee));
    await expect(
      caller.referrals.claim({ code: r.code })
    ).rejects.toThrow(/revoked/i);
  });

  it('normalizes lowercase input → uppercase match', async () => {
    const referrer = await seedUser();
    const referee = await seedUser();
    const minted = await appRouter
      .createCaller(makeCtx(referrer))
      .referrals.getMyCode();

    const res = await appRouter
      .createCaller(makeCtx(referee))
      .referrals.claim({ code: minted.code.toLowerCase() });
    expect(res.ok).toBe(true);
  });
});

describe('referrals.listMyReferrals', () => {
  beforeEach(async () => await resetDb());

  it('lists every attached referee with status + name', async () => {
    const referrer = await seedUser();
    const r1 = await seedUser({ name: 'Priya Menon' });
    const r2 = await seedUser({ name: 'Alex Kim' });

    const refCaller = appRouter.createCaller(makeCtx(referrer));
    const code1 = (await refCaller.referrals.getMyCode()).code;
    await appRouter
      .createCaller(makeCtx(r1))
      .referrals.claim({ code: code1 });

    // seed a second row directly to simulate another referral
    await seedReferral({
      referrerUserId: referrer.id,
      referredUserId: r2.id,
      status: 'onboarded',
      code: 'XYZ-111',
    });

    const res = await refCaller.referrals.listMyReferrals();
    expect(res.referrals).toHaveLength(2);
    const names = res.referrals.map((r: any) => r.referredName).sort();
    expect(names).toEqual(['Alex Kim', 'Priya Menon']);
  });

  it('excludes pending (un-claimed) rows', async () => {
    const referrer = await seedUser();
    const refCaller = appRouter.createCaller(makeCtx(referrer));
    // mint a code but don't have anyone claim it
    await refCaller.referrals.getMyCode();

    const res = await refCaller.referrals.listMyReferrals();
    expect(res.referrals).toHaveLength(0);
  });
});
