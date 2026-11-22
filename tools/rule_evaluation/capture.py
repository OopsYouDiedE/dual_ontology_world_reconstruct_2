"""Capture actual Forward+ decision snapshots through the existing game MCP."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp" / "game"))
import server  # noqa: E402


def verified_crew_stills(directory, seed):
    """Pair actual movie frames of an identified companion with the fixture they operate."""
    schedule = json.loads((directory/'schedule.json').read_text(encoding='utf-8'))
    receipt = json.loads((directory/'receipt.json').read_text(encoding='utf-8'))
    if (schedule['seed'] != seed or receipt['renderer'] != 'forward_plus' or receipt['status'] != 'CAMP'
            or receipt['tick'] != schedule['final_tick'] or receipt['packets'] != len(schedule['rows'])
            or receipt['state_sha256'] != schedule['final_state_sha256']):
        raise ValueError('crew frame receipt does not match the seed and verified replay')
    for row in schedule['rows']:
        if not row['proof'] or row['actor'] <= 0:
            continue
        for suffix, moment in (('-motion-start','stroke start'), ('','mechanism response')):
            key = row['proof'] + suffix
            frame = receipt['stills'][key]
            source = directory/(key+'.png')
            if not source.is_file():
                raise FileNotFoundError(f'missing Forward+ crew capture {source}')
            yield source, dict(view='crew-'+key, renderer='forward_plus', level=row['level'], tick=row['tick'],
                companion=row['actor'], fixture=row['target'], moment=moment, movie_frame=frame,
                movie_seconds=frame/schedule['fps'], source_policy=schedule['policy'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--warm-frames", type=int, default=10)
    parser.add_argument("--crew-film", type=Path, help="Include same-frame companion and equipment stills from a verified playthrough directory")
    parser.add_argument("--crew-only", action="store_true", help="Only collect the companion shots from --crew-film")
    args = parser.parse_args()
    if args.crew_only and not args.crew_film:
        parser.error("--crew-only requires --crew-film")
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    if args.crew_film:
        for path, row in verified_crew_stills(args.crew_film, args.seed):
            screenshot = args.out / (row['view'] + '.png')
            shutil.copyfile(path,screenshot)
            row['image'] = str(screenshot.resolve())
            rows.append(row)
        (args.out / 'manifest.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    if args.crew_only:
        return 0
    run = server.Run(args.seed, scene_key="rule_evaluation", eval_review=True)
    try:
        for _ in range(128):
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
