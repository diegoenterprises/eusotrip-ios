/**
 * server/routers/bayOps/_shared.ts
 *
 * Wave-4 · Theme 2.3 — common FSM machinery used by every bayOps wizard:
 *   discharge, disconnect, connectHose, backingAssist.
 *
 * Design notes
 * ------------
 * - FSM tables live in TypeScript, NOT in the database (per build brief).
 * - Each wizard exports `FSM: Record<Step, Step[]>` of legal transitions.
 * - In-memory session map is keyed by loadId and wizardKind — exactly one
 *   live wizard per (loadId, kind) at a time.
 * - Persistence is append-only to `bay_ops_events` (see migration 0130);
 *   re-hydrating a session is a matter of replaying rows ORDER BY created_at.
 * - S3 keys are accepted as opaque strings. Upload happens client-side via
 *   a presigned URL minted by the `uploads/` router family.
 */

import { z } from 'zod';
import { TRPCError } from '@trpc/server';
import { db } from '../../db';
import { bayOpsEvents } from '../../../drizzle/schema.additions.wave4-4';
import { and, desc, eq } from 'drizzle-orm';
import { roleProcedure, router } from '../../trpc';

/* -------------------------------------------------------------------------- */
/*  Types                                                                      */
/* -------------------------------------------------------------------------- */

export type WizardKind =
  | 'discharge'
  | 'disconnect'
  | 'connectHose'
  | 'backingAssist';

export type WizardStatus = 'in_progress' | 'complete' | 'aborted';

export interface WizardSession<Step extends string = string> {
  loadId: string;
  kind: WizardKind;
  step: Step;
  status: WizardStatus;
  startedAt: Date;
  startedBy: string;
  lastEventId: string;
}

/** In-memory map keyed by `${kind}:${loadId}`. */
const sessions = new Map<string, WizardSession>();

export const sessionKey = (kind: WizardKind, loadId: string) =>
  `${kind}:${loadId}`;

/* -------------------------------------------------------------------------- */
/*  Zod input helpers                                                          */
/* -------------------------------------------------------------------------- */

export const StartInput = z.object({
  loadId: z.string().uuid(),
  /** Free-form context (bay, trailer, etc.) persisted in payload. */
  context: z.record(z.unknown()).optional(),
});

export const AdvanceInput = z.object({
  loadId: z.string().uuid(),
  toStep: z.string(),
  payload: z.record(z.unknown()).optional(),
});

export const EvidenceInput = z.object({
  loadId: z.string().uuid(),
  step: z.string(),
  s3Key: z.string().min(4),
  kind: z.enum(['photo', 'video', 'audio', 'pdf', 'sensor_log']),
  note: z.string().optional(),
});

export const CompleteInput = z.object({
  loadId: z.string().uuid(),
  payload: z.record(z.unknown()).optional(),
});

export const AbortInput = z.object({
  loadId: z.string().uuid(),
  reason: z.string().min(1),
});

/* -------------------------------------------------------------------------- */
/*  Session helpers                                                            */
/* -------------------------------------------------------------------------- */

export function assertNoSession(kind: WizardKind, loadId: string) {
  if (sessions.has(sessionKey(kind, loadId))) {
    throw new TRPCError({
      code: 'CONFLICT',
      message: `A ${kind} wizard is already running for load ${loadId}.`,
    });
  }
}

export function requireSession<Step extends string>(
  kind: WizardKind,
  loadId: string,
): WizardSession<Step> {
  const s = sessions.get(sessionKey(kind, loadId)) as
    | WizardSession<Step>
    | undefined;
  if (!s) {
    throw new TRPCError({
      code: 'NOT_FOUND',
      message: `No active ${kind} wizard for load ${loadId}.`,
    });
  }
  if (s.status !== 'in_progress') {
    throw new TRPCError({
      code: 'FAILED_PRECONDITION',
      message: `Wizard ${kind} for load ${loadId} is ${s.status}.`,
    });
  }
  return s;
}

export function putSession(s: WizardSession) {
  sessions.set(sessionKey(s.kind, s.loadId), s);
}

export function dropSession(kind: WizardKind, loadId: string) {
  sessions.delete(sessionKey(kind, loadId));
}

/** Test-only helper to nuke in-memory state. */
export function __resetBayOpsSessions() {
  sessions.clear();
}

/* -------------------------------------------------------------------------- */
/*  FSM guard                                                                  */
/* -------------------------------------------------------------------------- */

export function guardTransition<Step extends string>(
  fsm: Record<Step, Step[]>,
  from: Step,
  to: Step,
) {
  const legal = fsm[from] ?? [];
  if (!legal.includes(to)) {
    throw new TRPCError({
      code: 'BAD_REQUEST',
      message: `Illegal transition ${from} → ${to}. Legal: [${legal.join(', ')}]`,
    });
  }
}

export function terminalSteps<Step extends string>(
  fsm: Record<Step, Step[]>,
): Step[] {
  return (Object.keys(fsm) as Step[]).filter((k) => fsm[k].length === 0);
}

/* -------------------------------------------------------------------------- */
/*  Persistence                                                                */
/* -------------------------------------------------------------------------- */

export async function persistEvent(params: {
  loadId: string;
  wizardKind: WizardKind;
  step: string;
  payload: Record<string, unknown>;
  evidenceS3Key?: string | null;
  driverId: string;
}): Promise<{ id: string }> {
  const [row] = await db
    .insert(bayOpsEvents)
    .values({
      loadId: params.loadId,
      wizardKind: params.wizardKind,
      step: params.step,
      payload: params.payload,
      evidenceS3Key: params.evidenceS3Key ?? null,
      createdByDriverId: params.driverId,
    })
    .returning({ id: bayOpsEvents.id });
  return { id: row.id };
}

/* -------------------------------------------------------------------------- */
/*  Wizard router factory                                                      */
/* -------------------------------------------------------------------------- */

export interface WizardRouterConfig<Step extends string> {
  kind: WizardKind;
  fsm: Record<Step, Step[]>;
  initialStep: Step;
}

/**
 * Builds a tRPC sub-router with the five canonical procedures.
 * Each wizard file calls this to avoid copy-pasting the boilerplate.
 */
export function buildWizardRouter<Step extends string>(
  cfg: WizardRouterConfig<Step>,
) {
  const DRIVER_WRITE = roleProcedure(['DRIVER']);
  const READ = roleProcedure(['DISPATCHER', 'DRIVER']);

  return router({
    /* ----- reads ------------------------------------------------------- */
    getSession: READ.input(z.object({ loadId: z.string().uuid() })).query(
      async ({ input }) => {
        const s = sessions.get(sessionKey(cfg.kind, input.loadId)) ?? null;
        const history = await db
          .select()
          .from(bayOpsEvents)
          .where(
            and(
              eq(bayOpsEvents.loadId, input.loadId),
              eq(bayOpsEvents.wizardKind, cfg.kind),
            ),
          )
          .orderBy(desc(bayOpsEvents.createdAt))
          .limit(200);
        return { session: s, history };
      },
    ),

    /* ----- writes (DRIVER only) --------------------------------------- */
    start: DRIVER_WRITE.input(StartInput).mutation(async ({ ctx, input }) => {
      assertNoSession(cfg.kind, input.loadId);
      const driverId = ctx.user.id;
      const ev = await persistEvent({
        loadId: input.loadId,
        wizardKind: cfg.kind,
        step: cfg.initialStep,
        payload: { phase: 'start', context: input.context ?? {} },
        driverId,
      });
      const session: WizardSession<Step> = {
        loadId: input.loadId,
        kind: cfg.kind,
        step: cfg.initialStep,
        status: 'in_progress',
        startedAt: new Date(),
        startedBy: driverId,
        lastEventId: ev.id,
      };
      putSession(session);
      return { session };
    }),

    advanceStep: DRIVER_WRITE.input(AdvanceInput).mutation(
      async ({ ctx, input }) => {
        const s = requireSession<Step>(cfg.kind, input.loadId);
        guardTransition(cfg.fsm, s.step, input.toStep as Step);
        const ev = await persistEvent({
          loadId: input.loadId,
          wizardKind: cfg.kind,
          step: input.toStep,
          payload: { phase: 'advance', from: s.step, ...(input.payload ?? {}) },
          driverId: ctx.user.id,
        });
        s.step = input.toStep as Step;
        s.lastEventId = ev.id;
        putSession(s);
        return { session: s };
      },
    ),

    recordEvidence: DRIVER_WRITE.input(EvidenceInput).mutation(
      async ({ ctx, input }) => {
        const s = requireSession<Step>(cfg.kind, input.loadId);
        const ev = await persistEvent({
          loadId: input.loadId,
          wizardKind: cfg.kind,
          step: input.step,
          payload: {
            phase: 'evidence',
            kind: input.kind,
            note: input.note ?? null,
          },
          evidenceS3Key: input.s3Key,
          driverId: ctx.user.id,
        });
        return { eventId: ev.id, step: s.step };
      },
    ),

    complete: DRIVER_WRITE.input(CompleteInput).mutation(
      async ({ ctx, input }) => {
        const s = requireSession<Step>(cfg.kind, input.loadId);
        const terminals = terminalSteps(cfg.fsm);
        if (!terminals.includes(s.step)) {
          throw new TRPCError({
            code: 'FAILED_PRECONDITION',
            message: `Cannot complete ${cfg.kind}: step ${s.step} is not terminal (terminals=${terminals.join(',')}).`,
          });
        }
        const ev = await persistEvent({
          loadId: input.loadId,
          wizardKind: cfg.kind,
          step: s.step,
          payload: { phase: 'complete', ...(input.payload ?? {}) },
          driverId: ctx.user.id,
        });
        s.status = 'complete';
        s.lastEventId = ev.id;
        putSession(s);
        // Keep session in memory briefly for clients to read, then drop.
        setTimeout(() => dropSession(cfg.kind, input.loadId), 15_000);
        return { session: s };
      },
    ),

    abort: DRIVER_WRITE.input(AbortInput).mutation(async ({ ctx, input }) => {
      const s = requireSession<Step>(cfg.kind, input.loadId);
      const ev = await persistEvent({
        loadId: input.loadId,
        wizardKind: cfg.kind,
        step: s.step,
        payload: { phase: 'abort', reason: input.reason },
        driverId: ctx.user.id,
      });
      s.status = 'aborted';
      s.lastEventId = ev.id;
      putSession(s);
      setTimeout(() => dropSession(cfg.kind, input.loadId), 15_000);
      return { session: s };
    }),
  });
}
