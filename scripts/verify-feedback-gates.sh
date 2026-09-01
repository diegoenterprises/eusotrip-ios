#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: scripts/verify-feedback-gates.sh [--mode=release|source-code]

  release      Require every ASC ledger item to be verified or deduplicated.
  source-code  Run source and contract checks without claiming release closure.
EOF
}

MODE="${FEEDBACK_GATE_MODE:-${ASC_FEEDBACK_GATE_MODE:-release}}"
for arg in "$@"; do
  case "$arg" in
    --mode=release|--release)
      MODE="release"
      ;;
    --mode=source-code|--mode=source|--source-code)
      MODE="source-code"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "release" && "$MODE" != "source-code" ]]; then
  echo "ERROR: FEEDBACK_GATE_MODE must be release or source-code." >&2
  exit 2
fi

ASC_LEDGER="${ASC_FEEDBACK_LEDGER:-docs/testflight-feedback-ledger.json}"

echo "Feedback gate mode: $MODE"
echo
echo "== ASC feedback source/code inventory =="
ASC_SUMMARY="${ASC_FEEDBACK_SUMMARY:-}"
if [[ -z "$ASC_SUMMARY" && -f "$ASC_LEDGER" ]]; then
  ASC_SUMMARY="$(node -e 'const fs=require("fs"); const p=process.argv[1]; const j=JSON.parse(fs.readFileSync(p,"utf8")); if (j.source) process.stdout.write(j.source);' "$ASC_LEDGER")"
fi
if [[ -n "$ASC_SUMMARY" ]]; then
  node scripts/build-asc-feedback-ledger.mjs --check --input="$ASC_SUMMARY"
else
  node scripts/build-asc-feedback-ledger.mjs --check
fi

if [[ "$MODE" == "release" ]]; then
  echo
  echo "== ASC release closure =="
  node scripts/verify-asc-feedback-release-closure.mjs --ledger="$ASC_LEDGER"
else
  echo
  echo "ASC release closure intentionally skipped in source-code mode."
fi

echo
echo "== Visible dev-copy gate =="
node scripts/check-dev-copy.mjs

echo
echo "== iOS tRPC endpoint existence gate =="
bash scripts/verify-trpc-endpoints.sh --summary-only

echo
echo "== iOS/server contract symmetry gate =="
node scripts/contract-symmetry.mjs --summary

echo
if [[ "$MODE" == "release" ]]; then
  echo "Feedback release gates passed."
else
  echo "Feedback source/code gates completed without a release-closure claim."
fi
