"""Measure full release acceptance using a compiled MoonSRI CLI. Python 3.10+."""

import argparse
import hashlib
import json
import os
import platform
import shutil
import statistics
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from fixtures import put, shared
from review_release import ROOT, RUNNERS, build, checked, invoke


def cpu_name():
    if os.name == "nt":
        import winreg
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                            r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
            return winreg.QueryValueEx(key, "ProcessorNameString")[0].strip()
    info = Path("/proc/cpuinfo")
    if info.exists():
        for line in info.read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    return platform.processor() or platform.machine()


def prepare(case_dir, name):
    before, after = case_dir / "before", case_dir / "after"
    if name == "storefront":
        example = ROOT / "examples" / "rollout"
        shutil.copytree(example / "before", before)
        shutil.copytree(example / "versioned", after)
        steps = json.loads((example / "order.json").read_bytes())
        waves, edges, checked_paths = [2, 2], 3, 6
    else:
        pages = 64
        shared(before, after, 512 * 1024, pages, 2)
        steps = [{"kind": "switch_page", "path": f"p{i:04}.html"} for i in range(pages)]
        steps.append({"kind": "replace_asset", "path": "assets/shared.js"})
        waves, edges, checked_paths = [pages, 1], pages, pages + 1

    for root in (before, after):
        inventory = sorted(path.relative_to(root).as_posix() for path in root.rglob("*.html"))
        put(case_dir, root.name + ".txt", "".join(name + "\n" for name in inventory))
    put(case_dir, "order.json", json.dumps(steps))
    # Separate on-disk deployment. Copy the starting tree first because the
    # storefront keeps its old-only app.js after both pages have migrated.
    live = case_dir / "live"
    shutil.copytree(before, live)
    for step in steps:
        target = live / step["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(after / step["path"], target)
    files = [p for p in live.rglob("*") if p.is_file()]
    if len(files) != checked_paths:
        raise ValueError("Unexpected live fixture shape")
    if name == "shared-512kib":
        drift = case_dir / "drift"
        shutil.copytree(live, drift)
        with (drift / "assets/shared.js").open("r+b") as asset:
            asset.seek(-1, 2)
            previous = asset.read(1)
            asset.seek(-1, 2)
            asset.write(bytes([previous[0] ^ 1]))
    return {
        "pages": sum(p.suffix == ".html" for p in files), "live_files": len(files),
        "live_bytes": sum(p.stat().st_size for p in files),
        "waves": waves, "constraints": edges, "steps": len(steps), "checked_paths": checked_paths,
    }


def sample(artifact, target, case_dir, metadata, mode):
    flags = [] if mode == "plan" else ["--check-order", "order.json", "--require-complete"]
    if mode in ("live_match", "live_drift"):
        flags.extend(["--verify-live", "drift" if mode == "live_drift" else "live"])
    elapsed, stdout = invoke(artifact, target, case_dir, flags, int(mode == "live_drift"))
    result = json.loads(stdout)
    if mode == "plan":
        if (result["status"], [len(wave) for wave in result["waves"]], len(result["constraints"]),
            result["cycle"]) != ("safe", metadata["waves"], metadata["constraints"], []):
            raise ValueError(f"{target}/{case_dir.name}: incorrect release plan")
    else:
        expected = {"status": "complete", "direction": "forward", "completed": metadata["steps"],
                    "total": metadata["steps"], "ready": []}
        if mode.startswith("live_"):
            drift = mode == "live_drift"
            expected["live"] = {"status": "drift" if drift else "match", "checked": metadata["checked_paths"],
                                "findings": [{"path": "assets/shared.js", "expected": "target",
                                              "status": "different"}] if drift else []}
        if result != expected:
            raise ValueError(f"{target}/{case_dir.name}/{mode}: {result!r}")
    return round(elapsed, 3), hashlib.sha256(stdout).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="WORKTREE", help="Git revision or WORKTREE")
    parser.add_argument("--targets", nargs="+", choices=RUNNERS, default=list(RUNNERS))
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("samples must be positive")
    toolchain = checked(["moon", "version", "--all"], ROOT).decode().splitlines()
    report = {
        "started_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "system": platform.platform(), "cpu": cpu_name(), "logical_cpus": os.cpu_count(),
        "python": platform.python_version(), "node": checked(["node", "--version"], ROOT).decode().strip()
        if "js" in args.targets else None,
        "moonbit": [line.split(")")[0] + ")" for line in toolchain if line.startswith(("moon ", "moonc ", "moonrun "))],
        "warmups_per_mode": 1, "samples_per_mode": args.samples, "cases": {},
    }
    with tempfile.TemporaryDirectory(prefix="moonsri-checkpoint-") as tmp:
        temp = Path(tmp)
        artifacts, report["build"] = build(temp, "candidate", args.revision, args.targets)
        for name in ("storefront", "shared-512kib"):
            case_dir = temp / "fixtures" / name
            metadata = prepare(case_dir, name)
            report["cases"][name] = {"input": metadata, "backends": {}}
            modes = ["plan", "order", "live_match"]
            if name == "shared-512kib":
                modes.append("live_drift")
            fingerprints = {}
            for target, artifact in artifacts.items():
                raw = {mode: [] for mode in modes}
                for round_no in range(args.samples + 1):
                    # Rotate the launch order on each round. Every sample
                    # starts a new process; warmup populates the filesystem cache.
                    offset = round_no % len(modes)
                    for mode in modes[offset:] + modes[:offset]:
                        elapsed, fingerprint = sample(artifact, target, case_dir, metadata, mode)
                        if fingerprints.setdefault(mode, fingerprint) != fingerprint:
                            raise ValueError(f"{name}/{target}/{mode} changed its JSON output")
                        if round_no:
                            raw[mode].append(elapsed)
                medians = {mode: statistics.median(values) for mode, values in raw.items()}
                report["cases"][name]["backends"][target] = {"samples_ms": raw, "median_ms": medians}
                print(name, target, medians, "ms", flush=True)
            report["cases"][name]["stdout_sha256"] = fingerprints
    report["finished_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
