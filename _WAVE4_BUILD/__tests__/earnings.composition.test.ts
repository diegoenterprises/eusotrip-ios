/**
 * Wave-4 · Theme 2.11 · earnings.getComposition + atomicTripWrapSubmit
 *
 * Test strategy:
 *   - Seed a load owned by `driverA` with settlement line items covering
 *     every kind branch (linehaul / fsc / detention / hazmat_premium /
 *     platform_fee / factoring_fee / unknown → accessorial).
 *   - Call getComposition and assert bucket sums + net math.
 *   - Assert a snapshot row was persisted.
 *   - Assert ownership guard (driverB gets FORBIDDEN).
 *   - atomicTripWrapSubmit: happy path freezes, advances lifecycle,
 *     persists snapshot with finalDocs + acceptedDeductions + disputes.
 *   - atomicTripWrapSubmit: rejects unknown lineItemId in acceptedDeductions.
 *   - atomicTripWrapSubmit: rejects wrong load status.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { appRouter } from '../server/router';
import { db } from '../server/db';
import {
  loads,
  settlements,
  settlementLineItems,
  payrollDeductions,
  users,
} from '../server/schema';
import { earningsCompositionSnapshots } from '../drizzle/schema.additions.wave4-10';
import { eq } from 'drizzle-orm';

function ctx(userId: string) {
  return { user: { id: userId, role: 'DRIVER' as const } };
}

const DRIVER_A = '11111111-1111-1111-1111-111111111111';
const DRIVER_B = '22222222-2222-2222-2222-222222222222';
const LOAD_1 = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const SETTLE_1 = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

beforeEach(async () => {
  await db.delete(earningsCompositionSnapshots);
  await db.delete(settlementLineItems);
  await db.delete(settlements);
  await db.delete(payrollDeductions);
  await db.delete(loads);
  await db.delete(users);
  await db.insert(users).values([
    { id: DRIVER_A, email: 'a@example.com', role: 'DRIVER' },
    { id: DRIVER_B, email: 'b@example.com', role: 'DRIVER' },
  ]);
  await db.insert(loads).values({
    id: LOAD_1,
    driverId: DRIVER_A,
    status: 'DELIVERED',
  });
  await db.insert(settlements).values({
    id: SETTLE_1,
    driverId: DRIVER_A,
    status: 'OPEN',
  });
  await db.insert(settlementLineItems).values([
    { id: 'c1', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'linehaul', label: 'Line-haul', amountCents: 450_00 },
    { id: 'c2', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'fsc',       label: 'FSC',       amountCents: 118_00 },
    { id: 'c3', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'detention', label: 'Detention', amountCents:  44_00 },
    { id: 'c4', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'hazmat_premium',   label: 'Hazmat+',  amountCents: 25_00 },
    { id: 'c5', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'platform_fee',     label: 'Platform', amountCents:  -3_06 },
    { id: 'c6', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'factoring_fee',    label: 'Factoring',amountCents:  -9_18 },
    { id: 'c7', settlementId: SETTLE_1, loadId: LOAD_1, kind: 'stop_charge',      label: 'Stop',     amountCents:  10_00 },
  ]);
  await db.insert(payrollDeductions).values([
    { id: 'd1', userId: DRIVER_A, loadId: LOAD_1, kind: 'federal',  label: 'Federal',  amountCents: -45_00, periodStart: new Date() },
    { id: 'd2', userId: DRIVER_A, loadId: LOAD_1, kind: 'fica',     label: 'FICA',     amountCents: -30_00, periodStart: new Date() },
  ]);
});

describe('earnings.getComposition', () => {
  it('buckets line items and computes gross/net', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const c = await caller.earnings.getComposition({ loadId: LOAD_1 });

    expect(c.linehaulCents).toBe(450_00);
    expect(c.fscCents).toBe(118_00);
    expect(c.detentionCents).toBe(44_00);
    expect(c.adders.find((a) => a.kind === 'hazmat_premium')?.amountCents).toBe(25_00);
    expect(c.accessorials.find((a) => a.kind === 'stop_charge')?.amountCents).toBe(10_00);

    const deductionSum = c.deductions.reduce((a, x) => a + x.amountCents, 0);
    expect(deductionSum).toBe(3_06 + 9_18 + 45_00 + 30_00);

    const gross = 450_00 + 118_00 + 44_00 + 25_00 + 10_00;
    expect(c.grossCents).toBe(gross);
    expect(c.netCents).toBe(gross - deductionSum);
  });

  it('persists a snapshot row on first query', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await caller.earnings.getComposition({ loadId: LOAD_1 });
    const rows = await db
      .select()
      .from(earningsCompositionSnapshots)
      .where(eq(earningsCompositionSnapshots.loadId, LOAD_1));
    expect(rows.length).toBe(1);
  });

  it('returns the existing snapshot on subsequent calls (no duplicate insert)', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await caller.earnings.getComposition({ loadId: LOAD_1 });
    await caller.earnings.getComposition({ loadId: LOAD_1 });
    const rows = await db
      .select()
      .from(earningsCompositionSnapshots)
      .where(eq(earningsCompositionSnapshots.loadId, LOAD_1));
    expect(rows.length).toBe(1);
  });

  it('forbids access to another driver', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_B));
    await expect(
      caller.earnings.getComposition({ loadId: LOAD_1 }),
    ).rejects.toThrow(/FORBIDDEN|not owned/i);
  });

  it('404s on missing load', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      caller.earnings.getComposition({
        loadId: '00000000-0000-0000-0000-000000000000',
      }),
    ).rejects.toThrow(/NOT_FOUND|not found/i);
  });
});

describe('earnings.atomicTripWrapSubmit', () => {
  it('freezes composition, advances lifecycle, persists final docs + disputes', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const r = await caller.earnings.atomicTripWrapSubmit({
      loadId: LOAD_1,
      finalDocsS3Keys: ['s3://bol/1.pdf', 's3://pod/1.pdf'],
      acceptedDeductions: [{ lineItemId: 'c5' }, { lineItemId: 'c6', note: 'ok' }],
      disputes: [
        { lineItemId: 'c3', reason: 'detention longer than paid', requestedAmountCents: 88_00 },
      ],
    });
    expect(r.ok).toBe(true);
    expect(r.acceptedDeductionsCount).toBe(2);
    expect(r.disputesCount).toBe(1);
    expect(r.load.status).toBe('TRIP_WRAPPED');
    const snaps = await db
      .select()
      .from(earningsCompositionSnapshots)
      .where(eq(earningsCompositionSnapshots.loadId, LOAD_1));
    expect(snaps.length).toBeGreaterThanOrEqual(1);
    const frozen = snaps[snaps.length - 1].snapshotJson as any;
    expect(frozen.finalDocsS3Keys).toEqual(['s3://bol/1.pdf', 's3://pod/1.pdf']);
    expect(frozen.disputes[0].reason).toMatch(/detention/);
  });

  it('rejects unknown lineItemId in acceptedDeductions', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      caller.earnings.atomicTripWrapSubmit({
        loadId: LOAD_1,
        finalDocsS3Keys: [],
        acceptedDeductions: [{ lineItemId: '99999999-9999-9999-9999-999999999999' }],
        disputes: [],
      }),
    ).rejects.toThrow(/unknown line item/i);
  });

  it('rejects a load that is not DELIVERED / POD_SIGNED', async () => {
    await db.update(loads).set({ status: 'IN_TRANSIT' }).where(eq(loads.id, LOAD_1));
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      caller.earnings.atomicTripWrapSubmit({
        loadId: LOAD_1,
        finalDocsS3Keys: [],
        acceptedDeductions: [],
        disputes: [],
      }),
    ).rejects.toThrow(/FAILED_PRECONDITION|cannot wrap trip/i);
  });
});
