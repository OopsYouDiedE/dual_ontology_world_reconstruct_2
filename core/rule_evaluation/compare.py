"""Compare two batch candidates on the same seed set and report next checks."""
import argparse
from collections import Counter
import json
from pathlib import Path

from .batch import INVALID


def compare(base, candidate):
    if base["seeds"] != candidate["seeds"]:
        raise ValueError("paired comparison requires identical seed sets and order")
    priorities = {
        "UNTELEGRAPHED_DEATH": "Inspect physical warning visibility and same-stance recovery; reject candidate.",
        "RAY_GAP_MISS": "Enlarge the interactive silhouette or add a clear scan position; reject candidate.",
        "TWITCH_EXECUTION_FAIL": "Lengthen the joint phase window or simplify the execution route; reject candidate.",
        "HIDDEN_MECHANIC_LEAK_OR_CONFLICT": "Reconcile the fixture with its whitebox transfer function; reject candidate.",
        "MULTI_AGENT_DEADLOCK": "Check that a safe evidence observation precedes the live multi-station conflict.",
        "TEMPORAL_PHASE_ERROR": "Compare the phase projection, observed reference clock, and available delay schedule.",
        "ACTIVE_SENSING_DEFICIT": "Inspect failed ray sweeps and the probe or comparison affordances.",
        "PSYCH_RISK_COLLAPSE": "Inspect coercion frequency and available low-risk alternatives.",
        "ANYTIME_BUDGET_BOTTLENECK": "Check last valid candidates and reduce redundant state expansion.",
    }
    out = {"paired_seeds":len(base["seeds"]),"config_before":base["config"],"config_after":candidate["config"],
           "validity_before":base["validity"],"validity_after":candidate["validity"],"deltas":{},"diagnostics":[]}
    for name, after in candidate["summary"].items():
        before=base["summary"].get(name)
        if not before or not after or before["count"] != after["count"]:
            continue
        if name == "sol" and base["roster"][name].get("sha256") != candidate["roster"][name].get("sha256"):
            continue
        out["deltas"][name] = {k:after[k]-before[k] for k in before if k!="count" and before[k] is not None and after.get(k) is not None}
        paired=[]
        for a,b in zip(base["per_seed"],candidate["per_seed"]):
            x,y=a["results"].get(name),b["results"].get(name)
            if x and y and x["status"] == y["status"] == "CAMP": paired.append(y["tick"]-x["tick"])
        if paired: out["deltas"][name]["paired_clear_tick_delta"] = sum(paired)/len(paired)
    counts=Counter()
    for row in candidate["per_seed"]:
        counts.update(d["tag"] for d in row["gate"]["invalid_design_defects"])
        for name in ("target","sol"):
            counts.update(row["results"].get(name,{}).get("failure_tags",[]))
    out["diagnostics"]=[{"tag":tag,"count":n,"action":priorities.get(tag,"Read the replay around the last successful operation.")}
                        for tag,n in sorted(counts.items(),key=lambda row:(row[0] not in INVALID,-row[1],row[0]))]
    out["recommendation"] = ("REJECT_INVALID_DESIGN" if candidate["validity"]["invalid_failure_count"] or
        any(candidate["validity"][k]<1 for k in ("zero_panic","reproducible","sampling_pass"))
        else "DISCRIMINATION_ACCEPTED" if candidate["release_accepted"] else "VALID_FOR_PLAYTEST; FINAL_DISCRIMINATION_PENDING")
    return out


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline",type=Path)
    parser.add_argument("candidate",type=Path)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    result=compare(*(json.loads(path.read_text(encoding="utf-8")) for path in (args.baseline,args.candidate)))
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(json.dumps(result,indent=2))
    return 1 if result["recommendation"] == "REJECT_INVALID_DESIGN" else 0


if __name__=="__main__":
    raise SystemExit(main())
