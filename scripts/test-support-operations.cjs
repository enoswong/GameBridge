// Offline behavioral tests for the exact github-script source in the monitor workflow.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { test } = require("node:test");
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const script = fs.readFileSync(process.argv[2], "utf8");
const execute = new AsyncFunction("github", "context", "process", script);

async function simulate(state, status, existing = false) {
  const calls = [];
  const alert = { number: 42, title: "[GameBridge support monitor] Catalog health" };
  const issues = {
    listForRepo: async () => [],
    create: async (params) => calls.push(["create", params]),
    update: async (params) => calls.push(["update", params]),
    createComment: async (params) => calls.push(["comment", params]),
  };
  const github = { rest: { issues }, paginate: async () => existing ? [alert] : [] };
  const context = { repo: { owner: "fixture", repo: "repo" },
    serverUrl: "https://github.com", runId: 123 };
  await execute(github, context, { env: { STATE: state, JOB_STATUS: status } });
  return calls;
}

test("missing active catalog creates alert", async () => {
  const calls = await simulate("missing", "failure");
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "create");
  assert.match(calls[0][1].body, /verification failed/);
});

test("repeated failure updates existing alert, does not create another", async () => {
  const calls = await simulate("unknown", "failure", true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "update");
  assert.equal(calls[0][1].issue_number, 42);
});

test("expiry warning creates an alert", async () => {
  const calls = await simulate("renewal-due", "success");
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "create");
  assert.match(calls[0][1].body, /seven days/);
});

test("verified recovery comments and closes", async () => {
  const calls = await simulate("healthy", "success", true);
  assert.deepEqual(calls.map(x => x[0]), ["comment", "update"]);
  assert.equal(calls[1][1].state, "closed");
});

test("healthy channel with no alert stays quiet", async () => {
  assert.deepEqual(await simulate("healthy", "success"), []);
});

test("package failure must not be treated as healthy recovery", async () => {
  const calls = await simulate("healthy", "failure", true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "update");
  assert.notEqual(calls[0][1].state, "closed");
});
