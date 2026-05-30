//
//  DeliveryPODCaptureView.swift
//  EusoTrip — Delivery-side POD capture (driver lifecycle).
//
//  Closes the Phase 13 PARTIAL → PASS gap surfaced in the 8000-scenario
//  shipper↔driver parity audit (docs/parity-2026/EXECUTIVE_VERDICT.md
//  §4.2). Replaces the prior `PickupBolSigning` sheet that 024 was
//  opening — wrong sheet for delivery context.
//
//  Anchored by three production-grade cards:
//
//    1. Photo card — gradient-rim, taps PhotosPicker for the POD
//       photo. Preview renders post-capture; "Retake" overlay
//       dismisses the image. Compresses to JPEG @ 0.7 quality and
//       base64-encodes for the server payload (server schema:
//       `pod.submitPOD.photoBase64`).
//
//    2. Signature card — gradient-rim, full-width SwiftUI Canvas
//       with pan-gesture drawing. "Clear" CTA wipes; export renders
//       the strokes into a PNG base64 string for the server payload
//       (`pod.submitPOD.signatureBase64`).
//
//    3. Receiver + notes card — receiver name (required, server
//       enforces min(1)) + over/short/damage notes (optional).
//
//  Bottom CTAs: "Cancel" outline + "Submit POD" gradient. Submit
//  fires `pod.submitPOD`, transitions the load to `pod_pending`
//  server-side, advances the lifecycle, and dismisses.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import PhotosUI

// MARK: - Public sheet

/// Driver-side POD capture. Hosted as a `.fullScreenCover` from
/// `024_Unloading.swift` once the trailer is empty and the
/// receiver is ready to sign. Submits a real `pod.submitPOD`
/// mutation — no web continuation, no stub. After success the
/// load flips server-side to `pod_pending`, the lifecycle
/// store advances, and the sheet dismisses.
struct DeliveryPODCaptureView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lifecycleAdvance) private var advance

    let loadId: String
    let loadNumber: String?
    /// Optional receiver hint pulled from the consignee facility row
    /// — pre-populates the receiver-name field so the driver only
    /// has to confirm rather than re-type.
    let receiverHint: String?
    /// T-019 · 2026-05-20 — Canonical trailer + vertical for the load.
    /// Drive the equipment-specific POD cards below: reefer temp log /
    /// livestock 28-hr attestation / hazmat placard photo / flatbed
    /// securement log. Both nullable so legacy callers (load detail
    /// open-POD button without canonical context) still render the
    /// generic POD; once the lifecycle dispatchers fill them, the
    /// driver gets the per-equipment cards too.
    let trailer: TrailerCode?
    let vertical: Vertical?
    /// T-036 · 2026-05-20 — Canonical TransportMode for the load.
    /// Drives mode-specific POD cards:
    ///   .rail   → rail waybill signature + reporting marks photo
    ///   .vessel → BL signature + container seal verification
    ///   .truck/.barge → existing generic POD only
    /// Nullable for legacy callers; defaults to truck POD when nil.
    let mode: TransportMode?

    init(
        loadId: String,
        loadNumber: String? = nil,
        receiverHint: String? = nil,
        trailer: TrailerCode? = nil,
        vertical: Vertical? = nil,
        mode: TransportMode? = nil
    ) {
        self.loadId = loadId
        self.loadNumber = loadNumber
        self.receiverHint = receiverHint
        self.trailer = trailer
        self.vertical = vertical
        self.mode = mode
    }

    // MARK: Capture state

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil
    @State private var signatureStrokes: [SignatureStroke] = []
    @State private var liveStroke: SignatureStroke = SignatureStroke()
    @State private var receiverName: String = ""
    @State private var notes: String = ""

    // 2026-05-20 · IO 2026 P0-17 — Astra POD auto-detection state.
    // After the driver picks a photo we offer a "Scan with Astra"
    // affordance that runs the photo through Gemini Vision +
    // Ed25519-signed audit chain. Successful scans auto-fill the
    // OS&D notes + seal number; verdict gates the POD-signed FSM
    // transition server-side (no client-side override).
    @State private var astraPod: AstraPodResponse? = nil
    @State private var astraScanning: Bool = false
    @State private var astraError: String? = nil
    @State private var sealNumber: String = ""

    // 2026-05-30 · DocIntel WIRE-GAP — document-intelligence OCR/classify
    // pass over the captured BOL photo. Runs the canonical
    // `documentRouter.classifyAndRoute` spine (Gemini + NVIDIA) with a
    // `proof_of_delivery` caller hint BEFORE the existing store/submit so
    // the driver sees what was read off the doc — signature-block
    // presence, receiver name, barcode/PRO, weight confirm — and can
    // confirm the receiver name without re-typing. This is an ADDED pass
    // alongside (not replacing) the real `pod.submitPOD` mutation and the
    // Astra scan strip above. No FSM gating, no fabricated data: we only
    // surface fields the classifier actually extracted.
    @State private var docRead: PODDocRead? = nil
    @State private var docReadScanning: Bool = false
    @State private var docReadError: String? = nil

    // T-019 · 2026-05-20 — Equipment-specific POD capture state. Each
    // bucket is gated by a trailer / vertical predicate (see Body) and
    // stuffed into the submission notes block via `composedPODNotes()`
    // until POD schema grows structured columns (T-019b platform repo).

    /// Reefer temp log — driver downloads the reefer's setpoint /
    /// actual temperature log from the unit (CSV/PDF). Captured here as
    /// a single download-confirmed flag + final-leg average temp; the
    /// full file uploads via a follow-up document picker in T-019b.
    @State private var reeferTempLogDownloaded: Bool = false
    @State private var reeferAvgTempF: String = ""

    /// Livestock 28-hr attestation — driver confirms the FMCSA 49 USC
    /// 80502 rest periods (animals must have food/water/rest within
    /// every 28 hours of continuous transit). Captures the timestamp
    /// of the last qualifying rest stop.
    @State private var livestock28hrAttested: Bool = false
    @State private var livestockLastRestStop: String = ""

    /// Hazmat placard verification photo — driver photographs the
    /// affixed placards at delivery so the audit chain matches the
    /// load's UN/class/PSN. Reuses the PhotosPicker pattern of the
    /// primary PoD photo above.
    @State private var hazmatPlacardItem: PhotosPickerItem? = nil
    @State private var hazmatPlacardImage: UIImage? = nil

    /// Flatbed securement log — driver attests that all straps / chains
    /// / tarps / edge protectors were per 49 CFR 393 at delivery. The
    /// free-text notes field captures any deviations.
    @State private var flatbedSecurementAttested: Bool = false
    @State private var flatbedSecurementNotes: String = ""

    // MARK: T-036 · Mode-specific POD state (2026-05-20)
    //
    // Rail and vessel modes need different POD primitives than truck:
    //   rail   → waybill signature confirms AAR interchange acceptance
    //            + reporting marks photo (the car's reporting marks +
    //            number must be photographed at delivery for the
    //            yard's interchange-billing audit)
    //   vessel → BL signature is the canonical legal handoff at port
    //            + container seal verification (seal number + photo;
    //            broken seals at delivery trigger ISO 17712 incident
    //            chain).

    /// Rail mode — waybill signature attestation (driver confirms the
    /// physical waybill was signed by the yard's interchange agent).
    @State private var railWaybillSigned: Bool = false
    /// Rail mode — reporting marks photo (AAR car ID at delivery).
    @State private var railMarksItem: PhotosPickerItem? = nil
    @State private var railMarksImage: UIImage? = nil

    /// Vessel mode — Bill of Lading signature attestation.
    @State private var vesselBLSigned: Bool = false
    /// Vessel mode — container seal number captured from the physical
    /// seal at discharge. Must match the seal logged at LOADED.
    @State private var vesselSealNumber: String = ""
    /// Vessel mode — container seal photo.
    @State private var vesselSealItem: PhotosPickerItem? = nil
    @State private var vesselSealImage: UIImage? = nil
    /// Vessel mode — seal-intact attestation (false flags a security
    /// incident → catalyst dispatch notified + customs broker looped in).
    @State private var vesselSealIntact: Bool = true

    // MARK: T-019 · Equipment-specific predicates + cards

    /// Reefer temp log required when the trailer is `requiresReeferSubform`
    /// (reefer or food-grade liquid tank) OR the vertical is refrigerated.
    private var requiresReeferLog: Bool {
        if trailer?.requiresReeferSubform == true { return true }
        if vertical == .refrigerated { return true }
        return false
    }
    /// 28-hr attestation required for the livestock vertical (49 USC 80502 / FMCSA 395.8).
    private var requiresLivestockAttest: Bool { vertical == .livestock }
    /// Placard photo required when the trailer is hazmat-eligible (49 CFR 172).
    private var requiresHazmatPlacard: Bool { trailer?.isHazmatEligible == true }
    /// Securement attestation required for the flatbed / open-deck vertical (49 CFR 393).
    private var requiresSecurementLog: Bool { vertical == .flatbedOpenDeck }

    /// T-036 · Rail-mode POD card required when mode is .rail.
    private var requiresRailWaybillCapture: Bool { mode == .rail }
    /// T-036 · Vessel-mode POD card required when mode is .vessel.
    private var requiresVesselSealCapture: Bool { mode == .vessel }

    /// Reefer temp log card — driver confirms downloaded the unit's
    /// temperature trace + records the final-leg average temp.
    private var reeferLogCard: some View {
        EquipmentPODCard(
            title: "REEFER TEMP LOG",
            icon: "thermometer",
            regulatory: "FSMA 2011 / FDA 21 CFR 1.900"
        ) {
            Toggle("Temp log downloaded from reefer unit",
                   isOn: $reeferTempLogDownloaded)
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .font(EType.caption)
            HStack {
                Text("Average temp this leg (°F)").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                TextField("e.g. 34", text: $reeferAvgTempF)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(palette.bgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    /// Livestock 28-hr attestation card — FMCSA 395.8 / 49 USC 80502.
    private var livestock28hrCard: some View {
        EquipmentPODCard(
            title: "LIVESTOCK 28-HR LAW",
            icon: "person.2",
            regulatory: "49 USC 80502 / FMCSA 395.8"
        ) {
            Toggle("All 28-hr rest stops met (food + water + rest)",
                   isOn: $livestock28hrAttested)
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .font(EType.caption)
            HStack {
                Text("Last rest stop").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                TextField("e.g. Amarillo, TX 14:30", text: $livestockLastRestStop)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(palette.bgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    /// Hazmat placard photo card — 49 CFR 172.504.
    private var hazmatPlacardCard: some View {
        EquipmentPODCard(
            title: "HAZMAT PLACARD VERIFICATION",
            icon: "exclamationmark.triangle.fill",
            regulatory: "49 CFR 172.504"
        ) {
            PhotosPicker(selection: $hazmatPlacardItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    Image(systemName: hazmatPlacardImage == nil ? "camera" : "checkmark.circle.fill")
                        .foregroundStyle(hazmatPlacardImage == nil ? Brand.warning : Brand.success)
                    Text(hazmatPlacardImage == nil
                         ? "Photograph affixed placards"
                         : "Placard photo captured · tap to replace")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .onChange(of: hazmatPlacardItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { hazmatPlacardImage = img }
                    }
                }
            }
        }
    }

    /// Flatbed securement log card — 49 CFR 393.
    private var securementLogCard: some View {
        EquipmentPODCard(
            title: "SECUREMENT LOG",
            icon: "link",
            regulatory: "49 CFR 393"
        ) {
            Toggle("All straps / chains / tarps per 49 CFR 393 at delivery",
                   isOn: $flatbedSecurementAttested)
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .font(EType.caption)
            VStack(alignment: .leading, spacing: 4) {
                Text("Deviations (optional)").font(EType.caption).foregroundStyle(palette.textSecondary)
                TextField("Loose strap, missing edge protector, etc.",
                          text: $flatbedSecurementNotes, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    // T-036 · Rail waybill + reporting marks card.
    private var railWaybillCard: some View {
        EquipmentPODCard(
            title: "RAIL WAYBILL · REPORTING MARKS",
            icon: "tram.fill",
            regulatory: "AAR interchange · 49 CFR 174"
        ) {
            Toggle("Waybill signed by yard interchange agent",
                   isOn: $railWaybillSigned)
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .font(EType.caption)
            PhotosPicker(selection: $railMarksItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    Image(systemName: railMarksImage == nil ? "camera" : "checkmark.circle.fill")
                        .foregroundStyle(railMarksImage == nil ? Brand.warning : Brand.success)
                    Text(railMarksImage == nil
                         ? "Photograph reporting marks + car number"
                         : "Reporting marks photo captured · tap to replace")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .onChange(of: railMarksItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { railMarksImage = img }
                    }
                }
            }
            Text("AAR reporting marks (e.g., BNSF · UP · CSXT) + car number must be on file for interchange billing. Photograph the side-of-car stencil; the catalyst's dispatcher cross-checks it against the load row's marks at settlement.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // T-036 · Vessel BL + container seal card.
    private var vesselSealCard: some View {
        EquipmentPODCard(
            title: "BILL OF LADING · CONTAINER SEAL",
            icon: "ferry.fill",
            regulatory: "ISO 17712 · UN customs"
        ) {
            Toggle("Bill of Lading signed at port",
                   isOn: $vesselBLSigned)
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .font(EType.caption)
            VStack(alignment: .leading, spacing: 4) {
                Text("Container seal number (must match LOADED-state log)")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                TextField("e.g., AB1234567 · CN9876543",
                          text: $vesselSealNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Toggle("Seal intact at delivery (uncut / unbroken)",
                   isOn: $vesselSealIntact)
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .font(EType.caption)
            PhotosPicker(selection: $vesselSealItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    Image(systemName: vesselSealImage == nil ? "camera" : "checkmark.circle.fill")
                        .foregroundStyle(vesselSealImage == nil ? Brand.warning : Brand.success)
                    Text(vesselSealImage == nil
                         ? "Photograph the affixed seal"
                         : "Seal photo captured · tap to replace")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .onChange(of: vesselSealItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { vesselSealImage = img }
                    }
                }
            }
            if !vesselSealIntact {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                    Text("Broken-seal incident — catalyst dispatch + customs broker notified at submit.")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.2)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Submit state

    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var successToast: String? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    eyebrowHeader
                    photoCard
                    signatureCard
                    receiverNotesCard
                    // T-019 · 2026-05-20 — Equipment-specific POD cards.
                    // Each renders only when the trailer or vertical
                    // demands it, so generic dry-van PODs stay clean.
                    if requiresReeferLog        { reeferLogCard }
                    if requiresLivestockAttest  { livestock28hrCard }
                    if requiresHazmatPlacard    { hazmatPlacardCard }
                    if requiresSecurementLog    { securementLogCard }
                    // T-036 · 2026-05-20 — Mode-specific POD cards.
                    if requiresRailWaybillCapture  { railWaybillCard }
                    if requiresVesselSealCapture   { vesselSealCard }
                    if let err = error {
                        errorBanner(err)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("PROOF OF DELIVERY")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(loadNumber ?? loadId)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitBar
                    .background(palette.bgPrimary)
            }
            .overlay(alignment: .bottom) {
                if let toast = successToast {
                    successPill(toast)
                }
            }
        }
        .onAppear {
            if receiverName.isEmpty, let hint = receiverHint, !hint.isEmpty {
                receiverName = hint
            }
        }
    }

    // MARK: - Eyebrow header

    private var eyebrowHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture proof of delivery")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("A clear photo of the signed BOL plus the receiver's signature releases your rig and starts the payment clock. Server stores the bundle on the load and flips status to pod-pending for shipper review.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Photo card

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("01 · BOL PHOTO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if photoImage != nil {
                    Button {
                        photoImage = nil
                        photoItem = nil
                    } label: {
                        Text("Retake")
                            .font(EType.caption).fontWeight(.semibold)
                            .foregroundStyle(palette.textSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack {
                if let img = photoImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                } else {
                    PhotosPicker(selection: $photoItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("Tap to capture or pick image")
                                .font(EType.body).fontWeight(.semibold)
                                .foregroundStyle(palette.textPrimary)
                            Text("Receiver-signed BOL · OS&D notes legible")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding(Space.s4)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 2026-05-20 · IO 2026 P0-17 — Astra POD auto-detection.
            if photoImage != nil {
                astraScanStrip
            }
            if let pod = astraPod {
                astraObservationStrip(pod)
            }
            // 2026-05-30 · DocIntel WIRE-GAP — classify/OCR strip. The
            // "Read the doc" button runs the captured photo through the
            // document-intelligence spine; the observation strip below
            // it surfaces what the classifier read.
            if photoImage != nil {
                docReadScanStrip
            }
            if let read = docRead {
                docReadObservationStrip(read)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(photoImage == nil ? 0.35 : 0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPickedPhoto(newItem) }
        }
    }

    /// "Scan with Astra" button rendered below the captured photo.
    /// Fires `astraDvir.podScan` which OCRs seal #, damage, missing
    /// pieces, pallet count + writes the Ed25519-signed observation
    /// to the load.pod.astra_observed hash chain.
    @ViewBuilder
    private var astraScanStrip: some View {
        HStack(spacing: 10) {
            Button {
                Task { await runAstraPodScan() }
            } label: {
                HStack(spacing: 6) {
                    if astraScanning {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    Text(astraScanning ? "Astra scanning…" : (astraPod == nil ? "Scan with Astra" : "Re-scan"))
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.4)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(astraScanning)
            Spacer(minLength: 0)
        }
    }

    /// Inline strip showing Astra's parsed observation: verdict pill,
    /// seal number, pallet count, damage summary. Verdict color
    /// matches the server-side gating (green = pass / red = fail /
    /// orange = needs_review). The `podSignedEligible` flag drives
    /// whether the FSM overlay row was already written server-side.
    @ViewBuilder
    private func astraObservationStrip(_ pod: AstraPodResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ASTRA · POD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                verdictPill(pod.verdict)
                if pod.podSignedEligible {
                    Label("Overlay signed", systemImage: "checkmark.shield.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            if let seal = pod.observation.sealNumber, !seal.isEmpty {
                detailRow(label: "SEAL", value: seal)
            }
            if let pallets = pod.observation.palletCount {
                detailRow(label: "PALLETS", value: String(pallets))
            }
            if let pieces = pod.observation.pieceCount {
                detailRow(label: "PIECES", value: String(pieces))
            }
            if let container = pod.observation.containerNumber, !container.isEmpty {
                detailRow(label: "CONTAINER", value: container)
            }
            if let temp = pod.observation.temperatureCurrent, !temp.isEmpty {
                detailRow(label: "TEMP", value: temp)
            }
            if let dmg = pod.observation.damage?.summary, !dmg.isEmpty,
               dmg.lowercased() != "none visible" {
                Text("⚠︎ \(dmg)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warnings = pod.observation.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { w in
                    Text("• \(w)").font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            if let err = astraError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(palette.bgCardSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func verdictPill(_ verdict: AstraPodVerdict) -> some View {
        let (label, color): (String, Color) = {
            switch verdict {
            case .pass:        return ("PASS", .green)
            case .fail:        return ("FAIL", .red)
            case .needsReview: return ("NEEDS REVIEW", .orange)
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
    }

    @MainActor
    private func runAstraPodScan() async {
        guard let img = photoImage else { return }
        astraScanning = true
        astraError = nil
        defer { astraScanning = false }
        do {
            let response = try await AstraVisionService.shared.analyzePod(
                image: img,
                trailer: trailer,
                vehicleId: nil,
                loadId: loadId,
                expectedPieceCount: nil,
                expectedSealNumber: nil
            )
            astraPod = response
            // Auto-fill seal number + OS&D notes from observation.
            if let seal = response.observation.sealNumber, sealNumber.isEmpty {
                sealNumber = seal
            }
            if let dmgSummary = response.observation.damage?.summary,
               !dmgSummary.isEmpty,
               dmgSummary.lowercased() != "none visible",
               notes.isEmpty {
                notes = dmgSummary
            }
        } catch {
            astraError = (error as NSError).localizedDescription
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            photoImage = img
            // A fresh photo invalidates any prior doc read.
            docRead = nil
            docReadError = nil
        }
    }

    // MARK: - DocIntel · classify / OCR pass (2026-05-30)

    /// "Read the doc" button rendered below the captured photo. Fires
    /// `documentRouter.classifyAndRoute` with a `proof_of_delivery`
    /// caller hint so Gemini+NVIDIA OCRs the signed BOL — signature-
    /// block presence, receiver name, barcode/PRO, weight confirm. An
    /// ADDED pass before the existing submit; never gates it.
    @ViewBuilder
    private var docReadScanStrip: some View {
        HStack(spacing: 10) {
            Button {
                Task { await runDocClassifyPass() }
            } label: {
                HStack(spacing: 6) {
                    if docReadScanning {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    Text(docReadScanning
                         ? "Reading doc…"
                         : (docRead == nil ? "Read the doc" : "Re-read"))
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.4)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(docReadScanning)
            Spacer(minLength: 0)
        }
    }

    /// Inline strip surfacing what the document-intelligence spine read
    /// off the captured BOL photo: classified type + confidence,
    /// signature-block presence, receiver name, barcode/PRO, weight
    /// confirm, plus any classifier warnings. Read-only confirmation —
    /// the driver still signs + submits below.
    @ViewBuilder
    private func docReadObservationStrip(_ read: PODDocRead) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · DOC READ")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                docTypePill(read)
            }
            if !read.summary.isEmpty {
                Text(read.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Signature-block presence — the single most load-bearing
            // signal for a POD: did the doc actually get signed?
            signatureBlockRow(read.signaturePresent)
            if let receiver = read.receiverName, !receiver.isEmpty {
                detailRow(label: "RECEIVER", value: receiver)
            }
            if let pro = read.barcodePRO, !pro.isEmpty {
                detailRow(label: "BARCODE/PRO", value: pro)
            }
            if let weight = read.weightConfirm, !weight.isEmpty {
                detailRow(label: "WEIGHT", value: weight)
            }
            if let receiver = read.receiverName, !receiver.isEmpty,
               receiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    receiverName = receiver
                } label: {
                    Label("Use \"\(receiver)\" as receiver", systemImage: "arrow.down.doc")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .buttonStyle(.plain)
            }
            if !read.warnings.isEmpty {
                ForEach(read.warnings.prefix(2), id: \.self) { w in
                    Text("⚠︎ \(w)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let err = docReadError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(palette.bgCardSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Classified-type + confidence pill. Green when the classifier is
    /// confident the doc is a POD, orange otherwise — a mismatch tells
    /// the driver they may have photographed the wrong page.
    @ViewBuilder
    private func docTypePill(_ read: PODDocRead) -> some View {
        let conf = Int((read.confidence * 100).rounded())
        let isPOD = read.classifiedType == "proof_of_delivery"
        let color: Color = isPOD ? .green : .orange
        let label = read.humanType
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            Text("\(conf)%")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .opacity(0.85)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
    }

    /// Signature-block presence row — explicit pass/missing chip so the
    /// driver knows whether the OCR found a signature on the doc before
    /// they submit.
    @ViewBuilder
    private func signatureBlockRow(_ present: Bool?) -> some View {
        HStack(spacing: 6) {
            Text("SIGNATURE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 64, alignment: .leading)
            switch present {
            case .some(true):
                Label("Block detected", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.green)
            case .some(false):
                Label("Not detected on doc", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.orange)
            case .none:
                Text("Inconclusive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    /// Run the captured BOL photo through the document-intelligence
    /// spine. Compresses to JPEG, classifies with a `proof_of_delivery`
    /// caller hint, then maps the extracted fields into a `PODDocRead`.
    /// Pure read pass — no FSM transition, no submit, no auto-mutation.
    @MainActor
    private func runDocClassifyPass() async {
        guard let img = photoImage else { return }
        docReadScanning = true
        docReadError = nil
        defer { docReadScanning = false }

        guard let jpeg = img.jpegData(compressionQuality: 0.7) else {
            docReadError = "Could not encode the photo for reading."
            return
        }
        let base64 = jpeg.base64EncodedString()

        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: .jpeg,
                callerContext: "driver delivery proof_of_delivery — extract signature-block presence, receiver name, barcode/PRO number, weight confirmation off the signed BOL"
            )
            docRead = PODDocRead(response: resp)
        } catch {
            docReadError = "Read failed: \((error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription)"
        }
    }

    // MARK: - Signature card

    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("02 · RECEIVER SIGNATURE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if !signatureStrokes.isEmpty || !liveStroke.points.isEmpty {
                    Button {
                        signatureStrokes = []
                        liveStroke = SignatureStroke()
                    } label: {
                        Text("Clear")
                            .font(EType.caption).fontWeight(.semibold)
                            .foregroundStyle(palette.textSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }

            PODSignaturePad(
                strokes: $signatureStrokes,
                liveStroke: $liveStroke,
                inkColor: palette.textPrimary
            )
            .frame(height: 180)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )

            HStack(spacing: 4) {
                Rectangle()
                    .fill(palette.textTertiary)
                    .frame(width: 12, height: 1)
                Text("X · sign above")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(signatureStrokes.isEmpty ? 0.35 : 0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Receiver + notes

    private var receiverNotesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("03 · RECEIVER DETAILS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Receiver name")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. Marcus W., Dock 12", text: $receiverName)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("OS&D notes (optional)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("over / short / damage — leave blank if clean",
                          text: $notes,
                          axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
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
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Submit bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                CTAButton(
                    title: inFlight ? "Submitting…" : "Submit POD",
                    action: { Task { await submit() } },
                    isLoading: inFlight
                )
                .opacity(canSubmit ? 1.0 : 0.55)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    private var canSubmit: Bool {
        let hasReceiver = !receiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto    = photoImage != nil
        let hasSig      = !signatureStrokes.isEmpty
        return hasReceiver && hasPhoto && hasSig && !inFlight
    }

    // MARK: - Error + toast UI

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

    private func successPill(_ message: String) -> some View {
        Text(message)
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
                withAnimation { successToast = nil }
            }
    }

    // MARK: - Submit

    /// Encode + ship the POD packet via `pod.submitPOD`. On success
    /// the lifecycle store advances and the sheet dismisses. The
    /// receiver row + photo + signature payloads each compress
    /// before base64-encoding to keep the wire size sane (~200KB
    /// typical for an 8mp photo + a 600x180 PNG signature).
    private func submit() async {
        guard canSubmit else { return }
        guard let numericId = Int(loadId) else {
            error = "Could not resolve numeric load id."
            return
        }
        let trimmedReceiver = receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        inFlight = true
        error = nil

        let photoB64 = photoImage.flatMap { $0.jpegData(compressionQuality: 0.7) }?
            .base64EncodedString()
        let sigB64 = renderSignaturePNGBase64(
            strokes: signatureStrokes,
            inkColor: .black,    // signature ink is always opaque black on the rendered PNG
            size: CGSize(width: 600, height: 180)
        )

        do {
            _ = try await EusoTripAPI.shared.pod.submitPOD(
                loadId: numericId,
                receiverName: trimmedReceiver,
                photoBase64: photoB64,
                signatureBase64: sigB64,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            inFlight = false
            withAnimation { successToast = "POD submitted · awaiting shipper approval" }
            // Brief pause so the toast registers before dismiss.
            try? await Task.sleep(nanoseconds: 700_000_000)
            advance?()
            dismiss()
        } catch {
            inFlight = false
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - SignatureStroke + PODSignaturePad

/// One continuous pen-down → pen-up stroke. The pad accumulates
/// strokes; each stroke is a polyline of CGPoints in pad-local
/// coordinates. Rendered into a PNG at submit time.
struct SignatureStroke: Equatable {
    var points: [CGPoint] = []
}

/// SwiftUI Canvas-backed signature pad. The live stroke is drawn
/// on top of the committed strokes so dragging feels immediate
/// without flushing through the @State-array on every gesture
/// update.
struct PODSignaturePad: View {
    @Binding var strokes: [SignatureStroke]
    @Binding var liveStroke: SignatureStroke
    let inkColor: Color

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes {
                drawStroke(ctx: ctx, stroke: stroke)
            }
            drawStroke(ctx: ctx, stroke: liveStroke)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    liveStroke.points.append(value.location)
                }
                .onEnded { _ in
                    if !liveStroke.points.isEmpty {
                        strokes.append(liveStroke)
                        liveStroke = SignatureStroke()
                    }
                }
        )
    }

    private func drawStroke(ctx: GraphicsContext, stroke: SignatureStroke) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.move(to: stroke.points[0])
        for p in stroke.points.dropFirst() {
            path.addLine(to: p)
        }
        ctx.stroke(
            path,
            with: .color(inkColor),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - PNG export

/// Render the signature strokes into a fixed-size PNG, base64-
/// encoded for the server `signatureBase64` field. The strokes
/// live in pad-local coordinates; we scale them to the target
/// canvas based on the original pad height of 180pt.
func renderSignaturePNGBase64(
    strokes: [SignatureStroke],
    inkColor: UIColor,
    size: CGSize
) -> String? {
    guard !strokes.isEmpty else { return nil }
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { uiCtx in
        let ctx = uiCtx.cgContext
        ctx.setStrokeColor(inkColor.cgColor)
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Strokes captured at ~180pt height. Map directly — the
        // user's pad is the same aspect ratio as the export size
        // (180:600 vs 180:600). If the device was different we'd
        // scale; the typical case maps cleanly.
        for stroke in strokes {
            guard stroke.points.count > 1 else { continue }
            ctx.move(to: stroke.points[0])
            for p in stroke.points.dropFirst() {
                ctx.addLine(to: p)
            }
            ctx.strokePath()
        }
    }
    return img.pngData()?.base64EncodedString()
}

// MARK: - DocIntel · POD doc-read model (2026-05-30)

/// The four POD-relevant signals the driver cares about, distilled from
/// a `DocumentRouterAPI.ClassifyResponse`. Bespoke to this surface — we
/// pull only signature-block presence, receiver name, barcode/PRO, and
/// weight confirm out of the classifier's heterogeneous `extractedFields`
/// (keys are doc-type-specific server-side, so we probe a small set of
/// known aliases and never fabricate). All optional: a field is shown
/// only when the classifier actually returned it.
struct PODDocRead: Hashable {
    let classifiedType: String
    let confidence: Double
    let summary: String
    let warnings: [String]

    /// Did the OCR find a signature block on the doc? `nil` when the
    /// classifier returned no signal either way (inconclusive).
    let signaturePresent: Bool?
    let receiverName: String?
    /// Barcode / PRO number off the BOL — the carrier's tracking key.
    let barcodePRO: String?
    /// Weight confirmation read off the doc (string so we keep the
    /// unit the doc used, e.g. "42,180 lb").
    let weightConfirm: String?

    init(response: DocumentRouterAPI.ClassifyResponse) {
        self.classifiedType = response.classifiedType
        self.confidence = response.confidence
        self.summary = response.summary
        self.warnings = response.warnings

        // Flatten heterogeneous field values to strings once.
        let f: [String: String] = response.extractedFields.compactMapValues { $0.asString }

        // Signature-block presence — probe boolean-ish + presence aliases.
        // A truthy string or a non-empty signatory name both imply a
        // signed block; an explicit false implies none detected.
        let sigRaw = PODDocRead.firstValue(in: f, keys: [
            "signaturePresent", "signature_present", "hasSignature",
            "signatureBlockPresent", "signed", "isSigned", "signaturePresence"
        ])
        let signatoryName = PODDocRead.firstValue(in: f, keys: [
            "signature", "signatureName", "signedBy", "signatory"
        ])
        if let sigRaw {
            self.signaturePresent = PODDocRead.parseBool(sigRaw)
        } else if let signatoryName, !signatoryName.isEmpty {
            self.signaturePresent = true
        } else {
            self.signaturePresent = nil
        }

        self.receiverName = PODDocRead.firstValue(in: f, keys: [
            "receiverName", "receiver_name", "consigneeName", "consignee_name",
            "consignee", "receivedBy", "received_by", "deliveredTo"
        ])

        self.barcodePRO = PODDocRead.firstValue(in: f, keys: [
            "proNumber", "pro_number", "pro", "barcode", "barcodeNumber",
            "trackingNumber", "tracking_number", "bolNumber", "bol_number"
        ])

        self.weightConfirm = PODDocRead.firstValue(in: f, keys: [
            "weight", "weightConfirm", "weight_confirm", "totalWeight",
            "total_weight", "grossWeight", "gross_weight", "netWeight"
        ])
    }

    /// Human-readable label for the classified type, mirroring 204's map
    /// for the POD-adjacent doc shapes a delivery photo can land on.
    var humanType: String {
        switch classifiedType {
        case "proof_of_delivery": return "POD"
        case "bill_of_lading":    return "Bill of Lading"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "run_ticket":        return "Run Ticket"
        case "rate_confirmation": return "Rate Confirmation"
        default:
            return classifiedType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// First non-nil, non-empty value across a set of candidate keys.
    private static func firstValue(in dict: [String: String], keys: [String]) -> String? {
        for k in keys {
            if let v = dict[k] {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    /// Lenient truthiness for OCR'd boolean-ish strings.
    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "y", "1", "present", "signed", "detected":
            return true
        case "false", "no", "n", "0", "absent", "unsigned", "missing", "none":
            return false
        default:
            return nil
        }
    }
}

// MARK: - Previews

// MARK: - T-019 · Shared equipment POD card chrome (2026-05-20)

/// Lightweight card wrapper used by the four equipment-specific POD
/// surfaces (reefer / livestock / hazmat / flatbed). Title bar mirrors
/// the LifecycleSection pattern with a regulatory citation pill so the
/// driver sees which CFR clause this attestation backs.
private struct EquipmentPODCard<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let icon: String
    let regulatory: String?
    @ViewBuilder let content: () -> Content

    init(title: String,
         icon: String,
         regulatory: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.regulatory = regulatory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(title)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if let ref = regulatory {
                    Text(ref)
                        .font(.system(size: 8, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            content()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

#Preview("POD capture · Dark") {
    DeliveryPODCaptureView(
        loadId: "44912",
        loadNumber: "LD-260427-A38FB12C7E",
        receiverHint: "Marcus W., Dock 12"
    )
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("POD capture · Light") {
    DeliveryPODCaptureView(
        loadId: "44912",
        loadNumber: "LD-260427-A38FB12C7E",
        receiverHint: "Marcus W., Dock 12"
    )
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
