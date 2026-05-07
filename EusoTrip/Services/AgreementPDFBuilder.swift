//
//  AgreementPDFBuilder.swift
//  EusoTrip — Renders a `ShipperAgreementsAPI.Agreement` row to a PDF
//  on-device for Continuity / Save-to-Files / Mail / AirPrint flows.
//
//  Founder mandate 2026-05-05: shipper Agreements row needs three
//  actions — Open in app, Open on web (Handoff), Download PDF. Web
//  parity is at `/agreements/:id` already; this file owns the on-
//  device PDF path.
//
//  The on-device renderer keeps the round-trip free of a server PDF
//  endpoint while still producing a well-formatted document. When
//  the server eventually ships `agreements.exportPdf`, swap the
//  call site to fetch the canonical PDF; the share sheet keeps
//  working without further changes.
//
//  Powered by ESANG AI™.
//

import Foundation
import UIKit

enum AgreementPDFBuilder {

    /// Build a PDF representation of an agreement row and return the
    /// resulting Data. Renders to a US Letter (612×792 pt) page using
    /// `UIGraphicsPDFRenderer`. Wraps long bodies across pages.
    static func render(agreement row: ShipperAgreementsAPI.Agreement) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 56

            // Brand header
            "EusoTrip · Shipper Agreement".draw(
                at: CGPoint(x: 56, y: y),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.08, green: 0.45, blue: 1.0, alpha: 1.0),
                    .kern: 1.0,
                ]
            )
            y += 22

            // Agreement number — large mono.
            let title = row.agreementNumber ?? "AGR-\(row.id)"
            title.draw(
                at: CGPoint(x: 56, y: y),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .heavy),
                    .foregroundColor: UIColor.label,
                ]
            )
            y += 34

            // Status / type strip
            let status = (row.status ?? "—").uppercased()
            let kind   = (row.agreementType ?? "AGREEMENT").uppercased()
            "STATUS · \(status)    TYPE · \(kind)".draw(
                at: CGPoint(x: 56, y: y),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
                    .foregroundColor: UIColor.secondaryLabel,
                    .kern: 0.6,
                ]
            )
            y += 20

            // Hairline
            let hairline = UIBezierPath()
            hairline.move(to: CGPoint(x: 56, y: y))
            hairline.addLine(to: CGPoint(x: pageRect.width - 56, y: y))
            UIColor.separator.setStroke()
            hairline.lineWidth = 0.5
            hairline.stroke()
            y += 16

            // Section: Parties
            y = drawSectionHeader("PARTIES", at: y)
            if let pa = row.partyAUserId {
                y = drawKVRow(label: "Party A (user)", value: "#\(pa)",
                              at: y, pageRect: pageRect)
            }
            if let pb = row.partyBUserId {
                y = drawKVRow(label: "Party B (user)", value: "#\(pb)",
                              at: y, pageRect: pageRect)
            }
            y += 12

            // Section: Term
            y = drawSectionHeader("TERM", at: y)
            if let eff = row.effectiveDate, !eff.isEmpty {
                y = drawKVRow(label: "Effective", value: eff, at: y, pageRect: pageRect)
            }
            if let exp = row.expirationDate, !exp.isEmpty {
                y = drawKVRow(label: "Expires", value: exp, at: y, pageRect: pageRect)
            }
            if let created = row.createdAt, !created.isEmpty {
                y = drawKVRow(label: "Created", value: created, at: y, pageRect: pageRect)
            }
            y += 12

            // Section: Commercial
            y = drawSectionHeader("COMMERCIAL", at: y)
            if let rate = row.baseRate, !rate.isEmpty {
                y = drawKVRow(label: "Base rate", value: rate, at: y, pageRect: pageRect)
            }
            y += 12

            // Section: Notes (free-form body)
            if let notes = row.notes, !notes.isEmpty {
                y = drawSectionHeader("NOTES", at: y)
                y = drawWrappedParagraph(text: notes, at: y, pageRect: pageRect, ctx: ctx)
            } else {
                y = drawSectionHeader("NOTES", at: y)
                "No additional notes.".draw(
                    at: CGPoint(x: 56, y: y),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: UIColor.tertiaryLabel,
                    ]
                )
                y += 18
            }

            // Footer
            let footer = "Generated by EusoTrip iOS · \(Self.dateString())"
            let footerY = pageRect.height - 40
            footer.draw(
                at: CGPoint(x: 56, y: footerY),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                    .foregroundColor: UIColor.tertiaryLabel,
                ]
            )
        }
    }

    private static func drawSectionHeader(_ text: String, at y: CGFloat) -> CGFloat {
        text.draw(
            at: CGPoint(x: 56, y: y),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
                .foregroundColor: UIColor(red: 0.08, green: 0.45, blue: 1.0, alpha: 1.0),
                .kern: 0.8,
            ]
        )
        return y + 18
    }

    private static func drawKVRow(label: String, value: String, at y: CGFloat, pageRect: CGRect) -> CGFloat {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.label,
        ]
        label.draw(at: CGPoint(x: 56, y: y), withAttributes: labelAttrs)
        let valueRect = CGRect(x: 200, y: y, width: pageRect.width - 256, height: 18)
        value.draw(in: valueRect, withAttributes: valueAttrs)
        return y + 18
    }

    /// Wraps a long body string across the page width. Adds a new
    /// page when the cursor approaches the bottom margin.
    private static func drawWrappedParagraph(
        text: String,
        at y: CGFloat,
        pageRect: CGRect,
        ctx: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.label,
        ]
        let bodyWidth = pageRect.width - 112
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        var cursorY = y
        var charIndex = 0
        let totalChars = attributed.length

        while charIndex < totalChars {
            let availableHeight = pageRect.height - cursorY - 60
            if availableHeight < 60 {
                ctx.beginPage()
                cursorY = 56
                continue
            }
            // CoreText draws bottom-up; flip context so PDF y matches.
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: pageRect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            let flippedRect = CGRect(
                x: 56,
                y: pageRect.height - (cursorY + availableHeight),
                width: bodyWidth,
                height: availableHeight
            )
            let flippedPath = CGPath(rect: flippedRect, transform: nil)
            let flippedFrame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(charIndex, 0),
                flippedPath,
                nil
            )
            CTFrameDraw(flippedFrame, ctx.cgContext)
            ctx.cgContext.restoreGState()

            let visibleRange = CTFrameGetVisibleStringRange(flippedFrame)
            if visibleRange.length == 0 { break }   // paranoid guard
            charIndex += visibleRange.length
            cursorY += availableHeight
        }
        return cursorY
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
    }

    /// Writes the PDF to a temporary file and returns the URL — what
    /// `UIActivityViewController` / `UIDocumentInteractionController`
    /// expect to share. File name uses the agreement number so
    /// AirDrop / Files / Mail recipients see a meaningful title.
    static func writeToTemp(agreement row: ShipperAgreementsAPI.Agreement) -> URL? {
        let data = render(agreement: row)
        let fileName = "\(row.agreementNumber ?? "AGR-\(row.id)").pdf"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
