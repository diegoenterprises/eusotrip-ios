#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FILES=(
  "EusoTrip/Views/Rail/605_RailCargoClaim.swift"
  "EusoTrip/Views/Rail/652_RailClaimsDashboard.swift"
  "EusoTrip/Views/Rail/653_RailClaimsList.swift"
  "EusoTrip/Views/Rail/654_RailClaimWorkflow.swift"
  "EusoTrip/Views/Rail/660_RailClaimReport.swift"
  "EusoTrip/Views/Rail/671_RailClaimTemplates.swift"
  "EusoTrip/Views/Vessel/732_VesselCargoClaim.swift"
  "EusoTrip/Views/Vessel/800_VesselClaimsDashboard.swift"
  "EusoTrip/Views/Vessel/801_VesselClaimsList.swift"
  "EusoTrip/Views/Vessel/808_VesselClaimWorkflow.swift"
  "EusoTrip/Views/Vessel/812_VesselClaimTemplates.swift"
  "EusoTrip/Views/Vessel/813_VesselClaimReport.swift"
)

for file in "${FILES[@]}"; do
  swiftc -parse "$file"
  rg -q '^//  Purpose:' "$file"
  rg -q '^//  Archetype:' "$file"
done

if rg -n \
  'ShipperFreightClaimsAPI|query\("freightClaims\.|mutation\("freightClaims\.|getClaimTemplates|generateClaimReport|claim_7F2A|currencyCode[[:space:]]*=[[:space:]]*"USD"|amount[[:space:]]*\?\?[[:space:]]*0' \
  "${FILES[@]}"; then
  echo "Freight-claim consumer gate failed: unsafe local contract or fallback found." >&2
  exit 1
fi

if rg -n \
  'freightClaims\.(fileClaim|updateClaimStatus|addClaimEvidence)' \
  "${FILES[@]}"; then
  echo "Freight-claim consumer gate failed: mutation bypasses a transaction-bound composer." >&2
  exit 1
fi

rg -q 'FreightClaimConsumerCanon\.claims\(mode: \.rail\)' \
  EusoTrip/Views/Rail/652_RailClaimsDashboard.swift \
  EusoTrip/Views/Rail/653_RailClaimsList.swift
rg -q 'FreightClaimConsumerCanon\.claims\(mode: \.vessel\)' \
  EusoTrip/Views/Vessel/800_VesselClaimsDashboard.swift \
  EusoTrip/Views/Vessel/801_VesselClaimsList.swift

for file in \
  EusoTrip/Views/Rail/605_RailCargoClaim.swift \
  EusoTrip/Views/Rail/654_RailClaimWorkflow.swift \
  EusoTrip/Views/Rail/660_RailClaimReport.swift; do
  rg -q 'FreightClaimConsumerCanon\.detail\(claimId: claimId, mode: \.rail\)' "$file"
done

for file in \
  EusoTrip/Views/Vessel/732_VesselCargoClaim.swift \
  EusoTrip/Views/Vessel/808_VesselClaimWorkflow.swift \
  EusoTrip/Views/Vessel/813_VesselClaimReport.swift; do
  rg -q 'FreightClaimConsumerCanon\.detail\(claimId: claimId, mode: \.vessel\)' "$file"
done

FILE_REQUEST_BLOCK="$(sed -n \
  '/struct FileClaimRequest: Encodable {/,/struct FileClaimResult: Decodable/p' \
  EusoTrip/Services/EusoTripAPI.swift)"
missing_shortage_fields=()
for field in expectedQuantity receivedQuantity quantityUnit; do
  if ! grep -q "let ${field}:" <<<"$FILE_REQUEST_BLOCK"; then
    missing_shortage_fields+=("$field")
  fi
done
if ((${#missing_shortage_fields[@]} == 0)); then
  echo "Typed shortage evidence is present in FreightClaimsAPI.FileClaimRequest."
else
  echo "KNOWN CONTRACT GAP: FreightClaimsAPI.FileClaimRequest is missing ${missing_shortage_fields[*]}."
fi

echo "Freight-claim consumer source contract: PASS"
