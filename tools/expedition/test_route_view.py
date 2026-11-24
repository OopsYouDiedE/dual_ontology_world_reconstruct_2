"""Tests for the standalone route viewer. Run from the repository root with unittest."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

from tools.expedition.route_view import finite, normalize, read_geometry, render, xyz


REPORT = {
    'profile': 'curious', 'outcome': 'completed', 'decision_trace': [{'tick': 10}], 'seed': 31, 'tick': 30, 'policy_parameters': {'hold': 12},
    'path_samples': [[20, 10, 4, 0], [0, 0, 0, 0]], 'feet': [13, 4, 0],
    'hale_path_samples': [[0, 1, 0, 0], [20, 3, 4, 0]],
    'events': [
        {'tick': 20, 'event': 'confirmed', 'value': '拉杆已启动', 'feet': [10, 4, 0]},
        {'tick': 10, 'event': 'input', 'value': {'key': 'Q'}},
        {'tick': 20, 'event': 'dialogue', 'value': '</script><img src=x onerror=alert(1)>', 'feet': [10, 4, 0]},
        {'tick': 0, 'event': 'probe', 'value': {'feet': [2, 0, 0]}},
        {'tick': 40, 'event': 'notice', 'value': 'after last sample'},
    ],
}
GEOMETRY = {
    'schema': 'expedition-collision-v1', 'plane': ['x', 'z'], 'vertical': 'y', 'units': 'meters', 'errors': [],
    'shapes': [
        {'shape': 'ConcavePolygonShape3D', 'y_range': [0, 4],
         'transform': [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]],
         'parameters': {'faces': [[0, 0, 0], [1, 0, 0], [1, 0, 1], [8, 4, 0], [9, 4, 0], [9, 4, 1]]},
         'footprints_xz': [[[0, 0], [1, 0], [1, 1]], [[8, 0], [9, 0], [9, 1]]]},
        {'role': 'player'}, {'disabled': True},
    ],
}


class RouteViewTests(unittest.TestCase):
    def test_audit_and_legacy_events(self):
        run = normalize(REPORT, 'test')
        self.assertEqual(run['end'], 40)
        self.assertNotIn('decision_trace', run['metadata'])
        self.assertEqual([0, 20, 30], [p[0] for p in run['path']])
        self.assertEqual(REPORT['hale_path_samples'], run['hale'])
        events = run['events']
        self.assertEqual([0, 10, 20, 20, 40], [e['tick'] for e in events])
        self.assertEqual(['Intent', 'Intent', 'Confirmed', 'Dialogue', 'Observed'], [e['phase'] for e in events])
        self.assertEqual([2, 0, 0], events[0]['point'])
        self.assertEqual([5, 2, 0], events[1]['point'])
        self.assertIn('estimate', events[1]['source'])
        self.assertEqual('Audit feet', events[2]['source'])
        self.assertIsNone(events[-1]['point'])

    def test_invalid_report(self):
        with self.assertRaisesRegex(ValueError, r'hale_path_samples\[0\]'):
            normalize({'hale_path_samples': [[0, 0, float('inf'), 0]]}, 'bad')
        with self.assertRaisesRegex(ValueError, 'events'):
            normalize({'events': [{'tick': True, 'event': 'probe'}]}, 'bad')

    def test_geometry_triangles_preserve_elevation_and_openings(self):
        shapes = read_geometry(GEOMETRY, finite, xyz)
        self.assertEqual([['static', 0, 0], ['static', 4, 4]], [s[:3] for s in shapes])
        self.assertEqual(GEOMETRY['shapes'][0]['footprints_xz'][1], shapes[1][3])
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            read_geometry({**GEOMETRY, 'errors': [{'shape': 'unknown'}]}, finite, xyz)

    def test_inert_payload_and_unicode_roundtrip(self):
        injection = '</ScRiPt><script>throw 1</script>'
        html = render([normalize(REPORT, injection)])
        payload = re.search(r'id="route-data">(.*?)</script>', html).group(1)
        self.assertNotIn('<', payload)
        self.assertEqual(injection, json.loads(payload)['runs'][0]['label'])
        self.assertEqual('拉杆已启动', json.loads(payload)['runs'][0]['events'][2]['value'])
        self.assertNotIn('innerHTML', html)

    def test_cli_with_geometry(self):
        Path('.runtime').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir='.runtime') as directory:
            root = Path(directory)
            (root/'report.json').write_text(json.dumps(REPORT), encoding='utf-8')
            (root/'geometry.json').write_text(json.dumps(GEOMETRY), encoding='utf-8')
            output = root/'viewer.html'
            subprocess.run([sys.executable, '-m', 'tools.expedition.route_view', str(root/'report.json'),
                            '--geometry', str(root/'geometry.json'), '-o', str(output)], check=True, capture_output=True)
            self.assertIn('"geometry": [["static", 0, 0', output.read_text(encoding='utf-8'))

    @unittest.skipUnless(os.environ.get('ROUTE_VIEW_BROWSER'), 'set ROUTE_VIEW_BROWSER to a Chromium executable')
    def test_offline_browser_interactions(self):
        checks = '''<script>
try {
  function check(ok,message){if(!ok)throw Error(message);}
  check(document.querySelectorAll('#timeline .event').length===6,'full action list');
  check(document.querySelectorAll('#actors > *').length===2,'player and Hale');
  check(!document.querySelectorAll('#runs input')[1].checked,'attempt route starts hidden');
  check(!document.querySelectorAll('#categories input')[3].checked,'dialogue starts filtered on map');
  document.querySelectorAll('#categories input')[3].click();
  const marker=[...document.querySelectorAll('.marker')].find(g=>g.textContent.includes('×2'));
  marker.dispatchEvent(new MouseEvent('click'));
  check(document.querySelectorAll('#stack button').length===2,'overlap stack');
  document.querySelectorAll('#stack button')[1].click();
  check(document.querySelector('#tick').value==='20','stack seeks to action');
  check(document.querySelector('button[aria-current]').dataset.phase==='Dialogue','dialogue selected');
  check(!document.querySelector('img'),'untrusted HTML stays text');
  const floor=document.querySelector('#floor');floor.value='0';floor.dispatchEvent(new Event('change'));
  check(!document.querySelector('#actors > *'),'upper actors hidden on lower floor');
  document.querySelector('button[aria-current]').click();
  check(floor.value==='2','timeline jumps to event elevation');
  check(document.querySelectorAll('#collision path').length===1,'collision visible on upper floor');
  const tick=document.querySelector('#tick');tick.value='0';tick.dispatchEvent(new Event('input'));
  check(document.querySelector('#time').textContent==='0 / 40','manual scrub');
  document.querySelector('#runs input').click();
  check(!document.querySelector('.marker'),'run filter hides map markers');
  check([...document.querySelectorAll('.event')].every(e=>getComputedStyle(e).display!=='none'),'run filter preserves full log');
  [...document.querySelectorAll('.event')].find(e=>e.textContent.includes('attempt')).click();
  check(document.querySelectorAll('#runs input')[1].checked,'log can enable hidden attempt');
  document.body.dataset.test='pass';
} catch(e) { document.body.dataset.test=e.message; }
</script>'''
        Path('.runtime').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir='.runtime') as directory:
            root = Path(directory).resolve()
            path = root/'browser-test.html'
            attempt = normalize({'outcome': 'failed', 'events': [{'tick': 0, 'event': 'decision',
                                 'value': '回头', 'feet': [2, 0, 0]}]}, 'attempt')
            html = render([normalize(REPORT, 'test'), attempt], read_geometry(GEOMETRY, finite, xyz))
            path.write_text(html.replace('</body>', checks + '</body>'), encoding='utf-8')
            output = subprocess.run([os.environ['ROUTE_VIEW_BROWSER'], '--headless', '--disable-gpu',
                                     f'--user-data-dir={root / "profile"}', '--dump-dom', path.as_uri()],
                                    check=True, timeout=45, capture_output=True).stdout
            result = re.search(rb'<body data-test="([^"]*)"', output)
            self.assertIsNotNone(result, 'Chromium did not return the test DOM')
            self.assertEqual(b'pass', result.group(1))


if __name__ == '__main__':
    unittest.main()
