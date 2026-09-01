import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const iosRoot = resolve(import.meta.dirname, "..");
const backendRoot = process.env.EUSOTRIP_BACKEND_ROOT
  ? resolve(process.env.EUSOTRIP_BACKEND_ROOT)
  : "/Users/diegousoro/_codex_rios_hardening/frontend";

const files = {
  api: resolve(iosRoot, "EusoTrip/Services/EusoTripAPI.swift"),
  truckDetail: resolve(iosRoot, "EusoTrip/Views/Components/LoadDetailSheet.swift"),
  truckBid: resolve(iosRoot, "EusoTrip/Views/Driver/109_MeBidDetail.swift"),
  shipperThread: resolve(iosRoot, "EusoTrip/Views/Shipper/230_ShipperBidThread.swift"),
  shipperReview: resolve(iosRoot, "EusoTrip/Views/Shipper/241_ShipperCounterReview.swift"),
  vessel: resolve(iosRoot, "EusoTrip/Views/Vessel/009_VesselTenderWorkflow.swift"),
  vesselCarrier: resolve(iosRoot, "EusoTrip/Views/Vessel/677_VesselCarrierTenderWorkflow.swift"),
  rail: resolve(iosRoot, "EusoTrip/Views/Rail/627_RailBidBoard.swift"),
  loadBidding: resolve(backendRoot, "server/routers/loadBidding.ts"),
  shippers: resolve(backendRoot, "server/routers/shippers.ts"),
  railRouter: resolve(backendRoot, "server/routers/railShipments.ts"),
  vesselRouter: resolve(backendRoot, "server/routers/vesselShipments.ts"),
  advancedWeb: resolve(backendRoot, "client/src/pages/LoadBiddingAdvanced.tsx"),
  catalystWeb: resolve(backendRoot, "client/src/pages/CatalystLoadBoardNW.tsx"),
  shipperWeb: resolve(backendRoot, "client/src/pages/ShipperDashboardNW.tsx"),
  vesselWeb: resolve(backendRoot, "client/src/pages/vessel/VesselBookingDetail.tsx"),
};

for (const [label, path] of Object.entries(files)) {
  if (!existsSync(path)) throw new Error(`${label} source is missing: ${path}`);
}

const source = Object.fromEntries(
  Object.entries(files).map(([label, path]) => [label, readFileSync(path, "utf8")])
);

const checks = [
  [
    source.loadBidding.includes("load-bid:submit:${input.requestKey}") &&
      source.loadBidding.includes("load-bid:award:${input.requestKey}") &&
      source.loadBidding.includes("requestFingerprint") &&
      source.loadBidding.includes("recoveredReplayBinding: true"),
    "canonical truck submit and award bind a full fingerprint to a durable outbox request key",
  ],
  [
    source.shippers.includes("load-bid:award:${input.requestKey}") &&
      source.shippers.includes("mintRateConfirmationInTransaction") &&
      source.shippers.includes("resolveAuthenticatedDatabaseUser(ctx.user)") &&
      !source.shippers.includes('eventType: "load.bid_accepted"'),
    "shipper truck award shares the canonical replay namespace, authoritative actor, and rate confirmation",
  ],
  [
    source.railRouter.includes("rail.bid_award:${input.requestKey}") &&
      source.railRouter.includes("recoveredReplayBinding: true") &&
      source.railRouter.includes("await tx.insert(notifications).values(notificationRows)") &&
      source.railRouter.includes('eventType: "bid_rejected"') &&
      source.railRouter.includes("Every durable winner/loser notification committed with the award"),
    "rail award binds replay recovery and winner/loser outcomes to the award transaction",
  ],
  [
    source.vesselRouter.includes("vessel.bid_award:${input.requestKey}") &&
      source.vesselRouter.includes("recoveredReplayBinding: true") &&
      source.vesselRouter.includes("activeInvitations") &&
      source.vesselRouter.includes("await tx.insert(notifications).values(notificationRows)") &&
      source.vesselRouter.includes("pushAfterCommit(pendingPushes)"),
    "vessel award binds replay and every operator outcome to the committed award",
  ],
  [
    source.railRouter.includes("rail.bid_submit:${input.requestKey}") &&
      source.railRouter.includes('eventType: "rail.bid_submitted"') &&
      source.vesselRouter.includes("vessel.bid_submit:${input.requestKey}") &&
      source.vesselRouter.includes('eventType: "vessel.bid_submitted"'),
    "rail and vessel quote submissions bind caller keys to durable outbox fingerprints",
  ],
  [
    source.api.includes("private func awardRequestStorageKey(loadId: String, bidId: String)") &&
      source.api.includes("UserDefaults.standard.set(requestKey, forKey: storageKey)") &&
      source.api.includes("UserDefaults.standard.removeObject(forKey: durable.storageKey)") &&
      !source.api.includes("requestKey: String = UUID().uuidString.lowercased()"),
    "native canonical truck API persists a credential-scoped key and clears it only after confirmation",
  ],
  [
    [source.truckDetail, source.truckBid, source.shipperThread, source.shipperReview, source.vessel]
      .every(text => text.includes("requestKey")),
    "active native truck and vessel award callers send an explicit request key",
  ],
  [
    source.rail.includes("railShipments.acceptRailBid") &&
      source.rail.includes("awardRequestStorageKey(") &&
      source.rail.includes("UserDefaults.standard.set(requestKey, forKey: storageKey)") &&
      source.rail.includes("UserDefaults.standard.removeObject(forKey: storageKey)") &&
      source.rail.includes("let carrierId: Int?") &&
      source.rail.includes('context?.status == "requested"'),
    "native rail owner can award an exact carrier bid with a key retained across relaunches",
  ],
  [
    source.rail.includes('case "not_selected": return "Your quote was not selected') &&
      source.rail.includes('context?.isOwner == true ? "QUOTES · LOWEST FIRST" : "YOUR QUOTE"') &&
      source.railRouter.includes("const visibleBids = isOwner ? bids : bids.filter(isOwnBid)") &&
      source.railRouter.includes('["bid_accepted", "bid_rejected"]'),
    "rail bidders retain their own terminal outcome without competitor quote disclosure",
  ],
  [
    source.vesselCarrier.includes("quoteRequestStorageKey(") &&
      source.vesselCarrier.includes("UserDefaults.standard.set(requestKey, forKey: storageKey)") &&
      source.vesselCarrier.includes("UserDefaults.standard.removeObject(forKey: storageKey)") &&
      source.vesselCarrier.includes('"vesselShipments.createVesselBid"'),
    "native vessel operators retain quote identity across relaunches until server confirmation",
  ],
  [
    [source.advancedWeb, source.catalystWeb, source.shipperWeb]
      .every(text => text.includes("crypto.randomUUID()") && text.includes("requestKey")),
    "active web award and submit callers allocate browser UUIDs",
  ],
  [
    source.advancedWeb.includes("awardRequestKeys.current.delete") &&
      source.catalystWeb.includes("bidRequestKeys.current.delete") &&
      source.shipperWeb.includes("awardRequestKeys.current.delete") &&
      source.vesselWeb.includes("bidRequestKeys.current.delete") &&
      source.vesselWeb.includes("bidRequestKeys.current.set(intent, requestKey)"),
    "web request keys are cleared only from confirmed success callbacks",
  ],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  process.exit(1);
}

for (const [, message] of checks) console.log(`PASS: ${message}`);
