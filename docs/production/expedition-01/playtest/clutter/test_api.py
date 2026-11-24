import unittest

from run import evaluate_rooms, generate_layout


class ClutterApiTest(unittest.TestCase):
    def test_graph_batch_and_layout_export(self):
        requests = [{'room_id': room_id, 'seed': 31}
                    for room_id in ('graph/entry', 'graph/archive', 'graph/entry')]
        report = evaluate_rooms(requests, controls=True)
        self.assertTrue(report['ok'])
        rows = report['rooms']
        self.assertEqual([(r['room_id'], r['seed']) for r in rows],
                         [(r['room_id'], r['seed']) for r in requests])
        for row in rows:
            self.assertEqual(row['status'], 'pass')
            self.assertEqual(row['layout_errors'], [])
            self.assertEqual(row['max_layer'], 3)
            self.assertEqual([t['direction'] for t in row['traversals']], ['west_to_east', 'east_to_west'])
            for traversal in row['traversals']:
                self.assertEqual(traversal['status'], 'pass')
                self.assertEqual(traversal['contacts'], {})
                self.assertEqual(traversal['off_floor_frames'], 0)
        self.assertEqual(rows[0]['layout'], rows[2]['layout'])
        self.assertNotEqual(rows[0]['layout']['items'], rows[1]['layout']['items'])
        self.assertEqual(rows[0]['layout'], generate_layout('graph/entry', 31))
        self.assertEqual(len(report['controls']), 6)
        self.assertTrue(all(c['caught'] for c in report['controls']))

    def test_packing_sweep(self):
        key = {'room_id': 'graph/entry', 'seed': 31}
        settings = [(0, 5), (0.3, 5), (1, 1), (1, 3), (1, 5)]
        rows = evaluate_rooms([dict(key, density=d, max_layers=m) for d, m in settings])['rooms']
        self.assertEqual([r['max_layer'] for r in rows], [0, 5, 1, 3, 5])
        self.assertTrue(all(r['status'] == 'pass' for r in rows))
        bases = [sum(item['layer'] == 1 for item in r['layout']['items']) for r in rows]
        self.assertLess(0, bases[1])
        self.assertLess(bases[1], bases[4])
        self.assertEqual(rows[1]['layout'], generate_layout(**key, density=0.3, max_layers=5))
        for density, max_layers in ((-1, 3), (True, 3), (float('nan'), 3), (1, 0), (1, 6), (1, 2.0)):
            with self.assertRaises(ValueError):
                generate_layout(**key, density=density, max_layers=max_layers)

    def test_furnished_same_envelope_and_obstructed_work_bay(self):
        key = {'room_id': 'prototype/workshop-dispatch', 'seed': 31}
        report = evaluate_rooms([key, dict(key, mode='furnished'),
                                 dict(key, mode='furnished', density=0)], furnished_control=True)
        self.assertTrue(report['ok'])
        before, after, empty_dressing = report['rooms']
        for field in ('room_size', 'room_id', 'seed', 'door_width'):
            self.assertEqual(before['layout'][field], after['layout'][field])
        self.assertNotEqual(before['layout']['items'], after['layout']['items'])
        self.assertEqual(len(empty_dressing['layout']['items']), 8)
        self.assertEqual(len(after['station_traversals']), 4)
        self.assertEqual({(t['station'], t['direction']) for t in after['station_traversals']},
                         {(s, d) for s in ('workshop', 'dispatch') for d in ('approach', 'return')})
        self.assertTrue(all(t['status'] == 'pass' and not t['contacts'] and not t['off_floor_frames']
                            for t in after['station_traversals']))
        control, = report['controls']
        self.assertEqual(control['traversal']['status'], 'blocked')
        self.assertTrue({'work_stool', 'stool_seat'} & control['traversal']['contacts'].keys())
        self.assertEqual(control['main_aisle']['status'], 'pass')
        self.assertEqual(after['layout'], generate_layout(**key, mode='furnished'))
        with self.assertRaises(ValueError):
            generate_layout(**key, mode='unknown')

    def test_invalid_seed(self):
        for seed in (True, 1.0, 2**53):
            with self.assertRaises(ValueError):
                generate_layout('graph/entry', seed)


if __name__ == '__main__':
    unittest.main()
