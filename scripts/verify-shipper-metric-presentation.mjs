import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const compact = (source) => source.replace(/\s+/g, " ");

const home = read("EusoTrip/Views/Shipper/200_ShipperHome.swift");
const profile = read("EusoTrip/Views/Shipper/202_ShipperProfile.swift");
const me = read("EusoTrip/Views/Shipper/320_MeHome.swift");

const swiftOutput = execFileSync(
  "xcrun",
  [
    "swift",
    "-e",
    `import Foundation
let locale = Locale(identifier: "en_US")
let whole = FloatingPointFormatStyle<Double>.Currency(code: "USD")
  .precision(.fractionLength(0))
  .locale(locale)
let rate = FloatingPointFormatStyle<Double>.Currency(code: "USD")
  .precision(.fractionLength(2))
  .locale(locale)
print(35_244_094.0.formatted(whole))
print(35_003_800.0.formatted(whole))
print(100.36.formatted(rate))`,
  ],
  { encoding: "utf8" },
).trim().split("\n");

const checks = [
  [
    home.includes('static let ratePerMileLabel = "Rate\\u{00A0}/\\u{00A0}mi"'),
    "rate-per-mile label is nonbreaking",
  ],
  [
    compact(home).includes('.currency(code: currencyCode) .precision(.fractionLength(0)) .locale(locale)'),
    "whole-currency formatting is locale-aware and grouping-capable",
  ],
  [
    home.includes("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize") &&
      home.includes("if dynamicTypeSize.isAccessibilitySize") &&
      home.includes("return [GridItem(.flexible(minimum: 0), alignment: .topLeading)]"),
    "Shipper Home collapses its metric grid at accessibility sizes",
  ],
  [
    home.includes("label: ShipperMetricFormatting.ratePerMileLabel") &&
      home.includes("value: rateValue(resolvedRatePerMile(s))") &&
      !home.includes("dollarsPerMile"),
    "Home rate tile uses the shared live-value formatter",
  ],
  [
    home.includes('label: "This month · USD"') &&
      home.includes("value: dollars(s.totalSpendThisMonth)"),
    "Home spend keeps its source amount and explicit currency basis",
  ],
  [
    !home.includes(".minimumScaleFactor(0.52)") &&
      !compact(home).includes(".font(.system(valueTextStyle, design: .default, weight: .semibold).monospacedDigit()) .lineLimit(1) .minimumScaleFactor") &&
      !compact(profile).includes(".font(.system(valueTextStyle, design: .default, weight: .semibold).monospacedDigit()) .lineLimit(1) .minimumScaleFactor") &&
      home.includes("ViewThatFits(in: .horizontal)"),
    "metric values preserve Dynamic Type and compact spend adapts without shrinking",
  ],
  [
      profile.includes("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize") &&
      profile.includes("totalSpendTile(s)") &&
      profile.includes("valueTextStyle: .title3") &&
      compact(profile).includes('label: "Total spend · USD", value: s.totalSpend <= 0 ? "—" : dollars(Double(s.totalSpend)), trail: "lifetime"'),
    "Profile gives lifetime spend a full-width Dynamic Type fallback",
  ],
  [
    me.includes('label: "Total spend · USD"') &&
      me.includes("ShipperMetricFormatting.wholeCurrency(Double(s.totalSpend))") &&
      me.includes("ViewThatFits(in: .horizontal)"),
    "Me/Profile hub groups spend and stacks the proof row when needed",
  ],
  [
    JSON.stringify(swiftOutput) === JSON.stringify(["$35,244,094", "$35,003,800", "$100.36"]),
    "Foundation formats both ASC spend values and the wrapped rate value exactly",
  ],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  console.error(`Shipper metric presentation verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(`Shipper metric presentation verification passed (${checks.length}/${checks.length}).`);
