import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  fetchJSON,
  latestBuildNumber,
  parseNumericBuild,
  selectReleaseBuild,
  validateKeyConfiguration,
} from './asc-latest-build.mjs';

test('parses the numeric build convention used by EusoTrip', () => {
  assert.equal(parseNumericBuild('850'), 850);
  assert.throws(() => parseNumericBuild('850.1'), /positive integer/);
  assert.throws(() => parseNumericBuild('0'), /positive integer/);
});

test('selects the first build above live ASC when project is already occupied', () => {
  assert.equal(selectReleaseBuild({ projectBuild: 850, latestAscBuild: 850 }), 851);
});

test('keeps a higher project build and rejects a stale override', () => {
  assert.equal(selectReleaseBuild({ projectBuild: 852, latestAscBuild: 850 }), 852);
  assert.throws(
    () => selectReleaseBuild({ projectBuild: 850, latestAscBuild: 850, overrideBuild: 850 }),
    /not above App Store Connect build 850/
  );
});

test('reads every build page and returns the highest live build', async () => {
  const calls = [];
  const pages = [
    {
      data: [{ id: 'app-1', attributes: { bundleId: 'com.app.eusotrip' } }],
      links: {},
    },
    {
      data: [{ attributes: { version: '849' } }],
      links: { next: 'https://api.appstoreconnect.apple.com/v1/builds?cursor=second' },
    },
    {
      data: [{ attributes: { version: '850' } }],
      links: {},
    },
  ];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), authorization: options.headers.Authorization });
    return new Response(JSON.stringify(pages.shift()), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };

  const latest = await latestBuildNumber({
    fetchImpl,
    token: 'signed-token',
    bundleId: 'com.app.eusotrip',
  });
  assert.equal(latest, 850);
  assert.equal(calls.length, 3);
  assert.ok(calls.every((call) => call.authorization === 'Bearer signed-token'));
});

test('ignores non-exact app rows returned by the ASC bundle filter', async () => {
  const pages = [
    {
      data: [
        { id: 'other', attributes: { bundleId: 'com.app.eusotrip.watchkitapp' } },
        { id: 'app-1', attributes: { bundleId: 'com.app.eusotrip' } },
      ],
      links: {},
    },
    { data: [{ attributes: { version: '850' } }], links: {} },
  ];
  const fetchImpl = async () => new Response(JSON.stringify(pages.shift()), { status: 200 });
  assert.equal(
    await latestBuildNumber({ fetchImpl, token: 'signed-token', bundleId: 'com.app.eusotrip' }),
    850
  );
});

test('rejects pagination that leaves the App Store Connect origin', async () => {
  const pages = [
    { data: [{ id: 'app-1', attributes: { bundleId: 'com.app.eusotrip' } }], links: {} },
    {
      data: [{ attributes: { version: '850' } }],
      links: { next: 'https://example.com/steal-token' },
    },
  ];
  const fetchImpl = async () => new Response(JSON.stringify(pages.shift()), { status: 200 });
  await assert.rejects(
    latestBuildNumber({ fetchImpl, token: 'signed-token', bundleId: 'com.app.eusotrip' }),
    /non-App-Store-Connect pagination URL/
  );
});

test('rejects an oversized App Store Connect response before parsing it', async () => {
  const fetchImpl = async () => new Response('x'.repeat(2 * 1024 * 1024 + 1), {
    status: 200,
  });
  await assert.rejects(
    fetchJSON(fetchImpl, 'signed-token', '/v1/apps', 1),
    /exceeded the 2 MiB limit/
  );
});

test('retries a transient App Store Connect failure and returns bounded JSON', async () => {
  let attempts = 0;
  const fetchImpl = async () => {
    attempts += 1;
    if (attempts === 1) return new Response('', { status: 503 });
    return new Response(JSON.stringify({ data: [] }), { status: 200 });
  };
  assert.deepEqual(
    await fetchJSON(fetchImpl, 'signed-token', '/v1/apps', 2),
    { data: [] }
  );
  assert.equal(attempts, 2);
});

test('requires an owner-private regular P-256 key and rejects a symlink', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'eusotrip-asc-key-'));
  try {
    const keyId = 'FIXTUREKEY';
    const key = path.join(root, `AuthKey_${keyId}.p8`);
    const link = path.join(root, 'link', `AuthKey_${keyId}.p8`);
    fs.mkdirSync(path.dirname(link));
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    fs.writeFileSync(key, privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });
    const configuration = {
      keyId,
      issuerId: '00000000-0000-0000-0000-000000000001',
      privateKeyPath: key,
    };
    assert.doesNotThrow(() => validateKeyConfiguration(configuration));
    fs.symlinkSync(key, link);
    assert.throws(
      () => validateKeyConfiguration({ ...configuration, privateKeyPath: link }),
      /regular non-symlink/,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
