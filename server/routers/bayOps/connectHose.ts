/**
 * server/routers/bayOps/connectHose.ts
 *
 * Wave-4 · Theme 2.3 — Connect-hose wizard (screen 044).
 *
 * Steps
 * -----
 *   grounding     → ESD bond probe live, continuity OK.
 *   coupling      → dry-break mate seated.
 *   pressureTest  → NAATS leak-test step-1 prime, 0 psi empty. Terminal.
 */

import { buildWizardRouter } from './_shared';

export type ConnectHoseStep = 'grounding' | 'coupling' | 'pressureTest';

export const FSM: Record<ConnectHoseStep, ConnectHoseStep[]> = {
  grounding: ['coupling'],
  coupling: ['pressureTest'],
  pressureTest: [], // terminal
};

export const connectHoseRouter = buildWizardRouter<ConnectHoseStep>({
  kind: 'connectHose',
  fsm: FSM,
  initialStep: 'grounding',
});
