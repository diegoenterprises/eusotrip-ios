import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const compact = (source) => source.replace(/\s+/g, " ");
const matches = (source, pattern) => pattern.test(compact(source));

const contentView = read("EusoTrip/ContentView.swift");
const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const bidding = read("EusoTrip/Views/Shipper/261_BiddingLiveFeed.swift");
const rfpInbox = read("EusoTrip/Views/Shipper/380_RfpInbox.swift");
const rfpDetail = read("EusoTrip/Views/Shipper/381_RfpDetail.swift");
const bidBoard = read("EusoTrip/Views/Shipper/420_BidReviewBoard.swift");
const partnerDetail = read("EusoTrip/Views/Shipper/434_PartnerDetail.swift");
const partnerAgreements = read("EusoTrip/Views/Shipper/435_PartnerAgreements.swift");

const checks = [
  [
    matches(bidBoard, /userInfo: \["screenId": "261", "loadId": lane\.loadId\]/),
    "420 emits the selected load id for 261",
  ],
  [
    matches(rfpInbox, /userInfo: \["screenId": "381", "rfpId": r\.id\]/),
    "380 emits the selected RFP id for 381",
  ],
  [
    matches(partnerDetail, /userInfo: \["screenId": screen, "partnerId": id, "catalystId": id\]/),
    "434 emits the selected partner id for 435",
  ],
  [
    matches(router, /if id == "261" \{ activeLoadId = ShipperLoadIdResolver\.normalize\(note\.userInfo\?\["loadId"\]\) \}/),
    "router captures or clears 261 load context on every target swap",
  ],
  [
    matches(router, /if id == "381" \{ activeRfpId = ShipperRoutedRecordIdResolver\.rfp\(note\.userInfo\?\["rfpId"\]\) \}/),
    "router captures or clears 381 RFP context on every target swap",
  ],
  [
    matches(router, /if id == "435" \{ activeAgreementPartnerId = ShipperRoutedRecordIdResolver\.positiveNumeric\( note\.userInfo\?\["partnerId"\] \) \}/),
    "router captures or clears 435 partner context on every target swap",
  ],
  [
    router.includes('return "shipper-261-\\(activeLoadId ?? "__missing")"') &&
      router.includes('return "shipper-381-\\(activeRfpId ?? "__missing")"') &&
      router.includes('return "shipper-435-\\(activeAgreementPartnerId ?? "__missing")"'),
    "screen identity changes when any routed record id changes",
  ],
  [
    matches(router, /BiddingLiveFeedScreen\(theme: p, loadId: loadId\)/) &&
      matches(router, /RfpDetailScreen\(theme: p, rfpId: rfpId\)/) &&
      matches(router, /PartnerAgreementsScreen\(theme: p, partnerId: partnerId\)/),
    "router injects captured ids into all three target screens",
  ],
  [
    matches(contentView, /id: "261"[^\n]*BiddingLiveFeedScreen\(theme: p, loadId: nil\)/) &&
      matches(contentView, /id: "381"[^\n]*RfpDetailScreen\(theme: p, rfpId: nil\)/) &&
      matches(contentView, /id: "435"[^\n]*PartnerAgreementsScreen\(theme: p, partnerId: nil\)/),
    "registry mounts all three targets without sentinel ids",
  ],
  [
    !matches(contentView, /id: "261".{0,220}loadId: "0"/) &&
      !matches(contentView, /id: "381".{0,220}rfpId: "0"/) &&
      !matches(contentView, /id: "435".{0,220}partnerId: "0"/),
    "registry has no zero-id mount for 261, 381, or 435",
  ],
  [
    bidding.includes("let loadId: String?") &&
      bidding.includes("if let routedLoadId = ShipperLoadIdResolver.normalize(loadId)") &&
      bidding.includes("loadId: routedLoadId") &&
      bidding.includes("BiddingBody(live: live, loadId: routedLoadId)") &&
      bidding.includes("ShipperRecordContextUnavailableScreen("),
    "261 validates once, threads the real load id, and fails closed",
  ],
  [
    rfpDetail.includes("let rfpId: String?") &&
      rfpDetail.includes("if let routedRfpId = ShipperRoutedRecordIdResolver.rfp(rfpId)") &&
      rfpDetail.includes("RfpDetailBody(rfpId: routedRfpId)") &&
      rfpDetail.includes("input: In(rfpId: rfpId, laneId: laneId)") &&
      rfpDetail.includes("ShipperRecordContextUnavailableScreen("),
    "381 validates once, threads the real RFP id, and fails closed",
  ],
  [
    partnerAgreements.includes("let partnerId: String?") &&
      partnerAgreements.includes("if let routedPartnerId = ShipperRoutedRecordIdResolver.positiveNumeric(partnerId)") &&
      partnerAgreements.includes("PartnerAgreementsBody(partnerId: routedPartnerId)") &&
      partnerAgreements.includes("input: In(partnerId: partnerId)") &&
      partnerAgreements.includes("ShipperRecordContextUnavailableScreen("),
    "435 validates once, threads the real partner id, and fails closed",
  ],
  [
    partnerAgreements.includes("guard let idNum = Int(a.id), idNum > 0 else") &&
      partnerAgreements.includes("agreementId: idNum"),
    "435 signs only with the positive server-issued agreement id",
  ],
  [
    !/BiddingLiveFeedScreen\([^\n]*loadId: "0"\)/.test(bidding) &&
      !/RfpDetailScreen\([^\n]*rfpId: "0"\)/.test(rfpDetail) &&
      !/PartnerAgreementsScreen\([^\n]*partnerId: "0"\)/.test(partnerAgreements),
    "target screen sources contain no zero-id construction",
  ],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  console.error(`Shipper record-context verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(`Shipper record-context verification passed (${checks.length}/${checks.length}).`);
