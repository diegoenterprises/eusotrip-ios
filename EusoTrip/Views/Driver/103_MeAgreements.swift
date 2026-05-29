//
//  103_MeAgreements.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Agreements)
//
//  Screen 103 · Me · Agreements — the driver's contract inbox.
//  Shows every master agreement where the signed-in user is a
//  party (lease-on, owner-op, employment, dispatch-service,
//  per-load rate agreements). Pending-signature items are
//  surfaced at the top so drivers don't miss a contract waiting
//  on their signature.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Stats + agreements ship from `agreements.getStats` +
//      `agreements.list` — MCP-verified at
//      `frontend/server/routers/agreements.ts`.
//    • Sign fires `agreements.sign` with a Gradient-Ink
//      signature payload. Server SHA-256s the signature and
//      flips the agreement from `pending_signature` → `active`.
//
//  Related surfaces NOT in this screen:
//
//    • Recurring lane contracts live in the `laneContracts`
//      router. Server scopes by shipperId / catalystId /
//      brokerId today — no driverId filter. When the backend
//      adds driver-scope, 105 Me · Dedicated Lanes lands.
//    • The 4-channel load-creation wizard (Open Market / Direct
//      Catalyst / Via Broker / Own Fleet) is a SHIPPER /
//      CATALYST / BROKER flow, not a driver one. Driver-side,
//      the channel is visible as metadata on each load; the
//      posting wizard lands under those roles' own screens.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on pending + sign CTA.
//         Brand.warning on negotiating. Brand.magenta on
//         terminated.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Agreement type

private enum AgreementKind {
    case leaseOn, ownerOp, employment, dispatchService, rateAgreement, other

    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "lease_on", "lease-on":     self = .leaseOn
        case "owner_operator",
             "owner-operator":           self = .ownerOp
        case "employment",
             "w2", "1099":               self = .employment
        case "dispatch_service",
             "dispatch":                 self = .dispatchService
        case "rate_agreement",
             "rate-agreement",
             "rate":                     self = .rateAgreement
        default:                         self = .other
        }
    }

    var label: String {
        switch self {
        case .leaseOn:         return "Lease-on"
        case .ownerOp:         return "Owner-Operator"
        case .employment:      return "Employment"
        case .dispatchService: return "Dispatch Service"
        case .rateAgreement:   return "Rate Agreement"
        case .other:           return "Agreement"
        }
    }

    var icon: String {
        switch self {
        case .leaseOn:         return "arrow.triangle.swap"
        case .ownerOp:         return "person.fill.turn.right"
        case .employment:      return "briefcase"
        case .dispatchService: return "headphones"
        case .rateAgreement:   return "dollarsign.circle"
        case .other:           return "doc.text"
        }
    }
}

// MARK: - Screen root

struct MeAgreements: View {
    @Environment(\.palette) var palette
    @StateObject private var store = AgreementsStore()

    @State private var signing: AgreementsAPI.Agreement?

    private let statusFilters: [(label: String, raw: String?)] = [
        ("All",          nil),
        ("Active",       "active"),
        ("Pending",      "pending_signature"),
        ("Negotiating",  "negotiating"),
        ("Expired",      "expired"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                statsStrip
                statusFilter
                pendingSection
                activeSection
                historySection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: store.statusFilter) { _, _ in Task { await store.refresh() } }
        // RealtimeService → refresh agreements when carrier-issued
        // agreements land or load assignment triggers a new sign-up.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
        .sheet(item: $signing) { agreement in
            SignSheet(agreement: agreement, store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Agreements")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Lease-on · owner-op · employment · dispatch service")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Stats

    private var statsStrip: some View {
        let s = store.stats
        return HStack(spacing: Space.s2) {
            statTile(label: "ACTIVE",  value: "\(s?.active ?? 0)",          gradient: true)
            statTile(label: "PENDING", value: "\(s?.pendingSignature ?? 0)", gradient: (s?.pendingSignature ?? 0) > 0)
            statTile(label: "DRAFT",   value: "\(s?.draft ?? 0)",           gradient: false)
            statTile(label: "EXPIRED", value: "\(s?.expired ?? 0)",         gradient: false)
        }
    }

    private func statTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Status filter

    private var statusFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(statusFilters, id: \.label) { f in
                    let selected = store.statusFilter == f.raw
                    Button {
                        store.statusFilter = f.raw
                    } label: {
                        Text(f.label)
                            .font(EType.caption)
                            .foregroundStyle(selected
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textSecondary))
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 6)
                            .overlay(
                                Capsule().stroke(
                                    selected ? Color.clear : palette.textTertiary.opacity(0.5),
                                    lineWidth: 1
                                )
                            )
                            .background(
                                Capsule().fill(selected
                                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                               : AnyShapeStyle(Color.clear))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Pending

    private var pendingSection: some View {
        let pending = store.agreements.filter { ($0.status ?? "").lowercased() == "pending_signature" }
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !pending.isEmpty {
                Text("AWAITING YOUR SIGNATURE")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(Brand.warning)
                ForEach(pending) { agreement in
                    agreementCard(agreement, pending: true)
                }
            }
        }
    }

    // MARK: Active

    private var activeSection: some View {
        let active = store.agreements.filter { ($0.status ?? "").lowercased() == "active" }
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !active.isEmpty {
                Text("ACTIVE")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(active) { agreement in
                    agreementCard(agreement, pending: false)
                }
            }
        }
    }

    // MARK: History + empty

    private var historySection: some View {
        let other = store.agreements.filter {
            let s = ($0.status ?? "").lowercased()
            return s != "active" && s != "pending_signature"
        }
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !other.isEmpty {
                Text("OTHER")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(other) { agreement in
                    agreementCard(agreement, pending: false)
                }
            } else if store.agreements.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "doc.plaintext",
                    title: "No agreements yet",
                    subtitle: "Lease-on / owner-op / dispatch-service contracts from any carrier or broker you work with land here with full e-signature flow."
                )
            }
        }
    }

    // MARK: Agreement card

    private func agreementCard(_ a: AgreementsAPI.Agreement, pending: Bool) -> some View {
        let kind = AgreementKind(a.agreementType)
        let status = (a.status ?? "").lowercased()
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: kind.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.tintNeutral.opacity(0.5))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let num = a.agreementNumber, !num.isEmpty {
                        Text(num)
                            .font(EType.caption.monospaced())
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                statusChip(status)
            }

            HStack(spacing: Space.s3) {
                if let rate = a.baseRate, rate > 0 {
                    metaCol(label: "RATE", value: rateLabel(rate: rate, type: a.rateType))
                }
                if let days = a.paymentTermDays, days > 0 {
                    metaCol(label: "PAYMENT", value: "Net \(days)")
                }
                if let duration = a.contractDuration, !duration.isEmpty {
                    metaCol(label: "DURATION", value: duration.capitalized)
                }
                Spacer()
            }

            HStack(spacing: Space.s2) {
                if let equip = a.equipmentTypes, !equip.isEmpty {
                    metaPill(icon: "truck.box", text: equip.prefix(2).joined(separator: ", "))
                }
                if a.hazmatRequired == true {
                    metaPill(icon: "exclamationmark.triangle", text: "HAZMAT")
                }
                if let eff = a.effectiveDate, !eff.isEmpty {
                    metaPill(icon: "calendar", text: humanDate(eff))
                }
                Spacer()
            }

            if pending {
                Button {
                    signing = a
                } label: {
                    HStack {
                        Image(systemName: "signature")
                        Text("Sign")
                    }
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(store.signingId == a.id)
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(
                            pending ? Brand.warning.opacity(0.6) : palette.borderFaint,
                            lineWidth: pending ? 1 : 0.5
                        )
                )
        )
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let (label, tint, filled): (String, Color, Bool) = {
            switch status {
            case "active":
                return ("ACTIVE", .green, true)
            case "pending_signature":
                return ("PENDING", Brand.warning, false)
            case "negotiating":
                return ("NEGOTIATING", Brand.warning, false)
            case "draft":
                return ("DRAFT", palette.textTertiary, false)
            case "terminated":
                return ("TERMINATED", Brand.magenta, false)
            case "expired":
                return ("EXPIRED", palette.textTertiary, false)
            default:
                return (status.isEmpty ? "—" : status.uppercased(), palette.textTertiary, false)
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(
                Group {
                    if filled {
                        Capsule().fill(LinearGradient.diagonal)
                    } else {
                        Capsule().stroke(tint, lineWidth: 1)
                    }
                }
            )
    }

    private func metaCol(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .font(EType.micro)
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(palette.tintNeutral.opacity(0.55))
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s1) {
            Text("Every agreement here is encrypted at rest + signed with a Gradient-Ink SHA-256 hash on execution. Signatures are verifiable against the server copy.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Text("Recurring lane contracts + the load-posting wizard (marketplace / direct / broker / own-fleet) live in shipper + broker role surfaces — not here.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func rateLabel(rate: Double, type: String?) -> String {
        let fmt = String(format: "$%.2f", rate)
        switch (type ?? "").lowercased() {
        case "per_mile":   return "\(fmt)/mi"
        case "per_load":   return "\(fmt)/load"
        case "per_stop":   return "\(fmt)/stop"
        case "percentage": return "\(Int(rate))%"
        case "flat":       return fmt
        default:           return fmt
        }
    }

    private func humanDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let altF = ISO8601DateFormatter()
        let date = f.date(from: String(iso.prefix(10))) ?? altF.date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }
}

// MARK: - Sign sheet (minimal signature capture)

private struct SignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) var palette
    let agreement: AgreementsAPI.Agreement
    @ObservedObject var store: AgreementsStore

    @State private var strokes: [[CGPoint]] = [[]]
    @State private var signerName: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(AgreementKind(agreement.agreementType).label)
                    .font(EType.h2)
                if let num = agreement.agreementNumber {
                    Text(num)
                        .font(EType.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                TextField("Printed name", text: $signerName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Text("SIGN BELOW")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                signaturePad
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.borderFaint, lineWidth: 1)
                            )
                    )

                HStack {
                    Button("Clear") { strokes = [[]] }
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Gradient-Ink signature • SHA-256 server hash")
                        .font(EType.micro)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(Space.s4)
            .navigationTitle("Sign agreement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let b64 = encodeSignatureBase64()
                            await store.sign(
                                agreement: agreement,
                                signatureBase64: b64,
                                role: "DRIVER",
                                signerName: signerName.isEmpty ? nil : signerName
                            )
                            dismiss()
                        }
                    } label: {
                        if store.signingId == agreement.id {
                            ProgressView()
                        } else {
                            Text("Sign").fontWeight(.semibold)
                        }
                    }
                    .disabled(!hasStroke || store.signingId == agreement.id)
                }
            }
        }
    }

    private var hasStroke: Bool {
        strokes.contains { $0.count > 2 }
    }

    private var signaturePad: some View {
        Canvas { ctx, size in
            // Gradient ink — strokes render in the EusoTrip brand gradient
            // (#1473FF → #7B3AFF → #BE01FF) in real time as the driver draws,
            // matching GradientSignaturePad + the founder signature-ink mandate.
            // Was `.color(.primary)` (solid system ink) despite this screen's
            // "Gradient-Ink signature" label — the label now tells the truth.
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Brand.blue, Color(hex: 0x7B3AFF), Brand.magenta]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            )
            for stroke in strokes where stroke.count > 1 {
                var path = Path()
                path.move(to: stroke[0])
                for pt in stroke.dropFirst() {
                    path.addLine(to: pt)
                }
                ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    strokes[strokes.count - 1].append(value.location)
                }
                .onEnded { _ in
                    strokes.append([])
                }
        )
    }

    /// Render the signature strokes to a PNG and base64-encode so
    /// the server can SHA-256 the bytes and stash them as the
    /// agreement's signature hash.
    private func encodeSignatureBase64() -> String {
        let size = CGSize(width: 600, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Gradient ink — clip to the stroked path and fill with the
            // EusoTrip brand gradient so the saved (and server-SHA-256'd)
            // signature image matches the on-screen gradient (was solid black).
            let cg = ctx.cgContext
            let cgPath = CGMutablePath()
            for stroke in strokes where stroke.count > 1 {
                cgPath.move(to: stroke[0])
                for pt in stroke.dropFirst() {
                    cgPath.addLine(to: pt)
                }
            }
            cg.addPath(cgPath)
            cg.setLineWidth(3)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.replacePathWithStrokedPath()
            cg.clip()
            if let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 20/255,  green: 115/255, blue: 255/255, alpha: 1).cgColor,
                    UIColor(red: 123/255, green: 58/255,  blue: 255/255, alpha: 1).cgColor,
                    UIColor(red: 190/255, green: 1/255,   blue: 255/255, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
        }
        return image.pngData()?.base64EncodedString() ?? ""
    }
}

// MARK: - Screen wrapper

struct MeAgreementsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeAgreements()
        } nav: {
            BottomNav(
                leading: driverNavLeading_103(),
                trailing: driverNavTrailing_103(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_103() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_103() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("103 · Agreements · Night") {
    MeAgreementsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("103 · Agreements · Afternoon") {
    MeAgreementsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
