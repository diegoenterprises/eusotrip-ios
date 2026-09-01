#!/usr/bin/env node

import { pathToFileURL } from "node:url";

const GITHUB_ORIGIN = "https://api.github.com";
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

function argument(name, argv = process.argv.slice(2)) {
  const prefix = `--${name}=`;
  return argv.find(value => value.startsWith(prefix))?.slice(prefix.length) ?? null;
}

const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function readLimitedJSON(response, pathname) {
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) {
    throw new Error("GitHub governance response exceeded 2 MiB");
  }
  if (!response.body) throw new Error(`GitHub returned an empty response for ${pathname}`);
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("GitHub governance response exceeded 2 MiB");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Error(`GitHub returned invalid JSON for ${pathname}`);
  }
}

async function githubJSON(fetchImpl, token, input, maxAttempts = 4) {
  const url = new URL(input, GITHUB_ORIGIN);
  if (url.origin !== GITHUB_ORIGIN) throw new Error("Refusing a non-GitHub governance URL");
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20_000);
    let response;
    try {
      response = await fetchImpl(url, {
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${token}`,
          "X-GitHub-Api-Version": "2022-11-28",
        },
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
      await sleep(250 * 2 ** (attempt - 1));
      continue;
    }
    try {
      if (!response.ok) {
        const requestID = response.headers.get("x-github-request-id");
        throw new Error(
          `GitHub governance HTTP ${response.status} on ${url.pathname}` +
          (requestID ? ` request=${requestID}` : ""),
        );
      }
      return await readLimitedJSON(response, url.pathname);
    } finally {
      clearTimeout(timeout);
    }
  }
  throw new Error("GitHub governance request exhausted retries");
}

export async function verifyGitHubReleaseGovernance({
  fetchImpl = fetch,
  token,
  repository,
  branch = "main",
  commit,
  requiredCheck,
  environment,
}) {
  if (typeof token !== "string" || token.trim().length < 20) {
    throw new Error("A non-placeholder GitHub governance token is required");
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? "")) {
    throw new Error("GitHub repository must be owner/name");
  }
  if (!/^[A-Za-z0-9._/-]{1,100}$/.test(branch ?? "") || !/^[a-f0-9]{40}$/.test(commit ?? "")) {
    throw new Error("Exact release branch and 40-character commit are required");
  }
  if (typeof requiredCheck !== "string" || requiredCheck.trim().length < 3 ||
      typeof environment !== "string" || !/^[A-Za-z0-9_. -]{3,100}$/.test(environment)) {
    throw new Error("Required HERE check and release environment names are required");
  }
  const encodedRepository = repository.split("/").map(encodeURIComponent).join("/");
  const repo = await githubJSON(fetchImpl, token, `/repos/${encodedRepository}`);
  if (repo.full_name !== repository || repo.default_branch !== branch || repo.archived || repo.disabled) {
    throw new Error("GitHub repository identity/default branch is not release eligible");
  }
  const branchData = await githubJSON(
    fetchImpl,
    token,
    `/repos/${encodedRepository}/branches/${encodeURIComponent(branch)}`,
  );
  if (!branchData.protected || branchData.commit?.sha !== commit) {
    throw new Error("The approved release commit must be the exact protected main head");
  }
  const protection = await githubJSON(
    fetchImpl,
    token,
    `/repos/${encodedRepository}/branches/${encodeURIComponent(branch)}/protection`,
  );
  const appBoundRequiredCheck = (protection.required_status_checks?.checks ?? []).find(check =>
    check.context === requiredCheck && Number.isSafeInteger(check.app_id) && check.app_id > 0);
  const reviews = protection.required_pull_request_reviews;
  if (
    !protection.enforce_admins?.enabled ||
    protection.allow_force_pushes?.enabled !== false ||
    protection.allow_deletions?.enabled !== false ||
    !reviews?.dismiss_stale_reviews ||
    !reviews?.require_last_push_approval ||
    reviews?.required_approving_review_count < 1 ||
    !appBoundRequiredCheck
  ) {
    throw new Error("Protected main lacks the required HERE check, independent review, or admin enforcement");
  }
  const checkQuery = new URL(
    `/repos/${encodedRepository}/commits/${commit}/check-runs`,
    GITHUB_ORIGIN,
  );
  checkQuery.searchParams.set("check_name", requiredCheck);
  checkQuery.searchParams.set("status", "completed");
  checkQuery.searchParams.set("filter", "latest");
  checkQuery.searchParams.set("per_page", "100");
  const checks = await githubJSON(fetchImpl, token, checkQuery);
  const successful = (checks.check_runs ?? []).filter(check =>
    check.name === requiredCheck && check.status === "completed" && check.conclusion === "success" &&
    check.app?.slug === "github-actions" && check.app?.id === appBoundRequiredCheck.app_id);
  if (successful.length !== 1 || successful[0].head_sha !== commit) {
    throw new Error("The exact release commit does not have one successful required HERE check");
  }
  const environmentData = await githubJSON(
    fetchImpl,
    token,
    `/repos/${encodedRepository}/environments/${encodeURIComponent(environment)}`,
  );
  const reviewerRules = (environmentData.protection_rules ?? []).filter(rule =>
    rule.type === "required_reviewers" && (rule.reviewers?.length ?? 0) > 0);
  if (environmentData.name !== environment || reviewerRules.length !== 1 ||
      environmentData.deployment_branch_policy?.protected_branches !== true ||
      environmentData.deployment_branch_policy?.custom_branch_policies !== false) {
    throw new Error("Release environment lacks independent reviewers or protected-branch-only deployment");
  }
  const deploymentsQuery = new URL(
    `/repos/${encodedRepository}/deployments`,
    GITHUB_ORIGIN,
  );
  deploymentsQuery.searchParams.set("sha", commit);
  deploymentsQuery.searchParams.set("environment", environment);
  deploymentsQuery.searchParams.set("per_page", "100");
  const deployments = await githubJSON(fetchImpl, token, deploymentsQuery);
  const exactDeployments = (Array.isArray(deployments) ? deployments : []).filter(deployment =>
    Number.isSafeInteger(deployment.id) && deployment.id > 0 &&
    deployment.sha === commit && deployment.ref === branch &&
    deployment.environment === environment && deployment.transient_environment !== true &&
    Number.isFinite(Date.parse(deployment.created_at ?? "")));
  if (exactDeployments.length < 1) {
    throw new Error("Exact commit lacks a reviewed GitHub release-environment deployment");
  }
  exactDeployments.sort((left, right) =>
    Date.parse(right.created_at ?? "") - Date.parse(left.created_at ?? ""));
  const deployment = exactDeployments[0];
  const statuses = await githubJSON(
    fetchImpl,
    token,
    `/repos/${encodedRepository}/deployments/${deployment.id}/statuses?per_page=100`,
  );
  const latestStatus = Array.isArray(statuses) ? statuses[0] : null;
  if (!latestStatus || !Number.isSafeInteger(latestStatus.id) || latestStatus.id <= 0 ||
      latestStatus.state !== "success" || latestStatus.environment !== environment) {
    throw new Error("Reviewed GitHub release-environment deployment is not successful");
  }
  return {
    repository,
    branch,
    commit,
    requiredCheck,
    environment,
    deploymentId: deployment.id,
    deploymentStatusId: latestStatus.id,
  };
}

async function main() {
  const token = process.env.GITHUB_TOKEN?.trim();
  const repository = argument("repository");
  const branch = argument("branch", process.argv.slice(2)) ?? "main";
  const commit = argument("commit");
  const requiredCheck = argument("required-check");
  const environment = argument("environment");
  const result = await verifyGitHubReleaseGovernance({
    token,
    repository,
    branch,
    commit,
    requiredCheck,
    environment,
  });
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(result));
  } else {
    console.log("GitHub release governance and reviewed environment deployment are enforced for the exact commit.");
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch(error => {
    console.error(error instanceof Error ? error.message : "GitHub release governance verification failed");
    process.exitCode = 1;
  });
}
