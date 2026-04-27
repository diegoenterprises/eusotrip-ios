/**
 * server/routers/bayOps/backingAssist.ts
 *
 * Wave-4 · Theme 2.3 — Backing-assist session + live telemetry (screen 039).
 *
 * Steps
 * -----
 *   align   → bay aligned, cameras live, spotter on-channel.
 *   approach→ driver reversing; ultrasonic distance streaming.
 *   engage  → distance <= engagementThreshold; "Set parking brake" prompt.
 *   secured → parking brake confirmed, air-dumped, chocks placed. Terminal.
 *
 * Unlike the three wizards above, this router also exposes:
 *   - recordDistanceSample: append an ultrasonic distance reading
 *   - recordTelemetry:      append a generic telemetry frame (cams, clearance)
 */

import { z } from 'zod';
import { TRPCError } from '@trpc/server';
import {
  buildWizardRouter,
  persistEvent,
  requireSession,
  sessionKey,
} from './_shared';
import { mergeRouters, roleProcedure, router } from '../../trpc';

export type BackingAssistStep = 'align' | 'approach' | 'engage' | 'secured';

export const FSM: Record<BackingAssistStep, BackingAssistStep[]> = {
  align: ['approach'],
  approach: ['engage'],
  engage: ['secured'],
  secured: [], // terminal
};

/** Default threshold (inches) at which the UI flips to "set parking brake". */
export const DEFAULT_ENGAGE_THRESHOLD_IN = 4;

const baseRouter = buildWizardRouter<BackingAssistStep>({
  kind: 'backingAssist',
  fsm: FSM,
  initialStep: 'align',
});

/* -------------------------------------------------------------------------- */
/*  Telemetry extensions                                                       */
/* -------------------------------------------------------------------------- */

const DistanceInput = z.object({
  loadId: z.string().uuid(),
  /** cm → inches conversion happens client-side; server stores both. */
  rearIn: z.number().nonnegative(),
  leftClearanceIn: z.number().nonnegative().optional(),
  rightClearanceIn: z.number().nonnegative().optional(),
  sensorSource: z.enum(['ultrasonic', 'lidar', 'camera-ai']).default('ultrasonic'),
  capturedAt: z.string().datetime().optional(),
});

const TelemetryInput = z.object({
  loadId: z.string().uuid(),
  frame: z.record(z.unknown()),
  /** Optional S3 key of a short camera clip tied to this frame. */
  clipS3Key: z.string().optional(),
});

const telemetryRouter = router({
  /**
   * Append one ultrasonic distance sample. Also evaluates whether the engage
   * threshold has been crossed and hints the client to prompt "set parking
   * brake" — the actual FSM transition still requires an explicit
   * advanceStep({ toStep: 'engage' }) from the driver.
   */
  recordDistanceSample: roleProcedure(['DRIVER'])
    .input(DistanceInput)
    .mutation(async ({ ctx, input }) => {
      const s = requireSession<BackingAssistStep>('backingAssist', input.loadId);
      const ev = await persistEvent({
        loadId: input.loadId,
        wizardKind: 'backingAssist',
        step: s.step,
        payload: {
          phase: 'distance',
          rearIn: input.rearIn,
          leftClearanceIn: input.leftClearanceIn ?? null,
          rightClearanceIn: input.rightClearanceIn ?? null,
          sensorSource: input.sensorSource,
          capturedAt: input.capturedAt ?? new Date().toISOString(),
        },
        driverId: ctx.user.id,
      });
      return {
        eventId: ev.id,
        shouldPromptEngage: input.rearIn <= DEFAULT_ENGAGE_THRESHOLD_IN,
        sessionStep: s.step,
      };
    }),

  /** Generic telemetry frame — camera tiles, LiDAR blobs, ESANG overlay, etc. */
  recordTelemetry: roleProcedure(['DRIVER'])
    .input(TelemetryInput)
    .mutation(async ({ ctx, input }) => {
      const s = requireSession<BackingAssistStep>('backingAssist', input.loadId);
      const ev = await persistEvent({
        loadId: input.loadId,
        wizardKind: 'backingAssist',
        step: s.step,
        payload: { phase: 'telemetry', frame: input.frame },
        evidenceS3Key: input.clipS3Key ?? null,
        driverId: ctx.user.id,
      });
      return { eventId: ev.id, sessionStep: s.step };
    }),

  /** Convenience read — lightweight "is there a live backing session?" probe. */
  hasActiveSession: roleProcedure(['DISPATCHER', 'DRIVER'])
    .input(z.object({ loadId: z.string().uuid() }))
    .query(({ input }) => {
      try {
        const s = requireSession<BackingAssistStep>(
          'backingAssist',
          input.loadId,
        );
        return { active: true, step: s.step, key: sessionKey('backingAssist', input.loadId) };
      } catch (e) {
        if (e instanceof TRPCError && e.code === 'NOT_FOUND') {
          return { active: false, step: null, key: sessionKey('backingAssist', input.loadId) };
        }
        throw e;
      }
    }),
});

export const backingAssistRouter = mergeRouters(baseRouter, telemetryRouter);
