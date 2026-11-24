"""Build an offline expedition replay: python tools/expedition/route_view.py REPORT [REPORT ...]."""
import argparse
import json
import math
from bisect import bisect_right
from pathlib import Path

if __package__:
    from .route_view_geometry import read_geometry
    from .route_view_html import PAGE
else:
    from route_view_geometry import read_geometry
    from route_view_html import PAGE


def finite(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def xyz(value):
    return isinstance(value, list) and len(value) == 3 and all(map(finite, value))


def tick_ok(value):
    return finite(value) and 0 <= value <= 2**53-1 and int(value) == value


def classify(kind):
    kind = kind.lower().replace('-', '_')
    if kind in {'input', 'probe', 'intent', 'decision', 'action_requested'} or kind.endswith('_intent'):
        return 'Intent'
    if kind in {'confirmed', 'action_confirmed'} or kind.endswith('_confirmed'):
        return 'Confirmed'
    return 'Dialogue' if kind == 'dialogue' else 'Observed'


def read_path(samples, field):
    if not isinstance(samples, list):
        raise ValueError(f'{field} must be an array')
    positions = {}
    for i, sample in enumerate(samples):
        if not isinstance(sample, list) or len(sample) != 4 or not tick_ok(sample[0]) or not xyz(sample[1:]):
            raise ValueError(f'invalid {field}[{i}]: expected [tick,x,y,z]')
        positions[sample[0]] = sample[1:]
    return positions


def normalize(report, label):
    if not isinstance(report, dict):
        raise ValueError('expected a report object')
    samples, records = report.get('path_samples', []), report.get('events', [])
    if not isinstance(samples, list) or not isinstance(records, list):
        raise ValueError('path_samples and events must be arrays')
    positions = read_path(samples, "path_samples")
    hale = read_path(report.get("hale_path_samples", []), "hale_path_samples")
    end = report.get('tick')
    if tick_ok(end) and xyz(report.get('feet')):
        positions.setdefault(end, report['feet'])
    ticks = sorted(positions)
    events = []
    for i, entry in enumerate(records):
        if not isinstance(entry, dict) or not tick_ok(entry.get('tick')) or not isinstance(entry.get('event'), str):
            raise ValueError(f'invalid events[{i}]: expected tick and event name')
        t, kind, value = entry['tick'], entry['event'], entry.get('value')
        point, source = entry.get('feet'), 'Audit feet'
        if not xyz(point):
            point = value.get('feet') if isinstance(value, dict) else None
            source = 'Legacy value.feet'
        if not xyz(point):
            point, source = None, 'No position recorded'
            j = bisect_right(ticks, t)
            if j and ticks[j-1] == t:
                point, source = positions[t], 'Path sample'
            elif 0 < j < len(ticks):
                a, b = ticks[j-1:j+1]
                fraction = (t-a)/(b-a)
                point = [u*(1-fraction)+v*fraction for u, v in zip(positions[a], positions[b])]
                source = 'Interpolated path (estimate)'
        events.append(dict(tick=t, kind=kind, value=value, phase=classify(kind), point=point, source=source))
    events.sort(key=lambda e: e['tick'])
    metadata = {k: v for k, v in report.items() if k not in {'path_samples', 'hale_path_samples', 'events', 'user_dir', 'feet', 'decision_trace'}}
    return dict(label=label, metadata=metadata, path=[[t, *positions[t]] for t in ticks], events=events,
                hale=[[t, *hale[t]] for t in sorted(hale)],
                end=max([0, *ticks, *hale, *(e['tick'] for e in events), end if tick_ok(end) else 0]))


def render(runs, geometry=None):
    # The JSON script element is inert, but HTML still recognizes a literal closing tag.
    payload = json.dumps(dict(runs=runs, geometry=geometry), ensure_ascii=True, allow_nan=False).replace('<', r'\u003c')
    return PAGE.replace('__ROUTE_PAYLOAD__', payload, 1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reports', type=Path, nargs='+')
    parser.add_argument('--geometry', type=Path, help='expedition-collision-v1 snapshot for the shared map')
    parser.add_argument('-o', '--output', type=Path, default=Path('.runtime/route-view.html'))
    args = parser.parse_args(argv)
    runs = []
    for path in args.reports:
        try:
            runs.append(normalize(json.loads(path.read_text(encoding='utf-8-sig')), (path.parent.name if path.name in ('route.json', 'report.json') else path.name)))
        except (OSError, ValueError) as exc:
            parser.error(f'{path}: {exc}')
    geometry = None
    if args.geometry:
        try:
            geometry = read_geometry(json.loads(args.geometry.read_text(encoding='utf-8-sig')), finite, xyz)
        except (OSError, ValueError) as exc:
            parser.error(f'{args.geometry}: {exc}')
    try:
        html = render(runs, geometry)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(html, encoding='utf-8')
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    print(args.output.resolve())


if __name__ == '__main__':
    main()
