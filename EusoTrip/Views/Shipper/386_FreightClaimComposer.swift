//
//  386_FreightClaimComposer.swift
//  EusoTrip — Shipper · Freight claim composer (Arc N).
//

import SwiftUI
import PhotosUI

struct FreightClaimComposerScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var initialClaimType: String = "damage"
    var body: some View {
        Shell(theme: theme) { ClaimComposerBody(loadId: loadId, claimType: initialClaimType) } nav: { shipperLifecycleNav() }
    }
}

private struct ClaimComposerBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State var claimType: String
    @State private var amount: Double? = nil
    @State private var description: String = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photo: UIImage? = nil
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    // ESANG document router — classify the evidence so the claim file
    // knows what it's looking at (damage photo / BOL / POD) instead of
    // shipping a raw image. Runs alongside, never blocks, the upload.
    @State private var classifying = false
    @State private var classification: DocumentRouterAPI.ClassifyResponse? = nil
    @State private var classifyError: String? = nil

    // Historical-weather evidence (Wave-4 server #85). When the claim is a
    // weather-peril type, the composer auto-attaches a CITED weather.historical
    // report via freightClaims.attachHistoricalWeatherEvidence so the carrier-
    // insurance file carries the contemporaneous readings (gust / visibility /
    // peak condition) that prove the peril. HONEST: the evidence is
    // Enterprise-gated → available:false today → we render the ENTERPRISE
    // state ("evidence available with the enterprise feed"), NEVER a fabricated
    // report. The toggle is user-opt; default-on for the weather-peril types.
    @State private var attachWeather = false
    @State private var weatherLoading = false
    @State private var weatherEvidence: HistoricalWeatherEvidence? = nil
    @State private var weatherError: String? = nil

    private let claimTypes = ["damage", "shortage", "loss", "delay", "contamination", "reefer_excursion", "weather", "other"]

    /// The claim types whose root cause is a weather peril — these default the
    /// historical-weather evidence toggle ON and surface the attach section.
    private static let weatherPerilTypes: Set<String> = ["weather", "delay", "reefer_excursion", "contamination"]
    private var isWeatherPeril: Bool { Self.weatherPerilTypes.contains(claimType) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Claim filed. Carrier insurance + Eusorone ops will respond within 24 hours.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                typeCard
                amountCard
                descriptionCard
                if isWeatherPeril { historicalWeatherCard }
                evidenceCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        // Weather-peril types default the historical-weather attach ON. Picking
        // a non-peril type tears down the evidence + toggle so a damage/loss
        // claim never carries a stale weather record.
        .onChange(of: claimType) { _, _ in
            if isWeatherPeril {
                if !attachWeather { attachWeather = true }
            } else {
                attachWeather = false
                weatherEvidence = nil
                weatherError = nil
            }
        }
        .onAppear { if isWeatherPeril { attachWeather = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · FREIGHT CLAIM").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("File a freight claim").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var typeCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM TYPE", icon: "tag")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(claimTypes, id: \.self) { t in
                        Button { claimType = t } label: {
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(claimType == t ? .white : palette.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(claimType == t ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var amountCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM AMOUNT (USD)", icon: "dollarsign.circle")
            TextField("e.g. 2400", value: $amount, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var descriptionCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DESCRIPTION", icon: "text.alignleft")
            TextField("What happened, when, where?", text: $description, axis: .vertical).lineLimit(4...10).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Historical weather evidence (freightClaims.attachHistoricalWeatherEvidence)

    /// Auto-attaches a CITED weather.historical report to a weather-peril claim.
    /// Bespoke: the sky condition renders via WeatherIcons (the live weatherCode
    /// glyph), the gust/visibility/alert metrics via utility glyphs — ZERO SF
    /// Symbols on the weather row. HONEST: the report is Enterprise-gated, so
    /// today the server returns available:false → we render the ENTERPRISE
    /// state ("evidence available with the enterprise feed") that reads now and
    /// lights the instant the key lands. We NEVER fabricate a report/peril/snapshot.
    private var historicalWeatherCard: some View {
        LifecycleCard {
            HStack(spacing: 6) {
                WeatherIcons.utility(.alert, size: 11, tint: Brand.info)
                Text("HISTORICAL WEATHER · EVIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // Opt-in toggle. Default-on for weather-peril types; the shipper
                // can drop it for a claim that isn't actually weather-caused.
                Button { attachWeather.toggle() } label: {
                    Text(attachWeather ? "ATTACHED" : "ATTACH")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(attachWeather ? .white : palette.textPrimary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(attachWeather ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Text("Pulls the contemporaneous National Weather Service reading at the load's position + window — gusts, visibility, and the peak condition that prove the peril — and files it as a cited weather.historical record on the claim.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if attachWeather { weatherEvidencePanel }
        }
    }

    @ViewBuilder
    private var weatherEvidencePanel: some View {
        if weatherLoading {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                Text("Pulling historical weather…").font(EType.caption).foregroundStyle(palette.textTertiary)
            }
        } else if let err = weatherError {
            Text("Couldn't pull the historical weather, \(err). Your claim will still file; you can re-attach the report from the claim file.")
                .font(EType.caption).foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if let ev = weatherEvidence {
            if ev.available == true, let snap = ev.snapshot {
                // LIVE (enterprise key present) — a real cited report. Bespoke
                // sky glyph + utility metric glyphs.
                attachedWeatherReport(snap)
            } else {
                // Enterprise-gated today — HONEST ENTERPRISE state. Never a
                // fabricated report; the panel reads now + lights on the key.
                weatherEnterpriseState(note: ev.note)
            }
        } else {
            // Toggle on but the fetch hasn't run yet — kick it.
            weatherEnterpriseState(note: nil)
                .task(id: weatherFetchKey) { await fetchHistoricalWeather() }
        }
    }

    /// HONEST gated state — bespoke (WeatherIcons), reads now, lights on the key.
    private func weatherEnterpriseState(note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 40, height: 40)
                    WeatherIcons.symbolView(for: 1001, size: 26)   // neutral cloud — no guessed condition
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence available with the enterprise feed")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(note?.isEmpty == false ? note! : "The cited weather.historical report lights here the instant the enterprise weather key lands — and attaches automatically when you file.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                WeatherIcons.utility(.eye, size: 10, tint: palette.textTertiary)
                Text("ENTERPRISE")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(10)
        .background(palette.bgCard.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// LIVE cited report (enterprise key present). Bespoke glyphs throughout.
    private func attachedWeatherReport(_ snap: HistoricalWeatherEvidence.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 44, height: 44)
                    WeatherIcons.symbolView(for: snap.weatherCode ?? 0, size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.peakCondition?.isEmpty == false ? snap.peakCondition! : "Cited weather record")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("weather.historical · attaches on file")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                if let g = snap.maxGustMph {
                    weatherMetric(.wind, value: String(format: "%.0f mph", g), label: "MAX GUST")
                }
                if let v = snap.minVisibilityMi {
                    weatherMetric(.eye, value: String(format: "%.1f mi", v), label: "MIN VIS")
                }
            }
        }
        .padding(10)
        .background(Brand.success.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.success.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func weatherMetric(_ kind: WeatherIcons.Utility, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            WeatherIcons.utility(kind, size: 13, tint: palette.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    /// Re-fetches whenever the toggle flips on or the claim type changes — so a
    /// type swap re-keys the window without a fabricated stale carry-over.
    private var weatherFetchKey: String { "\(claimType)-\(attachWeather)" }

    @MainActor
    private func fetchHistoricalWeather() async {
        guard attachWeather, !weatherLoading else { return }
        weatherLoading = true; weatherError = nil
        defer { weatherLoading = false }
        // Position + window are resolved server-side from the loadId; we send
        // only what we hold. Optionals stay nil rather than fabricating a
        // lat/lon/window the composer doesn't actually know.
        struct In: Encodable {
            let loadId: String
            let lat: Double?
            let lon: Double?
            let from: String?
            let to: String?
        }
        do {
            weatherEvidence = try await EusoTripAPI.shared.query(
                "freightClaims.attachHistoricalWeatherEvidence",
                input: In(loadId: loadId, lat: nil, lon: nil, from: nil, to: nil)
            )
        } catch {
            // A missing/unregistered proc or gated error must not block the
            // claim — fall to the honest ENTERPRISE state, never a fake report.
            weatherEvidence = HistoricalWeatherEvidence(available: false, note: nil, snapshot: nil)
        }
    }

    private var evidenceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EVIDENCE PHOTO", icon: "photo")
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(photo == nil ? "Attach photo" : "Replace photo")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    classification = nil; classifyError = nil
                    guard let i = item,
                          let data = try? await i.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else { return }
                    photo = img
                    await classifyEvidence(data: data)
                }
            }
            if let img = photo {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            classificationPanel
        }
    }

    @ViewBuilder
    private var classificationPanel: some View {
        if classifying {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                Text("Identifying evidence…").font(EType.caption).foregroundStyle(palette.textTertiary)
            }
        } else if let err = classifyError {
            Text("Couldn't auto-identify this evidence, \(err). Your photo will still be filed with the claim.")
                .font(EType.caption).foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if let c = classification {
            let conf = Int((c.confidence * 100).rounded())
            let unsure = c.classifiedType == "unknown" || c.confidence < 0.6
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ESANG · EVIDENCE DETECTED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                    Text("\(conf)%")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(conf >= 85 ? Brand.success : conf >= 60 ? Brand.warning : Brand.danger)
                }
                if unsure {
                    Text("Couldn't confidently identify this document. Please confirm it's the right evidence for the claim.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(humanEvidenceType(c.classifiedType))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                if !c.summary.isEmpty {
                    Text(c.summary).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                let keyFields = c.extractedFields.compactMap { (k, v) -> String? in
                    guard let s = v.asString, !s.isEmpty else { return nil }
                    return "\(k.replacingOccurrences(of: "_", with: " ").capitalized): \(s)"
                }.sorted()
                if !keyFields.isEmpty {
                    ForEach(keyFields.prefix(4), id: \.self) { f in
                        Text(f).font(EType.caption).foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                ForEach(c.warnings.prefix(2), id: \.self) { w in
                    Text("⚠ \(w)").font(EType.caption).foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(palette.bgCard.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func humanEvidenceType(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading": return "Bill of Lading"
        case "proof_of_delivery": return "Proof of Delivery"
        case "rate_confirmation": return "Rate Confirmation"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "damage_photo", "cargo_damage", "damage": return "Damage Photo"
        case "inspection_report": return "Inspection Report"
        case "us_coi", "ca_coi": return "Insurance Certificate"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @MainActor
    private func classifyEvidence(data: Data) async {
        classifying = true; classification = nil; classifyError = nil
        defer { classifying = false }
        // Compress oversized payloads to keep the wire light, mirroring
        // the upload's jpeg encoding.
        let payload: Data
        let mime: DocumentRouterAPI.MimeType
        if data.count > 900_000, let img = UIImage(data: data),
           let small = img.jpegData(compressionQuality: 0.7) {
            payload = small; mime = .jpeg
        } else {
            payload = data
            mime = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? .png : .jpeg
        }
        do {
            classification = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: payload.base64EncodedString(),
                mimeType: mime,
                callerContext: "freight claim evidence"
            )
        } catch {
            classifyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var ctaRow: some View {
        Button { Task { await fileClaim() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Filing…" : "File claim").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || amount == nil || description.isEmpty)
    }

    private func fileClaim() async {
        sending = true; actionError = nil
        struct In: Encodable {
            let loadId: String; let claimType: String; let amount: Double; let description: String; let evidenceBase64: String?
            // Records the shipper's intent to attach the cited weather.historical
            // report on the new claim. The server attaches the real record when
            // the enterprise weather key is present; gated → it's a no-op flag,
            // never a fabricated evidence row.
            let attachHistoricalWeather: Bool
        }
        struct Out: Decodable { let success: Bool; let claimId: String? }
        let evidenceB64 = photo?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("freightClaims.fileClaim", input: In(loadId: loadId, claimType: claimType, amount: amount ?? 0, description: description, evidenceBase64: evidenceB64, attachHistoricalWeather: attachWeather && isWeatherPeril))
            // If the shipper opted into the weather report and the claim landed
            // with an id, attach the cited historical record to THIS claim. Gated
            // → available:false comes back and nothing is fabricated.
            if attachWeather && isWeatherPeril, let cid = out.claimId {
                await attachWeatherToFiledClaim(claimId: cid)
            }
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }

    /// Best-effort post-file attach to the now-created claim id. Never throws
    /// into the file flow — a gated/missing proc leaves the claim filed and the
    /// evidence simply lights when the enterprise key lands.
    @MainActor
    private func attachWeatherToFiledClaim(claimId: String) async {
        struct In: Encodable {
            let claimId: String
            let lat: Double?; let lon: Double?; let from: String?; let to: String?
        }
        let ev: HistoricalWeatherEvidence? = try? await EusoTripAPI.shared.query(
            "freightClaims.attachHistoricalWeatherEvidence",
            input: In(claimId: claimId, lat: nil, lon: nil, from: nil, to: nil)
        )
        if let ev { weatherEvidence = ev }
    }
}

// MARK: - Historical weather evidence (decode shape · lenient)
//
// `freightClaims.attachHistoricalWeatherEvidence({claimId|loadId, lat, lon,
// from, to})` → a cited weather.historical evidence record. Enterprise-gated:
// today the server returns `available:false` (+ an optional note) and no
// snapshot, so EVERY field is optional and decode never throws on the gated
// shape. `snapshot` carries the cited readings the claim cites once the
// enterprise weather key lands. HONEST: available:false / nil snapshot ⇒ the
// composer renders the ENTERPRISE state, never a fabricated report.
private struct HistoricalWeatherEvidence: Decodable {
    let available: Bool?
    let note: String?
    let snapshot: Snapshot?

    struct Snapshot: Decodable {
        let weatherCode: Int?
        let peakCondition: String?
        let maxGustMph: Double?
        let minVisibilityMi: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case available, note, message, snapshot, weather, evidence
    }

    init(available: Bool?, note: String?, snapshot: Snapshot?) {
        self.available = available; self.note = note; self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try? c.decodeIfPresent(Bool.self, forKey: .available)
        // The honest note may arrive under `note` or `message`.
        if let n = try? c.decodeIfPresent(String.self, forKey: .note) {
            note = n
        } else {
            note = try? c.decodeIfPresent(String.self, forKey: .message)
        }
        // The cited readings may nest under `snapshot`, `weather`, or `evidence`.
        if let s = try? c.decodeIfPresent(Snapshot.self, forKey: .snapshot) {
            snapshot = s
        } else if let w = try? c.decodeIfPresent(Snapshot.self, forKey: .weather) {
            snapshot = w
        } else {
            snapshot = try? c.decodeIfPresent(Snapshot.self, forKey: .evidence)
        }
    }
}

#Preview("386 · Claim composer · Night") { FreightClaimComposerScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("386 · Claim composer · Afternoon") { FreightClaimComposerScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
