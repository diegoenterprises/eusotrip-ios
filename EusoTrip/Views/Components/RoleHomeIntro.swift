//
//  RoleHomeIntro.swift
//  EusoTrip — Canonical Home lead-in for every role.
//
//  Doctrine: Driver 010 is the baseline. Every role's Home opens with
//      movable Weather widget  →  ESANG brief  →  role-specific widgets.
//
//  This component renders only the ESANG brief. Weather belongs to the shared
//  HomeWidgetGrid so the user can move, resize, remove, and re-add it.
//    • eSangMorningBriefCard  — the "ESANG brief" top coaching card,
//                               role/vertical-aware, auto-loads on appear.
//
//  Usage from any role home body:
//      VStack(alignment: .leading, spacing: Space.s4) {
//          HomeWidgetGrid(...)              // ← movable weather first
//          RoleHomeIntro()                  // ← morning brief
//          // …role-specific widgets follow…
//      }
//

import SwiftUI

struct RoleHomeIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eSangMorningBriefCard()
        }
    }
}
