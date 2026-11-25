"""Compare release builds of two MoonSRI revisions. Requires Python 3.10+."""

import argparse
import hashlib
import io
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import tempfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from fixtures import CASES, make_case

ROOT = Path(__file__).resolve().parents[1]
RUNNERS = {"js": "node", "wasm-gc": "moonrun"}


def checked(command, cwd):
    return subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, check=True).stdout


def build(temp, label, revision, targets):
    if revision == "WORKTREE":
        source = ROOT
        identifier = "WORKTREE"
    else:
        identifier = checked(["git", "rev-parse", "--verify", revision + "^{commit}"], ROOT).decode().strip()
        archive = checked(["git", "archive", "--format=zip", identifier], ROOT)
        source = temp / label
        with zipfile.ZipFile(io.BytesIO(archive)) as snapshot:
            snapshot.extractall(source)
    # Fingerprint production sources and manifests even for an uncommitted build.
    digest = hashlib.sha256()
    for directory, children, files in os.walk(source):
        children[:] = sorted(d for d in children if not d.startswith(".") and d not in ("_build", "target"))
        if "moon.pkg" not in files and "moon.mod" not in files:
            continue
        for name in sorted(files):
            path = Path(directory) / name
            if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
                continue
            if path.suffix != ".mbt" and path.name not in ("moon.pkg", "moon.mod"):
                continue
            digest.update(path.relative_to(source).as_posix().encode() + b"\0")
            digest.update(path.read_bytes().replace(b"\r\n", b"\n") + b"\0")
    lines = checked([
        "moon", "build", "--release", "--output-json", "--target", ",".join(targets),
        "--target-dir", str(temp / f"build-{label}"), "cmd/main",
    ], source).decode().splitlines()
    artifacts = {}
    for line in lines:
        message = json.loads(line)
        if message.get("$message_type") == "artifact" and message["package"].endswith("/cmd/main"):
            artifacts[message["target_backend"]] = message["path"]
    if set(artifacts) != set(targets):
        raise RuntimeError(f"Missing build artifacts: {artifacts}")
    module = (source / "moon.mod").read_text(encoding="utf-8")
    version = re.search(r'^version\s*=\s*"([^"]+)"', module, re.M).group(1)
    return artifacts, {"revision": identifier, "version": version, "source_sha256": digest.hexdigest()}


def invoke(artifact, target, case_dir, options, expected_code):
    command = [
        RUNNERS[target], artifact, "review-release", "--before-root", "before", "--after-root", "after",
        "--before-pages", "before.txt", "--after-pages", "after.txt", "--json", *options,
    ]
    start = time.perf_counter_ns()
    run = subprocess.run(command, cwd=case_dir, capture_output=True)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    if run.returncode != expected_code or run.stderr:
        raise RuntimeError(f"{case_dir.name} exit {run.returncode}: {(run.stderr or run.stdout)[:500]!r}")
    return elapsed, run.stdout


def execute(artifact, target, case_dir, shape):
    expected_status = "blocked" if shape.cycle else "safe"
    elapsed, stdout = invoke(artifact, target, case_dir, [], int(bool(shape.cycle)))
    report = json.loads(stdout)
    if (report["status"], [len(w) for w in report["waves"]], len(report["constraints"]), len(report["cycle"])) != (
        expected_status, shape.waves, shape.edges, shape.cycle
    ):
        raise ValueError(f"{case_dir.name} failed its expected graph shape")
    if shape.cycle and report["cycle"][0] != report["cycle"][-1]:
        raise ValueError(f"{case_dir.name} has an open cycle witness")
    return elapsed, stdout


def compare(case_dir, shape, artifacts, target, samples):
    raw = {"baseline": [], "candidate": []}
    reference = None
    # Round zero warms up both versions. Alternate order to reduce order bias.
    for iteration in range(samples + 1):
        order = ("baseline", "candidate") if iteration % 2 == 0 else ("candidate", "baseline")
        for label in order:
            elapsed, stdout = execute(artifacts[label][target], target, case_dir, shape)
            if reference is None:
                reference = stdout
            elif reference != stdout:
                raise ValueError(f"{case_dir.name} JSON bytes differ for {target}/{label}")
            if iteration:
                raw[label].append(round(elapsed, 3))
    medians = {label: round(statistics.median(values), 3) for label, values in raw.items()}
    return {
        "stdout_sha256": hashlib.sha256(reference).hexdigest(),
        "stdout_bytes": len(reference),
        "samples_ms": raw,
        "median_ms": medians,
        "delta_percent": round((medians["candidate"] / medians["baseline"] - 1) * 100, 1),
    }, json.loads(reference)


def bootstrap_checkpoint(case_dir, plan, artifacts, samples):
    # Both assets and half the pages have been published. Materialize exactly
    # those file actions over the starting tree before starting the stopwatch.
    assets, pages = plan["waves"]
    steps = assets + pages[:12]
    live = case_dir / "live"
    shutil.copytree(case_dir / "before", live)
    for action in steps:
        target = live / action["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(case_dir / "after" / action["path"], target)
    (case_dir / "steps.json").write_text(json.dumps(steps), encoding="utf-8")
    rows = {}
    for target, artifact in artifacts.items():
        timed = {"order": [], "order_and_live": []}
        fingerprints = {}
        for iteration in range(samples + 1):
            modes = list(timed) if iteration % 2 == 0 else list(reversed(timed))
            for mode in modes:
                options = ["--check-order", "steps.json"]
                expected = {
                    "direction": "forward", "status": "partial", "completed": 14, "total": 26,
                    "ready": pages[12:],
                }
                if mode == "order_and_live":
                    options.extend(["--verify-live", "live"])
                    expected["live"] = {"status": "match", "checked": 28, "findings": []}
                elapsed, stdout = invoke(artifact, target, case_dir, options, 0)
                if json.loads(stdout) != expected:
                    raise ValueError(f"{target}/{mode} returned an incorrect deployment checkpoint")
                fingerprint = hashlib.sha256(stdout).hexdigest()
                if fingerprints.setdefault(mode, fingerprint) != fingerprint:
                    raise ValueError(f"{target}/{mode} produced inconsistent checkpoint output")
                if iteration:
                    timed[mode].append(round(elapsed, 3))
        rows[target] = {
            "samples_ms": timed, "median_ms": {k: statistics.median(v) for k, v in timed.items()},
            "stdout_sha256": fingerprints,
        }
        print(f"bootstrap-checkpoint {target} {rows[target]['median_ms']} ms", flush=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="v0.7.2", help="git revision")
    parser.add_argument("--candidate", default="WORKTREE", help="git revision or WORKTREE")
    parser.add_argument("--samples", type=int, default=5, help="timed runs per case/backend/version")
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    parser.add_argument("--targets", nargs="+", choices=RUNNERS, default=list(RUNNERS))
    parser.add_argument("--checkpoint", action="store_true", help="also time a candidate-only Bootstrap deployment checkpoint")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    if args.checkpoint and "bootstrap-upgrade" not in args.cases:
        parser.error("--checkpoint requires the bootstrap-upgrade case")
    toolchain = checked(["moon", "version", "--all"], ROOT).decode().splitlines()
    report = {
        "started_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "system": platform.platform(), "cpu": platform.processor(), "logical_cpus": os.cpu_count(),
        "python": platform.python_version(), "node": checked(["node", "--version"], ROOT).decode().strip()
        if "js" in args.targets else None,
        "moonbit": [line.split(")")[0] + ")" for line in toolchain if line.startswith(("moon ", "moonc ", "moonrun "))],
        "samples_per_version": args.samples, "warmups_per_version": 1, "revisions": {}, "cases": {},
    }
    with tempfile.TemporaryDirectory(prefix="moonsri-bench-") as tmp:
        temp = Path(tmp)
        artifacts = {}
        for label, ref in (("baseline", args.baseline), ("candidate", args.candidate)):
            artifacts[label], report["revisions"][label] = build(temp, label, ref, args.targets)
        for name in args.cases:
            case_dir = temp / "cases" / name
            shape, inputs = make_case(case_dir, name)
            case = {
                "inputs": inputs, "waves": shape.waves, "constraints": shape.edges,
                "cycle_length": shape.cycle, "exit_code": int(bool(shape.cycle)), "backends": {},
            }
            expected_report = None
            for target in args.targets:
                metrics, output = compare(case_dir, shape, artifacts, target, args.samples)
                if expected_report is not None and expected_report != output:
                    raise ValueError(f"{name} JSON differs between backends")
                expected_report = output
                case["backends"][target] = metrics
                print(f"{name:18} {target:8} {metrics['median_ms']} ms ({metrics['delta_percent']:+.1f}%)", flush=True)
            report["cases"][name] = case
            if args.checkpoint and name == "bootstrap-upgrade":
                report["bootstrap_checkpoint"] = bootstrap_checkpoint(case_dir, expected_report, artifacts["candidate"], args.samples)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
