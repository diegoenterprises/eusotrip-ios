//
//  435_PartnerAgreements.swift
//  EusoTrip — Shipper · Partner agreements list (deepens 223).
//
//  Cross-role chain: shipper signing an agreement here → carrier-side
//  catalysts.getMyPendingAgreements surfaces the inbound request →
//  catalysts.signAgreement closes the loop. Agreements router on the
//  server already broadcasts AGREEMENT_SIGNED.
//
//  Reshaped 2026-05-23 from a flat list (with the per-card Sign
//  button only rendered on `pending_shipper` rows) into a 3-column
//  Kanban with drag-to-sign:
//
//    AWAITING ME    — status `pending_shipper` (your move)
//    AWAITING OTHER — every other pending state (counterparty's move)
//    SIGNED         — terminal, signedAt populated
//
//  Drag AWAITING ME → SIGNED fires the real `agreements.sign`
//  mutation. Drag from AWAITING OTHER → anywhere is a no-op (you
//  can't sign on the counterparty's behalf — the server would
//  reject anyway). PDF button preserved on every card regardless
//  of column.
//

import SwiftUI

struct PartnerAgreementsScreen: View {
    let theme: Theme.Palette
    let partnerId: String
    var body: some View {
        Shell(theme: theme) { PartnerAgreementsBody(partnerId: partnerId) } nav: { shipperLifecycleNav() }
    }
}

private struct AgreementRow: Decodable, Identifiable, Hashable {
    let id: String
    let agreementNumber: String
    let kind: String
    let status: String
    let signedAt: String?
    let pdfUrl: String?
}

private struct AgreementKanbanColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

private let agreementKanbanColumns: [AgreementKanbanColumn] = [
    .init(id: "awaitingMe",    label: "AWAITING ME",    icon: "pencil.tip.crop.circle"),
    .init(id: "awaitingOther", label: "AWAITING OTHER", icon: "hourglass"),
    .init(id: "signed",        label: "SIGNED",         icon: "checkmark.seal.fill"),
]

private struct PartnerAgreementsBody: View {
    @Environment(\.palette) private var palette
    let partnerId: String
    @State private var rows: [AgreementRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var signing: String? = nil
    @State private var actionError: String? = nil
    @State private var lastSigned: String? = nil
    @State private var selected: String = "awaitingMe"
    @State private var dragHoverColumn: String? = nil
    @State private var presentedPDF: EusoPDFPresentation? = nil
    /// The agreement awaiting a drawn signature — drives the gradient
    /// signature pad. Both the drag-to-SIGNED drop and the card "Sign"
    /// button open the pad; `agreements.sign` fires only after the user
    /// draws. (The server REQUIRES a Gradient-Ink `signatureData` +
    /// `signatureRole`, so the prior signature-less drag could never sign.)
    @State private var signPadFor: AgreementRow? = nil

    private func columnId(for status: String) -> String {
        let s = status.lowercased()
        if s == "signed" { return "signed" }
        if s == "pending_shipper" { return "awaitingMe" }
        return "awaitingOther"
    }

    private var byColumn: [String: [AgreementRow]] {
        Dictionary(grouping: rows) { columnId(for: $0.status) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastSigned {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                scrubber
                if loading && rows.isEmpty {
                    LifecycleCard {
                        Text("Loading agreements…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if rows.isEmpty {
                    EusoEmptyState(
                        systemImage: "doc.append",
                        title: "No agreements",
                        subtitle: "Author one from the agreements wizard at /agreements."
                    )
                } else {
                    columnPager
                        .frame(minHeight: 480)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $presentedPDF) { p in
            EusoPDFViewer(title: p.title, subtitle: p.subtitle, source: .url(p.url))
        }
        .sheet(item: $signPadFor) { row in
            // Bespoke gradient signature pad (EusoSignaturePadSheet) — the same
            // on-screen gradient-ink capture the agreements PDF viewer uses.
            // Returns the drawn signature as a PNG; we base64 it for
            // agreements.sign (the server requires a real signatureData).
            EusoSignaturePadSheet { image in
                signPadFor = nil
                let b64 = image.pngData()?.base64EncodedString() ?? ""
                Task { await sign(row, signatureData: b64) }
            }
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.append")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PARTNER AGREEMENTS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Agreements")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a card from AWAITING ME onto SIGNED to e-sign. Counterparty sees AGREEMENT_SIGNED in realtime.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(agreementKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(agreementKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: AgreementKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if col.id == "signed" {
                        Text("DROP AWAITING ME TO E-SIGN")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if cards.isEmpty {
                    EusoEmptyState(
                        systemImage: col.icon,
                        title: emptyTitle(col),
                        subtitle: emptySubtitle(col)
                    )
                } else {
                    ForEach(cards) { a in
                        cardView(a, columnId: col.id)
                            .draggable(a.id) {
                                cardView(a, columnId: col.id)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first else { return false }
            guard let src = rows.first(where: { $0.id == droppedId }) else { return false }
            // Only one transition is user-driven: pending_shipper →
            // signed. The server enforces the same constraint
            // (agreements.sign rejects non-pending_shipper rows), so
            // the client-side guard mirrors that and spares the
            // round-trip on stray drops.
            guard col.id == "signed", src.status.lowercased() == "pending_shipper" else {
                return false
            }
            signPadFor = src
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ a: AgreementRow, columnId: String) -> some View {
        let isSigning = signing == a.id
        return LifecycleCard(accentGradient: columnId == "signed") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LifecycleSection(label: a.agreementNumber.uppercased(), icon: "doc.text")
                    Spacer(minLength: 0)
                    Text(columnLabel(columnId))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(columnTint(columnId).opacity(0.18)))
                        .foregroundStyle(columnTint(columnId))
                }
                LifecycleRow(label: "Kind",     value: a.kind.uppercased())
                LifecycleRow(label: "Status",   value: a.status.uppercased())
                LifecycleRow(label: "Signed",   value: humanISO(a.signedAt))
                HStack(spacing: 8) {
                    if let pdf = a.pdfUrl, !pdf.isEmpty {
                        Button {
                            if let u = URL(string: pdf) {
                                presentedPDF = EusoPDFPresentation(
                                    url: u,
                                    title: "Partner agreement",
                                    subtitle: a.agreementNumber
                                )
                            }
                        } label: {
                            Text("PDF")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(palette.tintNeutral).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    if columnId == "awaitingMe" {
                        Button { signPadFor = a } label: {
                            HStack(spacing: 6) {
                                if isSigning { ProgressView().tint(.white) }
                                Text(isSigning ? "Signing…" : "Sign")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(signing != nil)
                    }
                }
            }
        }
    }

    private func columnLabel(_ id: String) -> String {
        switch id {
        case "awaitingMe":    return "YOUR MOVE"
        case "awaitingOther": return "AWAITING OTHER"
        case "signed":        return "SIGNED"
        default:              return id.uppercased()
        }
    }

    private func columnTint(_ id: String) -> Color {
        switch id {
        case "awaitingMe":    return .orange
        case "awaitingOther": return .blue
        case "signed":        return Brand.success
        default:              return palette.textSecondary
        }
    }

    private func emptyTitle(_ col: AgreementKanbanColumn) -> String {
        switch col.id {
        case "awaitingMe":    return "Nothing awaiting you"
        case "awaitingOther": return "Counterparty in the clear"
        case "signed":        return "No signed agreements"
        default:              return "Empty"
        }
    }

    private func emptySubtitle(_ col: AgreementKanbanColumn) -> String {
        switch col.id {
        case "awaitingMe":    return "Agreements where it's your turn to e-sign will land here."
        case "awaitingOther": return "Agreements waiting on the counterparty land here."
        case "signed":        return "Drag a card from AWAITING ME here or tap Sign."
        default:              return ""
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let partnerId: String }
        do {
            let r: [AgreementRow] = try await EusoTripAPI.shared.query(
                "agreements.listForPartner",
                input: In(partnerId: partnerId)
            )
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func sign(_ a: AgreementRow, signatureData: String) async {
        await MainActor.run { signing = a.id; actionError = nil }
        // agreements.sign REQUIRES a Gradient-Ink signatureData (base64 PNG)
        // + signatureRole + a NUMERIC agreementId. The prior call sent only a
        // String agreementId and no signature, so it failed Zod validation
        // every time — drag-to-sign never actually signed. Send the drawn
        // signature via the typed accessor.
        guard let idNum = Int(a.id) else {
            await MainActor.run { actionError = "Couldn't resolve agreement id."; signing = nil }
            return
        }
        do {
            _ = try await EusoTripAPI.shared.agreements.sign(
                agreementId: idNum,
                signatureBase64: signatureData,
                signatureRole: "shipper",
                signerName: nil
            )
            await MainActor.run {
                lastSigned = "Signed \(a.agreementNumber) · counterparty sees AGREEMENT_SIGNED"
            }
            await load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) { selected = "signed" }
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { signing = nil }
    }
}

#Preview("435 · Agreements · Night") { PartnerAgreementsScreen(theme: Theme.dark, partnerId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("435 · Agreements · Afternoon") { PartnerAgreementsScreen(theme: Theme.light, partnerId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
