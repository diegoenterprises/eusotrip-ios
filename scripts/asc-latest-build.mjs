#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ASC_ORIGIN = 'https://api.appstoreconnect.apple.com';
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

function required(value, label) {
  const result = value?.trim();
  if (!result) throw new Error(`${label} is required`);
  return result;
}

export function parseNumericBuild(value, label = 'build number') {
  const normalized = String(value ?? '').trim();
  if (!/^[1-9]\d*$/.test(normalized)) {
    throw new Error(`${label} must be a positive integer, got ${JSON.stringify(normalized)}`);
  }
  const parsed = Number(normalized);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error(`${label} is outside JavaScript's safe integer range`);
  }
  return parsed;
}

export function selectReleaseBuild({ projectBuild, latestAscBuild, overrideBuild }) {
  const project = parseNumericBuild(projectBuild, 'CURRENT_PROJECT_VERSION');
  const latest = Number(latestAscBuild);
  if (!Number.isSafeInteger(latest) || latest < 0) {
    throw new Error('latest App Store Connect build must be a non-negative integer');
  }

  if (overrideBuild != null && String(overrideBuild).trim() !== '') {
    const candidate = parseNumericBuild(overrideBuild, 'RELEASE_BUILD_NUMBER');
    if (candidate <= latest) {
      throw new Error(
        `RELEASE_BUILD_NUMBER ${candidate} is not above App Store Connect build ${latest}`
      );
    }
    return candidate;
  }

  return Math.max(project, latest + 1);
}

function base64url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

export function validateKeyConfiguration({ keyId, issuerId, privateKeyPath }) {
  if (!/^[A-Z0-9]{10}$/.test(keyId)) {
    throw new Error('ASC_API_KEY_ID must be a 10-character uppercase alphanumeric key ID');
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(issuerId)) {
    throw new Error('ASC_API_KEY_ISSUER must be a UUID');
  }
  const expectedName = `AuthKey_${keyId}.p8`;
  if (path.basename(privateKeyPath) !== expectedName) {
    throw new Error(`ASC_API_KEY_PATH must end in ${expectedName}`);
  }
  const stat = fs.statSync(privateKeyPath, { throwIfNoEntry: false });
  if (!stat?.isFile()) throw new Error('ASC_API_KEY_PATH must reference a readable file');
  fs.accessSync(privateKeyPath, fs.constants.R_OK);
  if ((stat.mode & 0o077) !== 0) {
    throw new Error('ASC_API_KEY_PATH permissions must be 0600 or stricter');
  }
}

export function mintToken({ keyId, issuerId, privateKeyPath }, nowMs = Date.now()) {
  validateKeyConfiguration({ keyId, issuerId, privateKeyPath });
  const privateKey = crypto.createPrivateKey(fs.readFileSync(privateKeyPath, 'utf8'));
  if (privateKey.asymmetricKeyType !== 'ec') {
    throw new Error('ASC_API_KEY_PATH must contain an EC private key');
  }
  const namedCurve = privateKey.asymmetricKeyDetails?.namedCurve;
  if (namedCurve && !['prime256v1', 'P-256'].includes(namedCurve)) {
    throw new Error('ASC_API_KEY_PATH must use the P-256 curve');
  }

  const now = Math.floor(nowMs / 1000);
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }));
  const payload = base64url(JSON.stringify({
    iss: issuerId,
    iat: now,
    exp: now + 900,
    aud: 'appstoreconnect-v1',
  }));
  const signingInput = `${header}.${payload}`;
  const signature = crypto.sign('sha256', Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });
  return `${signingInput}.${base64url(signature)}`;
}

async function readLimitedText(response) {
  const declared = Number(response.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) {
    throw new Error('App Store Connect response exceeded the 2 MiB limit');
  }
  if (!response.body) return '';

  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error('App Store Connect response exceeded the 2 MiB limit');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function fetchJSON(fetchImpl, token, inputUrl, maxAttempts = 4) {
  const url = new URL(inputUrl, ASC_ORIGIN);
  if (url.origin !== ASC_ORIGIN) throw new Error('Refusing non-App-Store-Connect pagination URL');

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20_000);
    let response;
    try {
      response = await fetchImpl(url, {
        headers: { Authorization: `Bearer ${token}` },
        signal: controller.signal,
      });
    } catch (error) {
      clearTimeout(timeout);
      if (attempt === maxAttempts) throw error;
      await sleep(250 * 2 ** (attempt - 1));
      continue;
    }
    if ((response.status === 429 || response.status >= 500) && attempt < maxAttempts) {
      clearTimeout(timeout);
      await response.body?.cancel();
      const retryAfter = Number(response.headers.get('retry-after'));
      const delay = Number.isFinite(retryAfter) ? retryAfter * 1000 : 250 * 2 ** (attempt - 1);
      await sleep(Math.min(5_000, Math.max(250, delay)));
      continue;
    }

    let text;
    try {
      text = await readLimitedText(response);
    } finally {
      clearTimeout(timeout);
    }
    if (!response.ok) {
      const requestId = response.headers.get('x-request-id');
      throw new Error(
        `App Store Connect HTTP ${response.status} on ${url.pathname}`
          + (requestId ? ` request=${requestId}` : '')
      );
    }
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`App Store Connect returned invalid JSON on ${url.pathname}`);
    }
  }
  throw new Error('App Store Connect request exhausted retries');
}

export async function latestBuildNumber({ fetchImpl = fetch, token, bundleId }) {
  const appQuery = new URL('/v1/apps', ASC_ORIGIN);
  appQuery.searchParams.set('filter[bundleId]', bundleId);
  appQuery.searchParams.set('fields[apps]', 'bundleId,name');
  // ASC's bundle filter has returned prefix-adjacent rows for this account;
  // request the full page and enforce the exact bundle ID below.
  appQuery.searchParams.set('limit', '200');
  const appPage = await fetchJSON(fetchImpl, token, appQuery);
  const returnedApps = appPage.data ?? [];
  const apps = returnedApps.filter((app) => app.attributes?.bundleId === bundleId);
  if (apps.length !== 1) {
    throw new Error(
      `Expected exactly one exact App Store Connect app for ${bundleId}, found ${apps.length}`
        + ` (${returnedApps.length} rows returned)`
    );
  }

  let next = new URL('/v1/builds', ASC_ORIGIN);
  next.searchParams.set('filter[app]', apps[0].id);
  next.searchParams.set('fields[builds]', 'version,uploadedDate,processingState,expired');
  next.searchParams.set('limit', '200');
  let highest = 0;

  while (next) {
    const page = await fetchJSON(fetchImpl, token, next);
    for (const build of page.data ?? []) {
      const version = parseNumericBuild(build.attributes?.version, 'App Store Connect build version');
      highest = Math.max(highest, version);
    }
    next = page.links?.next ? new URL(page.links.next, ASC_ORIGIN) : null;
  }
  return highest;
}

async function main(env = process.env) {
  const bundleId = required(env.ASC_BUNDLE_ID, 'ASC_BUNDLE_ID');
  const config = {
    keyId: required(env.ASC_API_KEY_ID, 'ASC_API_KEY_ID'),
    issuerId: required(env.ASC_API_KEY_ISSUER, 'ASC_API_KEY_ISSUER'),
    privateKeyPath: path.resolve(required(env.ASC_API_KEY_PATH, 'ASC_API_KEY_PATH')),
  };
  const token = mintToken(config);
  const latest = await latestBuildNumber({ token, bundleId });
  process.stdout.write(`${latest}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    console.error(`ERROR: ${error.message}`);
    process.exitCode = 1;
  });
}
