#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const backendCandidates = [
  process.env.EUSOTRIP_BACKEND_ROOT,
  resolve(homedir(), "_codex_rios_hardening"),
  resolve(root, "..", "eusoronetechnologiesinc"),
].filter(Boolean);
const backendRoot = backendCandidates.find(candidate =>
  existsSync(resolve(candidate, "frontend/server/routers/wallet.ts")),
);

const api = readFileSync(resolve(root, "EusoTrip/Services/EusoTripAPI.swift"), "utf8");
const driver = readFileSync(resolve(root, "EusoTrip/Views/Driver/069_MeWallet.swift"), "utf8");
const shipper = readFileSync(resolve(root, "EusoTrip/Views/Shipper/290_WalletHome.swift"), "utf8");
const failures = [];

function requireSource(condition, message) {
  if (!condition) failures.push(message);
}

const payoutStart = api.indexOf("struct RequestPayoutInput: Encodable");
const payoutEnd = api.indexOf("// MARK: Earnings summary", payoutStart);
const payout = api.slice(payoutStart, payoutEnd);

requireSource(payoutStart >= 0 && payoutEnd > payoutStart, "missing iOS payout API boundary");
requireSource(payout.includes("let idempotencyKey: String"), "payout input omits its required idempotency key");
requireSource(payout.includes("idempotencyKey: UUID"), "payout caller cannot retain a retry identity");
requireSource(
  payout.includes('forContext: "wallet.requestPayout|\\(grossCents)|\\(payoutMethodId)|\\(instant ? 1 : 0)|\\(requestKey)"'),
  "App Attest context does not match the server payout payload",
);
requireSource(payout.includes("amount: Double(grossCents) / 100"), "payout does not send the attested cent-normalized amount");
requireSource(!payout.includes("server fail-opens"), "payout claims production attestation fails open");

for (const [role, source] of [["driver", driver], ["shipper", shipper]]) {
  requireSource(source.includes("@State private var payoutRequestId = UUID()"), `${role} cash-out does not retain a request identity`);
  requireSource(source.includes("idempotencyKey: payoutRequestId"), `${role} cash-out does not send its retained request identity`);
  requireSource(source.includes("rotatePayoutRequestId()"), `${role} cash-out does not rotate identity when request inputs change`);
}

if (!backendRoot) {
  failures.push("backend wallet router not found; set EUSOTRIP_BACKEND_ROOT so payout parity is actually verified");
} else {
  const server = readFileSync(resolve(backendRoot, "frontend/server/routers/wallet.ts"), "utf8");
  const helperStart = server.indexOf("async function submitWalletPayout");
  const helperEnd = server.indexOf("function computeNextPayoutDate", helperStart);
  const helper = server.slice(helperStart, helperEnd > helperStart ? helperEnd : undefined);
  const serverStart = server.indexOf("requestPayout: auditedProtectedProcedure");
  const serverEnd = server.indexOf("// MARK:", serverStart);
  const procedure = server.slice(serverStart, serverEnd > serverStart ? serverEnd : undefined);
  requireSource(helperStart >= 0 && helperEnd > helperStart, "missing canonical server payout helper boundary");
  requireSource(procedure.includes("idempotencyKey: z.string().uuid()"), "server payout no longer requires a UUID idempotency key");
  requireSource(
    procedure.includes('const attestPayload = `wallet.requestPayout|${grossCents}|${input.payoutMethodId}|${input.instant ? 1 : 0}|${input.idempotencyKey}`'),
    "server App Attest payload drifted from the iOS binding",
  );
  requireSource(procedure.includes("submitWalletPayout({"), "server payout no longer delegates to the canonical payout saga");
  requireSource(procedure.includes("idempotencyKey: input.idempotencyKey"), "server payout drops the attested retry identity before delegation");

  requireSource(helper.includes("eq(payoutMethods.userId, input.userId)"), "payout method lookup is no longer owner scoped");
  requireSource(helper.includes("payoutMethod.isVerified"), "server payout no longer requires a verified payout method");
  requireSource(helper.includes("stripe.accounts.retrieve(userRow.stripeConnectId)"), "server payout no longer verifies the connected account");
  requireSource(helper.includes("account.payouts_enabled"), "server payout no longer verifies that Stripe payouts are enabled");
  requireSource(helper.includes("stripe.accounts.retrieveExternalAccount("), "server payout no longer verifies the selected external account");
  requireSource(helper.includes("checkIdempotency(input.db, input.idempotencyKey"), "server payout does not claim a durable idempotency record");
  requireSource(helper.includes("await input.db.transaction(async (tx) =>"), "server payout staging is no longer transactional");
  requireSource(helper.includes('.for("update")'), "server payout no longer locks the wallet before debiting it");
  requireSource(helper.includes("storeIdempotencyProcessing(tx"), "server payout no longer persists a reconciliation-safe processing receipt");
  requireSource(helper.includes("stripe.payouts.create({"), "server payout no longer reaches the real Stripe rail");
  requireSource(helper.includes("destination: payoutMethod.stripeExternalAccountId"), "Stripe payout no longer targets the verified external account");
  requireSource(helper.includes('method: input.instant ? "instant" : "standard"'), "Stripe payout method no longer matches the requested rail");
  requireSource(helper.includes("stripeAccount: userRow.stripeConnectId"), "Stripe payout is no longer submitted on the connected account");
  requireSource(helper.includes("idempotencyKey: providerIdempotencyKey"), "Stripe payout no longer carries provider idempotency");
  requireSource(helper.includes("isDefinitiveStripePayoutFailure(error)"), "server payout no longer separates definitive rejection from ambiguous submission");
  requireSource(helper.includes("availableBalance: sql`${wallets.availableBalance} + ${grossAmount}`"), "definitive Stripe rejection no longer restores the wallet balance");
  requireSource(helper.includes("provider confirmation pending reconciliation"), "ambiguous Stripe outcomes no longer remain reconciliation pending");
  requireSource(helper.includes("requiresReconciliation: false"), "provider acceptance no longer clears reconciliation only after correlation");
}

if (failures.length) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log("PASS Wallet payout amount, App Attest, idempotency, role UI, and Stripe parity contract");
