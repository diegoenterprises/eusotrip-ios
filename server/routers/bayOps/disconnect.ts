/**
 * server/routers/bayOps/disconnect.ts
 *
 * Wave-4 · Theme 2.3 — Disconnect wizard (screens 042 / 043).
 *
 * Steps
 * -----
 *   blowdown → vent residual product, wait for pressure ≈ 0 psi.
 *   break    → retract dry-break collar, confirm uncoupled.
 *   cap      → cap/stow hose, close binder.
 *   photo    → photo evidence of stowed state + walk-around. Terminal.
 */

import { buildWizardRouter } from './_shared';

export type DisconnectStep = 'blowdown' | 'break' | 'cap' | 'photo';

export const FSM: Record<DisconnectStep, DisconnectStep[]> = {
  blowdown: ['break'],
  break: ['cap'],
  cap: ['photo'],
  photo: [], // terminal
};

export const disconnectRouter = buildWizardRouter<DisconnectStep>({
  kind: 'disconnect',
  fsm: FSM,
  initialStep: 'blowdown',
});
