/**
 * Wave-4 · Theme 2.8 · `missions` router tests.
 *
 * Path in the web repo: `server/routers/__tests__/missions.test.ts`.
 *
 * Harness: vitest + `appRouter.createCaller` — same pattern as
 * `server/routers/__tests__/users.test.ts`. DB helpers (`resetDb`,
 * `seedUser`, `seedDriverMission`, `seedWallet`) are expected to live in
 * `server/routers/__tests__/helpers.ts` (seeded by the earlier Wave-4
 * agents — see agent_06.md and agent_08.md).
 */

import { describe, expect, it, beforeEach } from 'vitest';
import { appRouter } from '../../routers';

// helpers — pattern-compatible with other Wave-4 test files
// eslint-disable-next-line @typescript-eslint/no-var-requires
const {
  makeCtx,
  seedUser,
  seedDriverMission,
  seedWallet,
  getDriverMission,
  getWalletBalance,
  resetDb,
} = require('./helpers');

describe('missions.listForMe', () => {
  beforeEach(async () => await resetDb());

  it('returns only my missions', async () => {
    const me = await seedUser();
    const stranger = await seedUser();
    await seedDriverMission({ driverId: me.id, status: 'active' });
    await seedDriverMission({ driverId: me.id, status: 'verifying' });
    await seedDriverMission({ driverId: stranger.id, status: 'active' });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.listForMe();
    expect(res.missions).toHaveLength(2);
    for (const m of res.missions) expect(m.driverId).toBe(me.id);
  });

  it('filters by status=verifying', async () => {
    const me = await seedUser();
    await seedDriverMission({ driverId: me.id, status: 'active' });
    await seedDriverMission({ driverId: me.id, status: 'verifying' });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.listForMe({ status: 'verifying' });
    expect(res.missions.every((m: any) => m.status === 'verifying')).toBe(true);
  });

  it('status=completed includes verified + completed', async () => {
    const me = await seedUser();
    await seedDriverMission({ driverId: me.id, status: 'verified' });
    await seedDriverMission({ driverId: me.id, status: 'completed' });
    await seedDriverMission({ driverId: me.id, status: 'active' });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.listForMe({ status: 'completed' });
    expect(res.missions).toHaveLength(2);
  });
});

describe('missions.getById', () => {
  beforeEach(async () => await resetDb());

  it('returns mission + badge payload', async () => {
    const me = await seedUser();
    const m = await seedDriverMission({
      driverId: me.id,
      kind: 'combo',
      cashRewardCents: 6000,
      badgeId: 101,
    });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.getById({ missionId: m.id });
    expect(res.mission.id).toBe(m.id);
    expect(res.mission.cashRewardCents).toBe(6000);
  });

  it('NOT_FOUND on stranger\'s mission', async () => {
    const me = await seedUser();
    const stranger = await seedUser();
    const m = await seedDriverMission({ driverId: stranger.id });

    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.missions.getById({ missionId: m.id })
    ).rejects.toThrow(/not found/i);
  });
});

describe('missions.claim', () => {
  beforeEach(async () => await resetDb());

  it('moves active → verifying', async () => {
    const me = await seedUser();
    const m = await seedDriverMission({ driverId: me.id, status: 'active' });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.claim({ missionId: m.id });
    expect(res.status).toBe('verifying');

    const persisted = await getDriverMission(m.id);
    expect(persisted.status).toBe('verifying');
  });

  it('rejects illegal transition (e.g. claim on completed)', async () => {
    const me = await seedUser();
    const m = await seedDriverMission({ driverId: me.id, status: 'completed' });

    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.missions.claim({ missionId: m.id })
    ).rejects.toThrow(/illegal mission transition/i);
  });

  it('rejects claim on stranger\'s mission', async () => {
    const me = await seedUser();
    const stranger = await seedUser();
    const m = await seedDriverMission({
      driverId: stranger.id,
      status: 'active',
    });

    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.missions.claim({ missionId: m.id })
    ).rejects.toThrow(/not found/i);
  });
});

describe('missions.redeem', () => {
  beforeEach(async () => await resetDb());

  it('verified → completed AND credits wallet for cash_reward', async () => {
    const me = await seedUser();
    await seedWallet({ userId: me.id, availableBalance: '0' });
    const m = await seedDriverMission({
      driverId: me.id,
      status: 'verified',
      kind: 'cash_reward',
      cashRewardCents: 6000, // $60 — matches 067 Haul Mission example
    });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.redeem({ missionId: m.id });
    expect(res.status).toBe('completed');
    expect(res.cashPaidCents).toBe(6000);
    expect(res.walletTxId).not.toBeNull();

    const bal = await getWalletBalance(me.id);
    expect(parseFloat(bal.availableBalance)).toBeCloseTo(60.0, 2);
  });

  it('no-cash badge-only mission closes without wallet tx', async () => {
    const me = await seedUser();
    await seedWallet({ userId: me.id, availableBalance: '0' });
    const m = await seedDriverMission({
      driverId: me.id,
      status: 'verified',
      kind: 'badge',
      cashRewardCents: null,
      badgeId: 101,
    });

    const caller = appRouter.createCaller(makeCtx(me));
    const res = await caller.missions.redeem({ missionId: m.id });
    expect(res.status).toBe('completed');
    expect(res.cashPaidCents).toBe(0);
    expect(res.walletTxId).toBeNull();
    expect(res.badgeAwardedId).toBe(101);
  });

  it('rejects redeem on verifying (must be verified first)', async () => {
    const me = await seedUser();
    const m = await seedDriverMission({ driverId: me.id, status: 'verifying' });

    const caller = appRouter.createCaller(makeCtx(me));
    await expect(
      caller.missions.redeem({ missionId: m.id })
    ).rejects.toThrow(/illegal mission transition|must be verified/i);
  });

  it('is idempotent at the FSM layer — second redeem fails', async () => {
    const me = await seedUser();
    await seedWallet({ userId: me.id, availableBalance: '0' });
    const m = await seedDriverMission({
      driverId: me.id,
      status: 'verified',
      kind: 'cash_reward',
      cashRewardCents: 500,
    });

    const caller = appRouter.createCaller(makeCtx(me));
    await caller.missions.redeem({ missionId: m.id });
    await expect(
      caller.missions.redeem({ missionId: m.id })
    ).rejects.toThrow(/illegal mission transition|must be verified/i);
  });
});
