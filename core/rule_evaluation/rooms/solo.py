"""Rooms 01-02: independent, seeded first-person teaching puzzles."""


def _entity(id, label, kind, x, z, width, height, depth, *, y=0,
            color, solid=True, state=None, ops=None, transform=None):
    entity = dict(id=id, label=label, kind=kind, pos=[x, z],
                  size=[width, height, depth], y=y, color=color, solid=solid)
    if state is not None:
        entity['state'] = state
    if ops is not None:
        entity['ops'] = ops
    if transform is not None:
        entity['transform'] = transform
    return entity


def _interact(target, op):
    return dict(type='Interact', target_entity_id=target, op_type=op)


def _move(x, z, ticks):
    return dict(type='Move', dir_vec=[x, z], speed_ratio=100, duration_ticks=ticks)


def _wait():
    return dict(type='Wait')


def _exit(z):
    return _entity('exit', 'EXIT', 'exit', 0, z, 1650, 2400, 250,
                   color='#628b84', solid=False)


def _synchronizer(rng, phase_bias):
    period = 20 * rng.randint(12, 14)
    offset = 20 * rng.randint(2, 3)
    window = min(period - 60, 160 + phase_bias)
    trim = ('#4f7e88', '#587886', '#4d8379')[rng.randint(0, 2)]
    aligned = ['and', ['phase', 'left_cam'], ['phase', 'right_cam']]
    return dict(
        title='01 | The Synchronizer', start=[0, 1500], size=[7600, 9200],
        entities=[
            _entity('left_cam', f'LEAD CAM {window}/{period} T',
                    'phase-cam', -1670, 4600, 1300, 1400, 720, y=650,
                    color='#b8874d', transform={'field': 'active', 'offset': [0, 360, 0]},
                    state={'active': 0, 'period': period,
                                            'offset': 0, 'window': window}),
            _entity('right_cam', f'LAG CAM +{offset} T',
                    'phase-cam', 1670, 4600, 1300, 1400, 720, y=650,
                    color=trim, transform={'field': 'active', 'offset': [0, 360, 0]},
                    state={'active': 0, 'period': period,
                                       'offset': -offset, 'window': window}),
            _entity('left_rail', '', 'divider', -1670, 5060,
                    1100, 2460, 440, color='#645d54'),
            _entity('right_rail', '', 'divider', 1670, 5060,
                    1100, 2460, 440, color='#645d54'),
            _entity('latch', 'LOCK BOTH CAMS', 'switch', 0, 3880,
                    1280, 1190, 650, color='#88725d', state={'latched': 0},
                    transform={'field': 'latched', 'offset': [0, -110, 0]},
                    ops={'latch': {'when': aligned,
                                   'effects': [['latch', 'latched', 1]]}}),
            _exit(7980),
        ],
        phases=[dict(id=id, period=period, offset=shift, window=window, field='active')
                for id, shift in [('left_cam', 0), ('right_cam', -offset)]],
        room_rules=[],
        manuals={0: [dict(rule_id='01.check-both-cams', scope='SELF',
                           modality='FORBID', condition=['not', aligned],
                           action=dict(op_type='latch', target_entity_id='latch'),
                           source='NATIVE')]},
        public_exit=True,
        exit_when=['eq', 'latch', 'latched', 1],
        witness=[_move(0, 1, 3), *[_wait() for _ in range(3)],
                 _interact('latch', 'latch'), _move(0, 1, 5),
                 _move(1, 0, 14), _move(1, 0, 14), _move(0, 1, 20), _move(0, 1, 20),
                 _move(-1, 0, 14), _move(-1, 0, 14), _interact('exit', 'traverse')],
        hint='Both cams must be engaged at once. Watch both active indicators, then lock the latch. A dry pull is harmless.',
    )


def _inspection(rng):
    fault = rng.randint(0, 2)
    standard = (-1, 1)[rng.randint(0, 1)]
    trim = ('#377e80', '#3d718b', '#627e69')[rng.randint(0, 2)]
    entities = [_exit(8300)]
    baseline_x = 3300
    # A vertical datum and a horizontal arm form a large, legible bracket.
    # The exported comparison is geometric: the arm shifts from above the
    # center of the datum to below it (or vice versa for the mirror fixture).
    for index, x in enumerate((baseline_x, 1100, -1100, -3300)):
        master = index == 0
        station = 'master' if master else f'bay_{index}'
        label = 'MASTER' if master else f'BAY {index}'
        arm_side = -standard if index == fault + 1 else standard
        entities.extend([
            _entity(f'{station}_datum', label, 'inspection-datum', x - 560, 5060,
                    320, 2950, 500, color='#877753'),
            _entity(f'{station}_arm', '', 'inspection-arm', x + 175, 5020,
                    1250, 700, 540, y=1575 + 525 * arm_side, color=trim),
        ])
        if not master:
            result = int(arm_side != standard)
            selection = [[f'bay_{number}', 'selected', int(number == index)]
                         for number in range(1, 4)]
            entities.append(_entity(
                station, f'REJECT {label}', 'switch', x, 4370, 1280, 1270, 450,
                color='#96774d', state={'selected': 0},
                transform={'field': 'selected', 'offset': [0, -120, 0]},
                ops={'reject': {'when': ['true'], 'effects':
                                selection + [['inspection', 'accepted', result]]}}))
            entities[-1]['public_ops'] = {'reject': {'when': ['true'], 'effects': selection}}
    entities.append(_entity('inspection', 'COMPARE TO MASTER',
                            'sign', 0, 4500, 2100, 360, 160, y=3060,
                            color='#73664e', solid=False, state={'accepted': 0}))
    target_x = (1100, -1100, -3300)[fault]
    side = 1 if target_x > 0 else -1
    shift = abs(target_x) // 100
    shifts = [min(20, shift), shift - min(20, shift)]
    shift_actions = [_move(side, 0, ticks) for ticks in shifts if ticks]
    undo_shift = [_move(-side, 0, ticks) for ticks in shifts if ticks]
    return dict(
        title='02 | The Inspection Gallery', start=[0, 1500], size=[9400, 9800],
        sampling_required=['master_arm', 'bay_1_arm', 'bay_2_arm', 'bay_3_arm'],
        entities=entities, room_rules=[], manuals={0: [dict(
            rule_id='02.verify-rejection-before-egress', scope='SELF', modality='FORBID',
            condition=['not', ['eq', 'inspection', 'accepted', 1]],
            action=dict(op_type='traverse', target_entity_id='exit'), source='NATIVE')]},
        public_exit=True,
        exit_when=['eq', 'inspection', 'accepted', 1],
        witness=[_move(0, 1, 10), *shift_actions, _interact(f'bay_{fault + 1}', 'reject'),
                 *undo_shift, _move(0, 1, 20), _move(0, 1, 19),
                 _interact('exit', 'traverse')],
        hint='The leftmost bracket is the master. Reject the one bay whose bracket arm sits on the wrong side of its upright. Rejection is reversible.',
    )


def build(rng, phase_bias=0):
    """Build rooms in curriculum order using only inclusive ``randint``."""
    return [_synchronizer(rng, phase_bias), _inspection(rng)]
