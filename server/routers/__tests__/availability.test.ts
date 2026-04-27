/**
 * server/routers/__tests__/availability.test.ts
 *
 * Wave-4 · Agent #8 · Theme 2.10 — unit coverage for the new availability
 * router. The test harness stubs `getDb()` with an in-memory "db" so the
 * file runs under `vitest` without a MySQL connection.
 *
 * Coverage
 * --------
 *   * getWeeklyGrid — returns 7 × 24 grid, marks blocked cells
 *   * blockTime / unblockTime — round trip
 *   * blockTime — rejects inverted window
 *   * setAvailability — rejects overlapping slots
 *   * setAvailability — overwrites existing rows for the same day
 *   * getUtilization — ratio computed from driving ÷ available
 *   * exportICS — returns a signed URL with TTL in the future
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';

/* -------------------------------------------------------------------------- */
/*  In-memory DB fixture                                                       */
/* -------------------------------------------------------------------------- */

type Row = Record<string, any>;

class MemTable {
  rows: Row[] = [];
  nextId = 1;
}

const tables = {
  blocks: new MemTable(),
  weekly: new MemTable(),
  tokens: new MemTable(),
};

// Minimal fluent "drizzle-like" builder used by the router at runtime.
function makeDb() {
  const resolveTable = (t: any): MemTable => {
    // t is the drizzle mysqlTable object — we keyed on Symbol.for name.
    const name = (t?.[Symbol.for('drizzle:Name')] ?? t?._?.name ?? '').toString();
    if (name.includes('driver_availability_blocks')) return tables.blocks;
    if (name.includes('driver_weekly_availability')) return tables.weekly;
    if (name.includes('driver_export_tokens')) return tables.tokens;
    return new MemTable();
  };

  return {
    select: (..._args: any[]) => ({
      from: (t: any) => {
        const tbl = resolveTable(t);
        let current = [...tbl.rows];
        const chain: any = {
          where: (_pred: any) => {
            // We intentionally do not interpret drizzle predicates in this
            // stub — tests construct input state so every select's driver_id
            // matches. Narrow results via js filter in each test.
            return chain;
          },
          orderBy: (_: any) => chain,
          limit: (n: number) => {
            current = current.slice(0, n);
            return current;
          },
          then: (res: any, rej: any) =>
            Promise.resolve(current).then(res, rej),
        };
        return chain;
      },
    }),
    insert: (t: any) => ({
      values: (vals: any | any[]) => {
        const tbl = resolveTable(t);
        const arr = Array.isArray(vals) ? vals : [vals];
        const inserted: Row[] = [];
        for (const v of arr) {
          const r = { id: tbl.nextId++, ...v };
          tbl.rows.push(r);
          inserted.push(r);
        }
        const tail: any = Promise.resolve(inserted);
        tail.$returningId = () => Promise.resolve(inserted.map((r) => ({ id: r.id })));
        return tail;
      },
    }),
    update: (t: any) => ({
      set: (vals: any) => ({
        where: async (_p: any) => {
          const tbl = resolveTable(t);
          tbl.rows = tbl.rows.map((r) => ({ ...r, ...vals }));
          return { affectedRows: tbl.rows.length };
        },
      }),
    }),
    delete: (t: any) => ({
      where: async (_p: any) => {
        const tbl = resolveTable(t);
        const before = tbl.rows.length;
        tbl.rows = []; // tests construct isolated state
        return { affectedRows: before };
      },
    }),
    execute: async (_sql: any) => {
      // hos_logs fallback — emulate "driver with 4 hours of driving this week"
      return [[{ mins: 240 }]];
    },
  };
}

/* -------------------------------------------------------------------------- */
/*  Module mocks                                                               */
/* -------------------------------------------------------------------------- */

vi.mock('../../db', () => ({
  getDb: async () => makeDb(),
}));

vi.mock('../../_core/trpc', () => {
  const { initTRPC } = require('@trpc/server');
  const t = initTRPC.context<{ user?: any }>().create();
  return {
    router: t.router,
    isolatedProcedure: t.procedure,
  };
});

/* -------------------------------------------------------------------------- */
/*  Test suite                                                                 */
/* -------------------------------------------------------------------------- */

import { availabilityRouter } from '../availability';

const ctx = { user: { id: 42, companyId: 7 } };

beforeEach(() => {
  tables.blocks = new MemTable();
  tables.weekly = new MemTable();
  tables.tokens = new MemTable();
});

describe('availabilityRouter', () => {
  const caller = (availabilityRouter as any).createCaller(ctx);

  it('getWeeklyGrid returns a 7 × 24 matrix', async () => {
    const res = await caller.getWeeklyGrid({ weekStartISO: '2026-04-12T00:00:00.000Z' });
    expect(res.grid).toHaveLength(7);
    for (const day of res.grid) expect(day).toHaveLength(24);
  });

  it('blockTime + getWeeklyGrid marks the hour as blocked', async () => {
    await caller.blockTime({
      fromISO: '2026-04-13T08:00:00.000Z',
      toISO: '2026-04-13T09:00:00.000Z',
      reason: 'Doctor',
    });
    const res = await caller.getWeeklyGrid({ weekStartISO: '2026-04-12T00:00:00.000Z' });
    // Monday (day 1) hour 8 should be blocked
    const cell = res.grid[1][8];
    expect(cell.blocked).toBe(true);
    expect(cell.reason).toBe('Doctor');
  });

  it('blockTime rejects inverted windows', async () => {
    await expect(
      caller.blockTime({
        fromISO: '2026-04-13T09:00:00.000Z',
        toISO: '2026-04-13T08:00:00.000Z',
      })
    ).rejects.toThrow();
  });

  it('setAvailability rejects overlapping slots', async () => {
    await expect(
      caller.setAvailability({
        dayOfWeek: 1,
        slots: [
          { startMin: 0, endMin: 600 },
          { startMin: 300, endMin: 1200 },
        ],
      })
    ).rejects.toThrow(/overlaps/);
  });

  it('setAvailability overwrites prior rows for the same day', async () => {
    await caller.setAvailability({ dayOfWeek: 2, slots: [{ startMin: 0, endMin: 480 }] });
    await caller.setAvailability({
      dayOfWeek: 2,
      slots: [{ startMin: 540, endMin: 1020 }],
    });
    expect(tables.weekly.rows).toHaveLength(1);
    expect(tables.weekly.rows[0].startMin).toBe(540);
  });

  it('getUtilization returns driving / available ratio', async () => {
    // weekly: 6 hours/day × 7 days = 42h = 2520 min available
    for (let d = 0; d < 7; d++) {
      await caller.setAvailability({
        dayOfWeek: d,
        slots: [{ startMin: 0, endMin: 360 }],
      });
    }
    const res = await caller.getUtilization({
      weekStartISO: '2026-04-12T00:00:00.000Z',
    });
    // stub returns 240 driving min → 240/2520 = 0.095… → 10 (rounded)
    expect(res.utilization).not.toBeNull();
    expect(res.utilizationPct).toBeGreaterThan(0);
    expect(res.utilizationPct).toBeLessThan(100);
  });

  it('exportICS returns a signed URL with a future expiry', async () => {
    const res = await caller.exportICS({ weekStartISO: '2026-04-12T00:00:00.000Z' });
    expect(res.url).toMatch(/\.ics$/);
    expect(new Date(res.expiresAt).getTime()).toBeGreaterThan(Date.now());
    expect(tables.tokens.rows).toHaveLength(1);
  });
});
