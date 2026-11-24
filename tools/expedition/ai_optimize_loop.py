#!/usr/bin/env python3
"""AI Closed-Loop Continuous Level Optimizer (Godot 4.7.2 .NET Headless).

Runs candidate level_genome.json configurations through REAL 60Hz Godot headless
simulations:
  1. CheeseBotTest.gd  -> adversarial exploit bot (ditch Hale, zero oil, solo stealth)
  2. WalkTest.gd       -> legitimate cooperative playthrough (A1 -> B4 -> B5 -> North -> Core -> Exit)
  3. HearingTest.gd    -> acoustic/rule fairness regression

Computes a composite multi-objective score:
  - Anti-Cheese (0..50): 50 if CheeseBot is blocked by rules, 0 if dominant exploit passes
  - Coop Fairness (0..30): 30 if WalkTest & HearingTest pass with zero regressions
  - Tension & Resource Engagement (0..20): rewards meaningful oil burn and high exposure pressure

Usage:
    python3 tools/expedition/ai_optimize_loop.py --godot /path/to/godot
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, Any, List


CANDIDATE_GENOMES: List[Dict[str, Any]] = [
    {
        "label": "R0_Old_Baseline (Pre-Fix)",
        "genome": {
            "base_oil_drain": 0.0,
            "dark_oil_drain": 1.0,
            "catwalk_oil_drain": 1.70,
            "both_lamp_exposure_rate": 0.0,
            "solo_bridge_sonar_interval": 999.0,
            "solo_bridge_sonar_exposure": 0.0,
            "hunter_rage_speed": 3.8,
            "catwalk_grace_sec": 0.0,
        },
    },
    {
        "label": "R1_Moderate_Sonar_Oil",
        "genome": {
            "base_oil_drain": 0.16,
            "dark_oil_drain": 1.05,
            "catwalk_oil_drain": 1.75,
            "both_lamp_exposure_rate": 0.45,
            "solo_bridge_sonar_interval": 6.5,
            "solo_bridge_sonar_exposure": 0.50,
            "hunter_rage_speed": 4.8,
            "catwalk_grace_sec": 3.5,
        },
    },
    {
        "label": "R2_Tuned_AntiCheese (Default)",
        "genome": {
            "base_oil_drain": 0.22,
            "dark_oil_drain": 1.05,
            "catwalk_oil_drain": 1.75,
            "both_lamp_exposure_rate": 0.55,
            "solo_bridge_sonar_interval": 4.8,
            "solo_bridge_sonar_exposure": 0.68,
            "hunter_rage_speed": 5.4,
            "catwalk_grace_sec": 3.5,
        },
    },
    {
        "label": "R3_Strict_Hardcore",
        "genome": {
            "base_oil_drain": 0.30,
            "dark_oil_drain": 1.15,
            "catwalk_oil_drain": 1.85,
            "both_lamp_exposure_rate": 0.65,
            "solo_bridge_sonar_interval": 3.8,
            "solo_bridge_sonar_exposure": 0.85,
            "hunter_rage_speed": 5.8,
            "catwalk_grace_sec": 3.0,
        },
    },
]


def run_godot(godot_bin: str, repo_root: Path, script: str, genome_path: Path, timeout_s: int = 35) -> tuple[int, str]:
    cmd = [
        godot_bin,
        "--headless",
        "--fixed-fps", "60",
        "--path", str(repo_root),
        "--script", f"res://{script}",
        "--",
        f"--genome={genome_path}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
    return proc.returncode, proc.stdout + "\n" + proc.stderr


def evaluate_candidate(godot_bin: str, repo_root: Path, label: str, genome: Dict[str, Any]) -> Dict[str, Any]:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as tf:
        json.dump(genome, tf, indent=2)
        gpath = Path(tf.name)
    try:
        rc_c, out_c = run_godot(godot_bin, repo_root, "scenes/expedition_01/CheeseBotTest.gd", gpath)
        cheese_data = {"cheesed": True, "fail_reason": "parse_err", "oil_left": 65.0, "peak_exposure": 0.0, "ticks": 0}
        for line in out_c.splitlines():
            if line.startswith("CHEESE_RESULT "):
                cheese_data = json.loads(line.split("CHEESE_RESULT ", 1)[1])
                break

        rc_w, out_w = run_godot(godot_bin, repo_root, "scenes/expedition_01/WalkTest.gd", gpath)
        walk_pass = rc_w == 0 and "PASS:" in out_w

        rc_h, out_h = run_godot(godot_bin, repo_root, "scenes/expedition_01/HearingTest.gd", gpath)
        hear_pass = rc_h == 0 and "PASS:" in out_h

        anti_cheese = 50.0 if not cheese_data["cheesed"] else 0.0
        coop_fairness = (20.0 if walk_pass else 0.0) + (10.0 if hear_pass else 0.0)
        oil_used = max(0.0, 65.0 - float(cheese_data["oil_left"]))
        tension = min(10.0, float(cheese_data["peak_exposure"]) / 1.45 * 10.0) + min(10.0, oil_used * 1.2)
        total = round(anti_cheese + coop_fairness + tension, 2)

        return {
            "label": label,
            "score": total,
            "cheesed": cheese_data["cheesed"],
            "cheese_fail": cheese_data["fail_reason"],
            "cheese_peak_exp": cheese_data["peak_exposure"],
            "cheese_oil_left": cheese_data["oil_left"],
            "walk_pass": walk_pass,
            "hearing_pass": hear_pass,
            "genome": genome,
        }
    finally:
        gpath.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="AI closed-loop headless Godot level optimizer")
    parser.add_argument("--godot", default=os.path.expanduser("~/.local/godot-4.7.2-mono/Godot_v4.7.2-stable_mono_linux.x86_64"))
    parser.add_argument("--json", default="", help="Optional output JSON report")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    results = []
    for item in CANDIDATE_GENOMES:
        res = evaluate_candidate(args.godot, repo_root, item["label"], item["genome"])
        results.append(res)

    print("=== AI Closed-Loop Level Optimization (60Hz Headless Godot) ===")
    hdr = f"{'Candidate':<30} | {'Score':>6} | {'Cheese?':>7} | {'PeakExp':>7} | {'OilLeft':>7} | {'Walk':>4} | {'Hear':>4}"
    print(hdr)
    print("-" * len(hdr))
    for r in results:
        print(
            f"{r['label']:<30} | {r['score']:>6.2f} | "
            f"{'BYPASS!' if r['cheesed'] else 'BLOCKED':>7} | "
            f"{r['cheese_peak_exp']:>7.2f} | {r['cheese_oil_left']:>7.1f} | "
            f"{'PASS' if r['walk_pass'] else 'FAIL':>4} | {'PASS' if r['hearing_pass'] else 'FAIL':>4}"
        )
    best = max(results, key=lambda x: x["score"])
    print(f"\nSelected Optimal Genome: {best['label']} (Score {best['score']})")
    if args.json:
        Path(args.json).write_text(json.dumps({"results": results, "best": best}, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
