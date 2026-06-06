//
//  GradientSignaturePad.swift
//  EusoTrip — Reusable signature pad with real-time brand-gradient ink.
//
//  iOS counterpart of the web `GradientSignaturePad.tsx` used across
//  BOL signing, Rate Confirmations, PODs, Contracts, etc. Founder
//  mandate 2026-05-05: signature ink renders the EusoTrip brand
//  gradient (#1473FF → #7B3AFF → #BE01FF) in real-time as the user
//  draws on the screen, OR as a typed "print" signature still in
//  the gradient.
//
//  Web parity:
//    • 3-stop gradient: #1473FF → #7B3AFF → #BE01FF
//    • Dark canvas: #1E1E2E
//    • Subtle signature line at canvas bottom
//    • Signer name + document title display
//    • Legal text disclosure (UETA / E-SIGN compliance)
//    • Verification chip (encrypted + audit logged)
//    • onSign returns a base64 PNG data URL (web matches)
//

import SwiftUI

public enum SignatureMode: String, CaseIterable, Identifiable {
    case draw, print
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .draw:  return "Draw"
        case .print: return "Print"
        }
    }
}

public struct GradientSignaturePad: View {
    /// Called when the user taps Sign. `signatureDataURL` is the
    /// base64-encoded PNG `data:image/png;base64,...` string the
    /// agreements / BOL / POD / RC pipelines accept verbatim — same
    /// shape as the web `onSign(signatureData)` callback.
    public let onSign: (_ signatureDataURL: String, _ typedName: String?) -> Void
    public let signerName: String?
    public let documentTitle: String?
    public let canvasHeight: CGFloat
    public let legalText: String

    @Environment(\.dismiss) private var dismiss

    @State private var mode: SignatureMode = .draw
    @State private var strokes: [[CGPoint]] = [[]]
    @State private var typedName: String = ""
    @State private var canvasSize: CGSize = .zero
    @State private var hasSignature: Bool = false

    /// Brand gradient stops — exact match to the web component so
    /// signed documents render identically across surfaces.
    private static let stop1 = Color(red: 20.0/255.0,  green: 115.0/255.0, blue: 255.0/255.0)
    private static let stop2 = Color(red: 123.0/255.0, green: 58.0/255.0,  blue: 255.0/255.0)
    private static let stop3 = Color(red: 190.0/255.0, green:   1.0/255.0, blue: 255.0/255.0)
    private static let canvasBG = Color(red: 30.0/255.0, green: 30.0/255.0, blue: 46.0/255.0) // #1E1E2E
    private static let lineColor = Color(red: 100.0/255.0, green: 116.0/255.0, blue: 139.0/255.0).opacity(0.25)
    private static let hintColor = Color(red: 148.0/255.0, green: 163.0/255.0, blue: 184.0/255.0).opacity(0.5)

    public init(
        signerName: String? = nil,
        documentTitle: String? = nil,
        canvasHeight: CGFloat = 220,
        legalText: String = "By electronically signing this document, I acknowledge and agree that my electronic signature holds the same legal validity as a handwritten signature, to the extent permitted by applicable laws and regulations of the United States.",
        onSign: @escaping (String, String?) -> Void
    ) {
        self.signerName = signerName
        self.documentTitle = documentTitle
        self.canvasHeight = canvasHeight
        self.legalText = legalText
        self.onSign = onSign
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            if signerName != nil || documentTitle != nil {
                metaRow
            }
            modePicker
            switch mode {
            case .draw:  drawCanvas
            case .print: printCanvas
            }
            legalRow
            actionRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.canvasBG.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "signature")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient(
                    colors: [Self.stop1, Self.stop2, Self.stop3],
                    startPoint: .leading, endPoint: .trailing
                ))
            Text("Sign here")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            // Verification chip — UETA / E-SIGN audit trail.
            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill").font(.system(size: 10, weight: .heavy))
                Text("ENCRYPTED").font(.system(size: 9, weight: .heavy)).tracking(1.0)
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().strokeBorder(Color.white.opacity(0.15)))
        }
    }

    @ViewBuilder
    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = documentTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            if let name = signerName, !name.isEmpty {
                Text("Signing as \(name)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(SignatureMode.allCases) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = m }
                } label: {
                    Text(m.label)
                        .font(.system(size: 12, weight: .heavy))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(mode == m
                                         ? AnyShapeStyle(Color.white)
                                         : AnyShapeStyle(Color.white.opacity(0.55)))
                        .background(
                            Capsule().fill(
                                mode == m
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Self.stop1, Self.stop2, Self.stop3],
                                    startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.clear)
                            )
                        )
                        .overlay(Capsule().strokeBorder(
                            mode == m ? Color.clear : Color.white.opacity(0.15)
                        ))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button(action: clear) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear signature")
        }
    }

    /// Real-time gradient ink — Canvas redraws on every gesture
    /// update, the path is filled with the 3-stop brand gradient.
    private var drawCanvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Subtle signature line at the bottom (matches web).
                var line = Path()
                line.move(to: CGPoint(x: 32, y: size.height - 44))
                line.addLine(to: CGPoint(x: size.width - 32, y: size.height - 44))
                context.stroke(line, with: .color(Self.lineColor), lineWidth: 1)

                // Hint text when empty.
                if !hasSignature {
                    let hintRect = CGRect(
                        x: 32, y: size.height - 70,
                        width: size.width - 64, height: 18
                    )
                    context.draw(
                        Text("Sign with finger")
                            .font(.system(size: 12)).foregroundStyle(Self.hintColor),
                        in: hintRect
                    )
                }

                // Strokes in 3-stop brand gradient.
                let gradient = Gradient(stops: [
                    .init(color: Self.stop1, location: 0.0),
                    .init(color: Self.stop2, location: 0.5),
                    .init(color: Self.stop3, location: 1.0),
                ])
                let shading = GraphicsContext.Shading.linearGradient(
                    gradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )
                for stroke in strokes where stroke.count >= 2 {
                    var path = Path()
                    path.move(to: stroke[0])
                    for p in stroke.dropFirst() {
                        path.addLine(to: p)
                    }
                    context.stroke(path, with: shading, style: StrokeStyle(
                        lineWidth: 3.0, lineCap: .round, lineJoin: .round
                    ))
                }
            }
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, new in canvasSize = new }
        }
        .frame(maxWidth: .infinity).frame(height: canvasHeight)
        .background(Self.canvasBG)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    hasSignature = true
                    let p = value.location
                    if strokes[strokes.count - 1].isEmpty {
                        strokes[strokes.count - 1].append(p)
                    }
                    strokes[strokes.count - 1].append(p)
                }
                .onEnded { _ in
                    if !strokes[strokes.count - 1].isEmpty {
                        strokes.append([])
                    }
                }
        )
    }

    /// Typed signature — gradient text overlay for a "print"
    /// signature variant (mirrors the web "Print" toggle).
    private var printCanvas: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Type your full legal name", text: $typedName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Self.canvasBG)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                Text(typedName.isEmpty ? "Your gradient signature renders here" : typedName)
                    .font(.system(size: 32, weight: .heavy, design: .serif))
                    .foregroundStyle(typedName.isEmpty
                                     ? AnyShapeStyle(Self.hintColor)
                                     : AnyShapeStyle(LinearGradient(
                                         colors: [Self.stop1, Self.stop2, Self.stop3],
                                         startPoint: .leading, endPoint: .trailing)))
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: canvasHeight - 60)
        }
        .onChange(of: typedName) { _, v in hasSignature = !v.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var legalRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 2)
            Text(legalText)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.6))
                .font(.system(size: 13, weight: .heavy))
                .padding(.horizontal, 16).padding(.vertical, 10)
            Spacer(minLength: 0)
            Button {
                Task { await sign() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12, weight: .heavy))
                    Text("Sign").font(.system(size: 13, weight: .heavy)).tracking(0.5)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(LinearGradient(
                    colors: [Self.stop1, Self.stop2, Self.stop3],
                    startPoint: .leading, endPoint: .trailing
                ))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSign)
            .opacity(canSign ? 1 : 0.4)
        }
    }

    private var canSign: Bool {
        switch mode {
        case .draw:  return strokes.contains(where: { !$0.isEmpty })
        case .print: return !typedName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func clear() {
        strokes = [[]]
        typedName = ""
        hasSignature = false
    }

    @MainActor
    private func sign() async {
        let renderSize = CGSize(
            width: max(800, canvasSize.width * 2),
            height: max(440, canvasHeight * 2)
        )
        let img = renderImage(size: renderSize)
        guard let png = img.pngData() else { return }
        let dataURL = "data:image/png;base64,\(png.base64EncodedString())"
        onSign(dataURL, mode == .print ? typedName.trimmingCharacters(in: .whitespaces) : nil)
        dismiss()
    }

    /// Rasterise to UIImage at the requested render size — matches
    /// the web canvas → toDataURL("image/png") output shape so the
    /// agreements / BOL / POD / RC backends accept the same payload.
    private func renderImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Dark canvas BG to match web.
            UIColor(red: 30/255, green: 30/255, blue: 46/255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext
            let stop1 = UIColor(red: 20/255,  green: 115/255, blue: 255/255, alpha: 1).cgColor
            let stop2 = UIColor(red: 123/255, green:  58/255, blue: 255/255, alpha: 1).cgColor
            let stop3 = UIColor(red: 190/255, green:   1/255, blue: 255/255, alpha: 1).cgColor
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [stop1, stop2, stop3] as CFArray,
                locations: [0, 0.5, 1]
            )!

            switch mode {
            case .draw:
                let scale = CGSize(
                    width: size.width / max(1, canvasSize.width),
                    height: size.height / max(1, canvasSize.height)
                )
                cg.saveGState()
                let path = CGMutablePath()
                for stroke in strokes where stroke.count >= 2 {
                    let scaled = stroke.map { CGPoint(x: $0.x * scale.width, y: $0.y * scale.height) }
                    path.move(to: scaled[0])
                    for p in scaled.dropFirst() {
                        path.addLine(to: p)
                    }
                }
                cg.addPath(path)
                cg.setLineWidth(6.0)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.replacePathWithStrokedPath()
                cg.clip()
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: 0),
                    options: []
                )
                cg.restoreGState()
            case .print:
                let text = typedName.trimmingCharacters(in: .whitespaces) as NSString
                let font = UIFont.systemFont(ofSize: size.height * 0.35, weight: .heavy)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white,
                ]
                let textBounds = text.boundingRect(
                    with: CGSize(width: size.width - 48, height: size.height),
                    options: [.usesLineFragmentOrigin],
                    attributes: attrs,
                    context: nil
                )
                let textRect = CGRect(
                    x: 24, y: (size.height - textBounds.height) / 2,
                    width: size.width - 48, height: textBounds.height
                )
                text.draw(in: textRect, withAttributes: attrs)
                cg.setBlendMode(.sourceIn)
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: textRect.midY),
                    end: CGPoint(x: size.width, y: textRect.midY),
                    options: []
                )
            }
        }
    }
}

#Preview("Gradient Signature Pad · Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        GradientSignaturePad(
            signerName: "Diego Usoro",
            documentTitle: "Catalyst-Shipper Agreement · AGR-2026-XYZ"
        ) { dataURL, name in
            print("signed:", name ?? "drawn", "· bytes:", dataURL.count)
        }
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
