import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const api = read("EusoTrip/Services/EusoTripAPI.swift");
const driver = read("EusoTrip/Views/Driver/113_DriverTruckPosted.swift");
const carrier = read("EusoTrip/Views/Carrier/321_CarrierTruckPosting.swift");

const checks = [
  [api.includes('"truckPosting.getPosting"'), "shared API calls the durable posting query"],
  [api.includes("func getPosting(vehicleId: Int? = nil)"), "shared API exposes optional vehicle scoping"],
  [driver.includes("api.truckPosting.getPosting(vehicleId: vehicleId)"), "driver reads its vehicle posting"],
  [!driver.includes('input: In(status: "available")'), "driver does not infer posting state from vehicle availability"],
  [driver.includes("api.truckPosting.listInboundOffers("), "driver reads durable inbound offer rows"],
  [driver.includes("api.truckPosting.acceptOffer(offerId: offer.offerId)"), "driver accepts the durable offer id"],
  [driver.includes("api.truckPosting.declineOffer(offerId: offer.offerId)"), "driver declines the durable offer id"],
  [!driver.includes('"truckPosting.getMatchSuggestions"'), "driver does not use the legacy parallel suggestion path"],
  [!driver.includes("api.drivers.acceptLoad"), "driver cannot bypass truck-offer transaction semantics"],
  [!driver.includes("?? 0"), "driver offer projection does not invent numeric values"],
  [carrier.includes("async let d: Void = loadPosting()"), "carrier hydrates posting state on cold open"],
  [carrier.includes("activePostingId = posting?.id"), "carrier uses the durable posting id"],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  console.error(`Truck-posting contract verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(`Truck-posting contract verification passed (${checks.length}/${checks.length}).`);
