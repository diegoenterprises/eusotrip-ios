#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
system="$repo_root/EusoTrip/Views/Components/HomeWidgetSystem.swift"

python3 - "$repo_root" "$system" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
source = pathlib.Path(sys.argv[2]).read_text()
failures = []

roles_match = re.search(r'static let roleIDs: \[String\] = \[(.*?)\n    \]', source, re.S)
roles = re.findall(r'"([A-Z_]+)"', roles_match.group(1)) if roles_match else []
entries = re.findall(r'^\s*\("([A-Z_]+)", \[', source, re.M)
if len(roles) != 25 or len(set(roles)) != 25:
    failures.append(f"expected 25 unique role IDs, found {len(set(roles))}")
if set(entries) != set(roles):
    failures.append(f"manifest roles differ from role IDs: {sorted(set(roles) ^ set(entries))}")
if 'defaultWidgetIDs: ["weather"] + ids + ["news"]' not in source:
    failures.append("role defaults are not constructed weather-first")
if 'if let remote = output.layout {' not in source or 'remote.isEmpty' in source:
    failures.append("server [] can be mistaken for an absent layout")
for token in [
    'users.getDashboardLayout', 'users.saveDashboardLayout',
    'euso.home.widgets.v3.\\(userID).\\(role)',
    'configuredIdentity == requestIdentity',
    'revision == requestRevision',
    'let destination = from < to ? to - 1 : to',
    '.accessibilityAction(named: "Move up")',
    '.accessibilityAction(named: "Move down")',
    '.accessibilityAction(named: "Remove")',
    '.accessibilityAdjustableAction', 'dynamicTypeSize.isAccessibilitySize',
]:
    if token not in source:
        failures.append(f"missing contract token: {token}")
for token in ['LinearGradient', 'RadialGradient', 'ultraThinMaterial', 'thinMaterial', '.blur(']:
    if token in source:
        failures.append(f"shared grid contains prohibited ambient treatment: {token}")

homes = [
    'Driver/010_DriverHome.swift', 'Shipper/200_ShipperHome.swift',
    'Admin/800_AdminHome.swift', 'Broker/400_BrokerHome.swift',
    'Carrier/300_CarrierHome.swift', 'Catalyst/500_CatalystHome.swift',
    'Dispatch/400_DispatcherHome.swift',
    'Escort/600_EscortHome.swift', 'Terminal/700_TerminalHome.swift',
    'Compliance/900_ComplianceOfficerHome.swift', 'Rail/001_RailShipperHome.swift',
    'Rail/550_RailEngineerHome.swift', 'Vessel/001_VesselShipperHome.swift',
    'Vessel/650_VesselOperatorHome.swift',
]
for relative in homes:
    text = (root / 'EusoTrip/Views' / relative).read_text()
    if 'HomeWidgetGrid(' not in text:
        failures.append(f"native home is not on shared grid: {relative}")
if 'struct ShipperWidgetBoard' in (root / 'EusoTrip/Views/Shipper/200_ShipperHome.swift').read_text():
    failures.append('legacy ShipperWidgetBoard still exists')
admin = (root / 'EusoTrip/Views/Admin/800_AdminHome.swift').read_text()
if 'SUPER_ADMIN' not in admin or 'role: widgetRole' not in admin:
    failures.append('ADMIN and SUPER_ADMIN do not use distinct role keys')

if failures:
    print('\n'.join(f'FAIL: {failure}' for failure in failures), file=sys.stderr)
    raise SystemExit(1)
print(f'PASS: 25 weather-first manifests; {len(homes)} native homes share HomeWidgetGrid')
PY
