#!/usr/bin/env python3
"""
Batch-adopt LoadModeBadge across Driver lifecycle screens 021-051.

Sentinel-guarded: every edited file gains a `// EUSOTRIP-MODE-BADGE-2026-05-17`
marker so re-running the script is idempotent (we skip files that already
have the marker).

The pattern this script targets is the canonical lifecycle kicker:

    Text(ctx.headerKicker)
        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
        .foregroundStyle(LinearGradient.diagonal)

Right after that block, inside the same HStack, we insert:

    // EUSOTRIP-MODE-BADGE-2026-05-17 — Mode chip on lifecycle screen
    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                  multiVehicleCount: activeLoad?.multiVehicleCount,
                  compact: true)

Files without the canonical kicker (021-033, 035-036, 038, 050-051) are
flagged for manual review — they each have unique chrome that doesn't fit
a regex-driven rewrite.
"""

import os
import re
import sys

DRIVER_DIR = "/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver"
SENTINEL = "EUSOTRIP-MODE-BADGE-2026-05-17"

KICKER_RE = re.compile(
    # Permissive single-line match for the Text(...) opener — uses
    # [^\n]* instead of [^)]* so it tolerates string interpolation
    # like Text("· \(ctx.headerKicker)") where the closing paren of
    # the closure expression would have killed the previous regex.
    # Then 1-4 dot-chained modifiers after it.
    r"(Text\([^\n]*ctx\.headerKicker[^\n]*\)"
    r"(?:\s*\n\s*\.[a-zA-Z][^\n]*){1,4})"
)

BADGE_INSERT = (
    "\\1\n"
    "                    // " + SENTINEL + " — mode chip on lifecycle screen\n"
    "                    LoadModeBadge(modeRaw: activeLoad?.transportMode,\n"
    "                                  multiVehicleCount: activeLoad?.multiVehicleCount,\n"
    "                                  compact: true)"
)


def main():
    targets = sorted(
        f for f in os.listdir(DRIVER_DIR)
        if re.match(r"^0[2-5][0-9]_.+\.swift$", f)
    )
    edited, skipped_done, skipped_no_kicker = 0, 0, 0
    no_kicker = []
    for name in targets:
        path = os.path.join(DRIVER_DIR, name)
        with open(path, "r", encoding="utf-8") as fh:
            src = fh.read()
        if SENTINEL in src:
            skipped_done += 1
            continue
        if not KICKER_RE.search(src):
            skipped_no_kicker += 1
            no_kicker.append(name)
            continue
        new_src, n = KICKER_RE.subn(BADGE_INSERT, src, count=1)
        if n != 1:
            no_kicker.append(name + " (subn fail)")
            continue
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new_src)
        edited += 1
        print(f"[done] {name}")
    print(f"\nEdited: {edited}, already-tagged: {skipped_done}, no-kicker: {skipped_no_kicker}")
    if no_kicker:
        print("Screens without the canonical kicker (need manual adoption):")
        for n in no_kicker:
            print(f"  - {n}")


if __name__ == "__main__":
    main()
