//
//  RailSecondaryActionButton.swift
//  EusoTrip - Rail secondary action affordance.
//
//  Small, self-contained Rail helper for replacing inert secondary controls
//  with an in-app action that opens live context from the hosting screen's
//  already-loaded server state.
//

import SwiftUI

struct RailSecondaryActionButton: View {
    @Environment(\.palette) private var palette

    let title: String
    let sheetTitle: String
    let lines: [String]
    var width: CGFloat = 148
    var fillWidth: Bool = false
    var systemImage: String = "list.bullet.rectangle"

    @State private var showingSheet = false

    private var visibleLines: [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "-" && $0 != "—" }
    }

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: fillWidth ? nil : width, height: 48)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            RailSecondaryActionSheet(
                title: sheetTitle,
                systemImage: systemImage,
                lines: visibleLines
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct RailSecondaryActionSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    let systemImage: String
    let lines: [String]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .frame(width: 32, height: 32)
                            .background(palette.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RAIL LIVE CONTEXT")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(title)
                                .font(EType.h2)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.74)
                        }
                    }

                    if lines.isEmpty {
                        liveContextRow("No live rows are available for this action yet.")
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            liveContextRow(line)
                        }
                    }
                }
                .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func liveContextRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            Text(text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
