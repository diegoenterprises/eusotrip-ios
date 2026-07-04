//
//  522_DispatcherBhBolPreSignCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 522 · BOL pre-sign (signature capture surface).
//
//  Wireframe slot: 04 Dispatcher / 522 Dispatcher BH Bol Pre Sign Card (Light+Dark SVG,
//  golden re-port 2026-06-25 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): signature-capture hero (BOL document header + status chip
//  over a dashed signature pad) → SIGNERS / EXPIRES / SEAL KPI triple → signature-request
//  detail card → reefer temp-trace strip → CTA pair (Send for signature / Sign on glass).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                            — load + parties + lane + equipment.
//    READ  documentManagement.getDocuments          — the delivery BOL on this load.
//    WRITE documentManagement.generateBol           — drafts the BOL from the load record
//                                                     when none is attached (empty state).
//    WRITE documentManagement.requestESignature     — sends / re-sends the e-sign request.
//    READ  documentManagement.getSignatureStatus    — signer progress + expiry.
//  Honest gaps (no server surface — rendered as data-absence states, never faked):
//    · on-glass capture from this board (signer ids aren't exposed to the requester,
//      so the receiver signs from their own link / the driver's cab — surfaced honestly)
//    · reefer temp-trace attach-to-packet binding (strip shows the unlinked state)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHBolPreSign522Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH522Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH522Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var bolDoc: BH522Doc?
    @State private var docsLoaded = false
    @State private var loadFailed = false
    @State private var signatureStatus: BH522SignatureStatus?
    @State private var sessionRequestId: String?
    @State private var draftInFlight = false
    @State private var sendInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showSignerSheet = false
    @State private var showGlassSheet = false
    @State private var signerName = ""
    @State private var signerEmail = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("SIGNATURE REQUEST")
                requestDetail
                tempTraceStrip
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the document vault for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showSignerSheet) { signerSheet }
        .sheet(isPresented: $showGlassSheet) { BH522GlassSheet() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · BOL PRE-SIGN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Pre-sign").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — BOL document + signature pad

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BILL OF LADING")
                        .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(bolHeaderLine)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH522Chip(text: bolStateChip.0, tint: bolStateChip.1)
            }
            HStack(spacing: 6) {
                Text(shipperLabel).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                Text(consigneeLabel).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            }
            // Signature pad
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text(padTitle)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Image(systemName: "pencil.tip").font(.system(size: 12)).foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Line().stroke(palette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 1)
                }
                .padding(.top, 26)
                Text(padSubline)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            HStack {
                Text(sealFooter).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(sentFooter).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    // MARK: KPI triple — SIGNERS / EXPIRES / SEAL

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH522Kpi(label: "SIGNERS",
                     value: signersText,
                     sub: signersText == "—" ? "no signature request linked" : "have signed",
                     tint: nil)
            BH522Kpi(label: "EXPIRES",
                     value: expiresText,
                     sub: expiresText == "—" ? "arms when a request sends" : "request lifetime",
                     tint: nil)
            BH522Kpi(label: "SEAL",
                     value: "—",
                     sub: "seal checks not shared to this board",
                     tint: nil)
        }
    }

    // MARK: Request detail

    private var requestDetail: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH522DetailRow(title: "Document",
                               value: bolDoc?.name ?? (docsLoaded ? "no BOL attached" : "—"))
                Divider().overlay(palette.borderFaint)
                BH522DetailRow(title: "Sent to",
                               value: signatureStatus?.signers?.first?.email ?? (signerEmail.isEmpty ? "—" : signerEmail))
                Divider().overlay(palette.borderFaint)
                BH522DetailRow(title: "Method",
                               value: signatureStatus != nil ? "e-signature" : "—")
            }
        }
    }

    // MARK: Temp-trace strip

    private var tempTraceStrip: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reefer temp trace")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("No temperature trace is linked to this document packet for this load.")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH522Chip(text: "NOT LINKED", tint: Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                if bolDoc == nil { Task { await draftBol() } }
                else { showSignerSheet = true }
            } label: {
                HStack(spacing: 6) {
                    if draftInFlight || sendInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: bolDoc == nil ? "doc.badge.plus" : "paperplane.fill").font(.system(size: 13, weight: .bold)) }
                    Text(primaryCtaLabel).font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(draftInFlight || sendInFlight)

            Button { showGlassSheet = true } label: {
                Text("Sign on glass").font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s2)
    }

    private var primaryCtaLabel: String {
        if draftInFlight { return "Drafting…" }
        if sendInFlight { return "Sending…" }
        if bolDoc == nil { return "Generate BOL" }
        return signatureStatus == nil ? "Send for signature" : "Send reminder"
    }

    // MARK: Signer sheet

    private var signerSheet: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Receiver signer").font(EType.h2).foregroundStyle(palette.textPrimary)
                Text("The e-sign request goes to the receiving clerk. Enter who signs for the consignee.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                TextField("Signer name", text: $signerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Signer email", text: $signerEmail)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Button {
                    showSignerSheet = false
                    Task { await sendForSignature() }
                } label: {
                    Text("Send e-sign request").font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(signerName.isEmpty || !signerEmail.contains("@"))
                Spacer()
            }
            .padding(Space.s4)
        }
        .presentationDetents([.medium])
    }

    // MARK: Derived display

    private var bolHeaderLine: String {
        var parts: [String] = []
        if let n = bolDoc?.name { parts.append(n) }
        if let eq = load?.equipmentType { parts.append(bh522Humanize(eq).lowercased()) }
        if let p = load?.palletCount, p > 0 { parts.append("\(p) plt") }
        return parts.isEmpty ? "draft from the load record below" : parts.joined(separator: " · ")
    }

    private var bolStateChip: (String, Color) {
        guard docsLoaded else { return ("—", Brand.neutral) }
        guard let doc = bolDoc else { return ("NO BOL", Brand.warning) }
        switch doc.status?.lowercased() {
        case "active", "pending_review": return ("DRAFT", Brand.warning)
        case "approved": return ("APPROVED", Brand.success)
        case let s?: return (bh522Humanize(s).uppercased(), Brand.neutral)
        default: return ("DRAFT", Brand.warning)
        }
    }

    private var shipperLabel: String {
        load?.shipper?.companyName ?? load?.shipper?.name ?? load?.pickupLocation?.city ?? "Shipper —"
    }

    private var consigneeLabel: String {
        if let c = load?.deliveryLocation?.city {
            if let s = load?.deliveryLocation?.state { return "\(c), \(s)" }
            return c
        }
        return "Consignee —"
    }

    private var padTitle: String {
        signatureStatus == nil ? "NO SIGNATURE REQUEST SENT" : "AWAITING RECEIVER SIGNATURE"
    }

    private var padSubline: String {
        if let s = signatureStatus {
            var parts = [s.id ?? "request live", "e-signature"]
            if let exp = bh522ISODate(s.expiresAt) {
                let days = max(0, Int(exp.timeIntervalSinceNow / 86_400))
                parts.append("expires in \(days) day\(days == 1 ? "" : "s")")
            }
            return parts.joined(separator: " · ")
        }
        return bolDoc == nil
            ? "draft the BOL first — the pad arms once the document exists"
            : "send the request to arm this pad for the receiver"
    }

    private var sealFooter: String { "Seal checks not shared to this board" }

    private var sentFooter: String {
        if let created = bh522ISODate(signatureStatus?.createdAt) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "SENT \(f.string(from: created))"
        }
        return "NOT SENT"
    }

    private var signersText: String {
        guard let p = signatureStatus?.progress else { return "—" }
        return "\(p.signed ?? 0)/\(p.total ?? 0)"
    }

    private var expiresText: String {
        guard let exp = bh522ISODate(signatureStatus?.expiresAt) else { return "—" }
        let days = max(0, Int(exp.timeIntervalSinceNow / 86_400))
        return "\(days)d"
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchBol()
        await fetchSignatureStatus()
    }

    private func fetchBol() async {
        struct In: Encodable { let entityType: String; let entityId: String; let type: String; let page: Int; let pageSize: Int }
        struct Out: Decodable { let documents: [BH522Doc]? }
        let numericId = (load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getDocuments",
                input: In(entityType: "load", entityId: numericId, type: "bol", page: 1, pageSize: 5))
            bolDoc = out.documents?.first
            docsLoaded = true
        } catch { docsLoaded = false }
    }

    private func fetchSignatureStatus() async {
        guard let requestId = sessionRequestId else { return }
        struct In: Encodable { let requestId: String }
        do {
            signatureStatus = try await EusoTripAPI.shared.query("documentManagement.getSignatureStatus", input: In(requestId: requestId))
        } catch { /* keeps the last known request state */ }
    }

    private func draftBol() async {
        guard !draftInFlight else { return }
        draftInFlight = true; actionAck = nil; actionError = nil
        defer { draftInFlight = false }
        guard let l = load else {
            actionError = "The load record hasn't loaded, so a BOL can't be drafted yet — pull to refresh first."
            return
        }
        let shipperName = l.shipper?.companyName ?? l.shipper?.name
        let consigneeCity = l.deliveryLocation?.city
        guard let shipperName, let consigneeCity, let pickup = l.pickupDate else {
            actionError = "This load record is missing shipper, consignee, or pickup details, so a BOL can't be drafted from this board."
            return
        }
        struct Commodity: Encodable {
            let description: String
            let weight: Double
            let pieces: Int
            let packagingType: String
            let hazmat: Bool
            let unNumber: String?
        }
        struct In: Encodable {
            let shipperName: String
            let shipperAddress: String
            let consigneeName: String
            let consigneeAddress: String
            let carrierName: String
            let carrierMc: String?
            let loadNumber: String
            let pickupDate: String
            let deliveryDate: String?
            let commodities: [Commodity]
            let sealNumbers: [String]?
            let trailerNumber: String?
        }
        struct Out: Decodable { let success: Bool?; let bolId: String?; let proNumber: String? }
        let originAddress = [l.pickupLocation?.address, l.pickupLocation?.city, l.pickupLocation?.state]
            .compactMap { $0 }.joined(separator: ", ")
        let destAddress = [l.deliveryLocation?.address, l.deliveryLocation?.city, l.deliveryLocation?.state]
            .compactMap { $0 }.joined(separator: ", ")
        let weight = Double(l.weight ?? "") ?? 0
        let commodity = Commodity(
            description: l.commodityName ?? l.commodity ?? l.cargoType ?? "Freight per load record",
            weight: weight,
            pieces: l.palletCount ?? 1,
            packagingType: "Pallets",
            hazmat: (l.hazmatClass?.isEmpty == false),
            unNumber: l.unNumber)
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "documentManagement.generateBol",
                input: In(shipperName: shipperName,
                          shipperAddress: originAddress.isEmpty ? shipperLabel : originAddress,
                          consigneeName: consigneeCity,
                          consigneeAddress: destAddress.isEmpty ? consigneeCity : destAddress,
                          carrierName: l.catalyst?.companyName ?? l.catalyst?.name ?? "Carrier of record",
                          carrierMc: l.catalyst?.mcNumber,
                          loadNumber: l.loadNumber,
                          pickupDate: pickup,
                          deliveryDate: l.deliveryDate,
                          commodities: [commodity],
                          sealNumbers: nil,
                          trailerNumber: nil))
            if out.success == true {
                actionAck = "Delivery BOL drafted from the load record\(out.proNumber.map { " · PRO \($0)" } ?? "") — it's now in the packet."
                await fetchBol()
            } else {
                actionError = "The BOL didn't draft. Nothing was attached — try again."
            }
        } catch {
            actionError = "The BOL didn't draft. Nothing was attached — check the connection and try again."
        }
    }

    private func sendForSignature() async {
        guard !sendInFlight else { return }
        sendInFlight = true; actionAck = nil; actionError = nil
        defer { sendInFlight = false }
        guard let doc = bolDoc, let docId = doc.id else {
            actionError = "No BOL is attached to this load yet — draft it first, then send for signature."
            return
        }
        struct Signer: Encodable { let name: String; let email: String; let order: Int }
        struct In: Encodable { let documentId: String; let signers: [Signer]; let message: String; let expiresInDays: Int }
        struct Out: Decodable { let success: Bool?; let requestId: String?; let expiresAt: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "documentManagement.requestESignature",
                input: In(documentId: docId,
                          signers: [Signer(name: signerName, email: signerEmail, order: 1)],
                          message: "Please review and sign the delivery Bill of Lading for \(load?.loadNumber ?? "this load").",
                          expiresInDays: 7))
            if out.success == true, let rid = out.requestId {
                sessionRequestId = rid
                actionAck = "E-sign request sent to \(signerEmail) — the pad above tracks their signature."
                await fetchSignatureStatus()
            } else {
                actionError = "The e-sign request didn't send. The BOL stays in the packet — try again."
            }
        } catch {
            actionError = "The e-sign request didn't send. The BOL stays in the packet — check the connection and try again."
        }
    }
}

// MARK: - Sign-on-glass honest sheet

private struct BH522GlassSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Sign on glass").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                LifecycleCard(accentWarning: true) {
                    Text("On-glass capture happens where the receiver is — their signing link, or the driver's cab screen at the dock.")
                        .font(EType.caption).foregroundStyle(palette.textPrimary)
                    Text("This board can send and track the e-sign request, but it can't sign on the receiver's behalf. Send the request and the signed BOL lands here the moment they ink it.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(Space.s4)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Small primitives

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct BH522Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH522Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH522DetailRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local decode + helpers

private struct BH522Doc: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let status: String?
    let url: String?
    let uploadedAt: String?
}

private struct BH522SignatureStatus: Decodable {
    struct Signer: Decodable { let name: String?; let email: String?; let status: String?; let signedAt: String? }
    struct Progress: Decodable { let total: Int?; let signed: Int?; let pending: Int?; let percent: Int? }
    let id: String?
    let documentId: String?
    let documentName: String?
    let status: String?
    let createdAt: String?
    let expiresAt: String?
    let completedAt: String?
    let signers: [Signer]?
    let progress: Progress?
}

private func bh522Humanize(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private func bh522ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("522 Pre-Sign · Dark") {
    DispatcherBHBolPreSign522Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("522 Pre-Sign · Light") {
    DispatcherBHBolPreSign522Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
