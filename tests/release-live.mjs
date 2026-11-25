import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

const [runtime, artifact] = process.argv.slice(2);
assert(runtime && artifact, "usage: node tests/release-live.mjs <runtime> <CLI artifact>");
const cli = resolve(artifact);
const temp = mkdtempSync(join(tmpdir(), "moonsri-live-"));
const before = join(temp, "before"), after = join(temp, "after"), live = join(temp, "live");
const oldList = join(temp, "before.txt"), newList = join(temp, "after.txt");
const journal = join(temp, "order.json");
const home = "catalog/index.html", retire = "legacy/hours.html", launch = "launch/中文 门店/index.html";
const shared = "assets/shared.js", oldOnly = "assets/old.js", added = "assets/app.v2.js";
const v1 = "window.version = 1;\n", v2 = "window.version = 2;\n";
const legacy = "/* legacy */\n", next = "/* release */\n";
const digest = data => "sha384-" + createHash("sha384").update(data).digest("base64");
const tag = (path, integrity) => `<script src="/${path}" integrity="${integrity}"></script>`;
const sharedTag = tag(shared, digest(v1) + " " + digest(v2));
const step = (kind, path) => ({kind, path});
const finding = (path, expected, status) => ({path, expected, status});
const publishAsset = step("publish_asset", added), replaceAsset = step("replace_asset", shared);
const switchHome = step("switch_page", home), retirePage = step("retire_page", retire);
const publishPage = step("publish_page", launch);

function write(root, path, data) {
  const file = join(root, path);
  mkdirSync(dirname(file), {recursive: true});
  writeFileSync(file, data);
}

function copy(root, path) {
  const destination = join(live, path);
  mkdirSync(dirname(destination), {recursive: true});
  cpSync(join(root, path), destination);
}

function run(args) {
  const command = spawnSync(runtime, [cli, "review-release", ...args], {encoding: "utf8"});
  if (command.error) throw command.error;
  assert.equal(command.signal, null, command.stderr);
  return command;
}

let checks = 0;
function verify(steps, {
  flags = [], order = "partial", state = "match", findings = [], liveRoot = live,
  code = state === "error" ? 2 : state === "drift" || order === "incomplete" ? 1 : 0
} = {}) {
  writeFileSync(journal, JSON.stringify(steps));
  const result = run(["--before-root", before, "--after-root", after, "--json",
    "--before-pages", oldList, "--after-pages", newList, "--check-order", journal,
    "--verify-live", liveRoot, ...flags]);
  assert.equal(result.status, code, result.stdout + result.stderr);
  const report = JSON.parse(result.stdout);
  assert.equal(report.status, order);
  assert.equal(report.direction, flags.includes("--rollback") ? "rollback" : "forward");
  assert.equal(report.live.status, state);
  assert.deepEqual(report.live.findings, findings);
  // Both directions start with three page paths and two referenced assets.
  assert.equal(report.live.checked, 5 + steps.filter(action => action.kind === "publish_asset").length);
  checks++;
  return report;
}

try {
  write(before, shared, v1);
  write(before, oldOnly, legacy);
  write(before, home, "<title>Current</title>" + sharedTag);
  write(before, retire, tag(oldOnly, digest(legacy)));
  write(after, shared, v2);
  write(after, added, next);
  write(after, home, "<title>New</title>" + sharedTag);
  write(after, launch, tag(added, digest(next)));
  writeFileSync(oldList, home + "\n" + retire + "\n");
  writeFileSync(newList, launch + "\n" + home + "\n");
  cpSync(before, live, {recursive: true});

  // The absent new page has two missing parent directories at this point.
  verify([]);
  verify([], {flags: ["--require-complete"], order: "incomplete"});
  copy(after, launch);
  verify([], {state: "drift", findings: [finding(launch, "absent", "unexpected")]});
  rmSync(join(live, "launch"), {recursive: true});
  write(live, "launch", "A regular file blocks traversal to a nested page");
  verify([], {state: "error", findings: [finding(launch, "absent", "read_error")]});
  write(live, shared, "drift at the same time as a traversal error");
  verify([], {flags: ["--require-complete"], order: "incomplete", state: "error", findings: [
    finding(shared, "start", "different"), finding(launch, "absent", "read_error")
  ]});
  copy(before, shared);
  rmSync(join(live, "launch"));

  write(live, shared, "unauthorized bytes");
  verify([], {state: "drift", findings: [finding(shared, "start", "different")]});
  copy(before, shared);
  verify([publishAsset], {state: "drift", findings: [finding(added, "target", "missing")]});
  mkdirSync(join(live, added));
  verify([publishAsset], {state: "drift", findings: [finding(added, "target", "not_file")]});
  rmSync(join(live, added), {recursive: true});
  write(live, added, "pre-staged bytes");
  verify([]);
  verify([publishAsset], {state: "drift", findings: [finding(added, "target", "different")]});
  copy(after, added);
  verify([publishAsset]);

  // The journal is complete only after changing both shared files and the page inventory.
  const complete = [publishAsset, retirePage, replaceAsset, publishPage, switchHome];
  verify([publishAsset, retirePage], {
    state: "drift", findings: [finding(retire, "absent", "unexpected")]
  });
  rmSync(join(live, retire));
  copy(after, shared);
  rmSync(join(live, oldOnly));
  verify([publishAsset, retirePage, replaceAsset], {
    state: "drift", findings: [finding(oldOnly, "start", "missing")]
  });
  copy(before, oldOnly);
  verify([publishAsset, retirePage, replaceAsset]);
  copy(after, launch);
  copy(after, home);
  verify(complete, {flags: ["--require-complete"], order: "complete"});
  copy(before, home);
  verify(complete, {
    flags: ["--require-complete"], order: "complete", state: "drift",
    findings: [finding(home, "target", "different")]
  });
  copy(after, home);
  verify([], {flags: ["--rollback"]});
  copy(before, shared);
  verify([replaceAsset], {flags: ["--rollback"]});
  copy(after, shared);
  verify([replaceAsset], {
    flags: ["--rollback"], state: "drift", findings: [finding(shared, "target", "different")]
  });

  // A failed root listing cannot prove the absence of any nested page.
  const unlistable = join(temp, "root-is-a-file");
  writeFileSync(unlistable, "not a directory");
  for (const liveRoot of [unlistable, join(temp, "missing-root")]) {
    const expected = [shared, oldOnly, home, retire, launch].sort().map(path =>
      finding(path, path === launch ? "absent" : "start", "read_error"));
    verify([], {liveRoot, state: "error", findings: expected});
  }

  // Identical page source never excuses a bad asset in the destination snapshot.
  write(after, home, "<title>Current</title>" + sharedTag);
  write(after, shared, "wrong target bytes");
  const mismatch = run(["--before-root", before, "--after-root", after, "--json", home]);
  assert.equal(mismatch.status, 2);
  assert.match(mismatch.stdout + mismatch.stderr, /after page "catalog\/index\.html": integrity mismatch for "assets\/shared\.js"/);
  checks++;
  console.log(`Passed ${checks} live release checks`);
} finally {
  rmSync(temp, {recursive: true, force: true});
}
