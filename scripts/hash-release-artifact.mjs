#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

function updateFile(hash, file, expectedMetadata = fs.lstatSync(file)) {
  if (!expectedMetadata.isFile() || expectedMetadata.isSymbolicLink()) {
    throw new Error("Release artifact file must be one regular non-symlink file");
  }
  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  const chunk = Buffer.allocUnsafe(1024 * 1024);
  try {
    const opened = fs.fstatSync(descriptor);
    if (!opened.isFile() || opened.dev !== expectedMetadata.dev || opened.ino !== expectedMetadata.ino) {
      throw new Error("Release artifact file changed while it was opened");
    }
    let total = 0;
    while (true) {
      const bytes = fs.readSync(descriptor, chunk, 0, chunk.length, null);
      if (bytes === 0) break;
      hash.update(chunk.subarray(0, bytes));
      total += bytes;
    }
    const final = fs.fstatSync(descriptor);
    if (total !== opened.size || final.size !== opened.size ||
        final.mtimeMs !== opened.mtimeMs || final.ctimeMs !== opened.ctimeMs) {
      throw new Error("Release artifact file changed while it was hashed");
    }
  } finally {
    fs.closeSync(descriptor);
  }
}

export function hashReleaseArtifact(inputPath) {
  const root = path.resolve(inputPath);
  const rootMetadata = fs.lstatSync(root);
  const hash = crypto.createHash("sha256");
  if (rootMetadata.isFile()) {
    updateFile(hash, root, rootMetadata);
    return hash.digest("hex");
  }
  if (!rootMetadata.isDirectory() || rootMetadata.isSymbolicLink()) {
    throw new Error("Release artifact root must be one regular file or directory");
  }

  const entries = [];
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop();
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const entryPath = path.join(directory, entry.name);
      entries.push(entryPath);
      if (entry.isDirectory() && !entry.isSymbolicLink()) pending.push(entryPath);
    }
  }
  entries.sort((left, right) =>
    Buffer.compare(Buffer.from(path.relative(root, left)), Buffer.from(path.relative(root, right)))
  );
  for (const entryPath of entries) {
    const relativePath = path.relative(root, entryPath).split(path.sep).join("/");
    const metadata = fs.lstatSync(entryPath);
    const mode = String(metadata.mode & 0o7777);
    if (metadata.isSymbolicLink()) {
      hash.update(`L\0${relativePath}\0${mode}\0${fs.readlinkSync(entryPath)}\0`);
    } else if (metadata.isDirectory()) {
      hash.update(`D\0${relativePath}\0${mode}\0`);
    } else if (metadata.isFile()) {
      hash.update(`F\0${relativePath}\0${mode}\0${metadata.size}\0`);
      updateFile(hash, entryPath, metadata);
      hash.update("\0");
    } else {
      throw new Error(`Release artifact contains an unsupported filesystem entry: ${relativePath}`);
    }
  }
  return hash.digest("hex");
}

const isMain = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argument = process.argv.find(value => value.startsWith("--path="));
  if (!argument) {
    console.error("Usage: hash-release-artifact.mjs --path=/absolute/artifact");
    process.exit(2);
  }
  try {
    process.stdout.write(hashReleaseArtifact(argument.slice("--path=".length)));
  } catch {
    console.error("Release artifact hashing failed without exposing artifact contents.");
    process.exit(1);
  }
}
