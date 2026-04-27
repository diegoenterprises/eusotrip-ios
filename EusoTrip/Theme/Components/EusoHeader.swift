//
//  EusoHeader.swift
//  EusoTrip — Unified pane / sheet header primitive (Patch #1, 2026-04-22)
//
//  One header to replace the six bespoke copies scattered across
//  DriverTabPanes (Eusoboards, My Loads, Wallet, Me),
//  MeDetailContainer, and HotZonesListSheet.
//
//  Doctrine: title uses the same 40pt / heavy / diagonal-gradient
//  treatment as Home's "Hey, <name>" greeting (see
//  010_DriverHome.swift lines 269–278) — no ALL-CAPS bullet-separated
//  subtitle. A supertitle, if supplied, is a single medium-weight
//  secondary-tinted line ABOVE the title (mirrors Home's right-rail
//  "GOOD AFTERNOON" micro-label rhythm but inline on the left axis).
//
//  Degrades gracefully when both `supertitle` and `trailing` are nil.
//

import SwiftUI

struct EusoHeader<Trailing: View>: View {

    // MARK: - Input

    let title: String
    let supertitle: String?
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    // MARK: - Sizing

    /// Pane headers match Home's 40pt hero rhythm; sheet headers
    /// drop to 28pt so they don't compete with the pane underneath.
    enum Size { case pane, sheet }
    var size: Size = .pane

    // MARK: - Environment

    @Environment(\.palette) private var palette

    // MARK: - Init overloads

    init(
        title: String,
        supertitle: String? = nil,
        subtitle: String? = nil,
        size: Size = .pane,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.supertitle = supertitle
        self.subtitle = subtitle
        self.size = size
        self.trailing = trailing
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                if let supertitle, !supertitle.isEmpty {
                    // Single-line, medium weight, secondary tint — NOT
                    // the bullet-separated uppercase tell ("CAREER ·
                    // COMPLIANCE · REPUTATION") that used to live here.
                    Text(supertitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(title)
                    .font(.system(size: titlePointSize, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    // Optional live-sentence descriptor beneath the title.
                    // Kept sentence-case, NOT bullet-separated uppercase.
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var titlePointSize: CGFloat {
        switch size {
        case .pane:  return 40
        case .sheet: return 28
        }
    }
}

// MARK: - Trailing-less convenience

extension EusoHeader where Trailing == EmptyView {
    init(
        title: String,
        supertitle: String? = nil,
        subtitle: String? = nil,
        size: Size = .pane
    ) {
        self.init(
            title: title,
            supertitle: supertitle,
            subtitle: subtitle,
            size: size,
            trailing: { EmptyView() }
        )
    }
}
