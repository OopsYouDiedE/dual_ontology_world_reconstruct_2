"""Capture authored reference cameras through the same Forward+ bridge as game MCP."""
import json
from pathlib import Path
import sys

from look_studies_e2e import Lab

VIEWS = {
    "Entrance": "01-hall", "Chapel": "02-chapel", "Garden Gate": "03-gate",
    "Forest Camp": "04-camp", "Attic": "05-attic", "Meridian": "06-tourbillon", "Draft": "07-draft", "Security": "08-security", "Inspect": "09-inspect",
}


def main():
    out = Path(__file__).resolve().parents[2] / ".runtime/reference-plates"
    out.mkdir(parents=True, exist_ok=True)
    selected = set(sys.argv[1:]) or set(VIEWS.values())
    if selected.difference(VIEWS.values()):
        raise SystemExit(f"Choose one or more of: {', '.join(VIEWS.values())}")
    for name, slug in VIEWS.items():
        if slug not in selected:
            continue
        with Lab() as lab:
            lab.send()
            lab.button(name)
            if not lab.state['sdfgi']:
                lab.button('SDFGI')
            lab.button('Hide UI')
            lab.wait(100)
            assert lab.state['view'] == name and lab.state['sdfgi'] and not lab.state['hud_visible']
            (out / f"{slug}.png").write_bytes(Path(lab.capture(slug)).read_bytes())
            (out / f"{slug}.json").write_text(json.dumps(lab.state, indent=2), encoding="utf8")
            print(name, lab.directory, flush=True)
        log = (lab.directory / 'godot.log').read_text(encoding='utf8')
        assert 'Forward+' in log and 'ERROR:' not in log, log


if __name__ == '__main__':
    main()
