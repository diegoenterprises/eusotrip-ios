/**
 * server/routers/bayOps/index.ts
 *
 * Wave-4 · Theme 2.3 — Grouped bayOps router.
 *
 * Mount this in `server/routers.ts` alongside `loadLifecycle`:
 *
 *   import { bayOpsRouter } from './routers/bayOps';
 *   export const appRouter = router({ ..., bayOps: bayOpsRouter });
 *
 * Client call-sites then look like:
 *   trpc.bayOps.discharge.start.useMutation()
 *   trpc.bayOps.backingAssist.recordDistanceSample.useMutation()
 */

import { router } from '../../trpc';
import { dischargeRouter, FSM as DISCHARGE_FSM } from './discharge';
import { disconnectRouter, FSM as DISCONNECT_FSM } from './disconnect';
import { connectHoseRouter, FSM as CONNECT_HOSE_FSM } from './connectHose';
import {
  backingAssistRouter,
  FSM as BACKING_ASSIST_FSM,
} from './backingAssist';

export const bayOpsRouter = router({
  discharge: dischargeRouter,
  disconnect: disconnectRouter,
  connectHose: connectHoseRouter,
  backingAssist: backingAssistRouter,
});

export const BAY_OPS_FSMS = {
  discharge: DISCHARGE_FSM,
  disconnect: DISCONNECT_FSM,
  connectHose: CONNECT_HOSE_FSM,
  backingAssist: BACKING_ASSIST_FSM,
} as const;

export type BayOpsRouter = typeof bayOpsRouter;
