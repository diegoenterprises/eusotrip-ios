//
//  205_ShipperLoadDetail.swift
//  EusoTrip — Shipper · Load Detail (brick 205).
//
//  Parity-reconciled to `02 Shipper/Code/205_ShipperLoadDetail.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: gradient TopBar (eyebrow with cargo type + load id mono +
//  back chevron + lane title + kebab), IridescentHairline, hero map
//  (gradient bg + grid + I-45 highway curve + origin/truck/destination
//  pins + planned-time + projection-truth pills), gradient-rim money card with hazmat
//  pills + amount + rate-line + progress %, carrier card with gradient
//  avatar + ON TIME pill, documents row (BOL · Rate-con · Insurance),
//  bottom CTA pair (View on map · Message eSang).
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
//  Notification names: eusoShipperLoadOpenMap, eusoShipperLoadMessageeSang,
//                      eusoShipperLoadActionMenu.
//
//  BottomNav: Loads slot stays current — out of scope per parity
//  mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation
import MapKit

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
    /// RIOS §12 — set true when any load party fails a HARD sanctions gate
    /// (surfaced by ComplianceGatesStrip). Informational on the shipper side.
    @State private var gateLocked: Bool = false

    /// In-app cancel-load sheet (no web fallback). Opened when the
    /// user picks "Cancel load" in the kebab menu. The sheet collects
    /// a cancel reason and submits via `loads.cancelWithReason`.
    @State private var showCancelSheet: Bool = false
    @State private var cancelReason: String = ""
    @State private var cancelInFlight: Bool = false
    @State private var cancelError: String? = nil
    @State private var cancelToast: String? = nil

    /// In-app edit-load sheet — replaces the prior "Open on web"
    /// continuation. Posts to `loads.update` with the changed fields
    /// only (rate / specialInstructions / dispatchNotes for now).
    @State private var showEditSheet: Bool = false
    @State private var editRateText: String = ""
    @State private var editSpecialInstructions: String = ""
    @State private var editDispatchNotes: String = ""
    @State private var editInFlight: Bool = false
    @State private var editError: String? = nil
    @State private var editToast: String? = nil

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

    /// Phase 8 (Pre-trip / driver readiness) — assigned-driver
    /// eligibility envelope from loads.getAssignedDriverReadiness.
    /// Hydrates alongside the load detail; stays nil for unassigned
    /// loads so the card renders an honest "no driver yet" state.
    @State private var driverReadiness: LoadsAPI.DriverReadiness? = nil

    /// Phase 10 (Pickup operations) — appointment for this load.
    /// Hydrates from appointments.getByLoad alongside the detail.
    /// Drives the "Assign dock" action-menu entry below.
    @State private var loadAppointment: AppointmentsAPI.ByLoadAppointment? = nil
    /// Wave B (2026-06-10) — escort assignments for this load
    /// (`loads.getEscortAssignment`). `[]` = confirmed solo OR fetch
    /// failed → the convoy strip stays hidden (never a fabricated
    /// pilot car).
    @State private var escortAssignments: [LoadsAPI.EscortAssignment] = []
    @State private var showDockAssign: Bool = false
    @State private var dockNumberDraft: String = ""
    @State private var dockAssignInFlight: Bool = false
    @State private var dockAssignError: String? = nil
    @State private var dockAssignToast: String? = nil

    /// Listing-trust verdict for this load — fetched from
    /// `fraud.getLoadTrust(loadId)` on appear. Drives the trust chip
    /// in the top bar (verified / review / flagged) plus the report-
    /// listing flow accessible from the chip's tap.
    @State private var listingTrust: ListingTrust? = nil

    /// Real road geometry for a truck load's pickup-to-delivery corridor.
    /// Non-road loads remain marker-only until a mode-specific provider
    /// supplies real route geometry.
    /// Exact server-owned mode-native route. The renderer keeps every
    /// LineString/MultiLineString member independent.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?

    private var lifecycleVertical: TripVertical {
        TripVertical(
            transportMode: liveDetail?.transportMode,
            equipmentType: liveDetail?.equipmentType,
            role: session.user?.role
        )
    }

    private var lifecycleProduct: TripProduct {
        let detail = detailStore.state.value ?? nil
        return TripProduct.resolveDirect(
            cargoType:   detail?.cargoType,
            hazmatClass: detail?.hazmatClass,
            vertical:    lifecycleVertical
        )
    }

    /// Wave B (2026-06-10) — the multi-vehicle convoy strip, mounted
    /// ONLY when real escort rows exist for this load. Renders nothing
    /// otherwise — no placeholder, no sample convoy.
    @ViewBuilder
    private var convoyStripIfEscorted: some View {
        if let detail = detailStore.state.value ?? nil,
           !escortAssignments.isEmpty,
           let shipment = Shipment.composed(fromLoad: detail, escorts: escortAssignments) {
            ConvoyAnimationStrip(shipment: shipment)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s3)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroMap
                    lifecycleCard
                    // Wave B (2026-06-10) — escorted loads mount the
                    // multi-vehicle convoy strip (one Shipment, N typed
                    // Vehicles per MULTI_VEHICLE_LOAD_ARCHITECTURE):
                    // lead pilot car(s), the primary rig with its
                    // lifecycle state-variant animation, chase car(s).
                    // Composed exclusively from the real load detail +
                    // real loads.getEscortAssignment rows — hidden
                    // entirely when the load has no escort wired.
                    convoyStripIfEscorted
                    moneyCard
                    carrierCard
                    driverReadinessCard
                    nrcCardIfHazmat7
                    documentsRow
                    // §27 — commodity / cross-border addenda. Each row is
                    // a real drill-down into a per-load record surface and
                    // is rendered only when THIS load's own attributes make
                    // it applicable, so the group disappears entirely on a
                    // plain domestic dry-van move.
                    commodityAddendaRow
                    contentExtras
                    // RIOS §11/§12 — sanctions screening of every load party
                    // (shipper/carrier/driver) before transact.
                    if let lid = Int(loadId) {
                        ComplianceGatesStrip(loadId: lid, role: "shipper", gateLocked: $gateLocked)
                    }
                    ctaRow
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s4)
            }
        }
        // Animate when the live detail status changes (e.g., POSTED→
        // BIDDING→IN_TRANSIT) so the lifecycle/progress reflows
        // smoothly. RemoteState itself isn't Equatable across optionals,
        // so observe a derived String key instead.
        .animation(.easeOut(duration: 0.18), value: detailStore.state.value??.status ?? "")
        .task {
            // Emergency Wave I1 acceptance: a 205 can no longer mount
            // with the id-0 sentinel — every nav path resolves a real
            // load id (or lands on the unresolved placeholder). Assert
            // in debug so any future regression screams immediately.
            #if DEBUG
            if loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (Int(loadId).map { $0 <= 0 } ?? false) {
                assertionFailure("[205] mounted with sentinel loadId '\(loadId)' — every nav entry must pass ShipperLoadIdResolver (Emergency I1)")
            }
            #endif
            await refreshAll()
            await loadListingTrust()
            joinLoadRoom()
        }
        .eusoRefreshable {
            await refreshAll()
            await loadListingTrust()
        }
        .onDisappear { leaveLoadRoom() }
        // Kebab (⋯) tap fires `eusoShipperLoadActionMenu`; listen
        // here on the same screen so the action sheet actually
        // surfaces instead of the notification dropping into the
        // void.
        .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadActionMenu)) { _ in
            showActionMenu = true
        }
        // RealtimeService → live updates from the load's Socket.IO
        // room — carrier accept, driver assign, status change, POD
        // submission, dock assignment. Keeps the shipper detail
        // surface in sync with the carrier/driver side.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await refreshAll() }
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
                Button("Review \(TransportLexicon.short(.proofOfDelivery, mode: loadMode, equipmentRaw: loadEquipmentRaw))") {
                    podError = nil
                    podRejectReason = ""
                    showPODReview = true
                    Task { await hydratePODPacket() }
                }
            }
            // Phase 10 closure: dock-door assignment. Only renders
            // when an appointment exists on this load.
            if loadAppointment != nil {
                Button("Assign dock") {
                    dockAssignError = nil
                    dockNumberDraft = loadAppointment?.dockNumber ?? ""
                    showDockAssign = true
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
                editError = nil
                editRateText = ""
                editSpecialInstructions = ""
                editDispatchNotes = ""
                showEditSheet = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        .sheet(isPresented: $showDockAssign) {
            dockAssignSheet
                .environment(\.palette, palette)
                .presentationDetents([.medium])
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
    private func podEvidenceImage(
        base64: String?,
        urlString: String?,
        emptyText: String,
        minHeight: CGFloat
    ) -> some View {
        if let image = decodeBase64Image(base64) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, minHeight: minHeight)
        } else if let urlString,
                  let url = URL(string: urlString),
                  url.scheme == "https" {
            AppRadioSilenceAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Text("Delivery evidence is temporarily unavailable")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                case .empty:
                    ProgressView()
                @unknown default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
        } else {
            Text(emptyText)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
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
                        Text("REVIEW \(TransportLexicon.short(.proofOfDelivery, mode: loadMode, equipmentRaw: loadEquipmentRaw).uppercased())")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1).minimumScaleFactor(0.7)
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
            Text(podPacket?.receiverName ?? "-")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Submitted \(podPacket?.submittedAt ?? "-")")
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
            Text("\(TransportLexicon.short(.billOfLading, mode: loadMode, equipmentRaw: loadEquipmentRaw).uppercased()) PHOTO")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.7)
            podEvidenceImage(
                base64: podPacket?.photoBase64,
                urlString: podPacket?.photoUrl,
                emptyText: "No photo on file",
                minHeight: 120
            )
            .background(palette.bgCardSoft,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
            podEvidenceImage(
                base64: podPacket?.signatureBase64,
                urlString: podPacket?.signatureUrl,
                emptyText: "No signature on file",
                minHeight: 80
            )
            .background(palette.bgCardSoft,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                    title: podDecisionInFlight ? "Approving…" : "Approve \(TransportLexicon.short(.proofOfDelivery, mode: loadMode, equipmentRaw: loadEquipmentRaw))",
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

    // MARK: - Dock-assign sheet (Phase 10 closure)

    /// Composer for `appointments.assignDock`. Shipper-of-record (or
    /// terminal manager / dispatch / admin) writes the assigned dock
    /// door number directly to the appointments.dockNumber column.
    /// On success the action-menu entry shows the new number on next
    /// open via the refreshed `loadAppointment` state.
    @ViewBuilder
    private var dockAssignSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ASSIGN DOCK")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(loadAppointment?.dockNumber.map { "Currently dock \($0)" } ?? "No dock assigned yet")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("Assigning a dock writes through to the gate-pass + driver lifecycle so the carrier sees the door number when they pull up. Use the facility's official dock label (e.g. '12', 'B-7', 'East 4').")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Dock door")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. 12 or B-7", text: $dockNumberDraft)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(palette.borderFaint))
            }
            if let err = dockAssignError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
            HStack(spacing: Space.s3) {
                Button {
                    showDockAssign = false
                } label: {
                    Text("Cancel")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s3)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .disabled(dockAssignInFlight)

                Button {
                    Task { await submitDockAssign() }
                } label: {
                    HStack(spacing: 6) {
                        if dockAssignInFlight {
                            ProgressView().tint(palette.textOnGradient)
                        }
                        Text(dockAssignInFlight ? "Assigning…" : "Confirm dock")
                            .font(EType.body).fontWeight(.semibold)
                    }
                    .foregroundStyle(palette.textOnGradient)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(LinearGradient.diagonal,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .opacity(canSubmitDock ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitDock)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
        .overlay(alignment: .bottom) {
            if let toast = dockAssignToast {
                Text(toast)
                    .font(EType.caption).fontWeight(.semibold)
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Brand.success,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation { dockAssignToast = nil }
                    }
            }
        }
    }

    private var canSubmitDock: Bool {
        let trimmed = dockNumberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !dockAssignInFlight
    }

    private func submitDockAssign() async {
        guard canSubmitDock, let appt = loadAppointment else { return }
        let trimmed = dockNumberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        dockAssignInFlight = true
        dockAssignError = nil
        defer { dockAssignInFlight = false }
        do {
            _ = try await EusoTripAPI.shared.appointments
                .assignDock(id: appt.id, dockNumber: trimmed)
            withAnimation { dockAssignToast = "Dock \(trimmed) assigned" }
            await refreshAll()
            try? await Task.sleep(nanoseconds: 700_000_000)
            showDockAssign = false
        } catch {
            dockAssignError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Edit-load sheet (real mutation)

    /// Composer for `loads.update`. Three editable fields: rate,
    /// special instructions, dispatch notes. The server merges into
    /// the existing row — anything left blank stays unchanged.
    /// Replaces the prior "Open on web" continuation.
    @ViewBuilder
    private var editSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EDIT LOAD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(displayLoadId)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("Update rate, instructions or a dispatch note. Pickup / delivery edits route through Reroute. Carrier sees changes the moment you save.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Rate (USD)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. 2850.00", text: $editRateText)
                    .keyboardType(.decimalPad)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Special instructions")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. Driver must call 30 min out", text: $editSpecialInstructions, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Dispatch note (timestamped)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("Append a one-liner the carrier sees on the dashboard", text: $editDispatchNotes, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            }
            if let err = editError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
            HStack(spacing: Space.s3) {
                Button {
                    showEditSheet = false
                } label: {
                    Text("Discard")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s3)
                        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .disabled(editInFlight)

                Button {
                    Task { await submitEdit() }
                } label: {
                    HStack(spacing: 6) {
                        if editInFlight {
                            ProgressView().tint(palette.textOnGradient)
                        }
                        Text(editInFlight ? "Saving…" : "Save changes")
                            .font(EType.body).fontWeight(.semibold)
                    }
                    .foregroundStyle(palette.textOnGradient)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(LinearGradient.diagonal, in: RoundedRectangle(cornerRadius: Radius.md))
                    .opacity(editCanSubmit && !editInFlight ? 1 : 0.6)
                }
                .buttonStyle(.plain)
                .disabled(!editCanSubmit || editInFlight)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    private var editCanSubmit: Bool {
        let hasRate = Double(editRateText.trimmingCharacters(in: .whitespaces)).map { $0 > 0 } ?? false
        let hasSI = !editSpecialInstructions.trimmingCharacters(in: .whitespaces).isEmpty
        let hasDN = !editDispatchNotes.trimmingCharacters(in: .whitespaces).isEmpty
        return hasRate || hasSI || hasDN
    }

    private func submitEdit() async {
        guard editCanSubmit else { return }
        editInFlight = true
        editError = nil
        defer { editInFlight = false }
        let rate = Double(editRateText.trimmingCharacters(in: .whitespaces))
        let si = editSpecialInstructions.trimmingCharacters(in: .whitespaces)
        let dn = editDispatchNotes.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await EusoTripAPI.shared.loads.updateLoad(
                loadId: loadId,
                rate: rate,
                specialInstructions: si.isEmpty ? nil : si,
                dispatchNotes: dn.isEmpty ? nil : dn
            )
            await MainActor.run {
                showEditSheet = false
                editToast = "Load updated"
                editRateText = ""
                editSpecialInstructions = ""
                editDispatchNotes = ""
            }
            await refreshAll()
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { editToast = nil }
        } catch {
            await MainActor.run {
                editError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
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

    /// Mode-aware terminology resolver for this load. Drives the
    /// document/label lexicon so a vessel load reads "Ocean Bill of
    /// Lading" and a rail load reads its native term instead of the
    /// hardcoded truck "BOL".
    private var loadMode: TransportMode {
        TransportMode(rawValue: liveDetail?.transportMode ?? "truck") ?? .truck
    }

    private var loadEquipmentRaw: String? {
        liveDetail?.equipmentType
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                EusoTripEyebrow(verbatim: "SHIPPER · LOAD · \(cargoEyebrow)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                ListingTrustBadge(trust: listingTrust, loadId: loadId)
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
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var cargoEyebrow: String {
        guard let d = liveDetail else { return "DETAIL" }
        if let un = d.unNumber, !un.isEmpty {
            return "\(un) HAZMAT"
        }
        if let c = d.cargoType, !c.isEmpty { return cleanLabel(c).uppercased() }
        return "DETAIL"
    }

    private var displayLoadId: String {
        liveDetail?.loadNumber ?? previewLoadNumber ?? loadId
    }

    private var laneTitle: String {
        if let d = liveDetail {
            let lane = d.laneDisplay
            if lane != "-" {
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
        // Pop the actual ShipperSurface stack so the user returns to
        // wherever they came from (settlements, agreements, market
        // intel, post-load review …) — NOT unconditionally to the
        // Loads tab. The previous post (`.eusoShipperLoadListOpen`)
        // collapsed the stack to `[201]` regardless of origin, which
        // is why the back button felt broken from non-Loads entry
        // points (founder report 2026-05-05).
        NotificationCenter.default.post(name: .eusoShipperNavBack, object: nil)
    }

    private func kebabTapped() {
        NotificationCenter.default.post(name: .eusoShipperLoadActionMenu, object: nil,
                                        userInfo: ["loadId": loadId])
    }

    // MARK: - Hero map
    //
    // 2026-05-18 — replaces the decorative SwiftUI Canvas + Path lane
    // preview with a real HereMapView. The Canvas version was
    // hardcoded to a light gradient (0xDDE4EE → 0xC9D2DD) so it stayed
    // bright against the dark-mode shipper shell, and never actually
    // connected to HERE — the route was a fake bezier curve. Now it
    // renders the actual road network around the pickup → delivery
    // corridor with auto dark/light tile style. Planned-time + projection pills
    // overlay on top as a `.overlay` so the live status grammar still
    // reads at a glance.

    // Emergency Wave I1 (2026-06-11) — the hero card now switches on
    // the store state. Before, a null getById (`.empty`) and a failed
    // one (`.error`) both rendered the same "Route loading…" skeleton
    // as `.loading` — visually indistinguishable from a load that
    // never finishes (the founder's dead 205). Each terminal state
    // gets distinct copy; `.error` carries an inline retry.
    private var heroMap: some View {
        Group {
            switch detailStore.state {
            case .loading:
                heroPlaceholder(icon: "map", title: "Route loading…", subtitle: nil)
            case .empty:
                heroPlaceholder(
                    icon: "doc.questionmark",
                    title: "Load not found",
                    subtitle: "This load is no longer in the system."
                )
            case .loaded(let opt):
                if opt == nil {
                    heroPlaceholder(
                        icon: "doc.questionmark",
                        title: "Load not found",
                        subtitle: "This load is no longer in the system."
                    )
                } else {
                    heroLoadedMap
                }
            case .error:
                heroErrorState
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .accessibilityLabel(heroAccessibilityLabel)
    }

    private var heroAccessibilityLabel: String {
        switch detailStore.state {
        case .loading:          return "Route loading"
        case .empty:            return "Load not found"
        case .loaded(let opt):
            if opt == nil { return "Load not found" }
            return "Verified route, \(originLabel) to \(destinationLabel), progress awaiting current trip evidence, \(etaLine)"
        case .error:            return "Couldn't load this route. Retry available."
        }
    }

    private var heroLoadedMap: some View {
        ZStack(alignment: .topLeading) {
            if let lane = laneForMap {
                // 2026-05-21: swapped the raster HereMapView (Maps Tile v3 —
                // the "Route loading…" forever blank) for the OMV vector
                // renderer the plan serves. Pickup/delivery pins + a route
                // connector layered on the vector basemap; dark/light native.
                //
                let mapTransportMode = EusoTripMapTransportMode(
                    canonicalValue: liveDetail?.transportMode
                )
                let layers: [HereMapLayer] = {
                    var result: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                        .eusoRoute(
                            polyline: line,
                            state: canonicalRoutePurpose == .activeJob ? .active : .planned,
                            label: index == 0
                                ? "Eusorone \(mapTransportMode.rawValue) route plan version \(canonicalRouteVersion ?? 0)"
                                : nil
                        )
                    }
                    result.append(.markers([
                        .init(at: .init(lane.pickup), kind: .pickup, label: lane.originTitle),
                        .init(at: .init(lane.delivery), kind: .delivery, label: lane.destinationTitle)
                    ]))
                    return result
                }()
                HereLiveMapView(
                    center: canonicalRouteLines.lazy.compactMap(\.first).first
                        ?? .init(lane.pickup),
                    zoom: 6,
                    route: [],
                    baseLayers: layers,
                    addOns: mapTransportMode == .truck ? .shipperTracking : .weather,
                    activeJob: canonicalRoutePurpose == .activeJob,
                    mapModeContext: .unconfirmed(mapTransportMode)
                )
            } else {
                // Detail is live but coords haven't been geocoded yet —
                // neutral pending tone while the server's self-healing
                // geocoder fills them in on the next read.
                heroPlaceholder(icon: "map", title: "Route pending geocode", subtitle: nil)
            }

            // Status pills layered above the map (top-right ETA,
            // bottom-left progress). Tile style handles its own dark/
            // light palette; the pills carry the brand surface.
            VStack {
                HStack {
                    Spacer()
                    pillCapsule(etaLine)
                        .padding(.top, 8)
                        .padding(.trailing, 10)
                }
                Spacer()
                HStack {
                    pillCapsule(progressMilesLine)
                        .padding(.bottom, 8)
                        .padding(.leading, 10)
                    Spacer()
                }
            }
            if let canonicalRouteStatus {
                Text(canonicalRouteStatus)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.92))
                    .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                    .clipShape(Capsule())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .accessibilityLabel(canonicalRouteStatus)
            }
        }
    }

    private func heroPlaceholder(icon: String, title: String, subtitle: String?) -> some View {
        Rectangle()
            .fill(palette.bgCard)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(title)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    if let subtitle {
                        Text(subtitle)
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.s4)
                    }
                }
            )
    }

    /// Hero-level error surface — distinct from loading AND from
    /// not-found, with an inline retry so the founder never stares at
    /// a silent skeleton after a transport/server failure.
    private var heroErrorState: some View {
        Rectangle()
            .fill(palette.bgCard)
            .overlay(
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                        Text("COULDN'T LOAD THIS LOAD")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(Brand.danger)
                    }
                    Button(action: { Task { await refreshAll() } }) {
                        Text("Retry")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(LinearGradient.diagonal)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            )
    }

    /// Composes a HereMapView Lane from the load's pickup + delivery
    /// coordinates. Returns nil when either endpoint hasn't been
    /// geocoded yet (server self-heals on the next read).
    private var laneForMap: HereMapView.Lane? {
        guard let p = liveDetail?.pickupLocation,
              let d = liveDetail?.deliveryLocation,
              let pickup = LatLongParser.validatedCoordinate(
                  latitude: p.lat,
                  longitude: p.lng
              ),
              let delivery = LatLongParser.validatedCoordinate(
                  latitude: d.lat,
                  longitude: d.lng
              ) else { return nil }
        return HereMapView.Lane(
            id: "load_\(loadId)",
            originTitle: originLabel,
            destinationTitle: destinationLabel,
            pickup: pickup,
            delivery: delivery
        )
    }

    private var canonicalRoutePurpose: CanonicalRoutePlanClient.Purpose {
        let status = liveDetail?.status.lowercased() ?? ""
        let activeStates = [
            "assigned", "accepted", "dispatched", "en_route", "enroute",
            "in_transit", "at_pickup", "loaded", "at_delivery", "delivered"
        ]
        return activeStates.contains(where: status.contains) ? .activeJob : .posting
    }

    /// Resolve through the server authority using subject + purpose only.
    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteStatus = nil
        canonicalRouteVersion = nil
        guard let numericId = Int(loadId) ?? liveDetail?.numericId else {
            canonicalRouteStatus = "Canonical route pending a persisted load identity"
            return
        }
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: numericId,
                purpose: canonicalRoutePurpose
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native route pending verified authority"
                await readExistingCanonicalRoute(loadId: numericId)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: numericId)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(loadId: Int) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId)
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalRouteStatus = "Canonical route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRouteStatus = nil
    }

    private var originLabel: String {
        let city = liveDetail?.pickupLocation?.city ?? ""
        return city.isEmpty ? "ORIGIN" : city.uppercased()
    }
    private var destinationLabel: String {
        let city = liveDetail?.deliveryLocation?.city ?? ""
        return city.isEmpty ? "DESTINATION" : city.uppercased()
    }
    private var etaLine: String {
        if let d = liveDetail, let eta = d.estimatedDeliveryDate ?? d.deliveryDate, !eta.isEmpty {
            return "PLANNED \(formatTime(eta))"
        }
        return "PLANNED -"
    }
    private var progressMilesLine: String { "PROJECTION PENDING" }

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
        // The pill background is always white (it sits over the dark map
        // tile), so the ink must always be a fixed dark color — NOT
        // palette.textPrimary, which is near-white in dark mode and
        // rendered the pill white-on-white / unreadable (the founder's
        // "cannot read writing" feedback on the planned-time + projection pills).
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.4).monospacedDigit()
            .foregroundStyle(Color(hex: 0x0D1117))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(.white)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12)))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.28), radius: 5, y: 1)
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
            return "\(un) HAZMAT \(cleanLabel(d.equipmentType ?? "TANKER").uppercased())"
        }
        if let c = d.cargoType, !c.isEmpty { return cleanLabel(c).uppercased() }
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
                            Text("PENDING")
                                .font(.system(size: 14, weight: .bold).monospacedDigit())
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
            pills.append(MoneyPill(text: "\(cleanLabel(equip)) · \(weightK)K",
                                   tint: palette.bgCardSoft,
                                   label: palette.textPrimary))
        } else if let equip = d.equipmentType, !equip.isEmpty {
            pills.append(MoneyPill(text: cleanLabel(equip),
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
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
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
        return "Catalyst - pending"
    }

    private func carrierMetaLine(for d: LoadsAPI.LoadDetail) -> String {
        var parts: [String] = []
        if let id = d.catalystId { parts.append("ID \(id)") }
        if let equip = d.equipmentType { parts.append(cleanLabel(equip)) }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private func carrierDriverLine(for d: LoadsAPI.LoadDetail) -> String {
        if let id = d.driverId {
            return "Driver #\(id) · CDL pending lookup"
        }
        return "Driver - awaiting assignment"
    }

    // MARK: - Documents row

    private var documentsRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DOCUMENTS")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                docTile(icon: "doc.text",
                        title: TransportLexicon.short(.billOfLading, mode: loadMode, equipmentRaw: loadEquipmentRaw),
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
            // Add-to-Wallet — routes through the ONE reusable entry point
            // (AddToWalletButton) so the bespoke card-style picker + themed
            // Add-to-Wallet behave identically everywhere ("across the board").
            // Server: eusoWallet.listWalletThemes / setWalletTheme +
            // createPickupCredential. The bespoke document-strip tile is supplied
            // as the button's label, so the 205 look is preserved while the picker
            // behavior lives in the shared component. Mints the themed Apple Wallet
            // pickup pass for THIS load.
            AddToWalletButton(loadId: loadId) {
                walletPassTile
            }
        }
    }

    /// Full-width "Add to Apple Wallet" affordance beneath the document tiles.
    private var walletPassTile: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(LinearGradient.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add to Apple Wallet")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Themed pickup pass · pick your card style")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .contentShape(Rectangle())
    }

    private var bolStateText: String {
        guard let d = liveDetail else { return "-" }
        switch d.status.lowercased() {
        case "posted", "bidding": return "draft"
        case "awarded", "assigned", "pickup": return "draft"
        case "in_transit", "in transit", "delivery", "delivering": return "issued"
        case "paperwork", "closed", "delivered", "complete": return "signed"
        default: return "-"
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
        guard let d = liveDetail else { return "-" }
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    // MARK: - Commodity / cross-border addenda (§27 inbound edges)

    /// One drill-down destination for this load.
    private struct AddendaLink205: Identifiable {
        let id: String          // registry screen id
        let title: String
        let subtitle: String
        let systemImage: String
    }

    /// Only the addenda this load actually qualifies for. A load with no
    /// hazmat class, no temperature control and no recorded cross-border
    /// pair produces an empty list and the whole group is hidden — a row
    /// that would only ever open an "operation does not apply" screen is
    /// noise, not navigation.
    private var applicableAddenda: [AddendaLink205] {
        guard let detail = liveDetail else { return [] }
        var links: [AddendaLink205] = []

        let equipmentSignal = "\(detail.cargoType ?? "") \(detail.equipmentType ?? "")".lowercased()
        let temperatureControlled = equipmentSignal.contains("reefer")
            || equipmentSignal.contains("refrigerat")
            || equipmentSignal.contains("temp")
            || equipmentSignal.contains("food_grade")
        if temperatureControlled {
            links.append(AddendaLink205(
                id: "204B",
                title: "Cold-chain spec",
                subtitle: "FSMA continuous record · USDA setpoint band",
                systemImage: "thermometer.snowflake"
            ))
        }

        if detail.hazmatClass?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            links.append(AddendaLink205(
                id: "204C",
                title: "Hazmat manifest gate",
                subtitle: "49 CFR / PHMSA validation for this load",
                systemImage: "exclamationmark.triangle"
            ))
        }

        let origin = detail.originCountry?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = detail.destCountry?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let origin, let destination, !origin.isEmpty, !destination.isEmpty, origin != destination {
            links.append(AddendaLink205(
                id: "216B",
                title: "Customs gate",
                subtitle: "Required filings · clearance verdict",
                systemImage: "globe.americas"
            ))
            links.append(AddendaLink205(
                id: "216D",
                title: "USMCA origin",
                subtitle: "Preferential-origin rules check",
                systemImage: "checkmark.seal"
            ))
            links.append(AddendaLink205(
                id: "216F",
                title: "Border wait",
                subtitle: "Ranked crossings · CBP feed state",
                systemImage: "road.lanes"
            ))
        }

        return links
    }

    @ViewBuilder
    private var commodityAddendaRow: some View {
        let links = applicableAddenda
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("COMMODITY & CROSS-BORDER")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s2)
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    addendaLinkRow(link)
                    if index < links.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 56)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func addendaLinkRow(_ link: AddendaLink205) -> some View {
        Button {
            openAddendum(link.id)
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: link.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.info)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(link.subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(link.title). \(link.subtitle)")
    }

    /// Routes to a §27 addendum carrying THIS load's id. The Shipper
    /// surface captures the payload for these ids (RoleSurfaceRouter
    /// `commodityAddendaIds`) and mounts the screen with a real load.
    private func openAddendum(_ screenId: String) {
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": screenId, "loadId": loadId]
        )
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
                scheduleRow(label: "Equipment", value: cleanLabel(equip))
            }
            // 2026-05-17 — Multi-modal payload surfacing. Mode is always
            // present (server defaults to "truck"); the rest only render
            // when present. Keeps the detail screen honest about what
            // the shipper actually posted (vessel-tanker @ WS 75 reads
            // differently than a $/mile truck load).
            if let mode = d.transportMode, !mode.isEmpty, mode != "truck" {
                scheduleRow(label: "Mode", value: mode.uppercased())
            }
            if let vc = d.vesselClass, !vc.isEmpty {
                scheduleRow(label: "Vessel class", value: vc)
            }
            if let count = d.multiVehicleCount, count > 1 {
                scheduleRow(label: "Vehicles", value: "\(count) ×")
            }
            if let perm = d.permitType, !perm.isEmpty, perm != "none" {
                scheduleRow(label: "Permit", value: perm.replacingOccurrences(of: "_", with: " ").uppercased())
            }
            if let ws = d.worldscalePct, !ws.isEmpty, let n = Double(ws), n > 0 {
                scheduleRow(label: "Worldscale", value: "WS \(Int(n.rounded()))")
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
                Text("No bids yet. Carriers will surface offers here as they come in.")
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
                Spacer(minLength: 0)
                Text("load \(loadId)")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button(action: { Task { await refreshAll() } }) {
                    Text("Retry")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    // Copy the FULL error string + load id to the
                    // clipboard so the founder can paste it into
                    // chat. The error mapper truncates display at
                    // 240 chars; the raw lastError on the store
                    // carries the full trace.
                    let full: String = {
                        let raw = (detailStore.lastError as? LocalizedError)?.errorDescription
                            ?? detailStore.lastError?.localizedDescription
                            ?? message
                        return "load=\(loadId)\n\(raw)"
                    }()
                    UIPasteboard.general.string = full
                } label: {
                    Text("Copy details")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.bgCardSoft)
                        .overlay(Capsule().strokeBorder(palette.borderSoft))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
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
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open live map view")

            Button {
                NotificationCenter.default.post(name: .eusoShipperLoadMessageeSang, object: nil,
                                                userInfo: ["loadId": loadId])
            } label: {
                Text("Message eSang")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask eSang about this load")
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

    /// Strip machine tokens (bracketed enum keys, key=value pairs) that
    /// occasionally bleed into server equipment/cargo display strings,
    /// e.g. "Tanker · Hazmat [tanker_hazmat] · vertical=truck" → "Tanker · Hazmat".
    /// Display-layer only — never apply to values used as lexicon keys
    /// (loadEquipmentRaw) or sent to the server. Never returns empty for
    /// a non-empty input.
    private func cleanLabel(_ s: String) -> String {
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
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: " ·•"))
        // Guard: never return empty for a non-empty input.
        if trimmed.isEmpty { return s.trimmingCharacters(in: .whitespaces) }
        return trimmed
    }

    private func humanCargoType(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "-" }
        switch r.lowercased() {
        case "general":      return "General freight"
        case "hazmat":       return "Hazmat"
        case "petroleum":    return "Petroleum"
        case "gas":          return "Gas"
        case "chemicals":    return "Chemicals"
        case "refrigerated": return "Refrigerated"
        case "container":    return "Container"
        case "bulk":         return "Bulk"
        default:             return cleanLabel(r).capitalized
        }
    }

    private func humanDate(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "-" }
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
        // Surface the actual server error to the user. The previous
        // mapper aggressively rewrote ANY "failed query" string to
        // "schema is out of sync — apply migrations", which was
        // misleading when (a) schema was fully in sync, but (b) the
        // failure was a Drizzle internal error containing "Failed
        // query:" anyway. Confirmed 2026-05-19: all 39 loads columns
        // present on prod, load 1077 selects cleanly in psql — yet
        // iOS still surfaced the "missing column" copy.
        //
        // New triage rules (tightened):
        //   • `unknown column` / `er_bad_field` — true MySQL schema
        //     drift signal. Keep the migration hint.
        //   • Decoding errors (JSONDecoder.DecodingError) — the
        //     server returned a row whose shape the iOS LoadDetail
        //     struct doesn't expect. Surface as "Server response
        //     shape doesn't match" + log the underlying details.
        //   • Anything else — pass through the raw first line so we
        //     stop hiding real errors behind a generic schema hint.
        let raw: String
        if let api = error as? EusoTripAPIError {
            raw = api.eusoUserCopy
        } else if let decode = error as? DecodingError {
            // Log so the device console catches the gory details —
            // the shopper-facing copy stays in user terms.
            print("[ShipperLoadDetail] DecodingError on loads.getById: \(decode)")
            return "EusoTrip couldn't read this load's details — the data came back in a shape this version of the app doesn't expect. Your other loads are unaffected. Pull to refresh, and update the app if it keeps happening."
        } else {
            raw = error.eusoUserCopy
        }
        let lower = raw.lowercased()
        // True MySQL schema-drift signal only.
        if lower.contains("unknown column") || lower.contains("er_bad_field") {
            print("[ShipperLoadDetail] schema-drift error suppressed from UI: \(raw)")
            return "EusoTrip couldn't read this load right now. Your other loads are unaffected — try again shortly."
        }
        // Emergency Wave I1 — SQL-shaped leak gate (iOS belt to S2's
        // server-side braces). Drizzle internals surface as
        // "Failed query: select `id`, `load_number` … from loads …"
        // — a raw SQL dump must NEVER render on the 205 error
        // surface. Map every SQL-shaped message to the friendly
        // deploy-drift copy; the full trace still lands in the
        // device console + the "Copy details" affordance.
        let sqlShaped = lower.contains("failed query")
            || lower.contains("sqlstate")
            || lower.contains("sql syntax")
            || lower.contains("drizzle")
            || lower.contains("er_parse_error")
            || (lower.contains("select ") && lower.contains(" from "))
        if sqlShaped {
            print("[ShipperLoadDetail] SQL-shaped error suppressed from UI: \(raw)")
            return "EusoTrip hit a data error reading this load. Your other loads are unaffected — try again shortly."
        }
        if lower.contains("network") || lower.contains("offline")
            || lower.contains("could not connect") {
            return "EusoTrip can't be reached right now. Pull to refresh once you're back online."
        }
        // Log everything else to the device console for debugging.
        print("[ShipperLoadDetail] raw error on loads.getById: \(raw)")
        // Long messages still fold but we keep the first line so a
        // genuine TRPC user-message ("Load not found", "Permission
        // denied") remains visible.
        let firstLine = raw.split(separator: "\n").first.map(String.init) ?? raw
        return firstLine.count > 240 ? String(firstLine.prefix(240)) + "…" : firstLine
    }

    private func joinLoadRoom() {
        guard let intId = Int(loadId), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.joinLoad(intId)
        }
    }

    private func leaveLoadRoom() {
        guard let intId = Int(loadId), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.leaveLoad(intId)
        }
    }

    private func refreshAll() async {
        detailStore.loadId = loadId
        bidsStore.setLoadId(loadId)
        async let a: Void = detailStore.refresh()
        async let b: Void = bidsStore.refresh()
        async let r: LoadsAPI.DriverReadiness? = (try? await EusoTripAPI.shared.loads.getAssignedDriverReadiness(loadId: loadId))
        async let p: AppointmentsAPI.ByLoadAppointment? = (try? await EusoTripAPI.shared.appointments.getByLoad(loadId: loadId)) ?? nil
        // Wave B — escort attachments; [] on failure keeps the convoy
        // strip honestly hidden.
        async let e: [LoadsAPI.EscortAssignment] = (try? await EusoTripAPI.shared.loads.getEscortAssignment(loadId: loadId)) ?? []
        _ = await (a, b)
        let readiness = await r
        let appointment = await p
        let escorts = await e
        await MainActor.run {
            driverReadiness = readiness
            loadAppointment = appointment
            escortAssignments = escorts
        }
        // Detail (and thus laneForMap coords) is now resolved — fetch the
        // real road geometry for the hero map. Skips vessel legs and folds
        // any failure to the marker-only state inside the loader.
        await refreshCanonicalRoute()
    }

    /// Pull the listing-trust verdict for this load. Verdict comes
    /// straight off the load's `metadata.trust` JSON, computed at
    /// post time and updated on user reports / admin overrides.
    /// Failures fold to nil — the badge silently doesn't render.
    private func loadListingTrust() async {
        struct In: Encodable { let loadId: String }
        let trust: ListingTrust? = try? await EusoTripAPI.shared.query(
            "fraud.getLoadTrust",
            input: In(loadId: loadId)
        )
        await MainActor.run { listingTrust = trust }
    }

    // MARK: - NRC compliance card (Hazmat-7 closure)

    /// Renders the hazmat-7 NRC card when the load's cargo is
    /// radioactive. Read-only on the shipper side — the driver
    /// surfaces (NRCComplianceCard with driverSide:true) ship the
    /// "Log reading" CTA. Closes the final 160 MISSING scenarios
    /// in the 8000-scenario parity audit (cargo type 08).
    @ViewBuilder
    private var nrcCardIfHazmat7: some View {
        if isHazmat7Load {
            NRCComplianceCard(loadId: loadId, driverSide: false)
                .environmentObject(session)
        }
    }

    private var isHazmat7Load: Bool {
        let h = (liveDetail?.hazmatClass ?? "").lowercased()
        let c = (liveDetail?.cargoType ?? "").lowercased()
        // 49 CFR 173.403 / 10 CFR 71 — Class 7 covers RAM. Match
        // the explicit "7" hazmat class first; fall through to the
        // un-number-anchored cargo descriptor.
        if h.contains("7") || h == "class_7" || h == "class 7" { return true }
        if c.contains("radioactive") || c.contains("hazmat-7") || c.contains("class-7") { return true }
        return false
    }

    // MARK: - Driver readiness card (Phase 8 closure)

    /// Pre-pickup view of the assigned driver's eligibility. Renders
    /// a top-line readiness score + the four cert tiles (HOS,
    /// insurance, hazmat, TWIC). Severity coloring driven by the
    /// server-evaluated *DaysRemaining fields so the card flashes
    /// CLEAR / WATCH / WARN / EXPIRED without client-side parsing.
    /// Renders an honest "no driver assigned yet" empty state when
    /// the load hasn't been booked.
    @ViewBuilder
    private var driverReadinessCard: some View {
        if let r = driverReadiness {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("DRIVER READINESS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                    if let s = r.readinessScore {
                        Text("\(s)/100")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                            .foregroundStyle(scoreColor(s))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(scoreColor(s).opacity(0.14),
                                        in: Capsule())
                    }
                }
                if r.driverId == nil {
                    Text("No driver assigned yet")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text(r.driverName ?? "Driver")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    if let carrier = r.carrierName {
                        Text("\(carrier) · USDOT \(r.carrierDot ?? "-") · MC \(r.carrierMc ?? "-")")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                    HStack(spacing: 6) {
                        readinessTile(label: "HOS",       primary: hosPrimary(r), severity: hosSeverity(r))
                        readinessTile(label: "INSURANCE", primary: daysLabel(r.carrierInsuranceDaysRemaining), severity: daysSeverity(r.carrierInsuranceDaysRemaining))
                        readinessTile(label: "HAZMAT",    primary: daysLabel(r.hazmatDaysRemaining),            severity: daysSeverity(r.hazmatDaysRemaining))
                        readinessTile(label: "TWIC",      primary: daysLabel(r.twicDaysRemaining),              severity: daysSeverity(r.twicDaysRemaining))
                    }
                    if !r.readinessFlags.isEmpty {
                        Text(r.readinessFlags
                                .map { $0.uppercased() }
                                .joined(separator: " · ")
                                .replacingOccurrences(of: "_", with: " "))
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(Brand.warning)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func hosPrimary(_ r: LoadsAPI.DriverReadiness) -> String {
        guard let h = r.hosDrivingRemainingHours else { return "-" }
        return String(format: "%.1fh", h)
    }

    private func hosSeverity(_ r: LoadsAPI.DriverReadiness) -> ReadinessSeverity {
        if r.hosCanDrive == false { return .expired }
        guard let h = r.hosDrivingRemainingHours else { return .neutral }
        if h <= 0 { return .expired }
        if h < 1 { return .warn }
        if h < 2 { return .watch }
        return .clear
    }

    private func daysLabel(_ days: Int?) -> String {
        guard let d = days else { return "-" }
        if d <= 0 { return "LAPSED" }
        return "\(d)d"
    }

    private func daysSeverity(_ days: Int?) -> ReadinessSeverity {
        guard let d = days else { return .neutral }
        if d <= 0 { return .expired }
        if d <= 7 { return .warn }
        if d <= 30 { return .watch }
        return .clear
    }

    private enum ReadinessSeverity {
        case clear, watch, warn, expired, neutral
    }

    private func severityColor(_ sev: ReadinessSeverity) -> Color {
        switch sev {
        case .clear:   return Brand.success
        case .watch:   return Brand.warning
        case .warn:    return Brand.danger
        case .expired: return Brand.danger
        case .neutral: return palette.textSecondary
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return Brand.success }
        if score >= 70 { return Brand.warning }
        return Brand.danger
    }

    private func readinessTile(label: String, primary: String, severity: ReadinessSeverity) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(primary)
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .foregroundStyle(severityColor(severity))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperLoadOpenMap         = Notification.Name("eusoShipperLoadOpenMap")
    static let eusoShipperLoadMessageeSang    = Notification.Name("eusoShipperLoadMessageeSang")
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
    RoleNav.shipperLeading(current: .none)
}

private func shipperNavTrailing_205() -> [NavSlot] {
    RoleNav.shipperTrailing(current: .loads)
}

// MARK: - Unresolved placeholder (Emergency Wave I1)

/// What the registry mounts when 205 is reached with NO load context
/// (deep-link alias without an id, catalog walk, or a nav regression).
/// Replaces the old `loadId:"0"` sentinel mount, whose null-as-success
/// server response rendered the loading skeleton forever. Explicit
/// honest state + a real path to the loads list — never a fake detail.
struct ShipperLoadDetailUnresolvedScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    EusoTripEyebrow(verbatim: "SHIPPER · LOAD · DETAIL")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                    Spacer()
                }
                .padding(.top, Space.s5)
                IridescentHairline()
                Spacer(minLength: Space.s5)
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "Select a load",
                    subtitle: "Load detail opens from a specific load. Pick one from your loads list to see its live route, bids, and paperwork.",
                    cta: (label: "Browse loads", action: {
                        NotificationCenter.default.post(
                            name: .eusoShipperLoadListOpen, object: nil)
                    })
                )
                Spacer(minLength: Space.s5)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s3)
        } nav: {
            BottomNav(
                leading: shipperNavLeading_205(),
                trailing: shipperNavTrailing_205(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Previews

#Preview("205 · Shipper · Load Detail · Night") {
    ShipperLoadDetailScreen(
        theme: Theme.dark,
        loadId: "1077",
        previewLoadNumber: "LD-260427-A38FB12C7E",
        previewLane: "Houston, TX → Dallas, TX"
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("205 · Shipper · Load Detail · Afternoon") {
    ShipperLoadDetailScreen(
        theme: Theme.light,
        loadId: "1077",
        previewLoadNumber: "LD-260427-A38FB12C7E",
        previewLane: "Houston, TX → Dallas, TX"
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}

#Preview("205 · Shipper · Unresolved · Night") {
    ShipperLoadDetailUnresolvedScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
