"""Seeded dual-operator rooms. Geometry coordinates and offsets are in mm."""
from .gameplay_v2 import danger, handoff


def _entity(id, label, kind, x, z, size, color, **extra):
    return dict(id=id, label=label, kind=kind, pos=[x, z], size=size,
                color=color, **extra)


def _eq(id, field, value=1):
    return ['eq', id, field, value]


def _near(actor, id, radius):
    return ['near', actor, id, radius]


def _and(*parts):
    return ['and', *parts]


def _or(*parts):
    return ['or', *parts]


def _op(when, *effects):
    return dict(when=when, effects=list(effects))


def _rule(id, target, op, when=None, room=False):
    return dict(rule_id=id, scope='ROOM' if room else 'SELF', modality='FORBID',
                condition=when if when is not None else ['true'],
                action=dict(op_type=op, target_entity_id=target),
                source='ROOM_LOCAL' if room else 'NATIVE')


def _move(ticks, x=0, z=1):
    return dict(type='Move', dir_vec=[x, z], speed_ratio=100, duration_ticks=ticks)


def _use(id, op):
    return dict(type='Interact', target_entity_id=id, op_type=op)


def _cmd(action):
    return dict(type='CommandCompanion', agent_id=1, action_spec=action)


def _patch(id):
    return dict(type='PersuadeWithEvidence', agent_id=1, rule_node_id=id,
                proposed_ast_patch=dict(mode='EXEMPT_ACTION'), evidence_ref='last')


def _query():
    return dict(type='QueryCompanion', agent_id=1)


def _wait():
    return dict(type='Wait')


def _exit(z):
    return _entity('exit', 'Campward door', 'door', 0, z, [1800, 2600, 300],
                   '#303F52', solid=True)


def _frame(x, z, length):
    return _entity('pier', 'Masonry divider', 'divider', x, z,
                   [1250, 2900, length], '#717E86', solid=True)


def _track(id, x, z, width, depth, color='#798381'):
    # Flush mechanical routing: visible provenance, no reach or scan occlusion.
    return _entity(id, '', 'floor_channel', x, z, [width, 36, depth], color,
                   y=-19, solid=False, ray_ignore=True)


def _plate(id, label, x, z, actor, radius=650):
    occupied = (_or(_near(0, id, radius), _near(1, id, radius))
                if actor is None else _near(actor, id, radius))
    return _entity(id, label, 'pressure_plate', x, z, [1600, 100, 1500],
                   '#B68144', solid=False, state=dict(occupied=0),
                   derived={'occupied': occupied},
                   transform=dict(field='occupied', offset=[0, -55, 0]))


def _treadle(rng):
    side = rng.randint(0, 1) * 2 - 1
    gap = rng.randint(0, 4) * 100
    rule = 'treadle_keep_hands_off_bolt'
    live = _eq('selector', 'live')
    remote = _near(0, 'selector', 1500)
    bolt = _entity('bolt', 'Bolt lever', 'bolt_lever', 0, 4650,
                   [1300, 1500, 350], '#497A83', y=350, solid=True,
                   state=dict(extended=0, treadle_loaded=0),
                   derived=dict(treadle_loaded=_eq('treadle', 'occupied')),
                   ops={'throw': _op(
                       _and(_eq('treadle', 'occupied'), _or(['not', live], remote)), ['bolt', 'extended', 1])})
    tongue = _entity('tongue', '', 'carriage', side * 425, 4440,
                     [750, 165, 190], '#E9B55B', y=1160, ray_ignore=True,
                     state=dict(seated=0), derived=dict(seated=_eq('bolt', 'extended')),
                     transform=dict(field='seated', offset=[side * 580, 0, 0]))
    keeper = _entity('keeper', '', 'carriage', side * 1300, 4470,
                     [240, 355, 230], '#354651', y=1070, ray_ignore=True)
    selector = _entity('selector', 'Door-side live selector', 'selector', side * 1050,
                       8530 + gap, [1450, 1700, 420], '#729D62', solid=True,
                       state=dict(live=0), transform=dict(field='live', offset=[0, 420, 0]),
                       ops={'arm': _op(['not', live], ['selector', 'live', 1],
                                       ['bolt', 'extended', 0])})
    return dict(title='3 · The Spring-Bolt Gallery', start=[0, 1500], size=[8400, 10800],
                sampling_required=['treadle'],
                entities=[_plate('treadle', 'Spring-bolt treadle', 0, 3500, None, 700),
                          bolt, tongue, keeper, selector, _frame(-side * 2150, 6850, 2900),
                          _track('spring_link', 0, 4140, 130, 1230, '#B68144'),
                          _track('selector_link', side * 410, 6650, 130, 3800), _exit(9650)],
                room_rules=[], manuals={0: [_rule('unload_treadle_before_departure', 'exit', 'traverse',
                                                     _eq('treadle', 'occupied'))],
                                        1: [_rule(rule, 'bolt', 'throw')]},
                public_exit=True, exit_when=_and(live, _eq('bolt', 'extended'), ['not', _eq('treadle', 'occupied')]),
                hint='The treadle loads the spring bolt. Arm the selector to clear the test stroke. The doorway opens with the bolt thrown and the treadle unloaded.',
                witness=[_move(14), _use('bolt', 'throw'), _move(14, x=-side, z=0),
                         _move(20), _move(2), _move(14, x=side, z=0), _move(20), _move(8),
                         _use('selector', 'arm'), _cmd(_move(20)), _query(), _patch(rule),
                         _cmd(_use('bolt', 'throw')), _cmd(_move(9, z=-1)), _use('exit', 'traverse')])


def _flywheel(rng, phase_bias):
    period = rng.randint(7, 9) * 20
    offset = rng.randint(0, period - 1)
    window = min(period - 60, max(60, 60 + phase_bias))
    rule = 'flywheel_never_release_on_index'
    indexed = ['phase', 'wheel']
    armed = _eq('receiver', 'armed')
    charged = _eq('receiver', 'charged')
    overpressure = _eq('receiver', 'overpressure')
    receiving = _near(0, 'receiver', 1300)
    wheel = _entity('wheel', f'Indexed flywheel | {window}/{period} ticks', 'flywheel', -1750, 4930,
                    [2350, 2350, 600], '#527487', y=180, solid=True,
                    state=dict(active=0, period=period, offset=offset, window=window))
    marker = _entity('index', 'Raised alignment dog', 'index_marker', -1650, 4510,
                     [1250, 500, 300], '#E7BF60', y=900, solid=False,
                     state=dict(indexed=0), derived=dict(indexed=indexed),
                     transform=dict(field='indexed', offset=[0, 720, 0]))
    escapement = _entity('release', 'Escapement handle', 'escapement', 0, 4600,
                         [1400, 1500, 450], '#B17B45', y=500, solid=False,
                         state=dict(thrown=0), derived=dict(thrown=charged),
                         transform=dict(field='thrown', offset=[0, -475, 0]),
                         ops={'release': _op(_and(indexed, ['not', charged], _or(['not', armed], receiving)),
                                             ['receiver', 'charged', 1], ['receiver', 'pressure_kpa', 65]),
                              'double_feed': _op(_and(indexed, armed, charged, receiving),
                                                 ['receiver', 'pressure_kpa', 130])})
    receiver = _entity('receiver', 'Receiving yoke', 'receiver', 1100, 8330,
                       [1400, 1850, 550], '#99784D', solid=True,
                       state=dict(armed=0, charged=0, overpressure=0, pressure_kpa=0, probe_pressure_kpa=0),
                       derived={'overpressure': ['gte', 'receiver', 'pressure_kpa', 100]},
                       transform=dict(field='charged', offset=[0, 550, 0]),
                       ops={'arm': _op(['not', armed], ['receiver', 'armed', 1],
                                       ['receiver', 'charged', 0], ['receiver', 'pressure_kpa', 0]),
                            'relieve': _op(overpressure, ['receiver', 'pressure_kpa', 0],
                                           ['receiver', 'charged', 0])})
    alarm = _entity('alarm', 'RELIEVE THE YOKE', 'index_marker', -260, 8550,
                    [1250, 450, 300], '#E86345', y=720, state=dict(raised=0),
                    derived=dict(raised=overpressure),
                    transform=dict(field='raised', offset=[0, 830, 0]))
    witness = [_move(20)]

    def release_when_indexed(action):
        # Keep the release and its end-of-round observation in one open interval.
        while not all((len(witness) * 20 + offset + d) % period < window
                      for d in (-1, 0, 1, 19, 20)):
            witness.append(_wait())
        witness.append(action)

    release_when_indexed(_use('release', 'release'))
    witness.extend([_move(20), _move(20), _move(3), _use('receiver', 'arm'),
                    _cmd(_move(20)), _query(), _patch(rule)])
    release_when_indexed(_cmd(_use('release', 'release')))
    witness.append(_use('exit', 'traverse'))
    return dict(title='4 · The Indexed Flywheel', start=[0, 1500], size=[8200, 10600],
                entities=[wheel, marker, escapement, receiver, alarm,
                          _track('pulse_pipe', 425, 6500, 130, 3850, '#B17B45'), _exit(9500)],
                phases=[dict(id='wheel', period=period, offset=offset, window=window, field='active')],
                room_rules=[_rule('release_only_at_index', 'release', 'release', ['not', indexed], room=True)],
                manuals={0: [_rule('check_yoke_charge', 'exit', 'traverse', ['not', charged])],
                         1: [_rule(rule, 'release', 'release', indexed)]},
                public_exit=True, exit_when=_and(armed, charged, ['not', overpressure]), hazard=overpressure,
                probe=dict(target='receiver', field='probe_pressure_kpa', value=65),
                hazard_exercise=dict(at_op='traverse', trigger=['release', 'double_feed', 1], recover=['receiver', 'relieve']),
                hint='Brass dog up means indexed. The yoke sheds test charge when armed. A double feed lifts the red piston; use RELIEVE at the yoke immediately.',
                witness=witness)


def _shuttle(rng):
    side = rng.randint(0, 1) * 2 - 1
    rule = 'shuttle_never_shift_loaded'
    loaded = _eq('shuttle', 'loaded')
    docked = _eq('shuttle', 'docked')
    stroke = side * rng.randint(22, 26) * 100
    shuttle = _entity('shuttle', 'Loaded shuttle', 'carriage', 0, 5500,
                      [1450, 1850, 1600], '#A96149', solid=True,
                      state=dict(loaded=1, docked=0),
                      transform=dict(field='docked', offset=[stroke, 0, 0]))
    lever = _entity('capstan', 'Shuttle capstan', 'capstan', -side * 950, 4350,
                    [1500, 1600, 400], '#417D79', y=180, solid=False,
                    state=dict(stroked=0), derived=dict(stroked=docked),
                    transform=dict(field='stroked', offset=[0, 300, 0]),
                    ops={'shift': _op(_and(['not', docked],
                                          _or(_eq('ballast', 'attached'), _near(0, 'balance', 650)),
                                          _or(_near(0, 'capstan', 1450), _near(1, 'capstan', 1450))),
                                      ['shuttle', 'docked', 1])})
    # The deadweight is raised aside when the far plate is commissioned.
    ballast = _entity('ballast', 'Test counterweight', 'counterweight', -side * 2550, 3350,
                      [1350, 1400, 800], '#A78557', y=1500, solid=True,
                      state=dict(attached=1),
                      transform=dict(field='attached', offset=[0, -1450, 0]))
    commission = _entity('clutch', 'Counterweight clutch', 'clutch', side * 1150, 8360,
                         [1350, 1600, 400], '#769660', solid=True,
                         state=dict(plate_loaded=0, engaged=0), derived=dict(plate_loaded=_eq('balance', 'occupied')),
                         transform=dict(field='engaged', offset=[0, 380, 0]),
                         ops={'commission': _op(_eq('ballast', 'attached'),
                                                ['ballast', 'attached', 0], ['shuttle', 'docked', 0],
                                                ['clutch', 'engaged', 1])})
    room = dict(title='5 · Counterweight Transfer', start=[0, 1500], size=[9000, 11100],
                sampling_required=['shuttle', 'balance'],
                entities=[shuttle, lever, ballast,
                          *[_track(f'runner_{i}', stroke // 2, 5500 + i * 440,
                                   abs(stroke) + 1600, 115) for i in (-1, 1)],
                          _plate('balance', 'Far-side load plate', 0, 7700, 0), commission,
                          _frame(-side * 3250, 6780, 1950), _exit(9550)],
                room_rules=[], manuals={0: [_rule('leave_only_from_far_plate', 'exit', 'traverse',
                                                     ['not', _eq('balance', 'occupied')])],
                                        1: [_rule(rule, 'capstan', 'shift', loaded)]},
                public_exit=True, exit_when=_and(_eq('ballast', 'attached', 0), docked),
                hint='When the clutch raises the test weight, the far plate takes over the counterbalance. Dropping the test weight under load sends the shuttle back; catch the weight at the clutch.',
                witness=[_move(20), _use('capstan', 'shift'), _move(20), _move(20), _move(2),
                         _use('clutch', 'commission'), _cmd(_move(20)), _query(), _patch(rule),
                         _cmd(_use('capstan', 'shift')), _use('exit', 'traverse')])

    handoff(room, 1, 'capstan', 'shift', rule, ['not', _eq('ballast', 'attached')])
    return danger(room, 'clutch', 'traverse', 'drop_test_weight', 'catch_counterweight',
                  _and(docked, _eq('balance', 'occupied')), 'runaway',
                  'RUNAWAY COUNTERWEIGHT | Catch at clutch', side * 850, 8130, y=1700,
                  fault=(['shuttle', 'docked', 0],), reset=(['shuttle', 'docked', 1],))


def _shutter(rng):
    side = rng.randint(0, 1) * 2 - 1
    gap = rng.randint(0, 3) * 100
    rule = 'shutter_never_retract_unvented'
    bled = _eq('vent', 'bled')
    live = _eq('sight', 'live')
    open_ = _eq('shutter', 'open')
    sighted = _and(_near(0, 'sight', 1360), ['pose', 0, 'crouch'])
    vent = _entity('vent', 'Relief piston', 'relief_valve', side * 1575, 4620,
                   [1350, 1850, 490], '#6F9A8C', solid=True, state=dict(bled=1),
                   transform=dict(field='bled', offset=[0, 470, 0]),
                   ops={'bleed': _op(['true'], ['vent', 'bled', 1]),
                        'seal': _op(['true'], ['vent', 'bled', 0])})
    handle = _entity('handle', 'Shutter release', 'shutter_handle', -side * 975, 4580,
                     [1250, 1400, 400], '#AF7048', y=350, solid=False,
                     state=dict(released=0), derived=dict(released=open_),
                     transform=dict(field='released', offset=[0, -300, 0]),
                     ops={'retract': _op(_and(['not', bled], _or(['not', live], sighted)),
                                         ['shutter', 'open', 1])})
    sight = _entity('sight', 'Low inspection sight', 'inspection_sight', -side * 820,
                    8460 + gap, [1350, 740, 440], '#456C7C', solid=False,
                    state=dict(live=0), ops={'engage': _op(
                        _and(['not', live], bled, ['pose', 0, 'crouch']),
                        ['sight', 'live', 1], ['shutter', 'open', 0])})
    shutter = _entity('shutter', 'Graduated overhead shutter', 'sliding_shutter', 0, 8870,
                      [2250, 1250, 360], '#8D5D43', y=850 + gap, solid=True,
                      state=dict(open=0), transform=dict(field='open', offset=[0, 1550, 0]))
    returns = [_entity(f'jamb_{i}', 'Shutter jamb', 'divider', i * 2650, 8870,
                       [3050, 2920, 440], '#717E86', solid=True) for i in (-1, 1)]
    handle['ops']['retract']['when'] = _and(handle['ops']['retract']['when'], _eq('alarm', 'steam', 0))
    room = dict(title='6 · The Low-Sight Shutter', start=[0, 1500], size=[8300, 11400],
                sampling_required=['shutter', 'sight'],
                entities=[vent, handle, sight, shutter, *returns, _frame(side * 2400, 6800, 2600),
                          _track('sight_link', -side * 500, 6500, 130, 3830, '#456C7C'), _exit(9660)],
                room_rules=[_rule('shutter_lock_when_vented', 'handle', 'retract', bled, room=True)],
                manuals={0: [_rule('stay_below_the_sightline', 'sight', 'engage',
                                      ['not', ['pose', 0, 'crouch']])],
                         1: [_rule(rule, 'handle', 'retract', ['not', bled])]},
                public_exit=True, exit_when=_and(live, open_),
                hint='Relief pressure blocks the release; the inspection sight needs relief to engage. A purge against the closed shutter traps steam; isolate the purge at the sight.',
                witness=[_move(20), _use('vent', 'seal'), _use('handle', 'retract'),
                         _use('vent', 'bleed'), _move(20), _move(20), _move(4),
                         dict(type='SetPose', pose='crouch'), _use('sight', 'engage'),
                         _cmd(_move(20)), _query(), _patch(rule), _cmd(_use('vent', 'seal')),
                         _cmd(_use('handle', 'retract')), _move(13),
                         _use('exit', 'traverse')])

    handoff(room, 1, 'handle', 'retract', rule, live)
    return danger(room, 'sight', 'retract', 'purge_under_shutter', 'isolate_purge',
                  _and(live, ['not', open_], ['not', bled]), 'steam',
                  'STEAM DISCHARGE | Isolate at sight', -side * 800, 8490 + gap, y=770, at_actor=1)


def build(rng, phase_bias=0):
    """Generate rooms 3–6 in campaign order using only the supplied RNG."""
    return [_treadle(rng), _flywheel(rng, phase_bias), _shuttle(rng), _shutter(rng)]
