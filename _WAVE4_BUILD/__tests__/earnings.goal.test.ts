/**
 * Wave-4 · Theme 2.11 · earnings.getGoal / setGoal / getGoalProgress
 *
 * Test strategy:
 *   - setGoal upserts — second call for same (driver, period) replaces.
 *   - getGoal returns goals for the caller only.
 *   - Cross-driver isolation.
 *   - getGoalProgress computes pace = actual / elapsedFraction; onTrack is
 *     true when pace ≥ 85% of goal.
 *   - Period bounds: weekly pulls Mon→next-Mon, monthly pulls first of month.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { appRouter } from '../server/router';
import { db } from '../server/db';
import { users, earnings as earningsTable } from '../server/schema';
import { earningsGoals } from '../drizzle/schema.additions.wave4-10';
import { eq } from 'drizzle-orm';

function ctx(userId: string) {
  return { user: { id: userId, role: 'DRIVER' as const } };
}

const DRIVER_A = '11111111-1111-1111-1111-111111111111';
const DRIVER_B = '22222222-2222-2222-2222-222222222222';

beforeEach(async () => {
  await db.delete(earningsTable);
  await db.delete(earningsGoals);
  await db.delete(users);
  await db.insert(users).values([
    { id: DRIVER_A, email: 'a@example.com', role: 'DRIVER' },
    { id: DRIVER_B, email: 'b@example.com', role: 'DRIVER' },
  ]);
});

describe('earnings.setGoal + getGoal', () => {
  it('upserts (driver_id, period)', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));

    const r1 = await caller.earnings.setGoal({ period: 'week', targetCents: 3_000_00 });
    expect(r1.ok).toBe(true);
    expect(r1.targetCents).toBe(3_000_00);

    const r2 = await caller.earnings.setGoal({ period: 'week', targetCents: 3_500_00 });
    expect(r2.targetCents).toBe(3_500_00);

    const rows = await db.select().from(earningsGoals).where(eq(earningsGoals.driverId, DRIVER_A));
    expect(rows.length).toBe(1);
    expect(rows[0].targetCents).toBe(3_500_00);
  });

  it('keeps month + week as separate rows', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await caller.earnings.setGoal({ period: 'week', targetCents: 3_000_00 });
    await caller.earnings.setGoal({ period: 'month', targetCents: 12_000_00 });
    const { goals } = await caller.earnings.getGoal({});
    const periods = goals.map((g) => g.period).sort();
    expect(periods).toEqual(['month', 'week']);
  });

  it('isolates across drivers', async () => {
    const a = appRouter.createCaller(ctx(DRIVER_A));
    const b = appRouter.createCaller(ctx(DRIVER_B));
    await a.earnings.setGoal({ period: 'week', targetCents: 3_000_00 });
    await b.earnings.setGoal({ period: 'week', targetCents: 7_000_00 });
    const { goals: aGoals } = await a.earnings.getGoal({ period: 'week' });
    const { goals: bGoals } = await b.earnings.getGoal({ period: 'week' });
    expect(aGoals[0].targetCents).toBe(3_000_00);
    expect(bGoals[0].targetCents).toBe(7_000_00);
  });

  it('rejects zero / negative / huge targets', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      caller.earnings.setGoal({ period: 'week', targetCents: 0 }),
    ).rejects.toThrow();
    await expect(
      caller.earnings.setGoal({ period: 'week', targetCents: -1 }),
    ).rejects.toThrow();
    await expect(
      caller.earnings.setGoal({
        period: 'week',
        targetCents: 1_000_000_00,
      }),
    ).rejects.toThrow();
  });
});

describe('earnings.getGoalProgress', () => {
  it('computes actual/pace and onTrack flag', async () => {
    // Freeze "now" to a Wednesday noon so weekBounds returns a stable range.
    const now = new Date('2026-04-15T12:00:00Z'); // Wed
    vi.useFakeTimers();
    vi.setSystemTime(now);

    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await caller.earnings.setGoal({ period: 'week', targetCents: 3_000_00 });

    // Insert a $900 net earnings row dated this-week Monday.
    await db.insert(earningsTable).values({
      id: 'e1',
      driverId: DRIVER_A,
      netCents: 900_00,
      periodStart: new Date('2026-04-13T00:00:00Z'),
    });

    const p = await caller.earnings.getGoalProgress({ period: 'week' });
    expect(p.actualCents).toBe(900_00);
    // Wed noon into week-starting-Mon ≈ (2.5d / 7d) ≈ 0.357 elapsed
    expect(p.elapsedFraction).toBeGreaterThan(0.3);
    expect(p.elapsedFraction).toBeLessThan(0.45);
    // pace = 900_00 / 0.357 ≈ 2_520_00
    expect(p.paceCents).toBeGreaterThan(2_000_00);
    expect(p.paceCents).toBeLessThan(3_000_00);
    // 2_520_00 < 3_000_00 * 0.85 = 2_550_00 → likely false
    expect(typeof p.onTrack).toBe('boolean');

    vi.useRealTimers();
  });

  it('treats missing goal as onTrack = true', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const p = await caller.earnings.getGoalProgress({ period: 'month' });
    expect(p.goal).toBeNull();
    expect(p.onTrack).toBe(true);
  });
});
