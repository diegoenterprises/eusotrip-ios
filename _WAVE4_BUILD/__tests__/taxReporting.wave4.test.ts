/**
 * Wave-4 · Theme 2.11 · taxReporting.download1099 + estimateQuarterly
 *
 * Test strategy:
 *   - download1099: happy path returns a signed URL for the latest FILED
 *     form of (user, year, kind); 404 if absent; PRECONDITION if pending;
 *     500 if key missing.
 *   - estimateQuarterly: net SE income → SE tax + federal income tax, net
 *     of already-withheld.
 *   - Quarter bounds honour IRS Pub 505 irregular ranges.
 *   - Driver isolation (estimate uses ctx.user.id).
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { appRouter } from '../server/router';
import { db } from '../server/db';
import {
  users,
  taxForms,
  earnings as earningsTable,
  payrollDeductions,
} from '../server/schema';
import { eq } from 'drizzle-orm';

// Mock the s3 presigner so tests stay offline.
vi.mock('../server/lib/s3', () => ({
  getPresignedDownloadUrl: vi.fn(async ({ key, expiresSeconds }: any) => {
    return `https://signed.example.com/${encodeURIComponent(key)}?exp=${expiresSeconds}`;
  }),
}));

function ctx(userId: string) {
  return { user: { id: userId, role: 'DRIVER' as const } };
}

const DRIVER_A = '11111111-1111-1111-1111-111111111111';
const DRIVER_B = '22222222-2222-2222-2222-222222222222';

beforeEach(async () => {
  await db.delete(payrollDeductions);
  await db.delete(earningsTable);
  await db.delete(taxForms);
  await db.delete(users);
  await db.insert(users).values([
    { id: DRIVER_A, email: 'a@example.com', role: 'DRIVER' },
    { id: DRIVER_B, email: 'b@example.com', role: 'DRIVER' },
  ]);
});

describe('taxReporting.download1099', () => {
  it('returns a signed URL for the latest FILED 1099-NEC', async () => {
    await db.insert(taxForms).values([
      {
        id: 't1',
        userId: DRIVER_A,
        year: 2025,
        kind: 'NEC',
        status: 'FILED',
        pdfS3Key: 'tax/DRIVER_A/1099-NEC-2025-v2.pdf',
        generatedAt: new Date('2026-01-31T00:00:00Z'),
      },
      {
        id: 't0',
        userId: DRIVER_A,
        year: 2025,
        kind: 'NEC',
        status: 'FILED',
        pdfS3Key: 'tax/DRIVER_A/1099-NEC-2025-v1.pdf',
        generatedAt: new Date('2026-01-15T00:00:00Z'),
      },
    ]);
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const r = await caller.taxReporting.download1099({ year: 2025 });
    expect(r.url).toContain('1099-NEC-2025-v2');
    expect(r.filename).toBe('1099-NEC-2025.pdf');
    expect(r.status).toBe('FILED');
  });

  it('404s when no form exists for that year+kind', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      caller.taxReporting.download1099({ year: 2025 }),
    ).rejects.toThrow(/NOT_FOUND|on file/i);
  });

  it('PRECONDITION when form is still PENDING', async () => {
    await db.insert(taxForms).values({
      id: 't1',
      userId: DRIVER_A,
      year: 2025,
      kind: 'NEC',
      status: 'PENDING',
      pdfS3Key: null,
      generatedAt: new Date(),
    });
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      caller.taxReporting.download1099({ year: 2025 }),
    ).rejects.toThrow(/PENDING|FAILED_PRECONDITION/);
  });

  it('isolates forms by caller', async () => {
    await db.insert(taxForms).values({
      id: 't1',
      userId: DRIVER_B,
      year: 2025,
      kind: 'NEC',
      status: 'FILED',
      pdfS3Key: 'tax/DRIVER_B/1099-NEC-2025.pdf',
      generatedAt: new Date(),
    });
    const callerA = appRouter.createCaller(ctx(DRIVER_A));
    await expect(
      callerA.taxReporting.download1099({ year: 2025 }),
    ).rejects.toThrow(/NOT_FOUND/);
  });
});

describe('taxReporting.estimateQuarterly', () => {
  it('computes SE + federal income tax on quarterly net SE income', async () => {
    // Seed $40k net SE for Q1 2026.
    await db.insert(earningsTable).values([
      {
        id: 'e1',
        driverId: DRIVER_A,
        netCents: 40_000_00,
        periodStart: new Date('2026-02-15T00:00:00Z'),
      },
    ]);
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const r = await caller.taxReporting.estimateQuarterly({
      year: 2026,
      quarter: 1,
    });

    expect(r.year).toBe(2026);
    expect(r.quarter).toBe(1);
    expect(r.inputs.netSelfEmploymentCents).toBe(40_000_00);
    // SE base = 40_000 * 0.9235 = 36_940
    expect(r.breakdown.seBaseCents).toBe(Math.round(40_000_00 * 0.9235));
    // SE tax = seBase * 0.153
    expect(r.breakdown.seTaxCents).toBe(
      Math.round(r.breakdown.seBaseCents * 0.153),
    );
    // Due date = Apr 15 2026
    expect(r.dueDate.toISOString().slice(0, 10)).toBe('2026-04-15');
    // Total tax ≥ SE tax
    expect(r.totalTaxCents).toBeGreaterThanOrEqual(r.breakdown.seTaxCents);
    // recommendedWeeklySetAsideCents = ceil(due / 13)
    expect(r.recommendedWeeklySetAsideCents).toBe(Math.ceil(r.dueCents / 13));
  });

  it('subtracts already-withheld amounts from dueCents', async () => {
    await db.insert(earningsTable).values({
      id: 'e1',
      driverId: DRIVER_A,
      netCents: 20_000_00,
      periodStart: new Date('2026-02-15T00:00:00Z'),
    });
    await db.insert(payrollDeductions).values({
      id: 'd1',
      userId: DRIVER_A,
      kind: 'federal',
      label: 'Federal',
      amountCents: 1_500_00,
      periodStart: new Date('2026-02-15T00:00:00Z'),
    });
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const r = await caller.taxReporting.estimateQuarterly({ year: 2026, quarter: 1 });
    expect(r.inputs.alreadyWithheldCents).toBe(1_500_00);
    expect(r.dueCents).toBe(Math.max(0, r.totalTaxCents - 1_500_00));
  });

  it('returns 0 when no earnings', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const r = await caller.taxReporting.estimateQuarterly({ year: 2026, quarter: 2 });
    expect(r.inputs.netSelfEmploymentCents).toBe(0);
    expect(r.totalTaxCents).toBe(0);
    expect(r.dueCents).toBe(0);
    expect(r.dueDate.toISOString().slice(0, 10)).toBe('2026-06-15');
  });

  it('honours IRS Pub 505 irregular bounds for Q3 and Q4', async () => {
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const q3 = await caller.taxReporting.estimateQuarterly({ year: 2026, quarter: 3 });
    expect(q3.periodStart.toISOString().slice(0, 10)).toBe('2026-06-01');
    expect(q3.periodEnd.toISOString().slice(0, 10)).toBe('2026-08-31');
    expect(q3.dueDate.toISOString().slice(0, 10)).toBe('2026-09-15');

    const q4 = await caller.taxReporting.estimateQuarterly({ year: 2026, quarter: 4 });
    expect(q4.periodStart.toISOString().slice(0, 10)).toBe('2026-09-01');
    expect(q4.dueDate.toISOString().slice(0, 10)).toBe('2027-01-15');
  });

  it('scopes earnings/withholding to ctx.user.id', async () => {
    await db.insert(earningsTable).values({
      id: 'e1',
      driverId: DRIVER_B,
      netCents: 50_000_00,
      periodStart: new Date('2026-02-15T00:00:00Z'),
    });
    const caller = appRouter.createCaller(ctx(DRIVER_A));
    const r = await caller.taxReporting.estimateQuarterly({ year: 2026, quarter: 1 });
    expect(r.inputs.netSelfEmploymentCents).toBe(0);
  });
});
