import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const read = (path) => readFileSync(join(root, path), "utf8");

const walkSwift = (directory) => {
  const paths = [];
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) paths.push(...walkSwift(path));
    else if (path.endsWith(".swift")) paths.push(path);
  }
  return paths;
};

const sliceBetween = (source, startMarker, endMarker) => {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end < 0) return "";
  return source.slice(start, end);
};

const api = read("EusoTrip/Services/EusoTripAPI.swift");
const pricing = read("EusoTrip/Views/Shipper/252_PostLoadStep3Pricing.swift");
const postDraft = read("EusoTrip/Views/Shipper/PostLoadDraft.swift");
const flagshipPost = read("EusoTrip/Views/Shipper/204_ShipperPostLoad.swift");
const liveStores = read("EusoTrip/ViewModels/LiveDataStores.swift");
const loadDetail = read("EusoTrip/Views/Components/LoadDetailSheet.swift");
const driverBid = read("EusoTrip/Views/Driver/109_MeBidDetail.swift");
const shipperBids = read("EusoTrip/Views/Shipper/203_ShipperBids.swift");
const shipperThread = read("EusoTrip/Views/Shipper/230_ShipperBidThread.swift");
const shipperCounter = read(
  "EusoTrip/Views/Shipper/241_ShipperCounterReview.swift",
);
const dispatcherDelivery = read(
  "EusoTrip/Views/Dispatch/520_DispatcherBhAtDeliveryCard.swift",
);
const serverCandidates = [
  process.env.EUSOTRIP_SERVER_ROOT,
  "/Users/diegousoro/_codex_rios_hardening/frontend",
  join(root, "../eusoronetechnologiesinc/frontend"),
].filter(Boolean);
const serverRoot = serverCandidates.find((candidate) =>
  existsSync(join(candidate, "server/routers/shippers.ts")),
);
if (!serverRoot)
  throw new Error(
    "Shippers server checkout not found. Set EUSOTRIP_SERVER_ROOT.",
  );
const shippersRouter = readFileSync(
  join(serverRoot, "server/routers/shippers.ts"),
  "utf8",
);

const termsModel = sliceBetween(
  api,
  "struct TruckDetentionNegotiatedTerms",
  "/// Provenance attached to an adjudicated suspension allocation",
);
const calculation = sliceBetween(
  api,
  "func calculateDetention(",
  "// MARK: - Dispute",
);
const bidding = sliceBetween(
  api,
  "struct LoadBiddingAPI",
  "// MARK: - Auto-Accept Rules",
);
const postStoreMutation = sliceBetween(
  liveStores,
  "let ack = try await EusoTripAPI.shared.shipper.create(",
  "self.phase = .success(ack)",
);
const allViewSources = walkSwift(join(root, "EusoTrip/Views")).map((path) =>
  readFileSync(path, "utf8"),
);

const checks = [
  [
    termsModel.includes("case USD, CAD, MXN"),
    "negotiated terms preserve the server currency enum",
  ],
  [
    termsModel.includes("let freeTimeMinutes: Int"),
    "negotiated terms carry explicit free time",
  ],
  [
    termsModel.includes("let rateAmount: String"),
    "negotiated rate preserves decimal text",
  ],
  [
    termsModel.includes("let billingIncrementMinutes: Int"),
    "negotiated terms carry the billing increment",
  ],
  [
    termsModel.includes("let roundingRule: RoundingRule"),
    "negotiated terms carry the rounding rule",
  ],
  [
    termsModel.includes("let suspensionRule: SuspensionRule"),
    "negotiated terms carry the suspension rule",
  ],
  [
    termsModel.includes("let excludedShareBasisPoints: Int?"),
    "shared suspension allocation uses basis points",
  ],
  [
    api.includes('try container.encode("none_confirmed", forKey: .state)'),
    "no-suspension allocation uses the exact wire state",
  ],
  [
    api.includes('try container.encode("applied", forKey: .state)'),
    "applied suspension allocation uses the exact wire state",
  ],
  [
    calculation.includes("loadId: Int") &&
      calculation.includes("departureTime: String"),
    "calculation is bound to a load and closed observed window",
  ],
  [
    calculation.includes(
      "suspensionAllocation: TruckDetentionSuspensionAllocation",
    ),
    "calculation sends evidence-backed suspension allocation",
  ],
  [
    !calculation.includes("freeTimeMinutes") &&
      !calculation.includes("cargoType"),
    "calculation never sends caller-selected rate/free-time/cargo defaults",
  ],
  [
    pricing.includes("var currency: TruckDetentionNegotiatedTerms.Currency?") &&
      pricing.includes('var freeTimeMinutes = ""'),
    "terms editor begins without fabricated currency or free time",
  ],
  [
    pricing.includes('var rateAmount = ""') &&
      pricing.includes('var billingIncrementMinutes = ""'),
    "terms editor begins without fabricated rate or increment",
  ],
  [
    pricing.includes(
      "struct TruckDetentionTermsDraft: Codable, Equatable, Sendable",
    ),
    "editable terms are safe for durable off-main draft recovery",
  ],
  [
    postDraft.includes("truckDetentionTerms:   mode == .truck") &&
      postDraft.includes("truckDetentionTermsDraft.negotiatedTerms"),
    "truck post sends explicit negotiated terms",
  ],
  [
    flagshipPost.includes(
      "@State private var truckDetentionTermsDraft = TruckDetentionTermsDraft()",
    ),
    "flagship post screen owns editable truck terms",
  ],
  [
    flagshipPost.includes(
      "if transportMode == .truck {\n                truckDetentionTermsSection",
    ) &&
      flagshipPost.includes(
        "TruckDetentionTermsEditor(draft: $truckDetentionTermsDraft)",
      ),
    "flagship pricing renders the editor only for truck",
  ],
  [
    flagshipPost.includes("truckDetentionBlockReason == nil") &&
      flagshipPost.includes('return "Complete detention terms"'),
    "flagship navigation names and enforces incomplete terms",
  ],
  [
    flagshipPost.includes(
      "snap.truckDetentionTermsDraft = truckDetentionTermsDraft",
    ) &&
      flagshipPost.includes(
        "truckDetentionTermsDraft = snap.truckDetentionTermsDraft ?? TruckDetentionTermsDraft()",
      ),
    "flagship draft persists and restores incomplete commercial work",
  ],
  [
    flagshipPost.includes(
      "decodeIfPresent(\n                TruckDetentionTermsDraft.self",
    ) && flagshipPost.includes("transportModeRaw = try c.decodeIfPresent"),
    "legacy post drafts decode with explicit field defaults",
  ],
  [
    flagshipPost.includes(
      "if transportMode == .truck {\n            guard let terms = truckDetentionTermsDraft.negotiatedTerms",
    ) && flagshipPost.includes("truckDetentionTerms = nil"),
    "flagship sends validated truck terms and no truck terms for other modes",
  ],
  [
    flagshipPost.includes("truckDetentionTerms: truckDetentionTerms"),
    "flagship passes terms into its mutation store",
  ],
  [
    liveStores.includes(
      "transportMode: TransportMode? = nil,\n        truckDetentionTerms: TruckDetentionNegotiatedTerms?",
    ) &&
      liveStores.includes(
        "let resolvedTransportMode = transportMode ?? .truck",
      ),
    "post store revalidates mode-specific terms locally",
  ],
  [
    postStoreMutation.includes("transportMode: transportMode?.rawValue") &&
      postStoreMutation.includes("truckDetentionTerms: truckDetentionTerms"),
    "post store preserves terms at the typed API boundary",
  ],
  [
    shippersRouter.includes("if (!input.truckDetentionTerms)") &&
      shippersRouter.includes(
        "normalizeTruckDetentionNegotiatedTerms(input.truckDetentionTerms)",
      ),
    "server requires and normalizes explicit truck terms",
  ],
  [
    shippersRouter.includes(
      "Truck detention terms cannot be attached to a non-truck load.",
    ),
    "server rejects truck-only terms on other modes",
  ],
  [
    bidding.match(/let truckDetentionTerms: TruckDetentionNegotiatedTerms\?/g)
      ?.length >= 4,
    "submit and counter encode negotiated detention terms",
  ],
  [
    bidding.includes(
      "Nil deliberately inherits the signed terms on the truck load",
    ),
    "submit nil is documented as load-term inheritance",
  ],
  [
    bidding.includes(
      "Nil deliberately inherits the parent bid's negotiated terms",
    ),
    "counter nil is documented as parent-term inheritance",
  ],
  [
    bidding.includes("guard success != false") &&
      bidding.includes("id != nil") &&
      bidding.includes("let status"),
    "bid acknowledgement requires durable identity and server status",
  ],
  [
    !bidding.includes('?? "pending"'),
    "bid acknowledgement does not invent pending status",
  ],
  [
    loadDetail.includes("INHERITED FROM SIGNED LOAD") &&
      loadDetail.includes("Propose different detention terms"),
    "load bid UI distinguishes inherited and overridden terms",
  ],
  [
    loadDetail.includes("truckDetentionTerms: detentionTerms"),
    "load-detail counter sends explicit override or inheritance nil",
  ],
  [
    driverBid.includes("truckDetentionTerms: truckDetentionTerms") &&
      driverBid.includes("ack.isConfirmed"),
    "driver counter sends terms and verifies persistence",
  ],
  [
    shipperThread.includes("truckDetentionTerms: proposedCounterTerms") &&
      shipperThread.includes("ack.isConfirmed"),
    "shipper thread counter sends terms and verifies persistence",
  ],
  [
    shipperCounter.includes("truckDetentionTerms: proposedDetentionTerms") &&
      shipperCounter.includes("resp.confirmedStatus"),
    "shipper counter review sends terms and verifies persistence",
  ],
  [
    shipperBids.includes("truckDetentionTerms: termsForEveryCounter") &&
      shipperBids.includes("ack.isConfirmed"),
    "counter-all sends terms and verifies every durable response",
  ],
  [
    dispatcherDelivery.includes("getActive(limit: 100)") &&
      dispatcherDelivery.includes("getHistory(limit: 100)"),
    "dispatcher delivery reads signed live and closed commercial state",
  ],
  [
    !dispatcherDelivery.includes("freeTimeMinutes ?? 120") &&
      !dispatcherDelivery.includes('cargoType ?? "general"'),
    "dispatcher delivery has no retired detention defaults",
  ],
  [
    allViewSources.every(
      (source) =>
        !source.includes('"detentionAccessorials.calculateDetention"'),
    ),
    "no iOS view bypasses the typed load-bound calculator",
  ],
];

const failures = checks
  .filter(([passed]) => !passed)
  .map(([, message]) => message);
if (failures.length) {
  console.error(
    `iOS truck-detention contract verification failed:\n- ${failures.join("\n- ")}`,
  );
  process.exit(1);
}

console.log(
  `iOS truck-detention contract verification passed (${checks.length}/${checks.length}).`,
);
