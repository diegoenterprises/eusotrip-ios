import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const reader = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Driver/NewsArticleReader.swift"),
  "utf8",
);

function section(start, end) {
  const startIndex = reader.indexOf(start);
  assert.notEqual(startIndex, -1, `missing ${start}`);
  const endIndex = reader.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `missing ${end}`);
  return reader.slice(startIndex, endIndex);
}

const didFinish = section(
  "func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)",
  "func webView(_ webView: WKWebView, didFail navigation: WKNavigation!",
);
assert.match(didFinish, /parent\.isLoading = false/);
assert.match(didFinish, /parent\.progress = 1\.0/);
assert.match(didFinish, /parent\.failed = false/);

const processTermination = section(
  "func webViewWebContentProcessDidTerminate(_ webView: WKWebView)",
  "    }\n}\n#endif",
);
assert.match(processTermination, /loadTimeoutTask\?\.cancel\(\)/);
assert.match(processTermination, /parent\.isLoading = false/);
assert.match(processTermination, /parent\.failed = true/);

assert.match(reader, /Text\("Publisher summary"\)/);
assert.match(reader, /No valid publisher page link was provided\./);

const ledgerPath = process.env.ASC_ARTICLE_READER_LEDGER;
const screenshotPath = process.env.ASC_ARTICLE_READER_SCREENSHOT;
let ascEvidenceValidated = false;

if (ledgerPath || screenshotPath) {
  assert.ok(ledgerPath && screenshotPath, "set both ASC article-reader evidence paths");
  const ledger = JSON.parse(fs.readFileSync(ledgerPath, "utf8"));
  const row = ledger.rows.find((item) => item.ascId === "AAPfWygfRDTiSf0MO7kbrt4");
  assert.ok(row, "missing canonical article-reader ASC row");
  assert.equal(row.kind, "screenshot-feedback");
  assert.equal(row.build, "705");
  assert.equal(row.crashLogReference, null);
  assert.equal(row.screenshotReferences.length, 1);

  const screenshotHash = crypto
    .createHash("sha256")
    .update(fs.readFileSync(screenshotPath))
    .digest("hex");
  assert.equal(screenshotHash, row.screenshotReferences[0].sha256);
  ascEvidenceValidated = true;
}

console.log(JSON.stringify({
  verified: true,
  successfulNavigationClearsFailure: true,
  webContentTerminationFallsBack: true,
  publisherSummaryIsExplicit: true,
  ascEvidenceValidated,
}, null, 2));
