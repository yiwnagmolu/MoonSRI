import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { tmpdir } from "node:os";

const [host, artifact] = process.argv.slice(2);
assert(host && artifact, "usage: node tests/release-order.mjs <runtime> <CLI artifact>");
const sample = "examples/rollout";
const old = path.join(sample, "before");
const next = path.join(sample, "versioned");
const pages = ["index.html", "hours/index.html"];
const tmp = fs.mkdtempSync(path.join(tmpdir(), "moonsri-order-"));
const journal = path.join(tmp, "actions.json");
const app = { kind: "publish_asset", path: "assets/app.v2.js" };
const banner = { kind: "publish_asset", path: "assets/banner.js" };
const hours = { kind: "switch_page", path: "hours/index.html" };
const index = { kind: "switch_page", path: "index.html" };

function run(code, args) {
  const result = spawnSync(host, [artifact, "review-release", ...args], { encoding: "utf8" });
  if (result.error) throw result.error;
  assert.equal(result.status, code, result.stdout + result.stderr);
  return result;
}

function roots(start = old, end = next) {
  return ["--before-root", start, "--after-root", end, "--json"];
}

function check(steps, code, ...options) {
  fs.writeFileSync(journal, "\uFEFF" + JSON.stringify(steps));
  return JSON.parse(run(code, [...roots(), "--check-order", journal, ...options, ...pages]).stdout);
}

try {
  const empty = check([], 0);
  assert.deepEqual(empty, {
    status: "partial", direction: "forward", completed: 0, total: 4, ready: [app, banner],
  });
  const one = check([app], 0);
  assert.deepEqual(one.ready, [banner, hours]);
  const short = check([app, hours], 1, "--require-complete");
  assert.equal(short.status, "incomplete");
  assert.deepEqual(short.ready, [banner]);

  const example = JSON.parse(fs.readFileSync(path.join(sample, "order.json"), "utf8"));
  assert.deepEqual(example, [app, hours, banner, index]);
  assert.deepEqual(check(example, 0, "--require-complete"), {
    status: "complete", direction: "forward", completed: 4, total: 4, ready: [],
  });
  const early = check([app, index, banner], 1);
  assert.deepEqual(early.failure, {
    step: 2, reason: "unmet_prerequisites", action: index, waiting_for: [banner],
  });
  assert.deepEqual(early.ready, one.ready);
  assert.equal(early.completed, 1);
  assert.equal(check([index], 1, "--verify-live", old).live, undefined);
  assert.equal(check([app, app], 1).failure.reason, "repeated_action");
  assert.equal(check([{ ...app, path: "unknown.js" }], 1).failure.reason, "unknown_action");
  assert.equal(check([{ ...hours, kind: "publish_page" }], 1).failure.reason, "unknown_action");

  fs.writeFileSync(journal, "[]");
  const cyclic = JSON.parse(run(1, [
    ...roots(old, path.join(sample, "overwrite")), "--check-order", journal, ...pages,
  ]).stdout);
  assert.equal(cyclic.status, "blocked");
  assert.deepEqual(cyclic.cycle[0], cyclic.cycle.at(-1));
  assert(cyclic.cycle.length >= 3);
  for (const raw of [
    "{}", "{", "[null]", '[{"kind":"switch_page","path":42}]',
    '[{"kind":"switch_page","path":"x","path":"y"}]',
    '[{"kind":"update","path":"x"}]', '[{"kind":"switch_page","path":"../x"}]',
    '[{"kind":"switch_page","path":"x","extra":true}]',
  ]) {
    fs.writeFileSync(journal, raw);
    run(2, [...roots(), "--check-order", journal, ...pages]);
  }
  fs.writeFileSync(journal, Buffer.from([0xff, 0xfe]));
  run(2, [...roots(), "--check-order", journal, ...pages]);
  run(2, [...roots(), "--require-complete", ...pages]);
  run(2, [...roots(), "--verify-live", next, ...pages]);
  run(2, [...roots(), "--rollback", "--rollback", ...pages]);
  run(2, [...roots(), "--check-order", journal, "--check-order", journal, ...pages]);

  const listA = path.join(tmp, "old.txt");
  const listB = path.join(tmp, "new.txt");
  fs.writeFileSync(listA, "index.html\n");
  fs.writeFileSync(listB, "hours/index.html\n");
  function inventory(start, end) {
    return ["--before-pages", start, "--after-pages", end];
  }
  const reverseArgs = [...roots(), ...inventory(listA, listB), "--rollback"];
  const reverse = JSON.parse(run(0, reverseArgs).stdout);
  const explicit = JSON.parse(run(0, [...roots(next, old), ...inventory(listB, listA)]).stdout);
  assert.deepEqual(reverse, { ...explicit, direction: "rollback" });
  const reverseOrder = reverse.waves.flat();
  assert(reverseOrder.some(a => a.kind === "retire_page" && a.path === hours.path));
  assert(reverseOrder.some(a => a.kind === "publish_page" && a.path === index.path));
  fs.writeFileSync(journal, JSON.stringify(reverseOrder));
  const back = JSON.parse(run(0, [...reverseArgs, "--check-order", journal, "--require-complete"]).stdout);
  assert.equal(back.direction, "rollback");
  assert.equal(back.status, "complete");

  const textArgs = ["--before-root", old, "--after-root", next, "--check-order", journal];
  fs.writeFileSync(journal, JSON.stringify([index]));
  assert.match(run(1, [...textArgs, ...pages]).stdout, /step 1 unmet_prerequisites/);

  // Unchanged HTML can reuse parsing; each snapshot must still verify its own file bytes.
  const broken = path.join(tmp, "broken");
  fs.cpSync(old, broken, { recursive: true });
  fs.appendFileSync(path.join(broken, "assets/app.js"), "\nchanged\n");
  const result = run(2, [...roots(old, broken), ...pages]);
  assert.match(result.stdout + result.stderr, /after page .*integrity mismatch for "assets\/app.js"/);
  console.log("Release ordering, rollback inventories and snapshot isolation passed.");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
