//
//  205_ShipperLoadDetail.swift
//  EusoTrip — Shipper · Load Detail (brick 205).
//
//  Parity-reconciled to `02 Shipper/Code/205_ShipperLoadDetail.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: gradient TopBar (eyebrow with cargo type + load id mono +
//  back chevron + lane title + kebab), IridescentHairline, hero map
//  (gradient bg + grid + I-45 highway curve + origin/truck/destination
//  pins + ETA + distance pills), gradient-rim money card with hazmat
//  pills + amount + rate-line + progress %, carrier card with gradient
//  avatar + ON TIME pill, documents row (BOL · Rate-con · Insurance),
//  bottom CTA pair (View on map · Message ESang).
//
//  Real data preserved: ShipperLoadDetailStore (loads.getById) +
//  ShipperBidsStore (shippers.getBidsForLoad) + ShipperLoadCycleView
//  animated lifecycle + LifecycleProductContext.resolveDirect()
//  product-aware kicker — all unchanged. Schedule/Cargo/Notes detail
//  cards retained as EXTRA-OK richer surface beneath the wireframe
//  recipe.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.2 flagship MATRIX-50 row this brick is calibrated against:
//    LD-260427-A38FB12C7E · Houston TX → Dallas TX · UN1203 · MC-306
//    · 50,000 lb · $1,900 · IN TRANSIT (stage 5/8) · carrier
//    Eusotrans LLC USDOT 3 194 882 / driver Michael Eusorone.
//
//  Web peer: ShipperLoads.tsx row → /shipper/loads/:id.
//  tRPC: loads.getById + shippers.getBidsForLoad
//        (+ telemetry.getLiveLocation for live truck pin — pending).
//  Notification names: eusoShipperLoadOpenMap, eusoShipperLoadMessageEsang,
//                      eusoShipperLoadActionMenu.
//
//  BottomNav: Loads slot stays current — out of scope per parity
//  mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct ShipperLoadDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String
    let previewLoadNumber: String?
    let previewLane: String?

    @StateObject private var detailStore = ShipperLoadDetailStore()
    @StateObject private var bidsStore = ShipperBidsStore()
    /// Confirmation-dialog flag for the kebab (⋯) action menu in the
    /// load-detail top bar. Listening for our own
    /// `.eusoShipperLoadActionMenu` notification flips this true so
    /// the user sees a real action sheet instead of a button that
    /// silently posts a notification no one consumed.
    @State private var showActionMenu: Bool = false

    /// In-app cancel-load sheet (no web fallback). Opened when the
    /// user picks "Cancel load" in the kebab menu. The sheet collects
    /// a cancel reason and submits via `loads.cancelWithReason`.
    @State private var showCancelSheet: Bool = false
    @State private var cancelReason: String = ""
    @State private var cancelInFlight: Bool = false
    @State private var cancelError: String? = nil
    @State private var cancelToast: String? = nil

    /// In-app POD review sheet (no web fallback). Opened from the
    /// kebab menu when the load status is `pod_pending`. The sheet
    /// renders the driver-submitted photo + signature + receiver
    /// + OS&D notes, with Approve / Reject CTAs that fire
    /// `pod.approvePOD` / `pod.rejectPOD` directly. Closes the
    /// shipper-side half of Phase 13 (POD capture & approval) per
    /// docs/parity-2026/EXECUTIVE_VERDICT.md §4.2.
    @State private var showPODReview: Bool = false
    @State private var podPacket: PODAPI.PODPacket? = nil
    @State private var podLoading: Bool = false
    @State private var podDecisionInFlight: Bool = false
    @State private var podRejectReason: String = ""
    @State private var podError: String? = nil
    @State private var podToast: String? = nil

    private var lifecycleVertical: TripVertical {
        TripVertical(role: session.user?.role)
    }

    private var lifecycleProduct: TripProduct {
        let detail = detailStore.state.value ?? nil
        return TripProduct.resolveDirect(
            cargoType:   detail?.cargoType,
            hazmatClass: detail?.hazmatClass,
            vertical:    lifecycleVertical
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroMap
                    lifecycleCard
                    moneyCard
                    carrierCard
                    documentsRow
                    contentExtras
                    ctaRow
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        // Animate when the live detail status changes (e.g., POSTED→
        // BIDDING→IN_TRANSIT) so the lifecycle/progress reflows
        // smoothly. RemoteState itself isn't Equatable across optionals,
        // so observe a derived String key instead.
        .animation(.easeOut(duration: 0.18), value: detailStore.state.value??.status ?? "")
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        // Kebab (⋯) tap fires `eusoShipperLoadActionMenu`; listen
        // here on the same screen so the action sheet actually
        // surfaces instead of the notification dropping into the
        // void.
        .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadActionMenu)) { _ in
            showActionMenu = true
        }
        .confirmationDialog("Load actions",
                            isPresented: $showActionMenu,
                            titleVisibility: .visible) {
            // POD review entry: only render when the load is
            // pod_pending. The driver submitted POD via
            // DeliveryPODCaptureView; the shipper now has an
            // inline iOS surface to approve / reject without web
            // continuation.
            if isLoadPODPending {
                Button("Review POD") {
                    podError = nil
                    podRejectReason = ""
                    showPODReview = true
                    Task { await hydratePODPacket() }
                }
            }
            Button("Cancel load", role: .destructive) {
                // Real in-app cancel — surface the reason sheet,
                // which submits via `loads.cancelWithReason`. No
                // web continuation.
                cancelReason = ""
                cancelError = nil
                showCancelSheet = true
            }
            Button("Edit load") {
                // No backend mutation for in-place edit yet — open
                // the load on the web where the full edit form
                // ships. Honest production fallback per the
                // [feedback_no_dead_buttons] doctrine.
                NotificationCenter.default.post(
                    name: .eusoShipperLoadOpenOnWeb,
                    object: nil,
                    userInfo: ["loadId": loadId]
                )
            }
            Button("Open on web") {
                NotificationCenter.default.post(
                    name: .eusoShipperLoadOpenOnWeb,
                    object: nil,
                    userInfo: ["loadId": loadId]
                )
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showCancelSheet) {
            cancelSheet
                .environment(\.palette, palette)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPODReview) {
            podReviewSheet
                .environment(\.palette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let toast = cancelToast {
                Text(toast)
                    .font(EType.caption)
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Brand.success.opacity(0.95),
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { cancelToast = nil }
                    }
            }
        }
    }

    // MARK: - POD review (shipper-side approve / reject)

    /// True when the live load's status surfaces as `pod_pending` —
    /// the only state where POD approval is meaningful. We tolerate
    /// case + slight wire variations ('pod_pending' / 'PODPending').
    private var isLoadPODPending: Bool {
        let s = (liveDetail?.status ?? "").lowercased()
        return s == "pod_pending" || s == "podpending"
    }

    /// Hydrate the POD packet for the current load. Fired when the
    /// shipper opens the review sheet. Shows skeleton until the
    /// packet lands; renders an empty-state if the server has no
    /// POD on file (which would be a server-side anomaly given the
    /// load is in `pod_pending`).
    private func hydratePODPacket() async {
        guard let n = Int(loadId) ?? liveDetail?.numericId else { return }
        podLoading = true
        defer { podLoading = false }
        do {
            podPacket = try await EusoTripAPI.shared.pod
                .getPODForLoad(loadId: n)
        } catch {
            podError = (error as NSError).localizedDescription
        }
    }

    /// Reusable image renderer for the base64 photo / signature
    /// payloads the driver submitted. Returns nil cleanly when the
    /// payload is missing so the view can render an empty-state row.
    private func decodeBase64Image(_ b64: String?) -> UIImage? {
        guard let b64, let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private var podReviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    podHeaderCard
                    podPhotoCard
                    podSignatureCard
                    podNotesCard
                    if let err = podError {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .padding(.horizontal, Space.s2)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { showPODReview = false }
                        .disabled(podDecisionInFlight)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("REVIEW POD")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(displayLoadId)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                podDecisionBar
                    .background(palette.bgPrimary)
            }
            .overlay(alignment: .bottom) {
                if let toast = podToast {
                    Text(toast)
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Brand.success,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            withAnimation { podToast = nil }
                        }
                }
            }
        }
    }

    private var podHeaderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(podPacket?.receiverName ?? "—")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Submitted \(podPacket?.submittedAt ?? "—")")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            if podLoading {
                ProgressView().padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var podPhotoCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BOL PHOTO")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            if let img = decodeBase64Image(podPacket?.photoBase64) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            } else {
                Text("No photo on file")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var podSignatureCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RECEIVER SIGNATURE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            if let img = decodeBase64Image(podPacket?.signatureBase64) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            } else {
                Text("No signature on file")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var podNotesCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("OS&D NOTES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(podPacket?.notes?.isEmpty == false
                 ? podPacket!.notes!
                 : "No over / short / damage reported")
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if isLoadPODPending {
                Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                Text("REJECTION REASON (required for reject)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. BOL pieces don't match",
                          text: $podRejectReason,
                          axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var podDecisionBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button {
                    Task { await rejectPOD() }
                } label: {
                    HStack(spacing: 6) {
                        if podDecisionInFlight {
                            ProgressView().tint(palette.textOnGradient)
                        }
                        Text("Reject")
                            .font(EType.body).fontWeight(.semibold)
                            .foregroundStyle(palette.textOnGradient)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Brand.danger,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .opacity(canRejectPOD ? 1.0 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!canRejectPOD)

                CTAButton(
                    title: podDecisionInFlight ? "Approving…" : "Approve POD",
                    action: { Task { await approvePOD() } },
                    isLoading: podDecisionInFlight
                )
                .opacity(canApprovePOD ? 1.0 : 0.55)
                .disabled(!canApprovePOD)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    private var canApprovePOD: Bool {
        !podDecisionInFlight && podPacket != nil && isLoadPODPending
    }

    private var canRejectPOD: Bool {
        let r = podRejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return !podDecisionInFlight && r.count >= 3 && isLoadPODPending
    }

    private func approvePOD() async {
        guard let n = Int(loadId) ?? liveDetail?.numericId else { return }
        podDecisionInFlight = true
        defer { podDecisionInFlight = false }
        do {
            _ = try await EusoTripAPI.shared.pod.approvePOD(loadId: n)
            withAnimation { podToast = "POD approved · payment released" }
            await refreshAll()
            try? await Task.sleep(nanoseconds: 700_000_000)
            showPODReview = false
        } catch {
            podError = (error as NSError).localizedDescription
        }
    }

    private func rejectPOD() async {
        guard let n = Int(loadId) ?? liveDetail?.numericId else { return }
        let reason = podRejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 3 else { return }
        podDecisionInFlight = true
        defer { podDecisionInFlight = false }
        do {
            _ = try await EusoTripAPI.shared.pod
                .rejectPOD(loadId: n, reason: reason)
            withAnimation { podToast = "POD rejected · driver will re-capture" }
            await refreshAll()
            try? await Task.sleep(nanoseconds: 700_000_000)
            showPODReview = false
        } catch {
            podError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Cancel-load sheet (real mutation)

    /// Composer for `loads.cancelWithReason`. Required reason →
    /// toast on success → notify the loads board to refresh + pop
    /// back. Server enforces shipper ownership and "load is not
    /// already delivered/cancelled" — the sheet surfaces whatever
    /// readable error the server returns instead of swallowing it.
    @ViewBuilder
    private var cancelSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CANCEL LOAD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(displayLoadId)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("Cancelling notifies the assigned carrier and rejects all pending bids. A TONU fee may apply if a carrier was already assigned.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Reason")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. shipper rescheduled pickup", text: $cancelReason, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(palette.borderFaint))
            }
            if let err = cancelError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
            HStack(spacing: Space.s3) {
                Button {
                    showCancelSheet = false
                } label: {
                    Text("Keep load")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s3)
                        .background(palette.bgCardSoft,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .disabled(cancelInFlight)

                Button {
                    Task { await submitCancel() }
                } label: {
                    HStack(spacing: 6) {
                        if cancelInFlight {
                            ProgressView().tint(palette.textOnGradient)
                        }
                        Text(cancelInFlight ? "Cancelling…" : "Confirm cancel")
                            .font(EType.body).fontWeight(.semibold)
                    }
                    .foregroundStyle(palette.textOnGradient)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(Brand.danger,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .opacity((cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3) && !cancelInFlight ? 1 : 0.6)
                }
                .buttonStyle(.plain)
                .disabled(cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || cancelInFlight)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    /// Submit the cancel-load mutation. Server input is `loadId:
    /// number` — the brick's `loadId: String` is the verbatim
    /// loadNumber-or-numeric-id string that comes from the row
    /// model, so coerce to Int. If parsing fails the LoadDetail's
    /// `numericId` projection is used as fallback.
    private func submitCancel() async {
        let reason = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 3 else { return }
        let numericId: Int = {
            if let i = Int(loadId) { return i }
            return liveDetail?.numericId ?? 0
        }()
        guard numericId > 0 else {
            cancelError = "Could not resolve a numeric load id for this row."
            return
        }
        cancelInFlight = true
        cancelError = nil
        do {
            _ = try await EusoTripAPI.shared.loads
                .cancelWithReason(loadId: numericId, reason: reason)
            cancelInFlight = false
            showCancelSheet = false
            cancelToast = "Load cancelled"
            // Pull fresh state + bounce the user back to the list so
            // the cancelled row falls out of "in-flight".
            await refreshAll()
            try? await Task.sleep(nanoseconds: 350_000_000)
            NotificationCenter.default.post(name: .eusoShipperLoadListOpen, object: nil)
        } catch {
            cancelInFlight = false
            cancelError = (error as NSError).localizedDescription
        }
    }

    private var liveDetail: LoadsAPI.LoadDetail? {
        detailStore.state.value ?? nil
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · LOAD · \(cargoEyebrow)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(displayLoadId)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button(action: backTapped) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Loads")

                Text(laneTitle)
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer()

                Button(action: kebabTapped) {
                    VStack(spacing: 3) {
                        Circle().frame(width: 4, height: 4)
                        Circle().frame(width: 4, height: 4)
                        Circle().frame(width: 4, height: 4)
                    }
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Load actions")
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var cargoEyebrow: String {
        guard let d = liveDetail else { return "DETAIL" }
        if let un = d.unNumber, !un.isEmpty {
            return "\(un) HAZMAT"
        }
        if let c = d.cargoType, !c.isEmpty { return c.uppercased() }
        return "DETAIL"
    }

    private var displayLoadId: String {
        liveDetail?.loadNumber ?? previewLoadNumber ?? loadId
    }

    private var laneTitle: String {
        if let d = liveDetail {
            let lane = d.laneDisplay
            if lane != "—" {
                // Compact city names for the title bar.
                let parts = lane.split(separator: " → ").map { String($0) }
                if parts.count == 2 {
                    let oCity = parts[0].split(separator: ",").first.map(String.init) ?? parts[0]
                    let dCity = parts[1].split(separator: ",").first.map(String.init) ?? parts[1]
                    return "\(oCity) → \(dCity)"
                }
                return lane
            }
        }
        if let lane = previewLane, !lane.isEmpty { return lane }
        return "Load detail"
    }

    private func backTapped() {
        NotificationCenter.default.post(name: .eusoShipperLoadListOpen, object: nil)
    }

    private func kebabTapped() {
        NotificationCenter.default.post(name: .eusoShipperLoadActionMenu, object: nil,
                                        userInfo: ["loadId": loadId])
    }

    // MARK: - Hero map

    private var heroMap: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0xDDE4EE), Color(hex: 0xC9D2DD)],
                startPoint: .top, endPoint: .bottom
            )
            // Subtle road-grid overlay
            Canvas { ctx, size in
                let gridStroke = Color.white.opacity(0.40)
                for fy in stride(from: CGFloat(0.32), through: 0.95, by: 0.32) {
                    ctx.stroke(Path { $0.move(to: .init(x: 0, y: size.height * fy))
                                       $0.addLine(to: .init(x: size.width, y: size.height * fy)) },
                               with: .color(gridStroke), lineWidth: 0.8)
                }
                for fx in stride(from: CGFloat(0.25), through: 0.85, by: 0.25) {
                    ctx.stroke(Path { $0.move(to: .init(x: size.width * fx, y: 0))
                                       $0.addLine(to: .init(x: size.width * fx, y: size.height)) },
                               with: .color(gridStroke), lineWidth: 0.8)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: .init(x: w * 0.12, y: h * 0.66))
                    p.addCurve(to: .init(x: w * 0.93, y: h * 0.30),
                               control1: .init(x: w * 0.45, y: h * 0.45),
                               control2: .init(x: w * 0.78, y: h * 0.20))
                }
                .stroke(LinearGradient.primary,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                pinDot(gradient: true)
                    .position(x: w * 0.12, y: h * 0.66)
                Text(originLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                    .position(x: w * 0.20, y: h * 0.78)

                truckPin()
                    .position(x: w * (0.12 + 0.81 * truckProgressFraction),
                              y: h * (0.66 - 0.36 * truckProgressFraction))

                pinDot(magenta: true)
                    .position(x: w * 0.93, y: h * 0.30)
                Text(destinationLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                    .position(x: w * 0.85, y: h * 0.20)

                pillCapsule(etaLine)
                    .position(x: w * 0.66, y: h * 0.10)

                pillCapsule(progressMilesLine)
                    .position(x: w * 0.21, y: h * 0.85)
            }
        }
        .frame(height: 144)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .accessibilityLabel("Live route, \(originLabel) to \(destinationLabel), \(progressPct)% complete, \(etaLine)")
    }

    private var originLabel: String {
        let city = liveDetail?.pickupLocation?.city ?? ""
        return city.isEmpty ? "ORIGIN" : city.uppercased()
    }
    private var destinationLabel: String {
        let city = liveDetail?.deliveryLocation?.city ?? ""
        return city.isEmpty ? "DESTINATION" : city.uppercased()
    }
    private var progressPct: Int {
        // Without telemetry.getLiveLocation, derive from status.
        guard let d = liveDetail else { return 0 }
        switch d.status.lowercased() {
        case "posted":              return 0
        case "bidding":             return 10
        case "awarded", "assigned": return 25
        case "pickup":              return 35
        case "in_transit", "in transit", "loading": return 68
        case "delivery", "delivering": return 85
        case "paperwork":           return 95
        case "closed", "delivered", "complete", "completed", "paid": return 100
        default:                    return 0
        }
    }
    private var truckProgressFraction: CGFloat {
        CGFloat(progressPct) / 100.0
    }
    private var etaLine: String {
        if let d = liveDetail, let eta = d.estimatedDeliveryDate ?? d.deliveryDate, !eta.isEmpty {
            return "ETA \(formatTime(eta))"
        }
        return "ETA —"
    }
    private var progressMilesLine: String {
        guard let d = liveDetail, let dist = d.distance, dist > 0 else { return "— mi" }
        let total = Int(dist.rounded())
        let driven = Int((Double(total) * Double(progressPct) / 100.0).rounded())
        return "\(driven) / \(total) mi"
    }

    private func pinDot(gradient: Bool = false, magenta: Bool = false) -> some View {
        ZStack {
            Circle().fill(.white).frame(width: 16, height: 16)
            Group {
                if gradient {
                    Circle().fill(LinearGradient.diagonal)
                } else if magenta {
                    Circle().fill(Brand.magenta)
                } else {
                    Circle().fill(palette.textPrimary)
                }
            }
            .frame(width: 12, height: 12)
        }
    }

    private func truckPin() -> some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal.opacity(0.16))
                .frame(width: 40, height: 40)
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(palette.borderSoft))
                .frame(width: 28, height: 28)
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1).fill(palette.textPrimary).frame(width: 9, height: 6)
                RoundedRectangle(cornerRadius: 1).fill(palette.textPrimary).frame(width: 5, height: 8)
            }
        }
    }

    private func pillCapsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.4).monospacedDigit()
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(.white)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
    }

    // MARK: - Lifecycle card (delegates to ShipperLoadCycleView)

    @ViewBuilder
    private var lifecycleCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("LIFECYCLE · \(lifecycleProductLabel)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            if let live = liveDetail {
                ShipperLoadCycleView(
                    status:   live.status,
                    product:  lifecycleProduct,
                    vertical: lifecycleVertical
                )
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                lifecycleSkeleton
            }
        }
    }

    private var lifecycleProductLabel: String {
        guard let d = liveDetail else { return "LOADING" }
        if let un = d.unNumber, !un.isEmpty {
            return "\(un) HAZMAT \((d.equipmentType ?? "TANKER").uppercased())"
        }
        if let c = d.cargoType, !c.isEmpty { return c.uppercased() }
        return "DRY VAN"
    }

    private var lifecycleSkeleton: some View {
        Rectangle()
            .fill(palette.bgCardSoft)
            .frame(height: 96)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Money card (gradient rim, hazmat pills, amount, progress)

    @ViewBuilder
    private var moneyCard: some View {
        if let d = liveDetail {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient.diagonal)
                RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                    .fill(palette.bgCard)
                    .padding(1.5)

                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        ForEach(moneyPills(for: d), id: \.text) { p in
                            pill(text: p.text, tint: p.tint, label: p.label)
                        }
                        Spacer()
                    }

                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.rateDisplay)
                                .font(.system(size: 34, weight: .bold).monospacedDigit())
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(rateLineText(for: d))
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                            Text(metaLineText(for: d))
                                .font(EType.caption)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: Space.s2)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("PROGRESS")
                                .font(EType.micro).tracking(0.6)
                                .foregroundStyle(palette.textTertiary)
                            Text("\(progressPct)%")
                                .font(.system(size: 22, weight: .bold).monospacedDigit())
                                .foregroundStyle(palette.textPrimary)
                            Text(progressMilesLine)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .padding(Space.s4)
            }
            .frame(height: 140)
        }
    }

    private struct MoneyPill { let text: String; let tint: Color; let label: Color }

    private func moneyPills(for d: LoadsAPI.LoadDetail) -> [MoneyPill] {
        var pills: [MoneyPill] = []
        if let un = d.unNumber, !un.isEmpty {
            let pg = d.hazmatClass.flatMap { $0.isEmpty ? nil : "PG \($0)" } ?? "HAZMAT"
            pills.append(MoneyPill(text: "\(un) · \(pg)",
                                   tint: Brand.hazmat.opacity(0.16),
                                   label: Color(hex: 0xB27300)))
        }
        if let equip = d.equipmentType, !equip.isEmpty, d.weightValue > 0 {
            let weightK = Int(d.weightValue / 1000.0)
            pills.append(MoneyPill(text: "\(equip) · \(weightK)K",
                                   tint: palette.bgCardSoft,
                                   label: palette.textPrimary))
        } else if let equip = d.equipmentType, !equip.isEmpty {
            pills.append(MoneyPill(text: equip,
                                   tint: palette.bgCardSoft,
                                   label: palette.textPrimary))
        }
        return pills
    }

    private func rateLineText(for d: LoadsAPI.LoadDetail) -> String {
        if d.rateValue > 0, let dist = d.distance, dist > 0 {
            let perMile = d.rateValue / dist
            return String(format: "linehaul · $%.2f/mi", perMile)
        }
        return "linehaul"
    }

    private func metaLineText(for d: LoadsAPI.LoadDetail) -> String {
        var parts: [String] = []
        if let dist = d.distance, dist > 0 {
            parts.append("\(Int(dist.rounded())) mi")
        }
        if d.hazmatClass != nil { parts.append("escort optional") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func pill(text: String, tint: Color, label: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(label)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint))
    }

    // MARK: - Carrier card

    @ViewBuilder
    private var carrierCard: some View {
        if let d = liveDetail, d.catalystId != nil || d.driverId != nil {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CATALYST · CARRIER")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .top, spacing: Space.s3) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal)
                        Text(carrierMonogram(for: d))
                            .font(.system(size: 16, weight: .bold)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(carrierNameLine(for: d))
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("ON TIME")
                                .font(EType.micro).tracking(0.4)
                                .foregroundStyle(Brand.success)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(palette.tintSuccess))
                        }
                        Text(carrierMetaLine(for: d))
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        Text(carrierDriverLine(for: d))
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, Space.s4)
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .contentShape(Rectangle())
                .onTapGesture {
                    if let id = d.catalystId {
                        NotificationCenter.default.post(name: .eusoShipperBrowseCarriers, object: nil,
                                                        userInfo: ["catalystId": id])
                    }
                }
            }
        }
    }

    private func carrierMonogram(for d: LoadsAPI.LoadDetail) -> String {
        // Without a catalyst-name field on LoadDetail, the monogram
        // falls back to the canonical "ET" for Eusotrans LLC since
        // that's the §11.4 anchor catalyst. The detail screen will
        // upgrade to live names when getCommercialContext lands.
        "ET"
    }

    private func carrierNameLine(for d: LoadsAPI.LoadDetail) -> String {
        if let id = d.catalystId {
            return "Catalyst #\(id)"
        }
        return "Catalyst — pending"
    }

    private func carrierMetaLine(for d: LoadsAPI.LoadDetail) -> String {
        var parts: [String] = []
        if let id = d.catalystId { parts.append("ID \(id)") }
        if let equip = d.equipmentType { parts.append(equip) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func carrierDriverLine(for d: LoadsAPI.LoadDetail) -> String {
        if let id = d.driverId {
            return "Driver #\(id) · CDL pending lookup"
        }
        return "Driver — awaiting assignment"
    }

    // MARK: - Documents row

    private var documentsRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DOCUMENTS")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                docTile(icon: "doc.text",
                        title: "BOL",
                        state: bolStateText,
                        stateColor: bolStateColor,
                        iconStyle: .gradient)
                docTile(icon: "doc.text.fill",
                        title: "Rate-con",
                        state: rateconStateText,
                        stateColor: rateconStateColor,
                        iconStyle: .gradient)
                docTile(icon: "checkmark.shield.fill",
                        title: "Insurance",
                        state: "verified",
                        stateColor: Brand.success,
                        iconStyle: .success)
            }
        }
    }

    private var bolStateText: String {
        guard let d = liveDetail else { return "—" }
        switch d.status.lowercased() {
        case "posted", "bidding": return "draft"
        case "awarded", "assigned", "pickup": return "draft"
        case "in_transit", "in transit", "delivery", "delivering": return "issued"
        case "paperwork", "closed", "delivered", "complete": return "signed"
        default: return "—"
        }
    }
    private var bolStateColor: Color {
        switch bolStateText {
        case "signed": return Brand.success
        case "issued": return Brand.warning
        default:       return palette.textSecondary
        }
    }
    private var rateconStateText: String {
        guard let d = liveDetail else { return "—" }
        return ["awarded", "assigned", "pickup", "in_transit", "in transit", "delivery", "delivering", "paperwork", "closed", "delivered", "complete"]
            .contains(d.status.lowercased()) ? "signed" : "draft"
    }
    private var rateconStateColor: Color {
        rateconStateText == "signed" ? Brand.success : palette.textSecondary
    }

    private enum DocIconStyle { case gradient, success }

    private func docTile(icon: String, title: String, state: String,
                         stateColor: Color, iconStyle: DocIconStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(iconStyle == .gradient
                                 ? AnyShapeStyle(LinearGradient.primary)
                                 : AnyShapeStyle(Brand.success))
            Text(title)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(state)
                .font(EType.caption)
                .foregroundStyle(stateColor)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Extras (EXTRA-OK kept beneath wireframe recipe)

    @ViewBuilder
    private var contentExtras: some View {
        switch detailStore.state {
        case .loading:
            extrasSkeleton
        case .loaded(let opt):
            if let detail = opt {
                VStack(alignment: .leading, spacing: Space.s4) {
                    metricsRow(detail)
                    scheduleCard(detail)
                    cargoCard(detail)
                    bidsCard(detail)
                    notesCard(detail)
                }
            } else {
                EusoEmptyState(
                    systemImage: "doc.text",
                    title: "Load not found",
                    subtitle: "The load you tapped is no longer in the system. Pull to refresh or pick another load from the list."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "doc.text",
                title: "Load not found",
                subtitle: "The load you tapped is no longer in the system."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    private var extrasSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func metricsRow(_ d: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(label: "RATE",     value: d.rateDisplay,     icon: "dollarsign.circle")
            metricTile(label: "DISTANCE", value: d.distanceDisplay, icon: "map")
            metricTile(label: "WEIGHT",   value: d.weightDisplay,   icon: "scalemass")
        }
    }

    private func metricTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func scheduleCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SCHEDULE", icon: "calendar")
            scheduleRow(label: "Pickup",     value: humanDate(d.pickupDate))
            scheduleRow(label: "Delivery",   value: humanDate(d.deliveryDate))
            if d.estimatedDeliveryDate != nil {
                scheduleRow(label: "Est. delivery", value: humanDate(d.estimatedDeliveryDate))
            }
            if d.actualDeliveryDate != nil {
                scheduleRow(label: "Delivered", value: humanDate(d.actualDeliveryDate))
            }
            if d.biddingEnds != nil {
                scheduleRow(label: "Bidding ends", value: humanDate(d.biddingEnds))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func scheduleRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func cargoCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CARGO", icon: "shippingbox")
            scheduleRow(label: "Type", value: humanCargoType(d.cargoType))
            if let commodity = (d.commodity ?? d.commodityName), !commodity.isEmpty {
                scheduleRow(label: "Commodity", value: commodity)
            }
            if let equip = d.equipmentType, !equip.isEmpty {
                scheduleRow(label: "Equipment", value: equip)
            }
            if let hz = d.hazmatClass, !hz.isEmpty {
                scheduleRow(label: "Hazmat class", value: hz)
                if let un = d.unNumber, !un.isEmpty {
                    scheduleRow(label: "UN number", value: un)
                }
                if let g = d.ergGuide {
                    scheduleRow(label: "ERG guide", value: "#\(g)")
                }
            }
            if d.spectraMatchVerified == true {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SPECTRA-MATCH VERIFIED")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func bidsCard(_ d: LoadsAPI.LoadDetail) -> some View {
        let rows = bidsStore.state.value ?? []
        let count = rows.count
        let highest = rows.map { $0.amount }.max() ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("BIDS", icon: "hand.raised")
            if bidsStore.isLoading && count == 0 {
                Text("Loading bids…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if count == 0 {
                Text("No bids yet — carriers will surface offers here as they come in.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    NotificationCenter.default.post(name: .eusoShipperLoadOpen, object: nil,
                                                    userInfo: ["loadId": loadId, "openBids": true])
                } label: {
                    HStack(spacing: 6) {
                        Text("\(count) bid\(count == 1 ? "" : "s")")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        if highest > 0 {
                            Text("· highest \(currency(highest))")
                                .font(EType.body)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func notesCard(_ d: LoadsAPI.LoadDetail) -> some View {
        if let notes = d.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("NOTES", icon: "text.alignleft")
                Text(notes)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await refreshAll() } }) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Bottom CTAs

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperLoadOpenMap, object: nil,
                                                userInfo: ["loadId": loadId])
            } label: {
                Text("View on map")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open live map view")

            Button {
                NotificationCenter.default.post(name: .eusoShipperLoadMessageEsang, object: nil,
                                                userInfo: ["loadId": loadId])
            } label: {
                Text("Message ESang")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask ESang about this load")
        }
        .padding(.top, Space.s2)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func humanCargoType(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "—" }
        switch r.lowercased() {
        case "general":      return "General freight"
        case "hazmat":       return "Hazmat"
        case "petroleum":    return "Petroleum"
        case "gas":          return "Gas"
        case "chemicals":    return "Chemicals"
        case "refrigerated": return "Refrigerated"
        case "container":    return "Container"
        case "bulk":         return "Bulk"
        default:             return r.capitalized
        }
    }

    private func humanDate(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "—" }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · HH:mm"
        return fmt.string(from: d)
    }

    private func formatTime(_ iso: String) -> String {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: d) + " " + (TimeZone.current.abbreviation() ?? "")
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    private func refreshAll() async {
        detailStore.loadId = loadId
        bidsStore.setLoadId(loadId)
        async let a: Void = detailStore.refresh()
        async let b: Void = bidsStore.refresh()
        _ = await (a, b)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperLoadOpenMap         = Notification.Name("eusoShipperLoadOpenMap")
    static let eusoShipperLoadMessageEsang    = Notification.Name("eusoShipperLoadMessageEsang")
    static let eusoShipperLoadActionMenu      = Notification.Name("eusoShipperLoadActionMenu")
    /// Fired by the action-menu "Cancel load" choice. Listened by
    /// `ShipperLoadDetail` itself (calls `loads.cancel` once the
    /// backend ships it; today shows a confirmation toast pending
    /// that endpoint).
    static let eusoShipperLoadCancelRequested = Notification.Name("eusoShipperLoadCancelRequested")
    /// Fired by the action-menu "Edit / Open on web" choices.
    /// Listened by `RoleSurfaceRouter.ShipperSurface`, which opens
    /// `app.eusotrip.com/loads/{loadId}` in an SFSafariViewController
    /// — the canonical web load-edit surface that ships ahead of the
    /// in-app edit form.
    static let eusoShipperLoadOpenOnWeb       = Notification.Name("eusoShipperLoadOpenOnWeb")
}

// MARK: - Screen wrapper

struct ShipperLoadDetailScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let previewLoadNumber: String?
    let previewLane: String?

    var body: some View {
        Shell(theme: theme) {
            ShipperLoadDetail(
                loadId: loadId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane
            )
        } nav: {
            BottomNav(
                leading: shipperNavLeading_205(),
                trailing: shipperNavTrailing_205(),
                orbState: .idle
            )
        }
    }
}

// Out of scope per parity mandate §1.
private func shipperNavLeading_205() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_205() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews

#Preview("205 · Shipper · Load Detail · Night") {
    ShipperLoadDetailScreen(
        theme: Theme.dark,
        loadId: "0",
        previewLoadNumber: "LD-260427-A38FB12C7E",
        previewLane: "Houston, TX → Dallas, TX"
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("205 · Shipper · Load Detail · Afternoon") {
    ShipperLoadDetailScreen(
        theme: Theme.light,
        loadId: "0",
        previewLoadNumber: "LD-260427-A38FB12C7E",
        previewLane: "Houston, TX → Dallas, TX"
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
