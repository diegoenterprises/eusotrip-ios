/**
 * server/routers/bayOps/discharge.ts
 *
 * Wave-4 · Theme 2.3 — Discharge wizard (screens 040 / 041).
 *
 * Steps
 * -----
 *   arm    → operator arms the bay; ESD bond verified, VRC locked.
 *   purge  → pre-flow purge, residual vapor check.
 *   meter  → live discharge, flow/pressure/temp telemetry streamed separately.
 *   seal   → BOL sealed, run-ticket finalised. Terminal step.
 */

import { buildWizardRouter } from './_shared';

export type DischargeStep = 'arm' | 'purge' | 'meter' | 'seal';

export const FSM: Record<DischargeStep, DischargeStep[]> = {
  arm: ['purge'],
  purge: ['meter'],
  meter: ['seal'],
  seal: [], // terminal
};

export const dischargeRouter = buildWizardRouter<DischargeStep>({
  kind: 'discharge',
  fsm: FSM,
  initialStep: 'arm',
});
