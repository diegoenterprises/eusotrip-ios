//
//  DailyBriefWidget.swift
//  Home-screen ESang AI Daily Brief — IO 2026 P0-5.
//
//  Universal across all 24 roles per the founder's home widget
//  doctrine (`feedback_home_widgets_doctrine.md`). Renders cards in
//  severity order (greeting → critical → warning → notice → info)
//  and surfaces the Universal Cart at the bottom. Dismissable rows
//  fade out and update the local cache; tomorrow's brief starts
//  fresh.
//
//  Hosted from:
//    • Driver 010 Home
//    • Shipper 320 Home
//    • Catalyst Home
//    • Broker Home
//    • Dispatcher Home
//
//  Drop into: EusoTrip/Views/Home/DailyBriefWidget.swift
//

import SwiftUI

public struct DailyBriefWidget: View {
    @StateObject private var adapter = GeminiBriefAdapter.shared
    /// Optional vertical hint passed when the host screen knows the
    /// shipper's primary vertical (refrigerated → hide hazmat cards).
    let vertical: Vertical?
    let onCtaTap: ((String) -> Void)?

    public init(vertical: Vertical? = nil, onCtaTap: ((String) -> Void)? = nil) {
        self.vertical = vertical
        self.onCtaTap = onCtaTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if adapter.isLoading && adapter.brief.cards.isEmpty {
                loadingPlaceholder
            } else if adapter.visibleCards.isEmpty && adapter.brief.cart.isEmpty {
                emptyState
            } else {
                ForEach(adapter.visibleCards) { card in
                    DailyBriefCardRow(card: card,
                                      onCta: { path in onCtaTap?(path) },
                                      onDismiss: {
                        Task { await adapter.dismiss(card.id) }
                    })
                }
                if !adapter.brief.cart.isEmpty {
                    UniversalCartStrip(items: adapter.brief.cart, onCtaTap: onCtaTap)
                        .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .task {
            await adapter.refresh(vertical: vertical)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [.cyan, .green],
                    startPoint: .leading, endPoint: .trailing
                ))
            Text("ESANG · MORNING BRIEF")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if adapter.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await adapter.refresh(vertical: vertical) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.12))
                    .frame(height: 56)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quiet morning.")
                .font(.body)
                .foregroundStyle(.primary)
            if let err = adapter.loadError {
                Text(err).font(.caption).foregroundStyle(.red)
            } else {
                Text("Nothing requires your attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Card row

private struct DailyBriefCardRow: View {
    let card: DailyBriefCard
    let onCta: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.kind.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(severityColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = card.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let path = card.ctaPath, let label = card.ctaLabel {
                    Button { onCta(path) } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(severityColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(6)
                    .background(.gray.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(severityColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(severityColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var severityColor: Color {
        switch card.severity {
        case .info:     return .secondary
        case .notice:   return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Universal Cart strip

private struct UniversalCartStrip: View {
    let items: [CartRecommendation]
    let onCtaTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cart")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("UNIVERSAL CART")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button { onCtaTap?(item.ctaPath) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.kind.systemImage)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(item.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                }
                                Text(item.rationale)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: 200, alignment: .leading)
                                if let est = item.estValueUsd {
                                    Text("~$\(Int(est)) value")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(12)
                            .frame(width: 220, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.gray.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Daily Brief Widget · Dark") {
    DailyBriefWidget()
        .preferredColorScheme(.dark)
}

#Preview("Daily Brief Widget · Light") {
    DailyBriefWidget()
        .preferredColorScheme(.light)
}
