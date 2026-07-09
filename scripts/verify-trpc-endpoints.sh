#!/usr/bin/env bash
#
# verify-trpc-endpoints.sh
#
# Landed by the 68th firing on 2026-04-24 as the permanent fix for the
# "live-dead endpoint" problem the 67th firing surfaced: Swift tRPC
# paths that reference a backend procedure that doesn't actually exist
# yet. Previously we only caught these via ad-hoc greps; now it's a
# single script the brick-recipe (SKILL.md §4 Step 4.5) and any firing's
# hygiene sweep can call.
#
# What it does
# ------------
# Extracts every "namespace.procedure" literal from EusoTripAPI.swift,
# resolves each to the backend router file under
#   eusoronetechnologiesinc/frontend/server/routers/
# and checks whether the procedure key appears with any *Procedure
# builder (publicProcedure, protectedProcedure, isolatedProcedure,
# roleProcedure, driverProcedure, vesselProcedure, railProcedure,
# earningsProcedure, auditedProtectedProcedure,
# auditedPublicProcedure, auditedOperationsProcedure, etc.) — which is
# how every tRPC procedure is declared in this codebase.
#
# Output
# ------
# - Prints one line per path with LIVE / DEAD verdict.
# - Exit 0 if zero live-dead.
# - Exit 1 with a summary count if any live-dead are present.
#
# Usage
# -----
#   bash scripts/verify-trpc-endpoints.sh
#   bash scripts/verify-trpc-endpoints.sh --summary-only   # just the counts
#   BACKEND=/path/to/backend/routers bash scripts/verify-trpc-endpoints.sh
#
# The script works from a Linux bash sandbox too — no macOS-specific tools.

set -u

# Resolve repo root (this script lives in scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SWIFT_API_DEFAULT="$REPO_ROOT/EusoTrip/Services/EusoTripAPI.swift"
SWIFT_API="${SWIFT_API:-$SWIFT_API_DEFAULT}"
SWIFT_ROOT="${SWIFT_ROOT:-$REPO_ROOT/EusoTrip}"

# The canonical backend lives in a sibling checkout. Override with BACKEND=.
BACKEND_DEFAULT="$(cd "$REPO_ROOT/.." && pwd)/eusoronetechnologiesinc/frontend/server/routers"
BACKEND="${BACKEND:-$BACKEND_DEFAULT}"
SERVER_ROOT="$(dirname "$BACKEND")"

if [[ ! -d "$SWIFT_ROOT" ]]; then
  echo "ERROR: Swift source root not found at $SWIFT_ROOT" >&2
  exit 2
fi
if [[ ! -d "$BACKEND" ]]; then
  echo "ERROR: backend routers dir not found at $BACKEND" >&2
  echo "       Set BACKEND=... to override." >&2
  exit 2
fi

SUMMARY_ONLY=0
[[ "${1:-}" == "--summary-only" ]] && SUMMARY_ONLY=1

# Namespaces that don't live as NS.ts under routers/.
# Keep this Bash 3.2-compatible for macOS by avoiding associative arrays.
router_file_for_prefix() {
  case "$1" in
    auth)  printf '%s\n' "$SERVER_ROOT/routers.ts" ;;
    devPortal) printf '%s\n' "$BACKEND/developerPortal.ts" ;;
    esang) printf '%s\n' "$SERVER_ROOT/esangRouter.ts" ;;
    *)
      local namespaced="$BACKEND/$1.ts"
      local app_router="$SERVER_ROOT/routers.ts"
      if [[ -f "$namespaced" ]]; then
        printf '%s\n' "$namespaced"
      elif [[ -f "$app_router" ]] && grep -qE "^[[:space:]]*$1[[:space:]]*:[[:space:]]*router\\(" "$app_router"; then
        printf '%s\n' "$app_router"
      else
        printf '%s\n' "$namespaced"
      fi
      ;;
  esac
}

# Grouped routers (namespace.sub.procedure style, e.g. bayOps.discharge.start).
# If Swift ever calls one of these three-segment paths, verify against the
# corresponding sub-router file.
group_router_file_for_prefix() {
  case "$1" in
    bayOps.discharge)     printf '%s\n' "$BACKEND/bayOps/discharge.ts" ;;
    bayOps.disconnect)    printf '%s\n' "$BACKEND/bayOps/disconnect.ts" ;;
    bayOps.connectHose)   printf '%s\n' "$BACKEND/bayOps/connectHose.ts" ;;
    bayOps.backingAssist) printf '%s\n' "$BACKEND/bayOps/backingAssist.ts" ;;
    *)                    printf '%s\n' "" ;;
  esac
}

# Extract Swift tRPC paths from actual API callsites only. This avoids
# treating SF Symbol names like "doc.text.image" as backend procedures.
PATHS=$(find "$SWIFT_ROOT" -name '*.swift' -print0 \
  | xargs -0 perl -0ne 'while (/\.(?:query|mutation|queryNoInput)\(\s*"([a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9]*){1,2})"/g) { print "$1\n" }' \
  | sort -u)

TOTAL=0
LIVE=0
DEAD=0
DEAD_PATHS=()

# Broad procedure-builder regex. Covers every *Procedure naming convention
# used across the backend (we've seen: public / protected / isolated / role /
# driver / vessel / rail / earnings / audited* / t.procedure).
PROC_REGEX='^\s*KEY_NAME:\s*[a-zA-Z_][a-zA-Z_]*[Pp]rocedure'
PROC_REGEX_TDOT='^\s*KEY_NAME:\s*t\.procedure'

# Wizard-procedure spread. `bayOps/*.ts` uses `buildWizardProcedures(...)` in
# `_shared.ts` to inject a base set of procedures (start, advanceStep,
# recordEvidence, complete, abort, getSession) via object spread. If the
# router file spreads that builder in, those six procedures are live even
# without an explicit `start:` key in the router file.
WIZARD_PROCS=("start" "advanceStep" "recordEvidence" "complete" "abort" "getSession")

# Is this procedure provided by a buildWizardProcedures spread in the file?
# Arg1 = file, Arg2 = procedure name.
is_wizard_spread_proc() {
  local file="$1"
  local proc="$2"
  # Fast exit if not a wizard proc name
  local match=0
  for p in "${WIZARD_PROCS[@]}"; do
    if [[ "$p" == "$proc" ]]; then match=1; break; fi
  done
  [[ $match -eq 0 ]] && return 1
  # Does the file spread the builder in?
  grep -qE '\.\.\.buildWizardProcedures' "$file"
}

while read -r path; do
  [[ -z "$path" ]] && continue
  TOTAL=$((TOTAL+1))

  # Three-segment? Check GROUP_ROUTER_FILE table.
  PREFIX="${path%.*}"   # namespace or namespace.sub
  PROC="${path##*.}"    # procedure
  FILE=""

  if [[ "$path" == *.*.* ]]; then
    # namespace.sub.procedure
    FILE="$(group_router_file_for_prefix "$PREFIX")"
    if [[ -z "$FILE" ]]; then
      ROOT_PREFIX="${path%%.*}"
      FILE="$(router_file_for_prefix "$ROOT_PREFIX")"
    fi
  else
    # namespace.procedure
    FILE="$(router_file_for_prefix "$PREFIX")"
  fi

  if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    DEAD=$((DEAD+1))
    DEAD_PATHS+=("$path  (no router file: $FILE)")
    [[ $SUMMARY_ONLY -eq 0 ]] && printf "DEAD   %-60s -> (no router file)\n" "$path"
    continue
  fi

  # Substitute procedure name into regex.
  R1="${PROC_REGEX//KEY_NAME/$PROC}"
  R2="${PROC_REGEX_TDOT//KEY_NAME/$PROC}"

  if grep -qE "$R1" "$FILE" || grep -qE "$R2" "$FILE" || grep -qE "^[[:space:]]*$PROC[[:space:]]*:" "$FILE" || is_wizard_spread_proc "$FILE" "$PROC"; then
    LIVE=$((LIVE+1))
    [[ $SUMMARY_ONLY -eq 0 ]] && printf "LIVE   %-60s -> %s\n" "$path" "$(basename "$FILE")"
  else
    DEAD=$((DEAD+1))
    DEAD_PATHS+=("$path  (file=$FILE)")
    [[ $SUMMARY_ONLY -eq 0 ]] && printf "DEAD   %-60s -> %s (procedure missing)\n" "$path" "$(basename "$FILE")"
  fi
done <<< "$PATHS"

echo
echo "================================================================"
echo "tRPC endpoint verification — EusoTripAPI.swift ↔ backend/routers/"
echo "================================================================"
  echo "  Swift root:  $SWIFT_ROOT"
echo "  Backend:     $BACKEND"
echo "  Total paths: $TOTAL"
echo "  LIVE:        $LIVE"
echo "  DEAD:        $DEAD"
echo

if [[ $DEAD -gt 0 ]]; then
  echo "LIVE-DEAD landmines:"
  for p in "${DEAD_PATHS[@]}"; do
    echo "  - $p"
  done
  echo
  echo "Action: add the missing procedure on the backend OR rewire the"
  echo "Swift caller to a canonical replacement. See SKILL.md §4 Step 4.5."
  exit 1
fi

echo "All paths LIVE. Ship it."
exit 0
