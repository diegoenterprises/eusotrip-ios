import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const readerPath = "EusoTrip/Views/Driver/NewsArticleReader.swift";
const modelPath = "EusoTrip/Models/NewsArticle.swift";
const serverRoot = "/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server";
const reader = readFileSync(readerPath, "utf8");
const model = readFileSync(modelPath, "utf8");
const service = readFileSync(`${serverRoot}/services/articleTranslationService.ts`, "utf8");
const router = readFileSync(`${serverRoot}/routers/articleTranslation.ts`, "utf8");
const registry = readFileSync(`${serverRoot}/routers.ts`, "utf8");

function swiftRawScript(name) {
  const pattern = new RegExp(`static let ${name} = #"""([\\s\\S]*?)"""#`);
  const script = reader.match(pattern)?.[1];
  assert.ok(script, `${name} must exist`);
  return script;
}

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const extract = swiftRawScript("extractScript");
const apply = swiftRawScript("applyScript");
const restore = swiftRawScript("restoreScript");
new AsyncFunction(extract);
new AsyncFunction("translations", apply);
new AsyncFunction(restore);

assert.match(reader, /contentWorld: \.defaultClient/g, "WebKit translation must use an isolated content world");
assert.match(reader, /arguments: \["translations": translations\]/, "translations must cross as structured arguments");
assert.doesNotMatch(reader, /TranslatedArticleSheet|GeminiTranslatedArticleReader|news\.translateArticle/);
assert.doesNotMatch(extract + apply + restore, /innerHTML|outerHTML|insertAdjacentHTML|document\.write/);
assert.doesNotMatch(extract, /document\.body\.innerText|document\.body\.textContent/);
assert.match(extract, /itemprop='articleBody'/);
assert.match(extract, /"nav", "header", "footer", "aside"/);
assert.match(extract, /figcaption,caption,th,td/);
assert.match(extract, /kind: "imageAlt"/);
assert.match(apply, /reference\.node\.nodeValue/);
assert.match(apply, /reference\.node\.setAttribute\("alt"/);
assert.match(apply + restore, /captureAnchor/);
assert.match(apply + restore, /restoreAnchor/);
assert.match(reader, /Publisher summaries are not used as full articles\./);
assert.match(reader, /Partial machine translation:/);
assert.match(reader, /Machine translated/);
assert.match(model, /machineTranslated/);
assert.match(reader, /sourceLanguageEvidence/);

assert.match(model, /SHA256\.hash/);
assert.match(model, /canonicalURL.*contentFingerprint/s);
assert.match(service, /input\.canonicalURL/);
assert.match(service, /input\.contentFingerprint/);
assert.match(service, /input\.targetLocale\.toLowerCase\(\)/);
assert.match(service, /status: "complete" \| "partial" \| "unavailable" \| "not_needed"/);
assert.doesNotMatch(service, /translated:\s*input|return\s+input\.segments/);
assert.match(router, /isolatedProcedure/);
assert.match(registry, /articleTranslation:\s*articleTranslationRouter/);

console.log("article translation source and JavaScript safety: PASS");
