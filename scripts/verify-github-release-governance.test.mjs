#!/usr/bin/env node

import assert from "node:assert/strict";
import { verifyGitHubReleaseGovernance } from "./verify-github-release-governance.mjs";

const commit = "a".repeat(40);
const repository = "diegoenterprises/eusotrip-ios";
const requiredCheck = "HERE Offline Source Contract / source-contract";
const environment = "here-offline-release";

function fixture(overrides = {}) {
  const values = {
    repo: {
      full_name: repository,
      default_branch: "main",
      archived: false,
      disabled: false,
    },
    branch: { protected: true, commit: { sha: commit } },
    protection: {
      required_status_checks: { contexts: [], checks: [{ context: requiredCheck, app_id: 15368 }] },
      enforce_admins: { enabled: true },
      allow_force_pushes: { enabled: false },
      allow_deletions: { enabled: false },
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_last_push_approval: true,
        required_approving_review_count: 1,
      },
    },
    checks: {
      check_runs: [{
        name: requiredCheck,
        status: "completed",
        conclusion: "success",
        head_sha: commit,
        app: { slug: "github-actions", id: 15368 },
      }],
    },
    environment: {
      name: environment,
      protection_rules: [{ type: "required_reviewers", reviewers: [{ type: "User", reviewer: { id: 1 } }] }],
      deployment_branch_policy: { protected_branches: true, custom_branch_policies: false },
    },
    deployments: [{
      id: 4242,
      sha: commit,
      ref: "main",
      environment,
      transient_environment: false,
      created_at: "2026-09-01T01:00:00Z",
    }],
    deploymentStatuses: [{
      id: 4343,
      state: "success",
      environment,
    }],
    ...overrides,
  };
  return async input => {
    const url = new URL(input);
    let value;
    if (url.pathname.endsWith("/deployments/4242/statuses")) value = values.deploymentStatuses;
    else if (url.pathname.endsWith("/deployments")) value = values.deployments;
    else if (url.pathname.endsWith(`/environments/${environment}`)) value = values.environment;
    else if (url.pathname.endsWith("/check-runs")) value = values.checks;
    else if (url.pathname.endsWith("/branches/main/protection")) value = values.protection;
    else if (url.pathname.endsWith("/branches/main")) value = values.branch;
    else if (url.pathname.endsWith("/repos/diegoenterprises/eusotrip-ios")) value = values.repo;
    else return new Response("{}", { status: 404 });
    return new Response(JSON.stringify(value), { status: 200 });
  };
}

const verify = fetchImpl => verifyGitHubReleaseGovernance({
  fetchImpl,
  token: "fixture-governance-token-value",
  repository,
  branch: "main",
  commit,
  requiredCheck,
  environment,
});

await assert.doesNotReject(() => verify(fixture()));
console.log("ok - exact protected main/check/environment governance passes");

await assert.rejects(
  verify(fixture({ branch: { protected: false, commit: { sha: commit } } })),
  /exact protected main head/,
);
console.log("ok - unprotected main is rejected");

await assert.rejects(
  verify(fixture({
    protection: {
      ...fixtureValues().protection,
      enforce_admins: { enabled: false },
    },
  })),
  /admin enforcement/,
);
console.log("ok - bypassable admin protection is rejected");

await assert.rejects(
  verify(fixture({ checks: { check_runs: [] } })),
  /one successful required HERE check/,
);
console.log("ok - missing exact-commit required check is rejected");

await assert.rejects(
  verify(fixture({
    checks: {
      check_runs: [{
        name: requiredCheck,
        status: "completed",
        conclusion: "success",
        head_sha: commit,
        app: { slug: "github-actions", id: 99999 },
      }],
    },
  })),
  /one successful required HERE check/,
);
console.log("ok - successful check app must match the protected app binding");

await assert.rejects(
  verify(fixture({
    environment: {
      name: environment,
      protection_rules: [],
      deployment_branch_policy: { protected_branches: true, custom_branch_policies: false },
    },
  })),
  /independent reviewers/,
);
console.log("ok - unreviewed release environment is rejected");

await assert.rejects(
  verify(fixture({ deployments: [] })),
  /reviewed GitHub release-environment deployment/,
);
console.log("ok - configured environment without a reviewed deployment is rejected");

await assert.rejects(
  verify(fixture({
    deploymentStatuses: [{ id: 4343, state: "pending", environment }],
  })),
  /deployment is not successful/,
);
console.log("ok - pending reviewed deployment is rejected");

function fixtureValues() {
  return {
    protection: {
      required_status_checks: { contexts: [], checks: [{ context: requiredCheck, app_id: 15368 }] },
      enforce_admins: { enabled: true },
      allow_force_pushes: { enabled: false },
      allow_deletions: { enabled: false },
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_last_push_approval: true,
        required_approving_review_count: 1,
      },
    },
  };
}

console.log("GitHub release governance regression harness passed: 8 cases.");
