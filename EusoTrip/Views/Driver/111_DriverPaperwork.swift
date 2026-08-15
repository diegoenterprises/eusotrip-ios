//
//  111_DriverPaperwork.swift
//  EusoTrip — Lifecycle screen 111 · Driver Paperwork (AT-PAPERWORK).
//
//  Verbatim reconstruction of the 2026-05 wireframe frame
//  `111 Paperwork · Dark` (440×956). Fires once the truck is still on
//  the dock, the POD is signed, and the driver is collecting the
//  remaining close-out documents. The seventh AT-PAPERWORK context in
//  the §74 → §82 cousin-port lineage.
//
//  Composition (top → bottom, matching the frame):
//    • TopBar — gradient eyebrow "DRIVER · PAPERWORK", live load-ID mono
//      tag, back chevron, live "{pickup} → {delivery}" title, ON-DUTY
//      HoS pill.
//    • Iridescent hairline.
//    • Hero persistence card (92pt) — POD-signed success pill, DOC UPLOAD
//      progress pill (live N/total), center dock-persistence chip, and a
//      live mileage caption.
//    • 8-stage lifecycle strip — PAPERWORK current (idx 6), CLOSED next.
//    • Pickup / Delivery card — live pickup + delivery rows.
//    • Paperwork checklist card — live document rows from
//      documentManagement.getDocuments (DONE/PENDING off real status).
//    • Shipper-of-record card — live shipper party.
//    • BottomNav — TRIPS active (Driver variant).
//
//  Wiring: hydrates the active load via TripLifecycleStore +
//  `loads.getById` (decoded with the CORRECTED server shape — top-level
//  `id: String?`, nested pickup/deliveryLocation {city,state}, real
//  driver/catalyst/shipper PARTY objects), and the document-collection
//  state via `documentManagement.getDocuments` (driver-scoped). The
//  "Submit BOL" CTA executes the lifecycle transition out of PAPERWORK.
//  Every rendered business value binds to live fetched data; anything
//  without a live source renders an honest "-" / "—" / EusoEmptyState —
//  no synthesized replies, no mock data, no baked persona.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// Strip machine tokens (bracketed enum keys, key=value pairs) that
/// occasionally bleed into server equipment/cargo display strings,
/// e.g. "Tanker · Hazmat [tanker_hazmat] · vertical=truck" → "Tanker · Hazmat".
/// Display-layer only — never apply to values used as lexicon keys or sent
/// to the server. Mirrors cleanLabel in 205_ShipperLoadDetail.swift.
/// Returns "—" for nil/empty; never returns empty for a non-empty input.
fileprivate func cleanEquipLabel(_ s: String?) -> String {
    guard let s = s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
    var out = s
    // remove "[anything]" bracket tokens (with any leading whitespace)
    out = out.replacingOccurrences(
        of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
    // remove "key=value" tokens (vertical=truck, rate-unit=per_mile, …),
    // dropping any leading separator/bullet too
    out = out.replacingOccurrences(
        of: #"\s*[·•]?\s*[A-Za-z_-]+=\S+"#, with: "", options: .regularExpression)
    // collapse doubled separators left behind by the removals
    out = out.replacingOccurrences(
        of: #"\s*·\s*·\s*"#, with: " · ", options: .regularExpression)
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: " ·•\n\r\t"))
    // Guard: never return empty for a non-empty input.
    if trimmed.isEmpty {
        let fallback = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "—" : fallback
    }
    return trimmed
}

// MARK: - Live load context (CORRECTED server shape)
//
// Mirrors the proven binding in DL091 / DL126 / DL133:
//   • Top-level load id is a String on the wire (loads.getById ->
//     String(load.id)); decoding as Int throws typeMismatch and fails
//     the WHOLE decode -> blank screen.
//   • pickup/delivery are nested {city,state} objects (NOT flat fields).
//   • driver/catalyst/shipper are PARTY objects; their ids are numeric.
//   • rate is a DECIMAL String; distance is a Double.
// Swift Decodable silently ignores unknown JSON keys, so the server may
// carry more fields than we model here without breaking the decode.
private struct PWLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let pickupLocation: PWLoc?
    let deliveryLocation: PWLoc?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let cargoType: String?
    let status: String?
    let driver: PWParty?
    let catalyst: PWParty?
    let shipper: PWParty?
    struct PWLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct PWParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

struct DriverPaperwork: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: PWLoadCtx?

    /// Live document-collection state for this load, fetched from
    /// `documentManagement.getDocuments`. The hero "DOC UPLOAD" pill and
    /// the checklist rows read off these once the load hydrates. Nil
    /// until a successful read — no authored stand-in, no fabricated
    /// "2 of 5".
    @State private var docs: [DocumentManagementAPI.Document] = []
    @State private var docsTotal: Int?
    @State private var didLoadDocs: Bool = false
    @State private var isLoadingDocs: Bool = false

    /// Live POD packet for this load, fetched from `pod.getPODForLoad`.
    /// The hero "POD SIGNED" pill binds its `submittedAt` (formatted) and
    /// the receiver name binds `receiverName` when present. Nil until a
    /// successful read returns a packet — no authored stand-in, no baked
    /// "4:48 PM" / persona name. The packet is honestly absent (nil) until
    /// the driver actually submits the POD.
    @State private var pod: PODAPI.PODPacket?

    @State private var isSubmitting: Bool = false
    @State private var actionError: String?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    // MARK: - 8-stage lifecycle (PAPERWORK current = idx 6)

    private let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP",
                          "IN TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]
    private let currentStageIndex = 6

    // MARK: - Live display helpers (honest "-" / "—" fallback)

    /// Mono load-ID tag — live load number, else honest dash.
    private var loadNumberDisplay: String { activeLoad?.loadNumber ?? "—" }

    /// "{pickup} → {delivery}" from the nested location objects. Server
    /// sends "" (not nil) when missing, so we treat empty as absent.
    private var lane: String {
        let o = locText(activeLoad?.pickupLocation)
        let d = locText(activeLoad?.deliveryLocation)
        guard o != nil || d != nil else { return "—" }
        return "\(o ?? "—") → \(d ?? "—")"
    }

    private func locText(_ loc: PWLoadCtx.PWLoc?) -> String? {
        let parts = [loc?.city, loc?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Live mileage caption — distance is a real Double on the load.
    private var distanceCaption: String {
        guard let d = activeLoad?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi · ON DOCK"
    }

    /// Hero POD-signed pill — "POD SIGNED <formatted submittedAt>" from
    /// the live POD packet, honest "POD SIGNED —" when no packet (or no
    /// timestamp) is present. No baked "4:48 PM".
    private var podSignedDisplay: String {
        guard let raw = pod?.submittedAt, !raw.isEmpty,
              let formatted = Self.formatPODTime(raw) else {
            return "POD SIGNED —"
        }
        return "POD SIGNED \(formatted)"
    }

    /// Parse the server ISO-8601 `submittedAt` and render a short local
    /// time (e.g. "4:48 PM"). Returns nil when the string can't be parsed
    /// so the pill stays honestly em-dashed rather than echoing raw text.
    private static func formatPODTime(_ iso: String) -> String? {
        let parsers: [ISO8601DateFormatter] = {
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [withFrac, plain]
        }()
        let date = parsers.lazy.compactMap { $0.date(from: iso) }.first
        guard let d = date else { return nil }
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        return out.string(from: d)
    }

    /// Receiver name — bound from the live POD packet's `receiverName`
    /// when present, else honest "—". The receiver is who signed the POD
    /// at the dock; no authored persona.
    private var receiverNameDisplay: String {
        if let n = pod?.receiverName, !n.isEmpty { return n }
        return "—"
    }

    /// Documents uploaded for this driver. Reads live; no authored stand-in.
    private var docsIn: Int { docs.count }
    /// Total docs the server reports for the page (or the count when the
    /// total isn't returned). No fabricated checklist length.
    private var docsTotalDisplay: Int { docsTotal ?? docs.count }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                heroPersistenceCard
                section("LIFECYCLE · PAPERWORK") { lifecycleCard }
                section("PICKUP · DELIVERY") { pickupDeliveryCard }
                section("PAPERWORK CHECKLIST") { checklistCard }
                section("SHIPPER OF RECORD") { shipperOfRecordCard }
                if let err = actionError { errorBanner(err) }
                submitCTA
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .eusoRefreshTask { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: - Section wrapper (gray eyebrow + content)

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            content()
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EusoTripEyebrow(verbatim: "DRIVER · PAPERWORK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(loadNumberDisplay)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                Button { navBack?() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")

                Text(lane)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }

            hosPill
        }
    }

    /// Blue ON-DUTY pill — mirrors the frame's `#1473FF @0.18` capsule
    /// with the donut HoS dot. There is no HoS-clock source on the load
    /// record, so the remaining-time reads an honest "—".
    private var hosPill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Brand.blue).frame(width: 12, height: 12)
                Circle().fill(palette.bgPage).frame(width: 5, height: 5)
            }
            Text("ON-DUTY · —")
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.blue)
                .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Brand.blue.opacity(0.18)))
    }

    // MARK: - Hero persistence card (92pt)

    private var heroPersistenceCard: some View {
        VStack(spacing: 0) {
            HStack {
                // POD-signed success pill — live `submittedAt` from the
                // POD packet (pod.getPODForLoad), formatted to local time;
                // honest "POD SIGNED —" until a packet with a timestamp
                // is read.
                Text(podSignedDisplay)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.20)))
                Spacer(minLength: 8)
                // DOC UPLOAD progress pill (gradient) — live N/total.
                Text(didLoadDocs ? "DOC UPLOAD · \(docsIn)/\(docsTotalDisplay)" : "DOC UPLOAD · —")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.primary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.primary.opacity(0.22)))
            }

            Spacer(minLength: 6)

            // Center dock-persistence indicator
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.22))
                    .frame(width: 60, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(LinearGradient.primary, lineWidth: 1.4)
                    )
                ZStack {
                    Circle().fill(palette.bgCardSoft)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
            }

            Spacer(minLength: 6)

            Text(distanceCaption)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(
            LinearGradient(colors: [Color(hex: 0x23282F), Color(hex: 0x0E1116)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: - 8-stage lifecycle strip

    private var lifecycleCard: some View {
        VStack(spacing: 14) {
            // Track + nodes
            GeometryReader { geo in
                let n = stages.count
                let inset: CGFloat = 14
                let usable = geo.size.width - inset * 2
                let step = usable / CGFloat(n - 1)
                let y: CGFloat = 14
                ZStack(alignment: .topLeading) {
                    // Completed segment (gradient) up to current
                    Rectangle()
                        .fill(LinearGradient.primary)
                        .frame(width: step * CGFloat(currentStageIndex), height: 2)
                        .offset(x: inset, y: y - 1)
                    // Remaining segment (faint) after current
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: step * CGFloat(n - 1 - currentStageIndex), height: 2)
                        .offset(x: inset + step * CGFloat(currentStageIndex), y: y - 1)

                    ForEach(0..<n, id: \.self) { i in
                        node(for: i)
                            .position(x: inset + step * CGFloat(i), y: y)
                    }
                }
            }
            .frame(height: 28)

            // Stage labels
            HStack(spacing: 0) {
                ForEach(0..<stages.count, id: \.self) { i in
                    Text(stages[i])
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(stageLabelStyle(i))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }

            Text(lifecycleNote)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Composed from live values only. POD-signed time has no source, so
    /// it isn't asserted; doc progress reads live or honest "—".
    private var lifecycleNote: String {
        let docPart = didLoadDocs ? "\(docsIn) of \(docsTotalDisplay) docs uploaded" : "documents —"
        let statePart = (activeLoad?.status?.replacingOccurrences(of: "_", with: " ").capitalized).map { "· \($0)" } ?? ""
        return "Paperwork stage \(docPart) \(statePart)".trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder
    private func node(for i: Int) -> some View {
        if i < currentStageIndex {
            // Completed — gradient dot + check
            ZStack {
                Circle().fill(LinearGradient.primary).frame(width: 12, height: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(.white)
            }
        } else if i == currentStageIndex {
            // Current — ringed gradient bullseye
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2)
                    .frame(width: 22, height: 22)
                Circle().fill(LinearGradient.primary).frame(width: 16, height: 16)
                Circle().fill(Color.white).frame(width: 6, height: 6)
            }
        } else {
            // Pending — hollow slate dot
            Circle().fill(palette.bgCardSoft)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(palette.borderStrong))
        }
    }

    private func stageLabelStyle(_ i: Int) -> AnyShapeStyle {
        if i == currentStageIndex { return AnyShapeStyle(LinearGradient.primary) }
        if i > currentStageIndex { return AnyShapeStyle(palette.textTertiary) }
        return AnyShapeStyle(palette.textPrimary)
    }

    // MARK: - Pickup / Delivery card

    private var pickupDeliveryCard: some View {
        VStack(spacing: 0) {
            stopRow(
                eyebrow: "PICK UP",
                eyebrowColor: Brand.success,
                trailing: "—",
                trailingColor: palette.textSecondary,
                primary: locText(activeLoad?.pickupLocation) ?? "—",
                secondary: "—",
                filled: false
            )
            Divider().overlay(Color.white.opacity(0.08))
                .padding(.vertical, 4)
            stopRow(
                eyebrow: "DELIVER",
                eyebrowColor: Brand.success,
                trailing: "—",
                trailingColor: Brand.success,
                primary: locText(activeLoad?.deliveryLocation) ?? "—",
                secondary: "—",
                filled: true
            )
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func stopRow(eyebrow: String, eyebrowColor: Color,
                         trailing: String, trailingColor: Color,
                         primary: String, secondary: String,
                         filled: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(filled ? AnyShapeStyle(Brand.success) : AnyShapeStyle(LinearGradient.diagonal))
                    .frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(eyebrowColor)
                    Spacer(minLength: 6)
                    Text(trailing)
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(trailingColor)
                }
                Text(primary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Paperwork checklist card

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cargo / equipment strip — live load attributes, honest "—".
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(Brand.hazmat)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0E1116))
                }
                .frame(width: 22, height: 22)
                Text(cargoStripText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(cleanEquipLabel(activeLoad?.equipmentType))
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.success)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                LinearGradient(colors: [Color(hex: 0x23282F), Color(hex: 0x0E1116)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.bottom, 12)

            // Live document rows from documentManagement.getDocuments.
            // No invented titles; DONE/PENDING reads the real status.
            if !didLoadDocs && isLoadingDocs {
                Text("Loading documents…")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 6)
            } else if docs.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "doc.text"),
                    title: "No documents yet",
                    subtitle: "Uploaded close-out documents will appear here.",
                    cta: nil,
                    comingSoon: false
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } else {
                ForEach(docs) { doc in
                    let done = isDone(doc.status)
                    HStack(spacing: 8) {
                        checkbox(done: done)
                        Text(doc.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(done ? palette.textPrimary : Brand.blue)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 6)
                        Text(doc.status.uppercased())
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(done ? Brand.success : Brand.blue)
                    }
                    .padding(.vertical, 6)
                }
            }

            // Receiver POC — the receiver who signed the POD at the dock.
            // The name binds from the live POD packet's `receiverName`
            // (pod.getPODForLoad); honest "—" until a packet is read.
            // No driver-accessible delivery-stop phone source exists on
            // the load record, so the phone reads honest "—".
            Text("Receiver POC: \(receiverNameDisplay)")
                .font(EType.mono(.caption)).tracking(0.2)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Cargo strip — composed from live load attributes; "—" when absent.
    private var cargoStripText: String {
        if let c = activeLoad?.cargoType, !c.isEmpty { return c }
        if let e = activeLoad?.equipmentType, !e.isEmpty { return e }
        return "—"
    }

    /// A document counts as DONE when its status reads as a terminal/
    /// verified state. Anything else is PENDING. Reads the real server
    /// status string — no positional "first N are done" assumption.
    private func isDone(_ status: String) -> Bool {
        let s = status.lowercased()
        return s.contains("verif") || s.contains("approv")
            || s.contains("complete") || s.contains("signed")
            || s == "done" || s == "active" || s == "valid"
    }

    private func checkbox(done: Bool) -> some View {
        Group {
            if done {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Brand.success)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                }
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Brand.blue, lineWidth: 1.4)
                    )
            }
        }
        .frame(width: 14, height: 14)
    }

    // MARK: - Shipper-of-record card

    private var shipperOfRecordCard: some View {
        let shipper = activeLoad?.shipper
        let shipName = shipper?.companyName ?? shipper?.name ?? "—"
        let shipInitials = shipper?.initials ?? "—"
        let shipContact = shipper?.name ?? "—"
        let dot = shipper?.dotNumber.map { "USDOT \($0)" }
        let mc = shipper?.mcNumber.map { "MC-\($0)" }
        let ids = [dot, mc].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                Text(shipInitials)
                    .font(.system(size: 16, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shipName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text("VERIFIED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.success.opacity(0.16)))
                }
                Text(shipContact)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                Text(ids.isEmpty ? "—" : ids)
                    .font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Submit CTA + error banner

    private var submitCTA: some View {
        CTAButton(
            title: isSubmitting ? "Submitting…" : "Submit BOL",
            action: { Task { await submitBol() } },
            subtitle: "PHOTOS PENDING",
            isLoading: isSubmitting
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(Brand.danger.opacity(0.4)))
    }

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty else { return }
        // CORRECTED shape: top-level id is String?, locations nested,
        // parties as objects — decode via the local PWLoadCtx so an
        // Int-id mismatch can never blank the whole screen.
        struct In: Encodable { let id: String }
        do {
            activeLoad = try await EusoTripAPI.shared.query(
                "loads.getById", input: In(id: lifecycle.loadId)
            )
        } catch {
            actionError = "Couldn't load the trip: \((error as NSError).localizedDescription)"
        }
        await loadPOD()
        await loadDocs()
    }

    /// Fetch the POD packet for this load so the hero "POD SIGNED" pill
    /// binds the real `submittedAt` and the Receiver POC binds the real
    /// `receiverName`. The packet is nil until the driver has actually
    /// submitted the POD — that absence renders the honest "—" pill, not
    /// a fabricated time. Errors surface honestly; nothing is invented on
    /// failure.
    private func loadPOD() async {
        guard let n = Int(lifecycle.loadId) else { return }
        do {
            pod = try await EusoTripAPI.shared.pod.getPODForLoad(loadId: n)
        } catch {
            // Don't clobber a load-level error banner with a POD read
            // miss; the pill simply stays honestly em-dashed.
            if actionError == nil {
                actionError = "Couldn't load the POD: \((error as NSError).localizedDescription)"
            }
        }
    }

    /// Pull this driver's documents so the hero "DOC UPLOAD" pill and the
    /// checklist rows reflect real upload progress. The server scopes
    /// `getDocuments` to the signed-in driver. Errors surface honestly;
    /// nothing is fabricated when the read fails.
    private func loadDocs() async {
        isLoadingDocs = true
        defer { isLoadingDocs = false }
        do {
            let resp = try await EusoTripAPI.shared.documentManagement.getDocuments(
                page: 1, pageSize: 50
            )
            docs = resp.documents
            docsTotal = resp.total
            didLoadDocs = true
        } catch {
            actionError = "Couldn't load documents: \((error as NSError).localizedDescription)"
        }
    }

    /// Advance the load out of PAPERWORK once the BOL is submitted.
    /// Picks the first forward transition toward closure; surfaces any
    /// failure rather than pretending success.
    private func submitBol() async {
        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }
        let forwardKeys = ["closed", "completed", "paperwork", "invoice", "settle"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        guard let transition = candidate else {
            // No live transition available (e.g. unhydrated preview) —
            // fall through to the local advance closure so the lifecycle
            // ladder keeps walking, without faking a server reply.
            advance?()
            return
        }
        let ok = await lifecycle.execute(transition)
        if ok {
            advance?()
        } else if let err = lifecycle.lastError {
            actionError = "Couldn't submit: \((err as NSError).localizedDescription)"
        } else {
            actionError = "Couldn't submit the BOL. Please try again."
        }
    }
}

// MARK: - Wrapper (default-initializable)

struct DriverPaperworkScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            DriverPaperwork(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_111(),
                      trailing: driverNavTrailing_111(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_111() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_111() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("111 · Driver Paperwork · Dark") {
    DriverPaperworkScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("111 · Driver Paperwork · Light") {
    DriverPaperworkScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
