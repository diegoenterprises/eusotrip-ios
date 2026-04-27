/**
 * server/routers/__tests__/bayOps.test.ts
 *
 * Wave-4 · Theme 2.3 — tests for the bayOps router family.
 *
 * These tests hit the tRPC procedures through a server-side caller using a
 * mocked driver context. Database writes are stubbed: `../../db` is mocked so
 * every insert returns a fresh UUID and every select returns an empty history.
 *
 * Coverage
 * --------
 *  1. FSM tables — each wizard's `Record<Step, Step[]>` is well-formed.
 *  2. Happy path for every wizard: start → advance×N → complete.
 *  3. Guard rails — illegal transitions, double-start, complete-before-terminal,
 *     abort, driver-only mutations.
 *  4. backingAssist telemetry — recordDistanceSample / recordTelemetry.
 *
 * Test runner: vitest (swap for jest by renaming imports).
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { TRPCError } from '@trpc/server';

// --- db mock must be hoisted before router import ----------------------------
vi.mock('../../db', () => {
  const makeReturning = () => [{ id: cryptoRandom() }];
  const chain: any = {};
  chain.insert = () => chain;
  chain.values = () => chain;
  chain.returning = async () => makeReturning();
  chain.select = () => chain;
  chain.from = () => chain;
  chain.where = () => chain;
  chain.orderBy = () => chain;
  chain.limit = async () => [];
  return { db: chain };

  function cryptoRandom() {
    // RFC 4122 v4-ish, good enough for tests
    return (
      'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        const v = c === 'x' ? r : (r & 0x3) | 0x8;
        return v.toString(16);
      })
    );
  }
});

// --- trpc mock ---------------------------------------------------------------
vi.mock('../../trpc', async () => {
  // Minimal fakes so router files import cleanly and we can invoke procedures
  // directly. Not a full tRPC shim — enough for unit coverage.
  const makeProcedure = (allowedRoles: string[] | null) => {
    const build = (kind: 'query' | 'mutation') => {
      return (inputSchema: any) => ({
        [kind]: (resolver: any) => ({
          __kind: kind,
          __allowedRoles: allowedRoles,
          __inputSchema: inputSchema,
          __resolver: resolver,
        }),
      });
    };
    return {
      input: (schema: any) => ({
        query: (r: any) => ({
          __kind: 'query' as const,
          __allowedRoles: allowedRoles,
          __inputSchema: schema,
          __resolver: r,
        }),
        mutation: (r: any) => ({
          __kind: 'mutation' as const,
          __allowedRoles: allowedRoles,
          __inputSchema: schema,
          __resolver: r,
        }),
      }),
      // chainable variants unused by bayOps but included for safety
      query: build('query'),
      mutation: build('mutation'),
    };
  };
  return {
    roleProcedure: (roles: string[]) => makeProcedure(roles),
    router: (defs: Record<string, any>) => defs,
    mergeRouters: (a: Record<string, any>, b: Record<string, any>) => ({
      ...a,
      ...b,
    }),
  };
});

// ---- imports after mocks ----------------------------------------------------
import { bayOpsRouter, BAY_OPS_FSMS } from '../bayOps';
import { __resetBayOpsSessions } from '../bayOps/_shared';

// Tiny invoker that calls a procedure directly with a fake ctx.
type Ctx = { user: { id: string; role: 'DRIVER' | 'DISPATCHER' } };
const driverCtx: Ctx = { user: { id: 'drv-' + Date.now(), role: 'DRIVER' } };
const dispatcherCtx: Ctx = {
  user: { id: 'dsp-' + Date.now(), role: 'DISPATCHER' },
};

async function call(proc: any, ctx: Ctx, input: unknown) {
  if (proc.__allowedRoles && !proc.__allowedRoles.includes(ctx.user.role)) {
    throw new TRPCError({ code: 'FORBIDDEN', message: 'role not allowed' });
  }
  const parsed = proc.__inputSchema ? proc.__inputSchema.parse(input) : input;
  return proc.__resolver({ ctx, input: parsed });
}

const LOAD_A = '11111111-1111-4111-8111-111111111111';
const LOAD_B = '22222222-2222-4222-8222-222222222222';
const LOAD_C = '33333333-3333-4333-8333-333333333333';
const LOAD_D = '44444444-4444-4444-8444-444444444444';

beforeEach(() => __resetBayOpsSessions());

/* -------------------------------------------------------------------------- */
/*  1. FSM shape                                                               */
/* -------------------------------------------------------------------------- */

describe('bayOps FSM tables', () => {
  for (const [kind, fsm] of Object.entries(BAY_OPS_FSMS)) {
    it(`${kind}: every referenced target step is declared`, () => {
      const steps = new Set(Object.keys(fsm));
      for (const [from, tos] of Object.entries(fsm)) {
        for (const t of tos as string[]) {
          expect(steps.has(t), `${kind}: ${from} -> ${t}`).toBe(true);
        }
      }
    });
    it(`${kind}: exactly one terminal step`, () => {
      const terms = Object.entries(fsm).filter(
        ([, tos]) => (tos as string[]).length === 0,
      );
      expect(terms.length).toBe(1);
    });
  }
});

/* -------------------------------------------------------------------------- */
/*  2. Happy path                                                              */
/* -------------------------------------------------------------------------- */

describe('discharge happy path', () => {
  it('arm → purge → meter → seal → complete', async () => {
    const r = bayOpsRouter.discharge;
    await call(r.start, driverCtx, { loadId: LOAD_A });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_A, toStep: 'purge' });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_A, toStep: 'meter' });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_A, toStep: 'seal' });
    const res = await call(r.complete, driverCtx, { loadId: LOAD_A });
    expect(res.session.status).toBe('complete');
    expect(res.session.step).toBe('seal');
  });
});

describe('disconnect happy path', () => {
  it('blowdown → break → cap → photo → complete', async () => {
    const r = bayOpsRouter.disconnect;
    await call(r.start, driverCtx, { loadId: LOAD_B });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_B, toStep: 'break' });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_B, toStep: 'cap' });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_B, toStep: 'photo' });
    const res = await call(r.complete, driverCtx, { loadId: LOAD_B });
    expect(res.session.status).toBe('complete');
  });
});

describe('connectHose happy path', () => {
  it('grounding → coupling → pressureTest → complete', async () => {
    const r = bayOpsRouter.connectHose;
    await call(r.start, driverCtx, { loadId: LOAD_C });
    await call(r.advanceStep, driverCtx, {
      loadId: LOAD_C,
      toStep: 'coupling',
    });
    await call(r.advanceStep, driverCtx, {
      loadId: LOAD_C,
      toStep: 'pressureTest',
    });
    const res = await call(r.complete, driverCtx, { loadId: LOAD_C });
    expect(res.session.status).toBe('complete');
  });
});

describe('backingAssist happy path', () => {
  it('align → approach → engage → secured → complete', async () => {
    const r = bayOpsRouter.backingAssist;
    await call(r.start, driverCtx, { loadId: LOAD_D });
    await call(r.advanceStep, driverCtx, {
      loadId: LOAD_D,
      toStep: 'approach',
    });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_D, toStep: 'engage' });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_D, toStep: 'secured' });
    const res = await call(r.complete, driverCtx, { loadId: LOAD_D });
    expect(res.session.status).toBe('complete');
  });
});

/* -------------------------------------------------------------------------- */
/*  3. Guard rails                                                             */
/* -------------------------------------------------------------------------- */

describe('bayOps guard rails', () => {
  it('rejects illegal transition (discharge: arm -> seal)', async () => {
    const r = bayOpsRouter.discharge;
    await call(r.start, driverCtx, { loadId: LOAD_A });
    await expect(
      call(r.advanceStep, driverCtx, { loadId: LOAD_A, toStep: 'seal' }),
    ).rejects.toMatchObject({ code: 'BAD_REQUEST' });
  });

  it('rejects double start for the same load+kind', async () => {
    const r = bayOpsRouter.discharge;
    await call(r.start, driverCtx, { loadId: LOAD_A });
    await expect(
      call(r.start, driverCtx, { loadId: LOAD_A }),
    ).rejects.toMatchObject({ code: 'CONFLICT' });
  });

  it('allows parallel wizards of different kinds on the same load', async () => {
    await call(bayOpsRouter.discharge.start, driverCtx, { loadId: LOAD_A });
    await expect(
      call(bayOpsRouter.backingAssist.start, driverCtx, { loadId: LOAD_A }),
    ).resolves.toBeTruthy();
  });

  it('rejects complete before terminal step', async () => {
    const r = bayOpsRouter.disconnect;
    await call(r.start, driverCtx, { loadId: LOAD_B });
    await call(r.advanceStep, driverCtx, { loadId: LOAD_B, toStep: 'break' });
    await expect(
      call(r.complete, driverCtx, { loadId: LOAD_B }),
    ).rejects.toMatchObject({ code: 'FAILED_PRECONDITION' });
  });

  it('abort transitions session to aborted', async () => {
    const r = bayOpsRouter.connectHose;
    await call(r.start, driverCtx, { loadId: LOAD_C });
    const res = await call(r.abort, driverCtx, {
      loadId: LOAD_C,
      reason: 'spotter unavailable',
    });
    expect(res.session.status).toBe('aborted');
  });

  it('disallows DISPATCHER from calling a mutation', async () => {
    const r = bayOpsRouter.discharge;
    await expect(
      call(r.start, dispatcherCtx, { loadId: LOAD_A }),
    ).rejects.toMatchObject({ code: 'FORBIDDEN' });
  });

  it('allows DISPATCHER to call getSession (read)', async () => {
    const r = bayOpsRouter.discharge;
    const res = await call(r.getSession, dispatcherCtx, { loadId: LOAD_A });
    expect(res).toHaveProperty('session');
    expect(res).toHaveProperty('history');
  });

  it('recordEvidence attaches an S3 key without mutating FSM state', async () => {
    const r = bayOpsRouter.disconnect;
    await call(r.start, driverCtx, { loadId: LOAD_B });
    const res = await call(r.recordEvidence, driverCtx, {
      loadId: LOAD_B,
      step: 'blowdown',
      s3Key: 's3://evidence/foo.jpg',
      kind: 'photo',
      note: 'residual vented',
    });
    expect(res.step).toBe('blowdown');
    // Confirm we can still advance the FSM after evidence.
    await call(r.advanceStep, driverCtx, { loadId: LOAD_B, toStep: 'break' });
  });
});

/* -------------------------------------------------------------------------- */
/*  4. backingAssist telemetry                                                 */
/* -------------------------------------------------------------------------- */

describe('backingAssist telemetry', () => {
  it('recordDistanceSample flags shouldPromptEngage when rearIn <= threshold', async () => {
    const r = bayOpsRouter.backingAssist;
    await call(r.start, driverCtx, { loadId: LOAD_D });
    await call(r.advanceStep, driverCtx, {
      loadId: LOAD_D,
      toStep: 'approach',
    });
    const far = await call(r.recordDistanceSample, driverCtx, {
      loadId: LOAD_D,
      rearIn: 14,
      leftClearanceIn: 18,
      rightClearanceIn: 14,
    });
    expect(far.shouldPromptEngage).toBe(false);

    const close = await call(r.recordDistanceSample, driverCtx, {
      loadId: LOAD_D,
      rearIn: 3,
    });
    expect(close.shouldPromptEngage).toBe(true);
  });

  it('recordTelemetry accepts a generic frame + optional clip key', async () => {
    const r = bayOpsRouter.backingAssist;
    await call(r.start, driverCtx, { loadId: LOAD_D });
    const res = await call(r.recordTelemetry, driverCtx, {
      loadId: LOAD_D,
      frame: { rearCamFps: 30, leftMirror: 'ok', rightMirror: 'ok' },
      clipS3Key: 's3://telemetry/clip.mp4',
    });
    expect(res.eventId).toBeTruthy();
    expect(res.sessionStep).toBe('align');
  });

  it('hasActiveSession returns false when none is running', async () => {
    const r = bayOpsRouter.backingAssist;
    const res = await call(r.hasActiveSession, dispatcherCtx, {
      loadId: LOAD_D,
    });
    expect(res.active).toBe(false);
  });

  it('telemetry mutations reject when no wizard is running', async () => {
    const r = bayOpsRouter.backingAssist;
    await expect(
      call(r.recordDistanceSample, driverCtx, {
        loadId: LOAD_D,
        rearIn: 10,
      }),
    ).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });
});
