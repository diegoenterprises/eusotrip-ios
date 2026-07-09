#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== ASC feedback ledger =="
ASC_SUMMARY="${ASC_FEEDBACK_SUMMARY:-}"
if [[ -z "$ASC_SUMMARY" && -f docs/testflight-feedback-ledger.json ]]; then
  ASC_SUMMARY="$(node -e 'const fs=require("fs"); const p="docs/testflight-feedback-ledger.json"; const j=JSON.parse(fs.readFileSync(p,"utf8")); if (j.source) process.stdout.write(j.source);')"
fi
if [[ -n "$ASC_SUMMARY" ]]; then
  node scripts/build-asc-feedback-ledger.mjs --check --input="$ASC_SUMMARY"
else
  node scripts/build-asc-feedback-ledger.mjs --check
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
echo "Feedback gates completed."
