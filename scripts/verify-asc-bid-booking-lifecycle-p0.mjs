import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const iosRoot = resolve(import.meta.dirname, "..");
const backendRoot = resolve(
  process.env.EUSOTRIP_BACKEND_ROOT ??
    "/Users/diegousoro/_codex_rios_hardening/frontend",
);

const paths = {
  api: resolve(iosRoot, "EusoTrip/Services/EusoTripAPI.swift"),
  carrierCounters: resolve(
    iosRoot,
    "EusoTrip/Views/Carrier/305_CarrierCounterResponse.swift",
  ),
  carrierBids: resolve(
    iosRoot,
    "EusoTrip/Views/Carrier/308_CarrierMyBids.swift",
  ),
  driverBids: resolve(iosRoot, "EusoTrip/Views/Driver/107_MeMyBids.swift"),
  driverBoard: resolve(iosRoot, "EusoTrip/Views/Driver/108_MeLoadBoard.swift"),
  shipperCounter: resolve(
    iosRoot,
    "EusoTrip/Views/Shipper/415_CounterOfferComposer.swift",
  ),
  loadBidding: resolve(backendRoot, "server/routers/loadBidding.ts"),
  bidAwardNotifications: resolve(
    backendRoot,
    "server/services/bidAwardNotifications.ts",
  ),
  loadBoard: resolve(backendRoot, "server/routers/loadBoard.ts"),
};

for (const [label, path] of Object.entries(paths)) {
  if (!existsSync(path)) throw new Error(`${label} source is missing: ${path}`);
}

const source = Object.fromEntries(
  Object.entries(paths).map(([label, path]) => [
    label,
    readFileSync(path, "utf8"),
  ]),
);

const checks = [];
const check = (passed, message) => checks.push([Boolean(passed), message]);

check(
  source.shipperCounter.includes("loadBidding.counter(") &&
    source.shipperCounter.includes("requestKey: requestKey") &&
    source.shipperCounter.includes(
      'confirmedStatus?.lowercased() == "pending"',
    ) &&
    source.shipperCounter.includes("ack.opaqueLoadID == loadId") &&
    !source.shipperCounter.includes("shippers.counterBid") &&
    !source.shipperCounter.includes("catalysts."),
  "shipper counter composer uses the canonical append-only contract and confirms persisted identity/status",
);

check(
  ["getMyBids", "getBidChain", "accept", "reject"].every((method) =>
    source.carrierCounters.includes(`loadBidding.${method}(`),
  ) &&
    source.carrierCounters.includes("requestKeys") &&
    source.carrierCounters.includes("ack.opaqueID == bid.bidId") &&
    !source.carrierCounters.includes("catalysts.respondToCounter"),
  "carrier counter inbox reads the canonical chain and confirms accept/decline readback",
);

check(
  source.carrierBids.includes("loadBidding.getMyBids") &&
    source.carrierBids.includes("loadBidding.withdraw") &&
    source.carrierBids.includes('"bidId": b.opaqueID') &&
    source.carrierBids.includes('"loadId": b.opaqueLoadID') &&
    !source.carrierBids.includes("parseInt(") &&
    !source.carrierBids.includes("catalysts."),
  "carrier My Bids preserves opaque IDs for withdrawal and one counter-detail route",
);

const driverRouteEvents =
  source.driverBids.match(/name:\s*\.eusoDriverMeNavSwap/g) ?? [];
check(
  driverRouteEvents.length === 1 &&
    source.driverBids.includes('"screenId": "109"') &&
    source.driverBids.includes('"loadId": b.opaqueLoadID') &&
    source.driverBids.includes('"bidId": b.opaqueID') &&
    source.driverBids.includes("return HStack(alignment: .top") &&
    source.driverBids.includes(".frame(width: 44, height: 44)") &&
    !source.driverBids.includes('MeAction.fire("driver.bid.detail")'),
  "driver My Bids emits one detail route and keeps withdrawal as a separate accessible control",
);

check(
  source.api.includes('if httpStatus == 401 || code == "UNAUTHORIZED"') &&
    source.api.includes('if httpStatus == 403 || code == "FORBIDDEN"') &&
    source.api.includes("func counter(\n        parentBidId: String") &&
    source.api.includes("func accept(bidId: String") &&
    source.api.includes("func reject(bidId: String") &&
    source.api.includes("func withdraw(bidId: String") &&
    source.api.includes("durableMutationRequestKey") &&
    source.api.includes(
      "UserDefaults.standard.removeObject(forKey: storageKey)",
    ) &&
    source.api.includes("struct BookAck") &&
    source.api.includes('status.lowercased() == "assigned"'),
  "native transport distinguishes authentication from authorization and confirms opaque bid/booking replies",
);

check(
  source.driverBoard.includes("EusoTripAPIError.bidActionMessage(for: error") &&
    !source.driverBoard.includes(
      'phase = .error("Couldn\'t reach loadboard.")',
    ),
  "load-board read failures retain server authentication and permission meaning",
);

check(
  source.loadBidding.includes("participantBidRows(bids, actor)") &&
    source.loadBidding.includes(
      "participantBidRows(rows, actor, input.rootBidId)",
    ) &&
    source.loadBidding.includes("actorMatchesBidParty") &&
    source.loadBidding.includes('eventType: "LOAD_BID_AWARDED"') &&
    source.loadBidding.includes("stageBidAwardNotifications({") &&
    source.loadBidding.includes("pushAfterCommit(pendingPushes)") &&
    source.bidAwardNotifications.includes('kind: "bid_awarded"') &&
    source.bidAwardNotifications.includes('kind: "bid_rejected"') &&
    source.bidAwardNotifications.includes(
      "uniqueLosingBidNotificationRecipients",
    ) &&
    source.bidAwardNotifications.includes(
      "await input.tx.insert(notifications).values",
    ) &&
    source.bidAwardNotifications.includes("input.pendingPushes.push({") &&
    !source.bidAwardNotifications.includes("catch"),
  "backend bid lifecycle enforces scoped chain reads, durable audit intent, and counterpart fan-out",
);

check(
  source.loadBoard.includes('eventType: "loadBoard.load_booked"') &&
    source.loadBoard.includes('kind: "load_assigned"') &&
    source.loadBoard.includes('transportMode !== "truck"') &&
    source.loadBoard.includes("Booked load could not be read after commit") &&
    !source.loadBoard.includes("tx.insert(blockchainAuditTrail)"),
  "direct truck booking is atomic and modal rail/vessel tenders remain on their dedicated contracts",
);

const ascLedgerPath = process.env.ASC_FEEDBACK_LEDGER_PATH;
if (ascLedgerPath) {
  if (!existsSync(ascLedgerPath))
    throw new Error(`ASC ledger is missing: ${ascLedgerPath}`);
  const ledgerText = readFileSync(ascLedgerPath, "utf8");
  for (const id of [
    "AEuxcjFC6TqYZi_La_71nZE",
    "ANrM-rPrMp8qNus3VGzS5Ys",
    "AJEPP90FE99BJqwMgcIyuUI",
    "AJQF0lxpGKttgViCSJrkRr4",
  ]) {
    check(
      ledgerText.includes(id),
      `live ASC ledger contains source submission ${id}`,
    );
  }
}

const failures = checks
  .filter(([passed]) => !passed)
  .map(([, message]) => message);
if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  process.exit(1);
}
for (const [, message] of checks) console.log(`PASS: ${message}`);
