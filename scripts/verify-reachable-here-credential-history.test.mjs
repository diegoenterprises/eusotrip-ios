#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import test from "node:test";

const scanner = path.join(
  import.meta.dirname,
  "verify-reachable-here-credential-history.mjs",
);
const temporaryRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), "eusotrip-here-history-scan-tests-"),
);

function run(command, arguments_, options = {}) {
  return spawnSync(command, arguments_, {
    encoding: "utf8",
    maxBuffer: 2 * 1024 * 1024,
    ...options,
  });
}

function requireSuccess(command, arguments_, options = {}) {
  const result = run(command, arguments_, options);
  assert.equal(result.status, 0);
  return result;
}

function createRepository(name) {
  const repository = path.join(temporaryRoot, name);
  fs.mkdirSync(repository, { recursive: true });
  requireSuccess("/usr/bin/git", ["init", "-q"], { cwd: repository });
  requireSuccess(
    "/usr/bin/git",
    ["config", "user.name", "HERE History Scanner Fixture"],
    { cwd: repository },
  );
  requireSuccess(
    "/usr/bin/git",
    ["config", "user.email", "scanner-fixture@example.invalid"],
    { cwd: repository },
  );
  return repository;
}

function commitAll(repository, message) {
  requireSuccess("/usr/bin/git", ["add", "--all"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["commit", "-q", "-m", message], {
    cwd: repository,
  });
}

function runScanner(repository, extraArguments = [], options = {}) {
  return run(
    process.execPath,
    [scanner, `--repository=${repository}`, ...extraArguments],
    { cwd: repository, ...options },
  );
}

test("detects a committed-then-deleted production-shaped HERE token without disclosing it", () => {
  const repository = createRepository("deleted-token");
  const productionShapedToken =
    "Az9By8Cx7Dw6Ev5Fu4Gt3Hs2Jr1Kq0Lp9Mn8";
  const exposedPath = "historical/build-output.log";
  fs.mkdirSync(path.dirname(path.join(repository, exposedPath)), {
    recursive: true,
  });
  fs.writeFileSync(
    path.join(repository, exposedPath),
    `HERE_SDK_ACCESS_KEY_SECRET = ${productionShapedToken}\n`,
  );
  commitAll(repository, "synthetic exposure");
  fs.rmSync(path.join(repository, exposedPath));
  commitAll(repository, "remove exposed file from the worktree");

  const result = runScanner(repository);
  const output = `${result.stdout}${result.stderr}`;

  assert.equal(result.status, 1);
  assert.equal(output.includes(productionShapedToken), false);
  assert.equal(output.includes("historical/build-output.log"), false);
  assert.equal(output.includes("metadata_sha256="), true);
  assert.equal(output.includes("metadata_bytes="), true);
  assert.equal(output.includes("pattern=here-named-assignment"), true);
  assert.equal(
    output.includes("reachable Git objects or metadata"),
    true,
  );
});

test("allows explicit placeholders and sanitized fixture values", () => {
  const repository = createRepository("sanitized-placeholders");
  fs.writeFileSync(
    path.join(repository, "EusoTrip.xcconfig.sample"),
    [
      "HERE_API_KEY = REPLACE_WITH_HERE_API_KEY",
      "HERE_SDK_ACCESS_KEY_ID = $(HERE_SDK_ACCESS_KEY_ID)",
      "HERE_SDK_ACCESS_KEY_SECRET = [REMOVED: rotate in HERE portal]",
      "HERE_OAUTH_ACCESS_KEY_SECRET = fixture-secret_with-unreserved-characters",
      "HERESDKAccessKeyID = placeholder-not-a-production-credential",
      "",
    ].join("\n"),
  );
  commitAll(repository, "sanitized fixture");

  const result = runScanner(repository);
  const output = `${result.stdout}${result.stderr}`;

  assert.equal(result.status, 0);
  assert.equal(output.includes("HERE credential history scan passed"), true);
  assert.equal(output.includes("HERE credential metadata:"), false);
});

test("matches credentials across streaming chunk boundaries exactly once", () => {
  const repository = createRepository("overlap-boundary");
  const productionShapedToken =
    "Qw1Er2Ty3Ui4Op5As6Df7Gh8Jk9Lz0Xc1Vb2";
  fs.writeFileSync(
    path.join(repository, "boundary.log"),
    `${"p".repeat(4078)}\nHERE_API_KEY = ${productionShapedToken}\n`,
  );
  commitAll(repository, "boundary fixture");

  const result = runScanner(repository, ["--chunk-bytes=4096"]);
  const output = `${result.stdout}${result.stderr}`;
  const metadataLines = output
    .split(/\r?\n/)
    .filter(line => line.includes("pattern=here-named-assignment"));

  assert.equal(result.status, 1);
  assert.equal(output.includes(productionShapedToken), false);
  assert.equal(metadataLines.length, 1);
});

test("ignores poisoned Git environment and disables replace-object masking", () => {
  const repository = createRepository("replace-object");
  const productionShapedToken =
    "Rt8Yu7Io6Pa5Sd4Fg3Hj2Kl1Zx0Cv9Bn8Mq7";
  fs.writeFileSync(
    path.join(repository, "source.env"),
    `HERE_CLIENT_SECRET = ${productionShapedToken}\n`,
  );
  commitAll(repository, "original reachable history");
  const originalCommit = requireSuccess(
    "/usr/bin/git",
    ["rev-parse", "HEAD"],
    { cwd: repository },
  ).stdout.trim();
  const emptyTree = requireSuccess(
    "/usr/bin/git",
    ["mktree"],
    { cwd: repository, input: "" },
  ).stdout.trim();
  const replacementCommit = requireSuccess(
    "/usr/bin/git",
    ["commit-tree", emptyTree, "-m", "synthetic clean replacement"],
    { cwd: repository },
  ).stdout.trim();
  requireSuccess(
    "/usr/bin/git",
    ["replace", originalCommit, replacementCommit],
    { cwd: repository },
  );

  const decoy = createRepository("poison-environment-decoy");
  fs.writeFileSync(path.join(decoy, "README.md"), "sanitized\n");
  commitAll(decoy, "sanitized decoy");
  const result = runScanner(repository, [], {
    env: {
      ...process.env,
      GIT_ALTERNATE_OBJECT_DIRECTORIES: path.join(decoy, ".git", "objects"),
      GIT_DIR: path.join(decoy, ".git"),
      GIT_NAMESPACE: "empty-namespace",
      GIT_NO_REPLACE_OBJECTS: "0",
      GIT_OBJECT_DIRECTORY: path.join(decoy, ".git", "objects"),
      GIT_WORK_TREE: decoy,
    },
  });
  const output = `${result.stdout}${result.stderr}`;

  assert.equal(result.status, 1);
  assert.equal(output.includes(productionShapedToken), false);
  assert.equal(output.includes("pattern=here-named-assignment"), true);
});

test("detects prefixed and suffixed HERE credential identifiers", () => {
  const repository = createRepository("prefixed-identifiers");
  const productionShapedToken =
    "Ui7Op6As5Df4Gh3Jk2Lz1Xc0Vb9Nm8Qw7Er6";
  fs.writeFileSync(
    path.join(repository, "web.env"),
    [
      `VITE_HERE_API_KEY = ${productionShapedToken}`,
      `NEXT_PUBLIC_HERE_API_KEY_PRODUCTION = ${productionShapedToken}`,
      `REACT_APP_HERE_API_KEY = ${productionShapedToken}`,
      `EXPO_PUBLIC_HERE_API_KEY_IOS = ${productionShapedToken}`,
      "",
    ].join("\n"),
  );
  commitAll(repository, "prefixed identifiers");

  const result = runScanner(repository);
  const output = `${result.stdout}${result.stderr}`;

  assert.equal(result.status, 1);
  assert.equal(output.includes(productionShapedToken), false);
  assert.equal(output.includes("location=blob-content"), true);
  assert.equal(output.includes("pattern=here-named-assignment"), true);
});

test("scans commit, annotated-tag, ref, and Unicode-controlled path metadata safely", () => {
  const cases = [
    {
      name: "commit-metadata",
      location: "commit-content",
      hasMetadata: false,
      prepare(repository, token) {
        fs.writeFileSync(path.join(repository, "safe.txt"), "sanitized\n");
        commitAll(repository, `audit HERE_CLIENT_SECRET = ${token}`);
      },
    },
    {
      name: "tag-metadata",
      location: "tag-content",
      hasMetadata: false,
      prepare(repository, token) {
        fs.writeFileSync(path.join(repository, "safe.txt"), "sanitized\n");
        commitAll(repository, "sanitized base");
        requireSuccess(
          "/usr/bin/git",
          ["tag", "-a", "audit-note", "-m", `HERE_USER_ID = ${token}`],
          { cwd: repository },
        );
      },
    },
    {
      name: "ref-metadata",
      location: "ref",
      hasMetadata: true,
      prepare(repository, token) {
        fs.writeFileSync(path.join(repository, "safe.txt"), "sanitized\n");
        commitAll(repository, "sanitized base");
        requireSuccess(
          "/usr/bin/git",
          ["branch", `HERE_API_KEY=${token}`],
          { cwd: repository },
        );
      },
    },
    {
      name: "path-metadata",
      location: "path",
      hasMetadata: true,
      prepare(repository, token) {
        const controlledPath = `\u202e-HERE_API_KEY=${token}.txt`;
        fs.writeFileSync(path.join(repository, controlledPath), "sanitized\n");
        commitAll(repository, "credential-shaped path metadata");
      },
    },
  ];

  for (const metadataCase of cases) {
    const repository = createRepository(metadataCase.name);
    const productionShapedToken =
      `Ab9Cd8Ef7Gh6Jk5Lm4Np3Qr2St1Uv0Wx9Yz8${metadataCase.name.length}`;
    metadataCase.prepare(repository, productionShapedToken);
    const result = runScanner(repository);
    const output = `${result.stdout}${result.stderr}`;

    assert.equal(result.status, 1, metadataCase.name);
    assert.equal(output.includes(productionShapedToken), false, metadataCase.name);
    assert.equal(output.includes("\u202e"), false, metadataCase.name);
    assert.equal(
      output.includes(`location=${metadataCase.location}`),
      true,
      metadataCase.name,
    );
    assert.equal(
      output.includes("metadata_sha256="),
      metadataCase.hasMetadata,
      metadataCase.name,
    );
  }
});

test("detects marker-prefixed random credentials but permits explicit fixture prose", () => {
  const repository = createRepository("tight-placeholders");
  const productionShapedToken =
    "TEST_Az9By8Cx7Dw6Ev5Fu4Gt3Hs2Jr1Kq0Lp";
  fs.writeFileSync(
    path.join(repository, "credential.env"),
    [
      "HERE_CLIENT_ID = fixture-secret_with-unreserved-characters",
      `HERE_API_KEY = ${productionShapedToken}`,
      "",
    ].join("\n"),
  );
  commitAll(repository, "marker prefix is not sufficient");

  const result = runScanner(repository);
  const output = `${result.stdout}${result.stderr}`;

  assert.equal(result.status, 1);
  assert.equal(output.includes(productionShapedToken), false);
});

test("requires exact HERE host boundaries and assignment context", () => {
  const sanitized = createRepository("hostname-lookalikes");
  const productionShapedToken =
    "Zx9Cv8Bn7Mq6We5Rt4Yu3Io2Pa1Sd0Fg9Hj8";
  fs.writeFileSync(
    path.join(sanitized, "lookalikes.txt"),
    [
      `https://evilhere.com/routes?apiKey=${productionShapedToken}`,
      `https://router.hereapi.com.evil.invalid/routes?apiKey=${productionShapedToken}`,
      `evilaccount.api.here.com/oauth Bearer ${productionShapedToken}`,
      "HERE-12345678-1234-1234-1234-123456789abc",
      "",
    ].join("\n"),
  );
  commitAll(sanitized, "hostname lookalikes and unbound identifier");
  const sanitizedResult = runScanner(sanitized);

  const valid = createRepository("valid-here-host");
  fs.writeFileSync(
    path.join(valid, "request.txt"),
    `https://router.hereapi.com/v8/routes?apiKey=${productionShapedToken}+/=\n`,
  );
  commitAll(valid, "valid HERE query credential");
  const validResult = runScanner(valid);
  const validOutput = `${validResult.stdout}${validResult.stderr}`;

  assert.equal(sanitizedResult.status, 0);
  assert.equal(validResult.status, 1);
  assert.equal(validOutput.includes(productionShapedToken), false);
  assert.equal(validOutput.includes("pattern=here-api-query-credential"), true);
});

test("fails closed for shallow, partial, and promisor repositories", () => {
  const shallow = createRepository("shallow-repository");
  fs.writeFileSync(path.join(shallow, "safe.txt"), "sanitized\n");
  commitAll(shallow, "sanitized base");
  const head = requireSuccess(
    "/usr/bin/git",
    ["rev-parse", "HEAD"],
    { cwd: shallow },
  ).stdout.trim();
  fs.writeFileSync(path.join(shallow, ".git", "shallow"), `${head}\n`);

  const partial = createRepository("partial-repository");
  fs.writeFileSync(path.join(partial, "safe.txt"), "sanitized\n");
  commitAll(partial, "sanitized base");
  requireSuccess(
    "/usr/bin/git",
    ["config", "extensions.partialClone", "origin"],
    { cwd: partial },
  );

  const promisor = createRepository("promisor-repository");
  fs.writeFileSync(path.join(promisor, "safe.txt"), "sanitized\n");
  commitAll(promisor, "sanitized base");
  fs.writeFileSync(
    path.join(promisor, ".git", "objects", "pack", "fixture.promisor"),
    "",
  );

  for (const repository of [shallow, partial, promisor]) {
    const result = runScanner(repository);
    assert.equal(result.status, 2, path.basename(repository));
    assert.equal(
      `${result.stdout}${result.stderr}`.includes("scanner integrity error"),
      true,
      path.basename(repository),
    );
  }
});

test("fails closed when a reachable object cannot be read completely", () => {
  const repository = createRepository("corrupt-object");
  fs.writeFileSync(path.join(repository, "safe.txt"), "sanitized\n");
  commitAll(repository, "sanitized base");
  const blob = requireSuccess(
    "/usr/bin/git",
    ["rev-parse", "HEAD:safe.txt"],
    { cwd: repository },
  ).stdout.trim();
  const looseObject = path.join(
    repository,
    ".git",
    "objects",
    blob.slice(0, 2),
    blob.slice(2),
  );
  assert.equal(fs.existsSync(looseObject), true);
  fs.chmodSync(looseObject, 0o600);
  fs.writeFileSync(looseObject, "intentionally truncated synthetic object");

  const result = runScanner(repository);
  const output = `${result.stdout}${result.stderr}`;

  assert.equal(result.status, 2);
  assert.equal(output.includes("scanner integrity error"), true);
});

test("fails closed for an invalid repository or unsafe chunk configuration", () => {
  const notARepository = path.join(temporaryRoot, "not-a-repository");
  fs.mkdirSync(notARepository);
  const missingRepository = runScanner(notARepository);
  const invalidChunk = runScanner(
    createRepository("invalid-chunk"),
    ["--chunk-bytes=1"],
  );

  assert.equal(missingRepository.status, 2);
  assert.equal(invalidChunk.status, 2);
  assert.equal(
    `${missingRepository.stdout}${missingRepository.stderr}`.includes(
      "scanner integrity error",
    ),
    true,
  );
});

test.after(() => {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
});
