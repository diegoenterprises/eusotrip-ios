//
//  MeComplianceView.swift
//  EusoTrip — Regulatory Compliance Framework (Wave-6, 2026-04-22)
//
//  What this file is:
//    The shared compliance data model + inline UI primitives that every
//    driver-journey screen imports to surface FMCSA / PHMSA rule
//    acknowledgements INLINE, next to the work itself.
//
//  Why it's shaped this way:
//    Web platform reference: frontend/client/src/components/
//      RegulatoryCompliancePanel.tsx is embedded in LoadCreationWizard
//      and LoadDetails — compliance is NOT a hub, it's a drop-in panel
//      carried into the existing user journey. We mirror that pattern
//      here. No Me-tab hub, no dedicated tab. Just small chips and
//      panels that sit alongside DVIR, dispatch, pickup, delivery,
//      and any screen whose decisions touch a live regulation.
//
//  Ships here:
//    • ComplianceRule — struct with citation + effective date + detail.
//    • ComplianceRule.Tag — stable identifier for per-rule ack/lookup.
//    • ComplianceRule.Severity — informational / advisory / action.
//    • ComplianceStore — UserDefaults-backed per-driver ack ledger.
//    • ComplianceCatalog.march2026 — canonical rule list for the
//      March 23, 2026 FMCSA wave + the PHMSA Exxon docket.
//    • ComplianceInlineChip — single-line "Updated Mar 23, 2026 · § 396"
//      chip any screen can footer with.
//    • ComplianceInlinePanel — drop-in expandable card that pairs a
//      set of rule tags to the screen's topic (e.g. eDVIR next to
//      DVIR, overfill + auxPump next to the fuel strip).
//
//  Doctrine:
//    §2 (gradient-only brand accents — chip leading dot uses
//       LinearGradient.diagonal), §3 (numbers + citation first),
//       §4.3 (hairline between stacked inline panels).
//
//  Powered by ESANG AI™.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Data model

/// A single rule surfaced in the driver's journey. The `tag` is the
/// stable per-rule key — both the iPhone and Pulse watch acknowledgement
/// stores write/read on this. Changing an existing rule's tag breaks
/// ack reconciliation; only add new tags, never rename old ones.
struct ComplianceRule: Identifiable, Equatable {
    enum Tag: String, CaseIterable, Equatable {
        case eDvir        = "fmcsa.edvir.396"
        case overfill     = "fmcsa.overfill.393_67"
        case auxPump      = "fmcsa.auxpump.393_67"
        case warningDevice = "fmcsa.warning_device.flares"
        case phmsaExxon   = "phmsa.2025_0777.exxon_preemption"
    }
    enum Severity: Equatable { case informational, advisory, action }

    let tag: Tag
    let headline: String
    let citation: String
    let effective: String          // "Mar 23, 2026" — display-friendly
    let summary: String            // One sentence — shows on the card face
    let detail: String             // Multi-paragraph explanation
    let callToAction: String       // "Acknowledge" or "Open docket"
    let severity: Severity

    var id: Tag { tag }
    var requiresAcknowledgement: Bool {
        switch severity {
        case .informational: return false
        case .advisory, .action: return true
        }
    }
}

/// Per-driver acknowledgement ledger. Each ack stamps the rule tag with
/// the local timestamp at the moment the driver tapped "I understand".
/// Uses UserDefaults so the ledger survives app restarts without
/// shipping a full persistence layer in this wave. Singleton so any
/// inline panel on any screen reads the same ack state.
@MainActor
final class ComplianceStore: ObservableObject {
    static let shared = ComplianceStore()

    @Published private(set) var acknowledgements: [ComplianceRule.Tag: Date] = [:]

    private let key = "eusotrip.compliance.ack.v1"

    init() {
        hydrate()
    }

    /// Returns true if the driver has acknowledged this specific rule.
    func isAcknowledged(_ tag: ComplianceRule.Tag) -> Bool {
        acknowledgements[tag] != nil
    }

    /// Acknowledge a rule. Writing the same tag twice is a no-op — we
    /// don't reset the original ack timestamp.
    func acknowledge(_ tag: ComplianceRule.Tag) {
        guard acknowledgements[tag] == nil else { return }
        acknowledgements[tag] = Date()
        persist()
    }

    /// Completion rate across ack-required rules — drives inline strips
    /// on screens that aggregate more than one rule.
    func completion(of rules: [ComplianceRule]) -> Double {
        let ackable = rules.filter { $0.requiresAcknowledgement }
        guard !ackable.isEmpty else { return 1.0 }
        let done = ackable.filter { isAcknowledged($0.tag) }.count
        return Double(done) / Double(ackable.count)
    }

    func acknowledgedCount(in rules: [ComplianceRule]) -> Int {
        rules.filter { $0.requiresAcknowledgement && isAcknowledged($0.tag) }.count
    }

    // MARK: - Persistence

    private func hydrate() {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] else { return }
        var next: [ComplianceRule.Tag: Date] = [:]
        for (k, v) in raw {
            if let tag = ComplianceRule.Tag(rawValue: k) {
                next[tag] = Date(timeIntervalSince1970: v)
            }
        }
        self.acknowledgements = next
    }

    private func persist() {
        var raw: [String: Double] = [:]
        for (k, v) in acknowledgements {
            raw[k.rawValue] = v.timeIntervalSince1970
        }
        UserDefaults.standard.set(raw, forKey: key)
    }
}

// MARK: - Rule catalog

/// The canonical rule set for the March 23, 2026 compliance wave. The
/// catalog is a static property so any surface (iPhone DVIR footer,
/// Pulse watch HOS strip, web RegulatoryCompliancePanel) can import
/// the same text and citations.
enum ComplianceCatalog {
    static let march2026: [ComplianceRule] = [
        ComplianceRule(
            tag: .eDvir,
            headline: "eDVIR explicit in the regs",
            citation: "49 CFR § 396",
            effective: "Mar 23, 2026",
            summary: "Electronic DVIR creation, signature, and retention are now explicitly permitted in Part 396 — not just allowed by analogy via 49 CFR 390.32.",
            detail: """
FMCSA rewrote Part 396 to call out electronic DVIRs directly. Drivers may originate, sign, and retain DVIRs entirely on an app or tablet — no paper copy required — provided the record is reproducible on demand during an inspection.

What this means for your cab:
• Your EusoTrip DVIR counts. The pretrip you complete from 011 Pretrip DVIR and the post-trip from Me › Zeun both now meet Part 396 without a paper backup.
• Keep the device available. Inspectors can ask you to display any eDVIR for the current day plus the previous 14 calendar days.
• Signatures — your tap-to-sign on submit is the regulatory signature. No separate paper signature is required.
""",
            callToAction: "I understand",
            severity: .action
        ),
        ComplianceRule(
            tag: .overfill,
            headline: "95% fuel-tank overfill cap removed",
            citation: "49 CFR § 393.67",
            effective: "Mar 23, 2026",
            summary: "The 95% fill limit on the tractor's own liquid fuel tank is gone. Cargo-tank overfill rules are unchanged.",
            detail: """
FMCSA removed the 95% fill restriction from § 393.67(c)(5)(iii). CVSA, Energy Marketers of America, and OOIDA all supported the change — the 95% limit originally dated to concerns that have since been engineered out of modern saddle tanks.

Important scope:
• Applies ONLY to the tractor's vehicle fuel tank.
• Cargo-tank-motor-vehicle rules (the tank you haul) are completely separate and UNCHANGED. Never confuse the two.
• Your EusoTrip fuel-gauge validation now flashes only at true overfill (≥ 99 %), not at 95 %.
""",
            callToAction: "I understand",
            severity: .action
        ),
        ComplianceRule(
            tag: .auxPump,
            headline: "Narrow auxiliary-pump carve-out",
            citation: "49 CFR § 393.67",
            effective: "Mar 23, 2026",
            summary: "Small trailer-mounted gravity or siphon auxiliary fuel pumps are now allowed if the vehicle is stopped.",
            detail: """
FMCSA added an exception for very small trailer-mounted auxiliary fuel pumps that meet all three of the following:
• Gravity- or siphon-fed (not a powered pump).
• Auxiliary fuel tank is 5 gallons or less.
• Used only while the vehicle is stopped — never while in motion.

Common use case: a shop-transfer siphon or small DEF/reefer top-off pump mounted on the trailer. EusoTrip has added an auxiliaryPump field on the Load model so dispatch can flag loads that carry one.
""",
            callToAction: "I understand",
            severity: .action
        ),
        ComplianceRule(
            tag: .warningDevice,
            headline: "Liquid-burning flares are out",
            citation: "49 CFR § 393.95",
            effective: "Mar 23, 2026",
            summary: "Liquid-burning flares are no longer a valid emergency warning device. Use reflective triangles or solid-fuel flares only.",
            detail: """
FMCSA removed the option to use liquid-burning flares as emergency warning devices. Drivers must now use either:
• Bidirectional reflective triangles (3 per truck), or
• Solid-fuel (fusee) flares, provided they are not carried on a cargo tank hauling flammable gas or flammable liquid.

The flame-device restriction on flammable-gas and flammable-liquid cargo tanks remains in full force — if you haul those, you cannot carry any burning flare, solid-fuel or otherwise. EusoTrip has updated the in-cab emergency-warning-device picker to drop "Liquid flare".
""",
            callToAction: "I understand",
            severity: .action
        ),
        ComplianceRule(
            tag: .phmsaExxon,
            headline: "PHMSA preemption docket — Exxon Mobil",
            citation: "PHMSA-2025-0777",
            effective: "Comments closed Mar 23, 2026 · Rebuttals closed Apr 21, 2026",
            summary: "PHMSA is weighing whether federal hazmat law preempts state tort claims against a gasoline CTMV operator over benzene cancer risk.",
            detail: """
PHMSA docket PHMSA-2025-0777 concerns an application from Exxon Mobil Corporation asking for an administrative determination that federal hazardous-materials transportation law preempts certain common-law tort claims over marking, employee training, loading and unloading, and hazmat classification for gasoline transported by cargo tank motor vehicle (CTMV).

The underlying tort case was brought by a former Exxon driver in New Jersey whose claims rest on benzene-in-gasoline cancer risk. Comments closed March 23, 2026; rebuttals closed April 21, 2026. A determination from PHMSA's Chief Counsel is pending.

Why this matters to you: the determination — whenever it issues — will affect how marking, loading, and training requirements interact with state-law injury claims for gasoline CTMV operators. Purely informational for now; no action required.
""",
            callToAction: "Open docket",
            severity: .informational
        )
    ]

    /// Lookup helper — returns the rule for a tag, nil if the tag is
    /// unknown. Safer than force-unwrapping the array filter at call
    /// sites.
    static func rule(for tag: ComplianceRule.Tag) -> ComplianceRule? {
        march2026.first(where: { $0.tag == tag })
    }

    /// Convenience — returns the rules for a curated list of tags
    /// in catalog order. Used by inline panels that want to pin
    /// multiple rules (e.g. overfill + auxPump on the fuel strip).
    static func rules(for tags: [ComplianceRule.Tag]) -> [ComplianceRule] {
        march2026.filter { tags.contains($0.tag) }
    }
}

// MARK: - Inline chip — a single-line rule footer

/// Inline chip for a single rule. Designed to sit in the footer of
/// any journey screen that touches the rule's subject matter. Single
/// line, ~one row tall, tapping opens a sheet with the rule detail
/// and the "I understand" CTA.
///
/// Example:
///   ComplianceInlineChip(tag: .eDvir)
///
/// renders as:
///   ● Updated Mar 23, 2026 · 49 CFR § 396 · eDVIR explicit
///     ↑gradient dot                      tap → detail sheet
struct ComplianceInlineChip: View {
    @Environment(\.palette) var palette
    @ObservedObject private var store = ComplianceStore.shared
    @State private var showDetail = false

    let tag: ComplianceRule.Tag

    var body: some View {
        if let rule = ComplianceCatalog.rule(for: tag) {
            Button { showDetail = true } label: {
                HStack(spacing: 8) {
                    // Gradient-filled leading dot = "this is a compliance
                    // signal, not a generic info row". Doctrine §2.
                    Circle()
                        .fill(acknowledged(rule) ? AnyShapeStyle(palette.success) : AnyShapeStyle(LinearGradient.diagonal))
                        .frame(width: 6, height: 6)
                    Text(chipLabel(for: rule))
                        .font(EType.mono(.micro))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.bgElev)
                .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                ComplianceRuleDetailSheet(rule: rule)
                    .eusoSheetX()
            }
        }
    }

    private func acknowledged(_ rule: ComplianceRule) -> Bool {
        rule.requiresAcknowledgement ? store.isAcknowledged(rule.tag) : true
    }

    private func chipLabel(for rule: ComplianceRule) -> String {
        let prefix = acknowledged(rule) ? "Compliant" : "Updated"
        return "\(prefix.uppercased()) \(rule.effective.uppercased()) · \(rule.citation)"
    }
}

// MARK: - Inline panel — expandable, can pin multiple rules

/// Inline panel that pairs a set of compliance rules to the screen
/// that embeds it. Mirrors the web's RegulatoryCompliancePanel — a
/// status header row (label + ack count), then per-rule rows on
/// expand. Drop this in below any screen section whose work touches
/// one or more rules (DVIR section → [.eDvir], fuel strip →
/// [.overfill, .auxPump], emergency-warning picker → [.warningDevice]).
struct ComplianceInlinePanel: View {
    @Environment(\.palette) var palette
    @ObservedObject private var store = ComplianceStore.shared
    @State private var expanded: Bool = false
    @State private var openRule: ComplianceRule.Tag? = nil

    let tags: [ComplianceRule.Tag]
    let topic: String     // e.g. "Electronic DVIR" — prints next to the header

    private var rules: [ComplianceRule] { ComplianceCatalog.rules(for: tags) }

    var body: some View {
        if rules.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                    headerRow
                }
                .buttonStyle(.plain)
                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rules.enumerated()), id: \.element.id) { idx, rule in
                            if idx > 0 { IridescentHairline().opacity(0.6) }
                            ruleRow(rule)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .eusoCard(radius: Radius.md)
            .sheet(item: Binding(
                get: { openRule.flatMap { ComplianceCatalog.rule(for: $0) } },
                set: { openRule = $0?.tag }
            )) { rule in
                ComplianceRuleDetailSheet(rule: rule)
                    .eusoSheetX()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: headerIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(headerIconStyle)
                .frame(width: 24, height: 24)
                .background(palette.bgElev)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("FMCSA · MAR 23, 2026")
                    .font(EType.mono(.micro))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(topic)
                    .font(EType.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            StatusPill(text: pillText, kind: pillKind)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: ComplianceRule) -> some View {
        Button { openRule = rule.tag } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rule.headline)
                        .font(EType.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(rule.citation)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(rule.summary)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ackBadge(rule)
                    Text(rule.effective)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func ackBadge(_ rule: ComplianceRule) -> some View {
        if !rule.requiresAcknowledgement {
            Text("ADVISORY")
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(palette.tintInfo)
                .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        } else if store.isAcknowledged(rule.tag) {
            Text("ACK")
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(palette.tintSuccess)
                .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        } else {
            Text("ACTION")
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.warning)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(palette.tintWarning)
                .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        }
    }

    // MARK: Pill / icon derivation

    private var pendingAction: Int {
        rules.filter { $0.requiresAcknowledgement && !store.isAcknowledged($0.tag) }.count
    }

    private var pillText: String {
        if pendingAction == 0 { return "Compliant" }
        return "\(pendingAction) to review"
    }

    private var pillKind: StatusPill.Kind {
        pendingAction == 0 ? .success : .warning
    }

    private var headerIcon: String {
        pendingAction == 0 ? "checkmark.shield" : "exclamationmark.shield"
    }

    private var headerIconStyle: AnyShapeStyle {
        pendingAction == 0 ? AnyShapeStyle(palette.success) : AnyShapeStyle(LinearGradient.diagonal)
    }
}

// MARK: - Rule detail sheet — opens from any chip or panel row

/// Detail sheet reached from inline chip/panel. Shows the citation,
/// effective date, summary, full detail prose, and the acknowledge
/// CTA for action-severity rules. This is the ONLY compliance modal
/// in the app — everything else is inline next to the journey work.
struct ComplianceRuleDetailSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ComplianceStore.shared

    let rule: ComplianceRule

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    // Citation strip
                    HStack(spacing: 6) {
                        Text(rule.citation)
                            .font(EType.mono(.caption))
                            .tracking(0.4)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(palette.bgElev)
                            .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderSoft))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                        Text("Effective \(rule.effective)")
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    // Headline
                    Text(rule.headline)
                        .font(EType.title)
                        .fontWeight(.bold)
                        .foregroundStyle(palette.textPrimary)
                    // Summary
                    Text(rule.summary)
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    IridescentHairline()
                    // Detail
                    Text(rule.detail)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Ack CTA or advisory badge
                    if rule.requiresAcknowledgement {
                        if store.isAcknowledged(rule.tag) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.success)
                                Text(ackText)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(palette.tintSuccess)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        } else {
                            Button {
                                store.acknowledge(rule.tag)
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(rule.callToAction)
                                        .font(EType.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .frame(minHeight: 48)
                                .background(LinearGradient.diagonal)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(palette.textSecondary)
                            Text("Informational · no action required.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(palette.tintInfo)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                }
                .padding(Space.s5)
            }
            .background(palette.bgSheet.ignoresSafeArea())
            .navigationTitle("Regulatory update")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Close")
                            .font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    private var ackText: String {
        guard let when = store.acknowledgements[rule.tag] else { return "Acknowledged" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return "Acknowledged \(df.string(from: when))"
    }
}
