#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const source = {
  model: read("EusoTrip/Models/HOSStatus.swift"),
  api: read("EusoTrip/Services/EusoTripAPI.swift"),
  live: read("EusoTrip/Services/HOSLiveStore.swift"),
  eld: read("EusoTrip/Services/ELDIntegrationStore.swift"),
  watch: read("EusoTrip/Services/WatchCommandHandler.swift"),
  autopilot: read(
    "EusoTrip/Views/Dispatch/533_DispatcherAIDispatchAssist.swift",
  ),
  assign: read("EusoTrip/Views/Dispatch/702_DispatchLoadAssignment.swift"),
  availability: read(
    "EusoTrip/Views/Dispatch/535_DispatcherDriverAvailability.swift",
  ),
  legacyDispatch: read(
    "EusoTrip/Views/Dispatch/Dpch800_DispatcherBHCardDuodecet.swift",
  ),
  legacyShipper: read(
    "EusoTrip/Views/Shipper/SH250_ShipperBackhaulEchoSextet.swift",
  ),
  railCrew: read("EusoTrip/Views/Rail/632_RailCrewAvailability.swift"),
  railCallBoard: read("EusoTrip/Views/Rail/584_RailCrewCallBoard.swift"),
  railConductor: read("EusoTrip/Views/Rail/709_RailConductorCabRun.swift"),
  railDeadhead: read("EusoTrip/Views/Rail/678_RailDeadheadPositioning.swift"),
  railAudit: read("EusoTrip/Views/Rail/679_RailFRAPart228HOSAudit.swift"),
  railTieUp: read(
    "EusoTrip/Views/Rail/712_RailConductorJobBriefingTieUp.swift",
  ),
  eldRouter: read("EusoTrip/Services/EldComplianceRouter.swift"),
  driverCard: read("EusoTrip/Models/DriverStoreModels.swift"),
  driverNextBrief: read("EusoTrip/Views/Driver/027_NextLoadBrief.swift"),
  driverCompliance: read(
    "EusoTrip/Views/Driver/DriverComplianceDashboard.swift",
  ),
  driverPickup: read(
    "EusoTrip/Views/Driver/145_DriverPickupDepartedCelM04.swift",
  ),
  driverTransit: read("EusoTrip/Views/Driver/146_DriverInTransitCelM04.swift"),
  driverArrival: read(
    "EusoTrip/Views/Driver/147_DriverAtDeliveryArrivalCelM04.swift",
  ),
  driverDelivery: read(
    "EusoTrip/Views/Driver/148_DriverPodSignUnloadCelM04.swift",
  ),
  dispatchHome: read("EusoTrip/Views/Dispatch/400_DispatcherHome.swift"),
  dispatchRoster: read(
    "EusoTrip/Views/Dispatch/404_DispatcherDriverRoster.swift",
  ),
  dispatchCommand: read("EusoTrip/Views/Dispatch/Dpch714_DispatchTrio.swift"),
  dispatchReassign: read(
    "EusoTrip/Views/Dispatch/Dpch730_DispatcherOpsQuartet.swift",
  ),
  catalystRoster: read(
    "EusoTrip/Views/Catalyst/304_CatalystFleetDrivers.swift",
  ),
  catalystPickup: read(
    "EusoTrip/Views/Catalyst/374_CatalystPickupOnSiteEchoCelM04.swift",
  ),
  catalystTransit: read(
    "EusoTrip/Views/Catalyst/375_CatalystInTransitFleetTrackCelM04.swift",
  ),
  catalystDelivery: read(
    "EusoTrip/Views/Catalyst/376_CatalystAtDeliveryFleetTrackCelM04.swift",
  ),
  catalystLifecycle: read(
    "EusoTrip/Views/Catalyst/CV350_CatalystLifecycleSeptet.swift",
  ),
  dispatchTriage: read(
    "EusoTrip/Views/Dispatch/703_DispatchExceptionTriage.swift",
  ),
  watchModel: read("EusoTrip Pulse Watch App/Models/WatchHOS.swift"),
  watchStore: read("EusoTrip Pulse Watch App/Services/HOSStore.swift"),
  watchBridge: read("EusoTrip/Services/WatchAuthBridge.swift"),
  watchConnectivity: read(
    "EusoTrip Pulse Watch App/WatchConnectivityManager.swift",
  ),
  watchOffline: read("EusoTrip Pulse Watch App/Services/OfflineQueue.swift"),
  watchDriving: read(
    "EusoTrip Pulse Watch App/Services/DrivingSessionManager.swift",
  ),
  watchHOSView: read("EusoTrip Pulse Watch App/Views/HOSView.swift"),
  watchHome: read("EusoTrip Pulse Watch App/Views/HomeView.swift"),
  watchComplication: read(
    "EusoTrip Pulse Watch App/Complications/HOSComplication.swift",
  ),
};

const failures = [];
const requireText = (key, needle, label) => {
  if (!source[key].includes(needle))
    failures.push(`${label}: missing ${needle}`);
};
const forbidText = (key, needle, label) => {
  if (source[key].includes(needle))
    failures.push(`${label}: forbidden ${needle}`);
};

requireText("model", "let drivingRemaining: Double?", "nullable HOS counters");
requireText(
  "model",
  "static let maximumCurrentAge: TimeInterval = 15 * 60",
  "15-minute freshness policy",
);
requireText(
  "model",
  "func assignmentEligibility",
  "fail-closed assignment policy",
);
requireText(
  "api",
  "let hoursRemaining: Double?",
  "nullable driver profile HOS",
);
forbidText("api", "let intId = Int(driverId) ?? 0", "driver update identity");
requireText(
  "api",
  "guard !normalizedLocation.isEmpty",
  "regulated HOS location gate",
);
requireText(
  "live",
  "Current location is required before changing duty status.",
  "HOS UI location gate",
);
forbidText("watch", '?? "watch"', "Watch location provenance");
requireText(
  "watch",
  "guard let location, !location.isEmpty",
  "Watch location gate",
);
forbidText(
  "eld",
  'provider: providerIds.first ?? "none"',
  "ELD provider identity",
);
requireText("eld", "result.success == true", "ELD disconnect acknowledgement");
requireText("eld", "verificationState == .current", "ELD disconnect readback");
requireText(
  "autopilot",
  "let avgConfidence: Int?",
  "nullable Autopilot confidence",
);
requireText("autopilot", "let matchScore: Int?", "nullable match score");
requireText(
  "autopilot",
  '"dispatch.smartBulkAssign"',
  "atomic bulk assignment",
);
forbidText(
  "autopilot",
  '"dispatch.assignDriver"',
  "Autopilot direct assignment bypass",
);
requireText(
  "assign",
  "evidence.assignmentEligibility() == .eligible",
  "assignment display eligibility",
);
requireText("assign", "Current HOS left", "assignment evidence display");
forbidText(
  "availability",
  '?? "HOS current"',
  "availability missing-counter state",
);
for (const key of ["legacyDispatch", "legacyShipper"]) {
  const falsePositive = source[key]
    .split("\n")
    .some(
      (line) =>
        line.includes('"HOS"') &&
        line.includes('"no live source"') &&
        line.includes(".green"),
    );
  if (falsePositive)
    failures.push(`${key}: missing HOS source must not render as green`);
}
forbidText(
  "railCrew",
  'return "synced 5m ago"',
  "rail HOS synthetic freshness",
);
forbidText(
  "railCrew",
  "Deadheading 0 crew",
  "rail HOS synthetic deadhead count",
);
requireText("railCrew", 'return "UNVERIFIED"', "rail HOS unverified state");
requireText(
  "railCallBoard",
  "var hasCurrentEvidence",
  "rail call board freshness boundary",
);
requireText(
  "railCallBoard",
  'return (Brand.warning, "UNVERIFIED"',
  "rail call board unknown status",
);
requireText(
  "railCallBoard",
  "Call channel unavailable",
  "rail call board missing write path",
);
requireText(
  "railCallBoard",
  "Crew HOS source unavailable",
  "rail call board HOS failure state",
);
forbidText(
  "railCallBoard",
  'status ?? "callable"',
  "rail call board callable default",
);
forbidText(
  "railCallBoard",
  'boardStatus ?? "open"',
  "rail call board open default",
);
forbidText(
  "railCallBoard",
  "hosAvailableHours",
  "rail call board duty-hours-as-availability",
);
forbidText(
  "railCallBoard",
  "private func callCrew()",
  "rail call board query-only action",
);
requireText(
  "railConductor",
  "private var conductorHOSRow",
  "rail conductor dedicated HOS evidence",
);
requireText(
  "railConductor",
  "HOS source unavailable",
  "rail conductor HOS failure state",
);
forbidText(
  "railConductor",
  'queryNoInput("railShipments.getRailCrewHOS")) ?? []',
  "rail conductor swallowed HOS source",
);
forbidText(
  "railConductor",
  "return conductorRow?.hoursOnDuty",
  "rail conductor generic crew HOS fallback",
);
for (const key of ["railDeadhead", "railAudit"]) {
  requireText(key, "hasCurrentObservation", `${key} current evidence boundary`);
  requireText(key, "UNVERIFIED", `${key} unknown evidence state`);
}
requireText(
  "railTieUp",
  "hosEvidenceCurrent",
  "rail tie-up current evidence boundary",
);
forbidText(
  "railTieUp",
  "return crew.first(where: { $0.isConductor })",
  "rail tie-up cross-consist fallback",
);
requireText(
  "eldRouter",
  "ELD evidence unavailable",
  "ELD compliance failure state",
);
requireText("driverCard", "let tracked: Bool?", "driver HOS tracking state");
requireText(
  "driverCard",
  "func hasCurrentObservation",
  "driver HOS freshness boundary",
);
requireText(
  "driverNextBrief",
  "@StateObject private var hos = HOSLiveStore()",
  "next-load HOS evidence source",
);
requireText(
  "driverNextBrief",
  "status.assignmentEligibility() == .eligible",
  "next-load fail-closed acceptance",
);
requireText(
  "driverNextBrief",
  "guard await lifecycle.execute(candidate)",
  "next-load confirmed transition",
);
forbidText(
  "driverNextBrief",
  "fallbackHosHead",
  "next-load fabricated HOS headline",
);
forbidText(
  "driverNextBrief",
  "fallbackHosSub",
  "next-load fabricated HOS detail",
);
requireText(
  "driverCompliance",
  "guard h.hasCurrentObservation()",
  "driver compliance freshness boundary",
);
requireText(
  "driverCompliance",
  "counters withheld",
  "driver compliance stale-counter state",
);
for (const key of [
  "driverPickup",
  "driverTransit",
  "driverArrival",
  "driverDelivery",
]) {
  requireText(key, "hos.getStatus()", `${key} canonical HOS source`);
  requireText(key, "hasCurrentObservation()", `${key} current HOS boundary`);
  forbidText(key, "drivers.getMyHOSStatus", `${key} legacy HOS source`);
}
requireText(
  "dispatchHome",
  '"hos.getFleetHOS"',
  "dispatcher home fleet HOS source",
);
requireText(
  "dispatchHome",
  "currentHours.count == idle.count",
  "dispatcher home complete-evidence average",
);
forbidText(
  "dispatchHome",
  "live HoS-aware matching",
  "dispatcher home synthetic HOS claim",
);
requireText(
  "dispatchRoster",
  "$0.reassignable && evidence(for: $0)?.assignmentEligibility() == .eligible",
  "dispatcher roster reassignment gate",
);
requireText(
  "dispatchCommand",
  '"hos.getFleetHOS"',
  "dispatcher command fleet HOS source",
);
requireText(
  "dispatchCommand",
  "ASSIGNABLE DRIVERS · CURRENT HOS",
  "dispatcher command evidence label",
);
requireText(
  "dispatchReassign",
  '"dispatch.smartBulkAssign"',
  "dispatcher reassignment atomic write",
);
requireText(
  "dispatchReassign",
  '"hos.getFleetHOS"',
  "dispatcher reassignment evidence refresh",
);
requireText(
  "dispatchReassign",
  "resp.assigned == 1",
  "dispatcher reassignment confirmed write",
);
forbidText(
  "dispatchReassign",
  "URGENT · 0:42",
  "dispatcher reassignment fabricated urgency",
);
const reassignStart = source.dispatchReassign.indexOf(
  "private func confirmReassign() async",
);
const reassignEnd = source.dispatchReassign.indexOf(
  "private func loadCtx() async",
  reassignStart,
);
const reassignBlock = source.dispatchReassign.slice(reassignStart, reassignEnd);
if (
  reassignStart < 0 ||
  reassignEnd < 0 ||
  reassignBlock.includes("resp.success != false")
) {
  failures.push(
    "dispatcher reassignment: synthetic or unbounded success acknowledgement",
  );
}
for (const key of [
  "catalystRoster",
  "catalystPickup",
  "catalystTransit",
  "catalystDelivery",
  "catalystLifecycle",
]) {
  requireText(key, '"hos.getFleetHOS"', `${key} fleet HOS source`);
  requireText(key, "hasCurrentObservation()", `${key} current HOS boundary`);
}
requireText(
  "dispatchTriage",
  "let provider: String?",
  "dispatcher ELD provider provenance",
);
requireText(
  "dispatchTriage",
  "func hasCurrentDriveEvidence",
  "dispatcher ELD freshness gate",
);
requireText(
  "dispatchTriage",
  "var hasRecordedViolationEvidence",
  "dispatcher violation evidence gate",
);
requireText(
  "dispatchTriage",
  "ELD/HOS feed unavailable",
  "dispatcher ELD feed failure state",
);
forbidText(
  "dispatchTriage",
  "d.driverId ?? d.id ?? 0",
  "dispatcher ELD fabricated identity",
);
requireText("watchModel", "var tracked: Bool?", "Watch HOS tracking state");
requireText("watchModel", "var source: String?", "Watch HOS provider identity");
requireText(
  "watchModel",
  "var observedAt: Date?",
  "Watch HOS observation time",
);
requireText(
  "watchModel",
  "func hasCurrentObservation",
  "Watch HOS freshness gate",
);
requireText(
  "watchStore",
  "var currentObservation: WatchHOS?",
  "Watch HOS evidence boundary",
);
requireText(
  "watchStore",
  "guard let location = DrivingSessionManager.shared.currentHOSLocationEvidence",
  "Watch HOS GPS gate",
);
requireText(
  "watchStore",
  "the displayed status remains unchanged until confirmed",
  "Watch HOS non-optimistic mutation",
);
forbidText(
  "watchStore",
  "current.status = newStatus",
  "Watch HOS optimistic legal status",
);
requireText(
  "watchBridge",
  "driveRemainingMinutes: Int?",
  "phone-to-Watch nullable HOS counters",
);
forbidText(
  "watchBridge",
  'default: return "off"',
  "phone-to-Watch missing duty fallback",
);
requireText(
  "watchConnectivity",
  '(ctx["tracked"] as? Bool) == true',
  "Watch receiver tracked gate",
);
forbidText(
  "watchConnectivity",
  '?? "off"',
  "Watch receiver missing duty fallback",
);
requireText(
  "watchOffline",
  "case hosEventLocated",
  "Watch offline GPS-preserving HOS event",
);
forbidText(
  "watchOffline",
  '"location": "watch"',
  "Watch offline fabricated location",
);
requireText(
  "watchDriving",
  "var currentHOSLocationEvidence: String?",
  "Watch current GPS evidence contract",
);
for (const key of ["watchHOSView", "watchHome"]) {
  requireText(key, "currentObservation", `${key} current HOS evidence gate`);
}
requireText(
  "watchComplication",
  "hasCurrentObservation",
  "Watch complication current HOS evidence gate",
);

if (failures.length) {
  console.error(
    `iOS HOS/ELD truth contract failed:\n- ${failures.join("\n- ")}`,
  );
  process.exit(1);
}

console.log("iOS HOS/ELD truth contract verified.");
