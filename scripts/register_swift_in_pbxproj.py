#!/usr/bin/env python3
"""
Register unregistered Swift files in EusoTrip.xcodeproj/project.pbxproj.

Run: python3 scripts/register_swift_in_pbxproj.py

Adds each file via the SOURCE_ROOT path pattern (`name = X.swift;
path = EusoTrip/...; sourceTree = SOURCE_ROOT;`) so the registration
doesn't depend on PBXGroup nesting.

Sentinel-guarded — each entry checks that the UUID isn't already in
the file before inserting. Re-runnable.
"""

import os
import re
import sys

PBXPROJ = "/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcodeproj/project.pbxproj"

# (uuid_build, uuid_ref, basename, relative path from SOURCE_ROOT)
ENTRIES = [
    ("MMCO2026051700000011A1", "MMCO2026051700000012A1",
     "MultiModalCore.swift",   "EusoTrip/Models/Multimodal/MultiModalCore.swift"),
    ("RLLN2026051700000011A1", "RLLN2026051700000012A1",
     "RailLane.swift",          "EusoTrip/Models/RailLane.swift"),
    ("EWST2026051700000011A1", "EWST2026051700000012A1",
     "EusoWalletStore.swift",   "EusoTrip/ViewModels/EusoWalletStore.swift"),
    ("EWAP2026051700000011A1", "EWAP2026051700000012A1",
     "EusoWalletApplePayProvider.swift",
     "EusoTrip/Services/EusoWalletApplePayProvider.swift"),
    ("RIRG2026051700000011A1", "RIRG2026051700000012A1",
     "RoleIntegrationRegistry.swift",
     "EusoTrip/Services/RoleIntegrationRegistry.swift"),
    ("PRIM2026051700000011A1", "PRIM2026051700000012A1",
     "Primitives.swift",        "EusoTrip/Views/Primitives/Primitives.swift"),
]


def main():
    with open(PBXPROJ, "r", encoding="utf-8") as fh:
        src = fh.read()

    edited = 0
    for uuid_b, uuid_r, basename, relpath in ENTRIES:
        if uuid_b in src:
            print(f"[skip] {basename} — UUID already present")
            continue

        # 1. Add PBXBuildFile entry — anchor on LoadModeBadge build line.
        anchor_build = (
            "\t\tLMBD2026051700000011A1 /* LoadModeBadge.swift in Sources */ = "
            "{isa = PBXBuildFile; fileRef = LMBD2026051700000012A1 /* LoadModeBadge.swift */; };"
        )
        new_build = (
            f"\t\t{uuid_b} /* {basename} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {uuid_r} /* {basename} */; }};"
        )
        if anchor_build not in src:
            print(f"[ERR ] {basename}: build-anchor not found, abort")
            return 1
        src = src.replace(anchor_build, anchor_build + "\n" + new_build, 1)

        # 2. Add PBXFileReference entry — SOURCE_ROOT path pattern.
        anchor_ref = (
            "\t\tLMBD2026051700000012A1 /* LoadModeBadge.swift */ = "
            "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            "path = LoadModeBadge.swift; sourceTree = \"<group>\"; };"
        )
        new_ref = (
            f"\t\t{uuid_r} /* {basename} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"name = {basename}; path = {relpath}; sourceTree = SOURCE_ROOT; }};"
        )
        if anchor_ref not in src:
            print(f"[ERR ] {basename}: ref-anchor not found, abort")
            return 1
        src = src.replace(anchor_ref, anchor_ref + "\n" + new_ref, 1)

        # 3. Add to Sources build phase — anchor on LoadModeBadge sources line.
        anchor_sources = (
            "\t\t\t\tLMBD2026051700000011A1 /* LoadModeBadge.swift in Sources */,"
        )
        new_sources = f"\t\t\t\t{uuid_b} /* {basename} in Sources */,"
        if anchor_sources not in src:
            print(f"[ERR ] {basename}: sources-anchor not found, abort")
            return 1
        src = src.replace(anchor_sources, anchor_sources + "\n" + new_sources, 1)

        # 4. Add to a Group (use the same Components group as LoadModeBadge
        # for the SOURCE_ROOT pattern, since `name = ...` displays
        # correctly anywhere; group membership is just for the navigator).
        anchor_group = (
            "\t\t\t\tLMBD2026051700000012A1 /* LoadModeBadge.swift */,"
        )
        new_group = f"\t\t\t\t{uuid_r} /* {basename} */,"
        if anchor_group not in src:
            print(f"[ERR ] {basename}: group-anchor not found, abort")
            return 1
        src = src.replace(anchor_group, anchor_group + "\n" + new_group, 1)

        edited += 1
        print(f"[done] {basename}")

    with open(PBXPROJ, "w", encoding="utf-8") as fh:
        fh.write(src)
    print(f"\nRegistered {edited} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
