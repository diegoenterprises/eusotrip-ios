//
//  611_RailFSMACompliance.swift
//  EusoTrip — Rail Engineer · Cold-Chain FSMA Compliance (carrier-side GATE archetype).
//
//  Reconstructed from the stamped gauge+3KPI+3row skeleton into a purpose-built
//  COMPLIANCE-GATE surface: a release VERDICT hero (CLEARED / BLOCKED, a shield
//  seal that fills to the real temp-adherence fraction) over a citation-bearing
//  FSMA CHECKLIST — each row a regulatory gate (21 CFR 1.908) with a pass/block
//  verdict derived from a REAL returned field. This is a gate, not a meter: it
//  turns the sanitary-cert release decision at the ramp into one verdict + the
//  exact gate that would hold the car.
//
//  Live wiring (all real procs):
//    • reeferTemp.getFSMAStatus(loadId)  → verdict + KPI + checklist + violations
//    • reeferTemp.checkFSMARequired(cargoType) → excursion-tolerance gate (fail-soft)
//    • reeferTemp.recordFSMATemp(...)    → "Record temp" (mutation, confirm-gated sheet)
//    • reeferTemp.verifyPreCool(...)     → "Pre-cool" (mutation, confirm-gated sheet)
//  Needs a loadId — accepted via a simple field. Honest: no load → an entry
//  prompt; getFSMAStatus has no per-check array, so every gate is DERIVED from a
//  real returned field (readings.count, preCoolVerified, excursionCount, band),
//  never fabricated, and the big verdict comes straight from `isCompliant`.
//

import SwiftUI

struct RailFSMAComplianceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailFSMAComplianceBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable models (match reeferTemp.getFSMAStatus / checkFSMARequired)

private struct FSMAReading611: Decodable, Identifiable {
    let id: Int
    let temperature: Double
    let unit: String
    let eventType: String
    let isExcursion: Bool
    let createdAt: String
}

private struct FSMAStatus611: Decodable {
    let loadId: Int
    let cargoClass: String
    let isCompliant: Bool
    let currentTemp: Double?
    let setPoint: Double
    let minAllowed: Double
    let maxAllowed: Double
    let excursionCount: Int
    let excursionMinutes: Int
    let lastReading: String?
    let preCoolVerified: Bool
    let readings: [FSMAReading611]
    let violations: [String]
}

private struct FSMARules611: Decodable {
    let minTemp: Double
    let maxTemp: Double
    let setPoint: Double
    let excursionToleranceMinutes: Int
    let preCoolMinTemp: Double
    let preCoolMaxTemp: Double
}

private struct FSMARequired611: Decodable {
    let required: Bool
    let rules: FSMARules611?
}

private struct RecordTempResult611: Decodable {
    let id: Int
    let isExcursion: Bool
    let message: String
}

private struct PreCoolResult611: Decodable {
    let passed: Bool
    let tempF: Double
    let message: String
}

// A single derived FSMA gate row (built from a real returned field, never faked).
private struct Gate611: Identifiable {
    let id = UUID()
    let title: String
    let citation: String
    let passed: Bool
    let value: String
}

private enum FSMAEvent611: String, CaseIterable, Identifiable {
    case pickup, in_transit, delivery, excursion, alarm, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pickup:     return "Pickup"
        case .in_transit: return "In transit"
        case .delivery:   return "Delivery"
        case .excursion:  return "Excursion"
        case .alarm:      return "Alarm"
        case .manual:     return "Manual"
        }
    }
}

// MARK: - Body

private struct RailFSMAComplianceBody: View {
    @Environment(\.palette) private var palette

    @State private var loadIdText: String = ""
    @State private var status: FSMAStatus611? = nil
    @State private var rules: FSMARules611? = nil
    @State private var loading = false
    @State private var loadError: String? = nil

    // Record-temp sheet
    @State private var showRecord = false
    @State private var recordTempText = ""
    @State private var recordUnit = "F"
    @State private var recordEvent: FSMAEvent611 = .manual
    @State private var recordLocation = ""
    @State private var recordNotes = ""
    @State private var recordSubmitting = false

    // Pre-cool sheet
    @State private var showPreCool = false
    @State private var preCoolTempText = ""
    @State private var preCoolUnit = "F"
    @State private var preCoolSubmitting = false

    @State private var toast: String? = nil

    // Tri-country food-safety release regime (regulatory citations, not telemetry).
    private let regimes: [(region: String, body: String, cite: String)] = [
        ("US · FDA FSMA",  "Sanitary Transport",       "21 CFR 1.908"),
        ("CA · CFIA",      "Safe Food for Canadians",  "SFCR 2018-108"),
        ("MX · COFEPRIS",  "Cold-chain sanitary",      "NOM-251 + SENASICA"),
    ]

    private var enteredLoadId: Int? {
        let t = loadIdText.trimmingCharacters(in: .whitespaces)
        guard let n = Int(t), n > 0 else { return nil }
        return n
    }

    // MARK: Derived (all from real returned fields)

    private func fmtTemp(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var logCount: Int { status?.readings.count ?? 0 }
    private var excursions: Int { status?.excursionCount ?? 0 }

    /// Real temp-adherence = non-excursion readings / total readings.
    private var adherence: Double {
        guard let s = status else { return 0 }
        if s.readings.isEmpty { return s.isCompliant ? 1 : 0 }
        return Double(s.readings.count - s.excursionCount) / Double(s.readings.count)
    }

    private func gates(_ s: FSMAStatus611) -> [Gate611] {
        var g: [Gate611] = []
        g.append(Gate611(
            title: "Continuous sanitary transport log",
            citation: "21 CFR 1.908 · continuous",
            passed: !s.readings.isEmpty,
            value: "\(s.readings.count) logs"))
        g.append(Gate611(
            title: "Pre-cool verified before load",
            citation: "21 CFR 1.908(e)(3)",
            passed: s.preCoolVerified,
            value: s.preCoolVerified ? "verified" : "missing"))
        g.append(Gate611(
            title: "No temperature excursions",
            citation: "FDA danger-zone breach",
            passed: s.excursionCount == 0,
            value: "\(s.excursionCount)"))
        let bandPass: Bool = {
            if let t = s.currentTemp { return t >= s.minAllowed && t <= s.maxAllowed }
            return !s.readings.isEmpty
        }()
        g.append(Gate611(
            title: "Latest reading within FDA band",
            citation: "\(fmtTemp(s.minAllowed))–\(fmtTemp(s.maxAllowed))°F band",
            passed: bandPass,
            value: s.currentTemp != nil ? "\(fmtTemp(s.currentTemp!))°F" : "awaiting"))
        // Fifth gate only when the tolerance is really known (checkFSMARequired).
        if let r = rules {
            g.append(Gate611(
                title: "Excursion duration within tolerance",
                citation: "≤ \(r.excursionToleranceMinutes)min · FDA reportable",
                passed: s.excursionMinutes <= r.excursionToleranceMinutes,
                value: "\(s.excursionMinutes)min"))
        }
        return g
    }

    private func gatesPassed(_ s: FSMAStatus611) -> Int { gates(s).filter { $0.passed }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                loadIdField

                if enteredLoadId == nil {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enter a load to run the FSMA release gate")
                                .font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            Text("The gate reads the load's continuous temperature log against 21 CFR 1.908 and returns one CLEARED / BLOCKED verdict for the sanitary cert at the ramp.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                } else if loading {
                    LifecycleCard { Text("Running FSMA gate…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let s = status {
                    verdictHero(s)
                    kpiStrip(s)
                    if !s.isCompliant { blockBanner(s) }
                    checklist(s)
                    regimeCard
                    HStack(spacing: Space.s2) {
                        CTAButton(title: "Record temp", action: { openRecord() }, leadingIcon: "thermometer.medium")
                        CTAButton(title: "Pre-cool", action: { openPreCool() }, leadingIcon: "snowflake")
                    }
                } else {
                    LifecycleCard { Text("No FSMA status returned for this load.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showRecord) { recordSheet }
        .sheet(isPresented: $showPreCool) { preCoolSheet }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · COLD-CHAIN FSMA").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Cold-chain FSMA")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Load id field

    private var loadIdField: some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "number").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                TextField("Load ID", text: $loadIdText)
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .keyboardType(.numberPad)
                    .submitLabel(.go)
                    .onSubmit { Task { await load() } }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 12)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            Button {
                Task { await load() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 12, weight: .heavy))
                    Text("Run gate").font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(enteredLoadId == nil)
            .opacity(enteredLoadId == nil ? 0.5 : 1)
        }
    }

    // MARK: Verdict hero — release seal

    private func verdictHero(_ s: FSMAStatus611) -> some View {
        let color = s.isCompliant ? Brand.success : Brand.danger
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FSMA RELEASE GATE · 21 CFR 1.908")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    Text(s.isCompliant ? "CLEARED" : "BLOCKED")
                        .font(.system(size: 34, weight: .heavy)).kerning(-0.5)
                        .foregroundStyle(color)
                    Text(s.isCompliant
                         ? "Safe to issue sanitary cert at the ramp"
                         : "Hold car — clear the failing gate below")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(gatesPassed(s))/\(gates(s).count) checks · \(logCount) logs · \(excursions) excursion\(excursions == 1 ? "" : "s")")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                ReleaseSeal611(fraction: adherence, cleared: s.isCompliant, color: color)
            }
            .padding(Space.s4)
        }
    }

    // MARK: KPI strip

    private func kpiStrip(_ s: FSMAStatus611) -> some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "SETPOINT", value: "\(fmtTemp(s.setPoint))°F", gradientNumeral: true)
            MetricTile(label: "LOGS", value: "\(logCount)", accent: Brand.info)
            MetricTile(label: "EXCURSION", value: "\(excursions)", accent: excursions == 0 ? Brand.success : Brand.danger)
        }
    }

    // MARK: Block banner + violations

    private func blockBanner(_ s: FSMAStatus611) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(s.violations.count) FSMA violation\(s.violations.count == 1 ? "" : "s") holding release")
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.danger)
                    Text("Sanitary cert cannot issue until every gate below reads PASS")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            ForEach(Array(s.violations.enumerated()), id: \.offset) { _, v in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                    Text(v).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Checklist

    private func checklist(_ s: FSMAStatus611) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FSMA CHECKS · \(gatesPassed(s) == gates(s).count ? "ALL PASS" : "\(gates(s).count - gatesPassed(s)) BLOCKING")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(gates(s)) { g in gateRow(g) }
            }
        }
    }

    private func gateRow(_ g: Gate611) -> some View {
        let color = g.passed ? Brand.success : Brand.danger
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: g.passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(g.title)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(g.citation)
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(g.passed ? "PASS" : "BLOCK")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.14)))
                Text(g.value)
                    .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .background(g.passed ? palette.bgCard : Brand.danger.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(g.passed ? palette.borderFaint : Brand.danger.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Tri-country release regime reference

    private var regimeCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FOOD-SAFETY RELEASE REGIME")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(regimes, id: \.region) { r in
                    HStack(spacing: Space.s3) {
                        Image(systemName: "building.columns.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.region).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(r.body).font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Text(r.cite)
                            .font(.system(size: 11, weight: .heavy)).monospaced().foregroundStyle(palette.textTertiary)
                    }
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
        }
    }

    // MARK: Record-temp sheet

    private var recordSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RECORD FSMA TEMP").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Text("Log a continuous-chain reading")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
                Text("Appends to the load's 21 CFR 1.908 continuous log. An out-of-band value is auto-flagged as an excursion.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)

                inputField(label: "TEMPERATURE", placeholder: "e.g. 34", text: $recordTempText, numeric: true)

                unitToggle(selection: $recordUnit)

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("EVENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    ForEach(FSMAEvent611.allCases) { ev in
                        Button {
                            recordEvent = ev
                        } label: {
                            HStack {
                                Image(systemName: recordEvent == ev ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(recordEvent == ev ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                                Text(ev.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                                Spacer()
                            }
                            .padding(Space.s3)
                            .background(palette.bgCard)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(recordEvent == ev ? palette.borderFaint : Color.clear))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                inputField(label: "LOCATION (optional)", placeholder: "e.g. LB ICTF ramp", text: $recordLocation, numeric: false)
                inputField(label: "NOTES (optional)", placeholder: "context for the log", text: $recordNotes, numeric: false)

                Button {
                    Task { await submitRecord() }
                } label: {
                    HStack {
                        Spacer()
                        if recordSubmitting { ProgressView().tint(.white) }
                        else { Text("Record temperature").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white) }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(recordSubmitting || Double(recordTempText.trimmingCharacters(in: .whitespaces)) == nil)
                .opacity(Double(recordTempText.trimmingCharacters(in: .whitespaces)) == nil ? 0.5 : 1)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
    }

    // MARK: Pre-cool sheet

    private var preCoolSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "snowflake").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("PRE-COOL VERIFICATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Verify trailer pre-cool")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("21 CFR 1.908(e)(3) requires a pre-cool check before loading. Enter the measured trailer temperature at the dock.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            if let r = rules {
                Text("Required band: \(fmtTemp(r.preCoolMinTemp))–\(fmtTemp(r.preCoolMaxTemp))°F")
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.info)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Brand.info.opacity(0.12)))
            }

            inputField(label: "TRAILER TEMPERATURE", placeholder: "e.g. 34", text: $preCoolTempText, numeric: true)
            unitToggle(selection: $preCoolUnit)

            Button {
                Task { await submitPreCool() }
            } label: {
                HStack {
                    Spacer()
                    if preCoolSubmitting { ProgressView().tint(.white) }
                    else { Text("Verify pre-cool").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white) }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(preCoolSubmitting || Double(preCoolTempText.trimmingCharacters(in: .whitespaces)) == nil)
            .opacity(Double(preCoolTempText.trimmingCharacters(in: .whitespaces)) == nil ? 0.5 : 1)

            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // Small labelled input — a method (not a local func in a closure) so it is safe.
    private func inputField(label: String, placeholder: String, text: Binding<String>, numeric: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .keyboardType(numeric ? .numbersAndPunctuation : .default)
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func unitToggle(selection: Binding<String>) -> some View {
        HStack(spacing: Space.s2) {
            ForEach(["F", "C"], id: \.self) { u in
                Button {
                    selection.wrappedValue = u
                } label: {
                    Text("°\(u)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(selection.wrappedValue == u ? .white : palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selection.wrappedValue == u ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(selection.wrappedValue == u ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Actions

    private func openRecord() {
        recordTempText = ""
        recordUnit = "F"
        recordEvent = .manual
        recordLocation = ""
        recordNotes = ""
        showRecord = true
    }

    private func openPreCool() {
        preCoolTempText = ""
        preCoolUnit = "F"
        showPreCool = true
    }

    // MARK: Data

    private func load() async {
        guard let lid = enteredLoadId else {
            status = nil; rules = nil; loadError = nil; loading = false; return
        }
        loading = true; loadError = nil
        struct StatusInput: Encodable { let loadId: Int }
        do {
            let s: FSMAStatus611 = try await EusoTripAPI.shared.query("reeferTemp.getFSMAStatus", input: StatusInput(loadId: lid))
            self.status = s
            // Fail-soft: the tolerance gate is enriched from checkFSMARequired; a
            // failure there never blocks the primary verdict.
            struct RequiredInput: Encodable { let cargoType: String }
            do {
                let req: FSMARequired611 = try await EusoTripAPI.shared.query("reeferTemp.checkFSMARequired", input: RequiredInput(cargoType: s.cargoClass))
                self.rules = req.rules
            } catch {
                self.rules = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            self.status = nil
        }
        loading = false
    }

    private func submitRecord() async {
        guard let lid = enteredLoadId,
              let temp = Double(recordTempText.trimmingCharacters(in: .whitespaces)) else { return }
        struct RecordInput: Encodable {
            let loadId: Int
            let temperature: Double
            let unit: String
            let location: String?
            let eventType: String
            let notes: String?
        }
        recordSubmitting = true
        do {
            let res: RecordTempResult611 = try await EusoTripAPI.shared.mutation(
                "reeferTemp.recordFSMATemp",
                input: RecordInput(
                    loadId: lid,
                    temperature: temp,
                    unit: recordUnit,
                    location: recordLocation.isEmpty ? nil : recordLocation,
                    eventType: recordEvent.rawValue,
                    notes: recordNotes.isEmpty ? nil : recordNotes))
            showRecord = false
            withAnimation(.easeOut(duration: 0.18)) {
                toast = res.isExcursion ? "Excursion logged · gate re-run" : "Temp logged · gate re-run"
            }
            await load()
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        } catch {
            withAnimation(.easeOut(duration: 0.18)) { toast = (error as? EusoTripAPIError)?.errorDescription ?? "Record failed" }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
        recordSubmitting = false
    }

    private func submitPreCool() async {
        guard let lid = enteredLoadId,
              let temp = Double(preCoolTempText.trimmingCharacters(in: .whitespaces)) else { return }
        struct PreCoolInput: Encodable { let loadId: Int; let trailerTemp: Double; let unit: String }
        preCoolSubmitting = true
        do {
            let res: PreCoolResult611 = try await EusoTripAPI.shared.mutation(
                "reeferTemp.verifyPreCool",
                input: PreCoolInput(loadId: lid, trailerTemp: temp, unit: preCoolUnit))
            showPreCool = false
            withAnimation(.easeOut(duration: 0.18)) {
                toast = res.passed ? "Pre-cool PASSED · \(fmtTemp(res.tempF))°F" : "Pre-cool FAILED · do not load"
            }
            await load()
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        } catch {
            withAnimation(.easeOut(duration: 0.18)) { toast = (error as? EusoTripAPIError)?.errorDescription ?? "Pre-cool failed" }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
        preCoolSubmitting = false
    }
}

// MARK: - Release seal (hero verdict visual)
//
// A shield seal whose stroke fills (trim 0→adherence) to the REAL temp-adherence
// fraction (non-excursion readings / total). On CLEARED it stamps in with a
// decelerating settle spring + a brief overshoot, reading as the sanitary cert
// being sealed; on BLOCKED it settles without the stamp and carries the danger
// tint. Reduce Motion snaps straight to final with no stamp. The centre glyph
// (seal check vs shield warning) and percent are honest reflections of the same
// adherence number — never a fabricated fill.
private struct ReleaseSeal611: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double
    let cleared: Bool
    let color: Color

    @State private var shown: Double = 0
    @State private var stamp: CGFloat = 0.6

    var body: some View {
        ZStack {
            ShieldShape611()
                .stroke(color.opacity(0.16), lineWidth: 6)
                .frame(width: 76, height: 84)
            ShieldShape611()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: 76, height: 84)
            VStack(spacing: 2) {
                Image(systemName: cleared ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(color)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .scaleEffect(stamp)
        .onAppear { settle() }
        .onChange(of: fraction) { _, _ in settle() }
        .onChange(of: cleared) { _, _ in settle() }
    }

    private func settle() {
        if reduceMotion {
            shown = fraction
            stamp = 1.0
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            shown = fraction
        }
        // Cleared stamps in with a light overshoot; blocked just settles to 1.0.
        stamp = 0.6
        withAnimation(.spring(response: 0.4, dampingFraction: cleared ? 0.55 : 0.82)) {
            stamp = 1.0
        }
    }
}

// MARK: - Shield shape (a Shape method — safe, no closure-local func)

private struct ShieldShape611: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = rect.midX
        let shoulderY = rect.minY + h * 0.14
        let midY = rect.minY + h * 0.52
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + w, y: shoulderY))
        p.addLine(to: CGPoint(x: rect.minX + w, y: midY))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY),
                       control: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.90))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: midY),
                       control: CGPoint(x: rect.minX, y: rect.minY + h * 0.90))
        p.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        p.closeSubpath()
        return p
    }
}

#Preview("611 · Rail Cold-Chain FSMA · Night") { RailFSMAComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("611 · Rail Cold-Chain FSMA · Light") { RailFSMAComplianceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
