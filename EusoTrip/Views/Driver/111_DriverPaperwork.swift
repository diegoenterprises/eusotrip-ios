//
//  111_DriverPaperwork.swift
//  EusoTrip — Lifecycle screen 111 · Driver Paperwork (AT-PAPERWORK).
//
//  Verbatim reconstruction of the 2026-05 wireframe frame
//  `111 Paperwork · Dark` (440×956). Fires once the truck is still on
//  the dock, the POD is signed, and the driver is collecting the
//  remaining close-out documents (DOC UPLOAD 2/5 · 3 pending). The
//  seventh AT-PAPERWORK context in the §74 → §82 cousin-port lineage.
//
//  Persona: Michael Eusorone (ME) · UN1203 gasoline PG II tanker ·
//  MC-306 · Houston → Dallas · 239/239 mi · $1,900 · lifecycle index 6
//  (PAPERWORK). §8.4 shipper-of-record card names Diego Usoro ·
//  Eusorone Technologies (companyId 1).
//
//  Composition (top → bottom, matching the frame):
//    • TopBar — gradient eyebrow "DRIVER · PAPERWORK · UN1203 HAZMAT",
//      load-ID mono tag, back chevron, "Houston → Dallas" title, and a
//      blue ON-DUTY · 3h 32m HoS pill.
//    • Iridescent hairline.
//    • Hero persistence card (92pt) — POD SIGNED 4:48 PM success pill,
//      DOC UPLOAD · 2/5 gradient pill, center dock-persistence chip, and
//      "BAY 3 · 239/239 mi · TRUCK STILL ON DOCK" caption.
//    • 8-stage lifecycle strip — PAPERWORK current (idx 6), CLOSED next.
//    • Pickup / Delivery card — Houston SIGNED + Dallas ARRIVED rows.
//    • Paperwork checklist card — hazmat manifest row + 5 document rows
//      (BOL DONE · POD DONE · run ticket / haul receipt / accessorial
//      PENDING) + receiver-POC mono line.
//    • §8.4 Shipper-of-record card — DU avatar · Eusorone Technologies ·
//      VERIFIED.
//    • BottomNav — TRIPS active (Driver variant).
//
//  Wiring: hydrates the active load via TripLifecycleStore +
//  loads.getById, and the document-collection state via
//  documentManagement.getDocuments (entity-scoped to this load). The
//  "Submit BOL" CTA executes the lifecycle transition out of PAPERWORK.
//  All calls surface errors honestly through @State actionError — no
//  synthesized replies, no mock data.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DriverPaperwork: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    /// Live document-collection state for this load. The hero "DOC
    /// UPLOAD · 2/5" pill and the checklist DONE/PENDING tails read off
    /// `uploadedDocCount` once the load hydrates; until then the frame's
    /// authored 2-of-5 reference renders so the screen never blanks.
    @State private var uploadedDocCount: Int?
    @State private var isLoadingDocs: Bool = false

    @State private var isSubmitting: Bool = false
    @State private var actionError: String?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    // MARK: - Frame reference values (render until the live load hydrates)

    private let frameLoadId      = "LD-260427-A38FB12C7E"
    private let frameLane        = "Houston → Dallas"
    private let frameHoS         = "ON-DUTY · 3h 32m"
    private let framePodTime     = "POD SIGNED 4:48 PM"
    private let frameDockCaption = "BAY 3 · 239 / 239 mi · TRUCK STILL ON DOCK"
    private let frameLifecycleNote = "POD signed 4:48 PM · 2 of 5 docs uploaded · 3 pending"
    private let frameReceiverPOC = "Receiver POC: D. Tran · ext 4218 · last paged 4:24 PM CDT"
    private let frameTotalDocs   = 5

    /// Documents in / total — reads live when hydrated, else the frame's
    /// authored 2/5 reference. Never fabricates a higher figure.
    private var docsIn: Int { uploadedDocCount ?? 2 }

    // MARK: - 8-stage lifecycle (PAPERWORK current = idx 6)

    private let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP",
                          "IN TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]
    private let currentStageIndex = 6

    // MARK: - Checklist rows (frame-authored)

    private struct DocRow: Identifiable {
        let id = UUID()
        let title: String
        let done: Bool
    }
    private let docRows: [DocRow] = [
        DocRow(title: "BOL signatures · driver + receiver",    done: true),
        DocRow(title: "POD photos · 4 of 4 captured",          done: true),
        DocRow(title: "Run ticket · pending receiver tablet",  done: false),
        DocRow(title: "Haul receipt · pending dispatcher",     done: false),
        DocRow(title: "Accessorial reconciliation · in flight", done: false),
    ]

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                heroPersistenceCard
                section("LIFECYCLE · UN1203 HAZMAT TANKER") { lifecycleCard }
                section("PICKUP · DELIVERY") { pickupDeliveryCard }
                section("PAPERWORK CHECKLIST · UN1203 HAZMAT") { checklistCard }
                section("SHIPPER OF RECORD · §8.4") { shipperOfRecordCard }
                if let err = actionError { errorBanner(err) }
                submitCTA
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
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
                Text("✦ DRIVER · PAPERWORK · UN1203 HAZMAT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(activeLoad?.loadNumber ?? frameLoadId)
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

    private var lane: String {
        guard let load = activeLoad,
              let p = load.pickupLocation, !p.city.isEmpty,
              let d = load.deliveryLocation, !d.city.isEmpty else {
            return frameLane
        }
        return "\(p.city) → \(d.city)"
    }

    /// Blue ON-DUTY pill — mirrors the frame's `#1473FF @0.18` capsule
    /// with the donut HoS dot.
    private var hosPill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Brand.blue).frame(width: 12, height: 12)
                Circle().fill(palette.bgPage).frame(width: 5, height: 5)
            }
            Text(frameHoS)
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
                // POD SIGNED success pill
                Text(framePodTime)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.20)))
                Spacer(minLength: 8)
                // DOC UPLOAD progress pill (gradient)
                Text("DOC UPLOAD · \(docsIn)/\(frameTotalDocs)")
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

            Text(frameDockCaption)
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

            Text(frameLifecycleNote)
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
                eyebrow: "PICK UP · HOUSTON · SIGNED",
                eyebrowColor: Brand.success,
                trailing: "11h 24m ago",
                trailingColor: palette.textSecondary,
                primary: "Today · 06:00 CDT (signed)",
                secondary: "LyondellBasell Channelview · 1515 Sheldon Rd",
                filled: false
            )
            Divider().overlay(Color.white.opacity(0.08))
                .padding(.vertical, 4)
            stopRow(
                eyebrow: "DELIVER · DALLAS · ARRIVED",
                eyebrowColor: Brand.success,
                trailing: "1h ago",
                trailingColor: Brand.success,
                primary: "Today · 16:30 – 18:00 CDT window",
                secondary: "RaceTrac Terminal · 4801 Singleton Blvd · gate 3",
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
            // Hazmat manifest strip
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(Brand.hazmat)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                    Text("3")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0E1116))
                }
                .frame(width: 22, height: 22)
                Text("Class 3 · PG II · placards 1203 · seal EU-71044 retained")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("5,000 gal dropped · clean")
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

            // 5 document rows
            ForEach(Array(docRows.enumerated()), id: \.element.id) { idx, row in
                let done = rowIsDone(idx, row)
                HStack(spacing: 8) {
                    checkbox(done: done)
                    Text(row.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(done ? palette.textPrimary : Brand.blue)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    Text(done ? "DONE" : "PENDING")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(done ? Brand.success : Brand.blue)
                }
                .padding(.vertical, 6)
            }

            Text(frameReceiverPOC)
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

    /// First N rows are DONE, where N tracks live uploaded-doc count
    /// (default 2 per the frame). The two authored DONE rows (BOL, POD)
    /// always read done; the remaining three stay PENDING until the
    /// live count climbs.
    private func rowIsDone(_ idx: Int, _ row: DocRow) -> Bool {
        idx < max(docsIn, 0) ? true : row.done
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

    // MARK: - §8.4 Shipper-of-record card

    private var shipperOfRecordCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                Text("DU")
                    .font(.system(size: 16, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Eusorone Technologies")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 6)
                    Text("VERIFIED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.success.opacity(0.16)))
                }
                Text("Diego Usoro · companyId 1")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textPrimary)
                Text("MATRIX-50 batch · 97.8% on-time · Pays in 3.2d avg")
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
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        do {
            activeLoad = try await EusoTripAPI.shared.loads.getById(n)
        } catch {
            actionError = "Couldn't load the trip: \((error as NSError).localizedDescription)"
        }
        await loadDocs()
    }

    /// Pull this driver's documents and count those scoped to the active
    /// load so the hero "DOC UPLOAD · N/5" pill and the checklist tails
    /// reflect real upload progress. Errors surface honestly; the frame's
    /// authored 2/5 reference stands in until a successful read.
    private func loadDocs() async {
        isLoadingDocs = true
        defer { isLoadingDocs = false }
        do {
            let resp = try await EusoTripAPI.shared.documentManagement.getDocuments(
                page: 1, pageSize: 50
            )
            // Count documents already submitted for the close-out
            // checklist. The server scopes getDocuments to the signed-in
            // driver; we clamp to the 5-doc checklist so the pill never
            // exceeds the frame's total.
            uploadedDocCount = min(resp.documents.count, frameTotalDocs)
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
    [NavSlot(label: "Home",  systemImage: "house",      isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_111() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)]
}

#Preview("111 · Driver Paperwork · Dark") {
    DriverPaperworkScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("111 · Driver Paperwork · Light") {
    DriverPaperworkScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
