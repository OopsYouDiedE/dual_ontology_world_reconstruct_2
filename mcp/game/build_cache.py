"""Reuse only a verified, unchanged compilation in isolated production host runs.

Record after a successful ordinary dotnet/MSBuild invocation. The source fingerprint
must be captured before the build, and must still match when the result is recorded.
This is also useful on hosts whose nested process namespace prevents MSBuild startup.
No content, gameplay state or acceptance result is cached here.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".runtime/build-cache"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(backend):
    roots = [ROOT / "core", ROOT / "tools/building/SeatingFit.cs"]
    if backend == "cli":
        roots.append(ROOT / "tools/story")
    if backend == "godot":
        roots.append(ROOT / "scenes")
    files = [ROOT / "NuGet.Config", ROOT / "DualOntologyWorldReconstruct2.csproj",
             ROOT / "Directory.Build.props", ROOT / "global.json"]
    for root in roots:
        files.extend([root] if root.is_file() else
                     (p for p in root.rglob("*") if p.suffix in (".cs", ".csproj", ".props", ".targets")
                      and not any(part in ("obj", "bin", ".runtime") for part in p.relative_to(ROOT).parts)))
    digest = hashlib.sha256()
    for path in sorted(set(files)):
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def record(backend, output, log, expected, configuration):
    actual = fingerprint(backend)
    if actual != expected:
        raise RuntimeError("Source changed during compilation; build cache was not recorded")
    output = Path(output).resolve()
    assembly = "DuelView.Cli.dll" if backend == "cli" else "DualOntologyWorldReconstruct2.dll"
    if not (output / assembly).is_file() or not Path(log).is_file():
        raise RuntimeError("Missing real compiled assembly or original build log")
    artifacts = {p.relative_to(output).as_posix(): sha(p) for p in output.rglob("*") if p.is_file()}
    CACHE.mkdir(parents=True, exist_ok=True)
    receipt = {"backend": backend, "source_fingerprint": actual, "directory": str(output),
               "configuration": configuration, "recorded_epoch": time.time(),
               "build_log": str(Path(log).resolve()), "build_log_sha256": sha(Path(log)), "artifacts": artifacts}
    (CACHE / (backend + ".json")).write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    return receipt


def reuse(backend, destination=None):
    path = CACHE / (backend + ".json")
    if not path.is_file():
        return None
    receipt = json.loads(path.read_text(encoding="utf-8"))
    if receipt["source_fingerprint"] != fingerprint(backend):
        return None
    output = Path(receipt["directory"])
    for name, expected in receipt["artifacts"].items():
        source = output / name
        if not source.is_file() or sha(source) != expected:
            return None
    if destination:
        destination.mkdir(parents=True, exist_ok=False)
        for name in receipt["artifacts"]:
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(output / name, target)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("fingerprint", "record"))
    parser.add_argument("backend", choices=("cli", "godot"))
    parser.add_argument("--output")
    parser.add_argument("--log")
    parser.add_argument("--expected")
    parser.add_argument("--configuration", default="Release")
    args = parser.parse_args()
    if args.operation == "fingerprint":
        print(fingerprint(args.backend))
    else:
        result = record(args.backend, args.output, args.log, args.expected, args.configuration)
        print(json.dumps({key: result[key] for key in ("backend", "source_fingerprint", "directory", "configuration")}))
