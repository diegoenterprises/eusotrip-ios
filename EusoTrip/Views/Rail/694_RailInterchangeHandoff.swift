//
//  694_RailInterchangeHandoff.swift
//  EusoTrip — Rail Engineer · EDI 322 Interchange Handoff (carrier custody board).
//
//  Visual identity: a TWO-TOWER BATON RELAY — a delivering-road disc and a
//  receiving-road disc joined by a rail line, a gateway handoff diamond, and a
//  live baton that runs delivering→receiving while a car's custody transfers.
//  A 322 status pill sits under the relay; below it a per-car EDI 322 custody
//  board where each car can be ACCEPTED (irreversible custody-transfer, confirm-
//  gated) or FLAGGED with an exception. NOT a detail card.
//
//  Live wiring: railShipments.getInterchangeHandoff({shipmentId, interchangePointId?})
//  → the counts strip + per-car board; per-car / bulk "Accept custody" →
//  railShipments.acceptInterchange({confirm:true, handoffIds:[Int]}) (human-gated);
//  per-car "Flag exception" → railShipments.flagException({handoffId, reason}).
//  Honest: no shipment id → an enter-id prompt; empty board → an honest empty
//  state; the 322 pill reads "322 pending" when there is no offer, never a
//  fabricated ACK.
//

import SwiftUI

struct RailInterchangeHandoffScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailInterchangeHandoffBody() } nav: {
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

// MARK: - Decodable model (matches railShipments.getInterchangeHandoff)

private struct HandoffCar694: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let interchangePointId: Int?
    let deliveringRoad: String?
    let receivingRoad: String?
    let status: String?
    let exceptionReason: String?
    let acceptedAt: String?
}

private struct HandoffBoard694: Decodable {
    let shipmentId: Int
    let cars: [HandoffCar694]
    let counts: [String: Int]
}

private struct AcceptResult694: Decodable {
    let success: Bool?
    let accepted: Int
    let alreadyAccepted: Int?
    let shipmentIds: [Int]?
}

private struct FlagResult694: Decodable {
    let success: Bool?
    let handoffId: Int?
    let status: String?
}

private enum ExceptionReason694: String, CaseIterable, Identifiable {
    case sealBroken  = "Seal broken"
    case carDamage   = "Car damage"
    case badOrder    = "Bad order (BO)"
    case docMismatch = "Waybill / doc mismatch"
    case placard     = "Hazmat placard issue"
    case notManifest = "Wrong car / not on manifest"
    case other       = "Other"
    var id: String { rawValue }
}

// MARK: - Body

private struct RailInterchangeHandoffBody: View {
    @Environment(\.palette) private var palette

    @State private var shipmentIdText: String = ""
    @State private var board: HandoffBoard694? = nil
    @State private var loading = false
    @State private var loadError: String? = nil

    // Accept (custody transfer) flow — human-gated, confirm:true.
    @State private var acceptCar: HandoffCar694? = nil
    @State private var showBulkConfirm = false
    @State private var accepting = false

    // Flag-exception flow.
    @State private var flagCar: HandoffCar694? = nil
    @State private var flagReason: ExceptionReason694 = .sealBroken
    @State private var flagDetail: String = ""
    @State private var flagging = false

    @State private var toast: String? = nil

    private var cars: [HandoffCar694] { board?.cars ?? [] }
    private var counts: [String: Int] { board?.counts ?? [:] }
    private var offeredCars: [HandoffCar694] { cars.filter { $0.status == "offered" } }
    private var deliveringRoad: String { cars.compactMap { $0.deliveringRoad }.first ?? "—" }
    private var receivingRoad: String { cars.compactMap { $0.receivingRoad }.first ?? "—" }
    private var allAccepted: Bool { !cars.isEmpty && cars.allSatisfy { $0.status == "accepted" } }

    /// Aggregate EDI 322 pill — degraded reads "322 pending", never a fake ACK.
    private var pill322: (String, Color) {
        if cars.isEmpty { return ("322 pending", palette.textTertiary) }
        let exc = counts["exception"] ?? 0
        let held = counts["held"] ?? 0
        let offered = counts["offered"] ?? 0
        let accepted = counts["accepted"] ?? 0
        if exc > 0 { return ("322 exception", Brand.danger) }
        if offered > 0 || held > 0 { return ("322 offered", Brand.warning) }
        if accepted > 0 { return ("322 accepted", Brand.success) }
        return ("322 pending", palette.textTertiary)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                shipmentField
                if loading {
                    LifecycleCard { Text("Loading interchange board…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if board == nil {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enter a shipment ID to load its EDI 322 interchange board.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            Text("Every car's road-to-road custody state — offered · accepted · held · exception.")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                } else {
                    BatonRelayHero694(
                        deliveringRoad: deliveringRoad,
                        receivingRoad: receivingRoad,
                        pillText: pill322.0,
                        pillColor: pill322.1,
                        allAccepted: allAccepted,
                        palette: palette
                    )
                    countsStrip
                    if cars.isEmpty {
                        LifecycleCard { Text("No cars on this interchange board yet.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else {
                        carList
                        if !offeredCars.isEmpty {
                            CTAButton(title: "Accept all \(offeredCars.count) offered", action: { showBulkConfirm = true }, leadingIcon: "checkmark.seal.fill")
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $acceptCar) { car in acceptSheet(car) }
        .sheet(item: $flagCar) { car in flagSheet(car) }
        .sheet(isPresented: $showBulkConfirm) { bulkAcceptSheet }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · INTERCHANGE HANDOFF").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Interchange handoff")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Shipment id field

    private var shipmentField: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "number").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textTertiary)
            TextField("Shipment ID", text: $shipmentIdText)
                .keyboardType(.numberPad)
                .font(.system(size: 15, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.go)
                .onSubmit { Task { await load() } }
            Button { Task { await load() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 12, weight: .heavy))
                    Text("Load board").font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Counts strip

    private var countsStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "OFFERED",   value: "\(counts["offered"] ?? 0)",   accent: Brand.warning)
            MetricTile(label: "ACCEPTED",  value: "\(counts["accepted"] ?? 0)",  accent: Brand.success)
            MetricTile(label: "HELD",      value: "\(counts["held"] ?? 0)",      accent: Brand.info)
            MetricTile(label: "EXCEPTION", value: "\(counts["exception"] ?? 0)", accent: Brand.danger)
        }
    }

    // MARK: Car list

    private var carList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EDI 322 CARS · road-to-road custody")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(cars) { c in carRow(c) }
            }
        }
    }

    private func carRow(_ c: HandoffCar694) -> some View {
        let color = statusColor(c.status)
        let accepted = c.status == "accepted"
        let exception = c.status == "exception"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.railcarNumber ?? "—")
                        .font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                    HStack(spacing: 5) {
                        Text(c.deliveringRoad ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary)
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        Text(c.receivingRoad ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary)
                        Text("· pt \(c.interchangePointId ?? 0)").font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                Text((c.status ?? "unknown").uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.14)))
            }
            if exception, let reason = c.exceptionReason {
                Text("Exception · \(reason)").font(EType.caption).foregroundStyle(Brand.danger).lineLimit(2)
            }
            if accepted, let at = c.acceptedAt {
                Text("Custody accepted · \(shortDate(at))").font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            if !accepted {
                HStack(spacing: Space.s2) {
                    Button {
                        flagCar = c
                        flagReason = .sealBroken
                        flagDetail = ""
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "flag.fill").font(.system(size: 10, weight: .heavy))
                            Text("Flag exception").font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Brand.danger.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        acceptCar = c
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 10, weight: .heavy))
                            Text("Accept custody").font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Brand.success.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Space.s3)
        .background(exception ? Brand.danger.opacity(0.06) : (accepted ? Brand.success.opacity(0.05) : palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(exception ? Brand.danger.opacity(0.30) : (accepted ? Brand.success.opacity(0.28) : palette.borderFaint))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func statusColor(_ s: String?) -> Color {
        switch s {
        case "accepted":  return Brand.success
        case "exception": return Brand.danger
        case "held":      return Brand.info
        case "offered":   return Brand.warning
        default:          return palette.textTertiary
        }
    }

    private func shortDate(_ iso: String) -> String {
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return out.string(from: d) }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: iso) { return out.string(from: d) }
        return String(iso.prefix(16))
    }

    // MARK: Accept sheets (irreversible custody transfer — human-gated)

    private func acceptSheet(_ car: HandoffCar694) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ACCEPT CUSTODY · EDI 322").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Accept \(car.railcarNumber ?? "car")")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("This is an irreversible custody transfer. \(car.deliveringRoad ?? "delivering road") hands \(car.railcarNumber ?? "the car") to \(car.receivingRoad ?? "your road") at interchange point \(car.interchangePointId ?? 0). The EDI 322 acknowledgement is logged to the immutable audit trail.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            confirmButton(title: "Confirm custody transfer", busy: accepting) {
                Task { await acceptCars([car.id]) }
            }
            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private var bulkAcceptSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ACCEPT CUSTODY · EDI 322").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Accept \(offeredCars.count) offered car\(offeredCars.count == 1 ? "" : "s")")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("Irreversible custody transfer for every offered car on this board. Each acknowledgement is logged to the immutable audit trail.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(offeredCars) { c in
                    HStack(spacing: 8) {
                        Image(systemName: "train.side.front.car").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.warning)
                        Text(c.railcarNumber ?? "—").font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(c.deliveringRoad ?? "—") → \(c.receivingRoad ?? "—")").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }

            confirmButton(title: "Confirm \(offeredCars.count)-car transfer", busy: accepting) {
                Task { await acceptCars(offeredCars.map { $0.id }) }
            }
            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: Flag-exception sheet

    private func flagSheet(_ car: HandoffCar694) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("FLAG EXCEPTION · EDI 322").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Hold \(car.railcarNumber ?? "car")")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("Refuse custody with a reason. The car drops to EXCEPTION on the board until the delivering road resolves it.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("REASON").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                ForEach(ExceptionReason694.allCases) { reason in
                    Button {
                        flagReason = reason
                    } label: {
                        HStack {
                            Image(systemName: flagReason == reason ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(flagReason == reason ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                            Text(reason.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                            Spacer()
                        }
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(flagReason == reason ? palette.borderFaint : Color.clear))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DETAIL (optional)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                TextField("Add specifics…", text: $flagDetail)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            confirmButton(title: "Flag exception", busy: flagging) {
                Task { await submitException(car) }
            }
            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func confirmButton(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: Toast

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

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: Data

    private func load() async {
        let trimmed = shipmentIdText.trimmingCharacters(in: .whitespaces)
        guard let sid = Int(trimmed) else {
            board = nil; loadError = nil; loading = false
            return
        }
        loading = true; loadError = nil
        struct In: Encodable { let shipmentId: Int }
        do {
            self.board = try await EusoTripAPI.shared.query("railShipments.getInterchangeHandoff", input: In(shipmentId: sid))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func acceptCars(_ ids: [Int]) async {
        guard !ids.isEmpty else { return }
        struct In: Encodable { let confirm: Bool; let handoffIds: [Int] }
        accepting = true
        do {
            let res: AcceptResult694 = try await EusoTripAPI.shared.mutation(
                "railShipments.acceptInterchange",
                input: In(confirm: true, handoffIds: ids)
            )
            acceptCar = nil
            showBulkConfirm = false
            showToast("Accepted \(res.accepted) car\(res.accepted == 1 ? "" : "s") into custody")
            await load()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Accept failed")
        }
        accepting = false
    }

    private func submitException(_ car: HandoffCar694) async {
        let base = flagReason.rawValue
        let detail = flagDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = String((detail.isEmpty ? base : "\(base): \(detail)").prefix(255))
        struct In: Encodable { let handoffId: Int; let reason: String }
        flagging = true
        do {
            let _: FlagResult694 = try await EusoTripAPI.shared.mutation(
                "railShipments.flagException",
                input: In(handoffId: car.id, reason: reason)
            )
            flagCar = nil
            showToast("Exception flagged on \(car.railcarNumber ?? "car")")
            await load()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Flag failed")
        }
        flagging = false
    }
}

// MARK: - Two-tower baton relay hero
//
// The delivering-road disc and receiving-road disc are joined by a rail line
// with a center gateway diamond; a live baton runs delivering→receiving on a
// continuous loop to signal the custody hand-off in motion. The 322 pill under
// the relay carries the aggregate EDI 322 state (never a fabricated ACK). Once
// every car is accepted the baton rests at the receiving disc. Reduce Motion
// parks the baton at the diamond (or the receiving disc when fully accepted)
// with no travel loop.
private struct BatonRelayHero694: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let deliveringRoad: String
    let receivingRoad: String
    let pillText: String
    let pillColor: Color
    let allAccepted: Bool
    let palette: Theme.Palette

    @State private var travel: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(spacing: Space.s3) {
                HStack {
                    Text("EDI 322 · ROAD-TO-ROAD CUSTODY")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    Spacer()
                }
                HStack(spacing: 0) {
                    roadDisc(deliveringRoad, caption: "DELIVERING")
                    relayLine
                    roadDisc(receivingRoad, caption: "RECEIVING")
                }
                Text(pillText.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
            }
            .padding(Space.s4)
        }
        .frame(height: 182)
        .onAppear { animate() }
        .onChange(of: allAccepted) { _, _ in animate() }
    }

    private func roadDisc(_ code: String, caption: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(palette.bgSheet)
                Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2)
                Text(code)
                    .font(.system(size: 14, weight: .heavy)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                    .minimumScaleFactor(0.5).lineLimit(1).padding(6)
            }
            .frame(width: 62, height: 62)
            Text(caption)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var relayLine: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Rectangle().fill(palette.borderFaint).frame(height: 2)
                    .padding(.horizontal, 4)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.bgSheet)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(pillColor, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45))
                Circle().fill(pillColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: pillColor.opacity(0.6), radius: 4)
                    .offset(x: -w / 2 + 5 + (w - 10) * travel)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 62)
    }

    private func animate() {
        if reduceMotion {
            travel = allAccepted ? 1 : 0.5
            return
        }
        if allAccepted {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { travel = 1 }
            return
        }
        travel = 0
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
            travel = 1
        }
    }
}

#Preview("694 · Rail Interchange Handoff · Night") { RailInterchangeHandoffScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("694 · Rail Interchange Handoff · Light") { RailInterchangeHandoffScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
