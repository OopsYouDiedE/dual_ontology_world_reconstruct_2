"""Capture actual Forward+ decision snapshots through the existing game MCP."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp" / "game"))
import server  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--warm-frames", type=int, default=10)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    run = server.Run(args.seed, scene_key="rule_evaluation", eval_review=True)
    rows = []
    try:
        for i in range(75):
            data = run.request("wait", frames=args.warm_frames, screenshot=True, timeout=100)
            packet = json.loads(data[0])
            tag = packet["state"]["review"]
            if not tag or any(r["view"] == tag for r in rows):
                raise RuntimeError(f"review did not advance: {tag}; {run.log}")
            screenshot = args.out / (tag + ".png")
            shutil.copyfile(packet["screenshot"], screenshot)
            rows.append(dict(view=tag, image=str(screenshot.resolve()), renderer=packet["renderer"],
                             level=int(packet["state"]["level"]), tick=int(packet["state"]["tick"]),
                             exit_open=packet["state"]["exit_open"], worker_session=run.id))
            (args.out / "manifest.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
            print(tag, flush=True)
            if packet["state"]["status"] == "CAMP":
                return 0
            run.request("action", action="eval_next_review", frames=1, timeout=100)
        raise RuntimeError("capture limit reached before camp")
    finally:
        run.close()


if __name__ == "__main__":
    raise SystemExit(main())
