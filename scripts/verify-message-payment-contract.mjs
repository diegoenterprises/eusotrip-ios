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
  existsSync(resolve(candidate, "frontend/server/routers/messages.ts")),
);

const api = readFileSync(resolve(root, "EusoTrip/Services/EusoTripAPI.swift"), "utf8");
const conversation = readFileSync(resolve(root, "EusoTrip/Views/Driver/DriverConversationView.swift"), "utf8");
const models = readFileSync(resolve(root, "EusoTrip/Views/Driver/DriverTabPanes.swift"), "utf8");
const failures = [];

function requireSource(condition, message) {
  if (!condition) failures.push(message);
}

const clientStart = api.indexOf("func sendPayment(");
const clientEnd = api.indexOf("/// POST /api/trpc/messages.unsendMessage", clientStart);
const client = api.slice(clientStart, clientEnd);
requireSource(clientStart >= 0 && clientEnd > clientStart, "missing iOS messages.sendPayment API boundary");
requireSource(client.includes("amountCents: Int"), "iOS payment still crosses the boundary as floating-point input");
requireSource(client.includes("idempotencyKey: UUID"), "iOS payment cannot retain an idempotent retry identity");
requireSource(client.includes("let _attest: AppAttestClient.AttestEnvelope?"), "iOS payment omits App Attest proof");
requireSource(
  client.includes('forContext: "messages.sendPayment|\\(conversationId)|\\(amountCents)|\\(canonicalCurrency)|\\(canonicalType)|\\(requestKey)"'),
  "iOS App Attest context drifted from the payment request",
);
requireSource(client.includes("amount: Double(amountCents) / 100"), "iOS does not send the cent-normalized amount it attested");

requireSource(models.includes("let idempotencyKey: UUID?"), "chat transfer cards do not retain their request identity");
requireSource(conversation.includes("idempotencyKey: UUID()"), "the transfer confirmation does not mint one request identity");
requireSource(conversation.includes("retryTransfer(messageID:"), "failed transfers have no safe Retry path");
requireSource(conversation.includes("idempotencyKey: payload.idempotencyKey"), "Retry does not preserve the original request identity");
requireSource(conversation.includes("transferRequestsInFlight"), "parallel Retry taps are not gated");

if (!backendRoot) {
  failures.push("backend messages router not found; set EUSOTRIP_BACKEND_ROOT so payment parity is actually verified");
} else {
  const messages = readFileSync(resolve(backendRoot, "frontend/server/routers/messages.ts"), "utf8");
  const transfer = readFileSync(resolve(backendRoot, "frontend/server/services/internalWalletTransfer.ts"), "utf8");
  const serverStart = messages.indexOf("sendPayment: protectedProcedure");
  const serverEnd = messages.indexOf("unsendMessage:", serverStart);
  const server = messages.slice(serverStart, serverEnd);
  requireSource(server.includes("idempotencyKey: z.string().uuid()"), "server payment no longer requires a UUID idempotency key");
  requireSource(server.includes("_attest: z.object({"), "server payment schema does not accept App Attest proof");
  requireSource(
    server.includes('const attestPayload = `messages.sendPayment|${input.conversationId}|${amountCents}|${input.currency}|${input.type}|${input.idempotencyKey}`'),
    "server App Attest payload drifted from iOS",
  );
  requireSource(server.includes('assertHighTrust(\n        "messages.sendPayment"'), "server payment does not enforce device integrity");
  requireSource(server.includes("await db.transaction(async (tx)"), "payment is not transactional");
  requireSource(server.includes("await tx.insert(notifications).values"), "recipient notification is not committed with the transfer");
  requireSource(server.includes("await enqueueAuditEvent(tx"), "payment has no durable audit intent");
  requireSource(server.includes("lockedParticipantIds.includes(userId)"), "caller membership is not rechecked under lock");
  requireSource(server.includes("lockedParticipantIds.includes(recipientId)"), "recipient membership is not rechecked under lock");
  requireSource(!server.includes(".catch(() => {})"), "payment still swallows a required side effect");
  requireSource(transfer.includes("wallet.internal_transfer_completed"), "shared wallet transfer has no canonical audit event");
  requireSource(transfer.includes("await enqueueAuditEvent(tx"), "shared wallet transfer bypasses the durable audit outbox");
  requireSource(!transfer.includes("blockchainAuditTrail"), "shared wallet transfer still writes an unhashed blockchain row");
}

if (failures.length) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log("PASS Chat payment cents, App Attest, idempotent Retry, tenant lock, ledger, notification, and audit contract");
