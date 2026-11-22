"""Rooms 7–10: pressure, timing, projected light, and indexed transfer."""
from .gameplay_v2 import danger, handoff


def _eq(entity, field, value=1):
    return ['eq', entity, field, value]


def _and(*expressions):
    return ['and', *expressions]


def _near(actor, entity, radius):
    return ['near', actor, entity, radius]


_TRUE = ['true']
_COPPER = '#bd754b'
_COBALT = '#417da0'
_IVORY = '#d5caa7'
_STEEL = '#59646b'


def _entity(id, label, kind, x, z, size, color, **fields):
    return dict(id=id, label=label, kind=kind, pos=[x, z], size=size,
                color=color, **fields)


def _operation(when, *effects):
    return dict(when=when, effects=list(effects))


def _interact(target, op):
    return dict(type='Interact', target_entity_id=target, op_type=op)


def _command(role, action):
    return dict(type='CommandCompanion', agent_id=role, action_spec=action)


def _move(x, z, ticks):
    return dict(type='Move', dir_vec=[x, z], speed_ratio=100, duration_ticks=ticks)


def _waits(count):
    return [dict(type='Wait') for _ in range(count)]


def _proof(role, rule):
    return dict(type='PersuadeWithEvidence', agent_id=role, rule_node_id=rule,
                proposed_ast_patch={'mode': 'EXEMPT_ACTION'}, evidence_ref='last')


def _rule(id, target, op, condition=_TRUE, room=False):
    return dict(rule_id=id, scope='ROOM' if room else 'SELF', modality='FORBID',
                condition=condition, action=dict(target_entity_id=target, op_type=op),
                source='ROOM_LOCAL' if room else 'NATIVE')


class _Chamber:
    """A recessed twin-station bay with a shared central aisle."""

    def __init__(self, rng, title, *, aisle=1, tail=0):
        self.x_ticks = rng.randint(15, 19)
        self.x = self.x_ticks * 100
        self.dz = rng.randint(0, 5) * 100
        self.station_z = 4900 + self.dz
        self.console_z = 7000 + self.dz
        self.exit_z = 10400 + self.dz + tail
        self.exit_x = aisle * (500 + rng.randint(0, 3) * 100)
        self.aisle = aisle
        self.console_approach = 5700 + self.dz
        self.title = title
        self.entities = []
        self.rules = []
        self.manuals = {0: [], 1: [], 2: []}
        self.witness = []
        self.phases = []
        self.zero_on_arm = []

    def add(self, id, label, kind, x, z, size, color, **fields):
        item = _entity(id, label, kind, x, z, size, color, **fields)
        self.entities.append(item)
        return item

    def station(self, role, label, op, reset_field, condition=_TRUE,
                linked_effects=(), deny_when=_TRUE):
        side = -1 if role == 1 else 1
        id = ('copper', 'cobalt')[role - 1]
        color = (_COPPER, _COBALT)[role - 1]
        restriction = f'{id}_manual_{op}'
        plate = f'{id}_plate'
        self.add(plate, f'{label}: occupied by assigned operator', 'plate',
                 side * self.x, self.station_z - 800, [1350, 65, 1450], color,
                 state={'occupied': 0}, derived={'occupied': _near(role, plate, 550)},
                 transform={'field': 'occupied', 'offset': [0, -39, 0]})
        active_operator = _and(['actor', role], _eq(plate, 'occupied'))
        circuit = ['or', _eq('console', 'armed', 0), active_operator]
        self.zero_on_arm.extend([[id, reset_field, 0],
                                 *[[e, f, 0] for e, f, _ in linked_effects]])
        self.add(id, label, 'lever', side * self.x, self.station_z,
                 [1200, 1500, 450], color, solid=True,
                 state={reset_field: 0, 'occupied': 0},
                 geometry_references={plate: [0, -800]},
                 derived={'occupied': _eq(plate, 'occupied')},
                 ops={op: _operation(_and(circuit, condition),
                                     [id, reset_field, 1], *linked_effects)})
        if deny_when is not None:
            self.manuals[role].append(_rule(restriction, id, op, deny_when))
        return restriction

    def demonstrate(self, role, op):
        side = -1 if role == 1 else 1
        id = ('copper', 'cobalt')[role - 1]
        self.witness.extend([_move(side, 0, self.x_ticks), _interact(id, op),
                             _move(-side, 0, self.x_ticks), *_waits(2)])

    def start_demo(self):
        remaining = (self.station_z - 3000) // 100
        self.witness.append(_move(0, 1, min(remaining, 20)))
        if remaining > 20:
            self.witness.append(_move(0, 1, remaining - 20))

    def station_crew(self, role, op):
        side = -1 if role == 1 else 1
        id = ('copper', 'cobalt')[role - 1]
        self.witness.extend([_command(role, _move(side, 0, self.x_ticks)),
                             _command(role, _move(0, 1, 20)),
                             _command(role, _move(0, 1, (self.station_z - 800 - 3500) // 100)),
                             _command(role, _interact(id, op))])

    def approach_console(self):
        remaining = self.console_approach - (self.station_z - 1500)
        self.witness.append(_move(0, 1, min(remaining // 100, 20)))
        if remaining > 2000:
            self.witness.append(_move(0, 1, remaining // 100 - 20))

    def held(self):
        return _and(_eq('console', 'armed'), _eq('copper_plate', 'occupied'),
                    _eq('cobalt_plate', 'occupied'))

    def console(self, label, ops, state=None):
        arm = _operation(_and(_eq('console', 'armed', 0), ['actor', 0]),
                         ['console', 'armed', 1], *self.zero_on_arm)
        disarm = _operation(_and(_eq('console', 'armed'), ['actor', 0]),
                            ['console', 'armed', 0], *self.zero_on_arm)
        return self.add('console', label, 'console', 0, self.console_z,
                        [1500, 1000, 650], _IVORY, solid=True,
                        ops={'arm': arm, 'disarm': disarm, **ops},
                        state={'armed': 0, **(state or {})})

    def arm(self):
        self.approach_console()
        self.witness.append(_interact('console', 'arm'))

    def repeater(self, side, label, field, expression):
        id, color, direction = (('copper_status', _COPPER, -1) if side == 1
                                else ('cobalt_status', _COBALT, 1))
        self.add(id, label, 'signal', direction * 980, self.console_z + 160,
                 [1200, 280, 300], color, y=1160,
                 state={field: 0}, derived={field: expression})

    def cycle(self, period, offset, window, *, id='clock', x=0, color='#cba75c', z_offset=1750):
        self.phases.append(dict(id=id, period=period, offset=offset, window=window, field='active'))
        self.add(id, f'{id.replace("_", " ").title()} | Working sector', 'clock',
                 x, self.console_z + z_offset, [1300, 820, 430], color, y=1280,
                 state={'active': 0, 'period_ticks': period, 'offset_ticks': offset,
                        'window_ticks': window})
        self.add(f'{id}_sector', '', 'shutter', x, self.console_z + z_offset - 180,
                 [1200, 140, 200], '#edc46b', y=2030,
                 state={'active': 0}, derived={'active': ['phase', id]},
                 transform={'field': 'active', 'offset': [0, 370, 0]})

    def await_phase(self, *, active=True):
        """Choose a decision boundary with a 20-tick margin on each side."""
        def matches(phase, tick):
            position = (tick + phase['offset']) % phase['period']
            start, end = ((0, phase['window']) if active else (phase['window'], phase['period']))
            return start + 20 <= position < end - 20

        tick = len(self.witness) * 20
        count = 0
        while not all(matches(phase, tick) for phase in self.phases):
            count += 1
            tick += 20
            if count > max(p['period'] for p in self.phases):
                raise ValueError('Phase window cannot be reached on the decision lattice')
        self.witness.extend(_waits(count))

    def finish(self, hint, **fields):
        self.add('exit', 'Transfer door', 'exit', self.exit_x, self.exit_z, [1700, 2450, 300],
                 '#82978c', state={'open': 0})
        self.add('door_leaf', '', 'shutter', self.exit_x, self.exit_z - 5,
                 [1650, 2300, 230], _STEEL, solid=True,
                 state={'open': 0}, derived={'open': _eq('exit', 'open')},
                 transform={'field': 'open', 'offset': [self.aisle * 1900, 0, 0]})
        # Walk around the console and up to the open portal without crossing its leaf.
        self.witness.append(_move(self.aisle, 0, 13))
        remaining = (self.exit_z - 1500 - self.console_approach) // 100
        while remaining:
            segment = min(remaining, 20)
            self.witness.append(_move(0, 1, segment))
            remaining -= segment
        self.witness.extend([_move(-self.aisle, 0, 13 - abs(self.exit_x) // 100),
                             _interact('exit', 'traverse')])
        room = dict(title=self.title, start=[0, 1500], size=[8000, self.exit_z + 900],
                    entities=self.entities, phases=self.phases, room_rules=self.rules,
                    manuals=self.manuals, exit_when=_eq('exit', 'open'),
                    witness=self.witness, hint=hint, **fields)
        return room


def _counterweight(rng):
    room = _Chamber(rng, '07 / Counterweight Exchange')
    permit = room.station(1, 'Copper jack', 'charge', 'charged',
                          linked_effects=(['counterweight', 'raised', 1],))
    # Cobalt can brace as shipped; the second manual restriction covers the central crank.
    room.station(2, 'Cobalt return brace', 'brace', 'braced',
                 linked_effects=(['return_rail', 'raised', 1],), deny_when=None)
    room.manuals[2].append(_rule('cobalt_manual_release', 'console', 'release'))
    room.manuals[0].append(_rule('lead_manual_unbraced_release', 'console', 'release',
                                 ['not', _eq('cobalt', 'braced')]))
    room.add('hoist_lintel', '', 'frame', 0, room.console_z + 800,
             [4800, 270, 700], _STEEL, y=2700)
    room.add('counterweight', 'Copper counterweight', 'counterweight', -1700,
             room.console_z + 800, [1250, 1150, 950], _COPPER, solid=True,
             state={'raised': 0}, transform={'field': 'raised', 'offset': [0, 1350, 0]})
    room.add('return_rail', 'Cobalt return rail', 'shutter', 1700,
             room.console_z + 800, [1250, 620, 1150], _COBALT, solid=True,
             state={'raised': 0}, transform={'field': 'raised', 'offset': [0, 1800, 0]})
    room.repeater(1, 'Copper ready', 'active',
                  _and(_eq('console', 'armed'), _eq('copper_plate', 'occupied'), _eq('copper', 'charged')))
    room.repeater(2, 'Cobalt ready', 'active',
                  _and(_eq('console', 'armed'), _eq('cobalt_plate', 'occupied'), _eq('cobalt', 'braced')))
    room.console('Transfer crank | Both plates, both loads raised', {
        'release': _operation(_and(room.held(), _eq('copper', 'charged'),
                                  _eq('cobalt', 'braced'), ['actor', 0]),
                              ['exit', 'open', 1])})
    room.start_demo()
    room.demonstrate(1, 'charge')
    room.witness[-1] = dict(type='QueryCompanion', agent_id=1)
    room.witness.append(_proof(1, permit))
    room.arm()
    room.station_crew(1, 'charge')
    room.station_crew(2, 'brace')
    room.witness.append(_interact('console', 'release'))
    spec = room.finish('Demonstrate, then arm to reset the test loads. The crank needs each live plate. A witnessed dry jack cycle can clear the copper restriction. Uncoupling a loaded jack drops the counterweight; seat the ratchet at the crank.')

    handoff(spec, 1, 'copper', 'charge', permit, _eq('console', 'armed'))
    return danger(spec, 'console', 'release', 'uncouple_under_load', 'seat_ratchet',
                  _and(room.held(), _eq('copper', 'charged')), 'ratchet_slip',
                  'SLIPPING RATCHET | Seat at crank', 0, room.console_z + 410, y=1430,
                  fault=(['counterweight', 'raised', 0],), reset=(['counterweight', 'raised', 1],))


def _escapement(rng, phase_bias):
    room = _Chamber(rng, '08 / Escapement Gantry', aisle=-1, tail=500)
    period = 20 * rng.randint(16, 20)
    offset = rng.randint(0, period - 1)
    lag = rng.randint(40, 80)
    room.cycle(period, offset, 180 + phase_bias, x=-1200)
    room.cycle(period, (offset - lag) % period, 180 + phase_bias, id='return_clock', x=1200, color=_COBALT)
    both_phases = _and(['phase', 'clock'], ['phase', 'return_clock'])
    permit = room.station(2, 'Cobalt clutch', 'mesh', 'meshed',
                          linked_effects=(['right_link', 'extended', 1],))
    room.station(1, 'Copper clutch', 'drive', 'driven',
                 linked_effects=(['left_link', 'extended', 1],), deny_when=None)
    room.manuals[1].append(_rule('copper_manual_transfer', 'console', 'transfer'))
    room.manuals[0].append(_rule('lead_manual_off_phase_transfer', 'console', 'transfer',
                                 ['not', both_phases]))
    room.add('gantry', '', 'frame', 0, room.console_z + 450,
             [7300, 280, 750], _STEEL, y=2860)
    for sign, id, color in ((-1, 'left_link', _COPPER), (1, 'right_link', _COBALT)):
        room.add(f'{id}_column', 'Gantry bearing column', 'divider', sign * 3480,
                 room.console_z + 450, [420, 2860, 650], _STEEL, solid=True)
        room.add(id, f'{id.replace("_", " ").title()} | Gantry drive', 'shutter',
                 sign * 2800, room.console_z + 450, [1250, 850, 850], color, y=600,
                 state={'extended': 0}, transform={'field': 'extended', 'offset': [-sign * 750, 0, 0]})
    engaged = _and(room.held(), _eq('copper', 'driven'), _eq('cobalt', 'meshed'), ['actor', 0])
    room.console('Gantry index | Transfer with both shuttles raised', {
        'transfer': _operation(_and(engaged, both_phases), ['exit', 'open', 1]),
    })
    room.start_demo()
    room.demonstrate(2, 'mesh')
    room.witness[-1] = dict(type='QueryCompanion', agent_id=2)
    room.witness.append(_proof(2, permit))
    room.arm()
    room.station_crew(1, 'drive')
    room.station_crew(2, 'mesh')
    room.await_phase()
    room.witness.append(_interact('console', 'transfer'))
    spec = room.finish('Dry-cycle the matching clutch before arming; arming zeros both clutches. The linked drive runs only while both shuttles are raised. Alternatively compare the lead timing rule with the index transfer and bypass sheets, and certify the cobalt clutch only inside the overlapping sectors. A sync bypass outside overlap binds the gantry; declutch at the index.',
                       sampling_required=['clock', 'return_clock'])

    handoff(spec, 2, 'cobalt', 'mesh', permit, _eq('console', 'armed'))
    spec['document_proofs'] = {permit: dict(desk='console', permit_op='transfer', excluded_op='bypass_sync',
                                           safety_rule='lead_manual_off_phase_transfer', window=both_phases)}
    return danger(spec, 'console', 'transfer', 'bypass_sync', 'declutch_gantry',
                  _and(engaged, ['not', both_phases]), 'gear_bind', 'GANTRY BIND | Declutch at index',
                  0, room.console_z + 410, y=1430,
                  fault=(['right_link', 'extended', 0],), reset=(['right_link', 'extended', 1],))


def _shadow(rng):
    room = _Chamber(rng, '09 / The Shadow Register', aisle=-1)
    room.console_approach -= 600
    dark_gap = rng.randint(11, 13) * 100
    permit = room.station(1, 'Copper lamp yoke', 'raise', 'raised',
                          linked_effects=(['mask', 'raised', 1],))
    blue_rule = room.station(2, 'Cobalt register key', 'turn', 'turned',
                             condition=_eq('copper', 'raised'),
                             linked_effects=(['mask', 'indexed', 1],),
                             deny_when=['not', ['lit', 'reticle']])
    room.manuals[0].append(_rule('lead_manual_exposed_read', 'console', 'read',
                                 ['not', ['pose', 0, 'crouch']]))
    room.rules.append(_rule('shade_interlock', 'cobalt', 'turn',
                            ['not', _eq('copper', 'raised')], room=True))
    room.add('projector', 'Fixed projection lantern', 'lamp', -2860, room.console_z + 940,
             [1200, 550, 550], '#bf9b56', y=1840, state={'powered': 0},
             derived={'powered': _eq('console', 'armed')})
    room.add('mask', 'Projection mask | Raised by the lamp yoke', 'shutter',
             -1150, room.console_z + 475, [1500, 1050, 345], _STEEL, y=1100,
             state={'raised': 0, 'indexed': 0},
             transform={'field': 'raised', 'offset': [0, 1050, 0]})
    room.add('reticle_mount', '', 'frame', dark_gap, room.console_z + 240,
             [1240, 560, 170], '#373f47', y=680)
    room.add('reticle', 'Light register', 'reticle', dark_gap, room.console_z + 95,
             [1200, 395, 80], '#f0cd54', y=750,
             light_when=_and(_eq('projector', 'powered'), _eq('mask', 'indexed'),
                             ['beam_clear', 'projector', 'reticle', 'mask']))
    room.add('reading_hood', '', 'shutter', 0,
             room.console_z - 455, [1490, 175, 385], _STEEL, y=1170, solid=True)
    room.console('Reader | Crouch under the hood', {
        'read': _operation(_and(room.held(), _eq('mask', 'raised'), ['lit', 'reticle'],
                               ['pose', 0, 'crouch'], ['actor', 0]), ['exit', 'open', 1])})
    room.start_demo()
    room.demonstrate(1, 'raise')
    room.witness[-1] = dict(type='QueryCompanion', agent_id=1)
    room.witness.append(_proof(1, permit))
    room.demonstrate(2, 'turn')
    room.witness[-1] = dict(type='QueryCompanion', agent_id=2)
    room.witness.append(_proof(2, blue_rule))
    room.approach_console()
    room.witness.extend([dict(type='SetPose', pose='crouch'), _interact('console', 'arm')])
    room.station_crew(1, 'raise')
    room.station_crew(2, 'turn')
    room.witness.extend([_interact('console', 'read'), dict(type='SetPose', pose='stand'),
                         _move(0, 1, 6)])
    room.console_approach += 600  # Move beyond the station row before crossing the aisle.
    spec = room.finish('The yoke lifts the mask first. Use the approach to dry-cycle the register key before crouching at the controller to arm the reading circuit. Opening the iris drops the mask and floods the reader; cap the iris to recover.',
                       sampling_required=['mask', 'reticle'])

    handoff(spec, 1, 'copper', 'raise', permit, _eq('console', 'armed'))
    handoff(spec, 2, 'cobalt', 'turn', blue_rule, _eq('console', 'armed'))
    return danger(spec, 'console', 'read', 'open_lantern_iris', 'cap_lantern_iris',
                  _and(room.held(), ['lit', 'reticle']), 'glare',
                  'PROJECTOR GLARE | Cap iris at reader', 0, room.console_z - 360, y=820,
                  fault=(['mask', 'raised', 0],), reset=(['mask', 'raised', 1],))


def _transfer(rng, phase_bias):
    room = _Chamber(rng, '10 / Foundry Transfer', tail=1100)
    clear_role = rng.randint(1, 2)
    hold_role = 3 - clear_role
    names = {1: 'Copper', 2: 'Cobalt'}
    clear_name, hold_name = names[clear_role], names[hold_role]
    clear_plate, hold_plate = f'{clear_name.lower()}_plate', f'{hold_name.lower()}_plate'
    period = 20 * rng.randint(18, 22)
    room.cycle(period, rng.randint(0, period - 1), 160 + phase_bias, x=1430, z_offset=1200)
    permit = room.station(1, 'Copper retaining block', 'retain', 'retained',
                          linked_effects=(['beam', 'retained', 1],))
    blue = room.station(2, 'Cobalt return pulley', 'secure', 'secured',
                       condition=_eq('copper', 'retained'), linked_effects=(['pulley', 'secured', 1],))
    room.manuals[0].append(_rule('lead_manual_unsecured_index', 'console', 'index',
                                 ['not', _eq('cobalt', 'secured')]))
    room.rules.append(_rule('no_loading_without_retainer', 'cobalt', 'secure',
                            ['not', _eq('copper', 'retained')], room=True))
    room.add('pulley', 'Return pulley counterload', 'counterweight', 2950,
             room.console_z + 700, [1250, 1050, 1000], _COBALT, solid=True,
             state={'secured': 0}, transform={'field': 'secured', 'offset': [0, 1250, 0]})
    room.add('trolley_track', '', 'frame', -1050, room.console_z + 900,
             [5150, 320, 700], _STEEL, y=2470)
    room.add('beam', 'Load trolley', 'carriage', -2700,
             room.console_z + 900, [1450, 680, 950], _COPPER, y=1730,
             state={'retained': 0, 'transferred': 0},
             transform={'field': 'transferred', 'offset': [2400, 0, 0]})
    coupled = _and(room.held(), _eq('beam', 'retained'), _eq('pulley', 'secured'), ['actor', 0])
    room.add('stop_block', f'Stop block | Seats after {hold_name} settles the load', 'shutter',
             -300, room.console_z + 1350, [1250, 470, 400], _STEEL, y=2400,
             state={'seated': 0}, transform={'field': 'seated', 'offset': [0, -1000, 0]})
    # At the index stance this beacon sits just above the console's silhouette;
    # emergency stop stays accessible without any movement or phase dependency.
    room.add('alarm', 'Overload | Emergency stop at the controller', 'alarm', 0,
             room.console_z + 410, [1300, 240, 220], '#d85a44', y=1430,
             state={'active': 0}, light_when=_eq('alarm', 'active'))
    room.zero_on_arm.extend([['beam', 'transferred', 0], ['stop_block', 'seated', 0],
                             ['alarm', 'active', 0]])
    anchor_station = next(e for e in room.entities if e['id'] == hold_name.lower())
    anchor_station['ops']['settle'] = _operation(
        _and(['actor', hold_role], _eq(hold_plate, 'occupied'), ['not', _eq(clear_plate, 'occupied')],
             _eq('beam', 'transferred')),
        ['stop_block', 'seated', 1])
    room.rules.append(dict(rule_id=f'{hold_name.lower()}_holds_until_return_clear', scope='ROOM',
                           modality='FORBID', source='ROOM_LOCAL', action={'type': 'Move'},
                           condition=_and(['actor', hold_role], _eq('beam', 'transferred'), room.held()),
                           label=f'{hold_name} holds the loaded trolley until {clear_name} clears its plate.'))
    room.repeater(1, 'Copper plate', 'active', _eq('copper_plate', 'occupied'))
    room.repeater(2, 'Cobalt plate', 'active', _eq('cobalt_plate', 'occupied'))
    room.console('Load controller | Index high, unload low', {
        'index': _operation(_and(coupled, ['phase', 'clock'], _eq('beam', 'transferred', 0)),
                            ['beam', 'transferred', 1]),
        'advance_against_stop': _operation(
            _and(coupled, ['not', ['phase', 'clock']], _eq('beam', 'transferred', 0)),
            ['alarm', 'active', 1]),
        'emergency_stop': _operation(_and(['actor', 0], _eq('alarm', 'active')),
                                     ['alarm', 'active', 0]),
        'unload': _operation(_and(_eq('stop_block', 'seated'), ['not', ['phase', 'clock']],
                                  ['not', _eq('copper_plate', 'occupied')],
                                  ['not', _eq('cobalt_plate', 'occupied')], ['actor', 0]),
                             ['exit', 'open', 1]),
    }, state={'probe_clearance_mm': 0})
    room.start_demo()
    room.demonstrate(1, 'retain')
    room.witness.append(_proof(1, permit))
    room.demonstrate(2, 'secure')
    room.witness.append(_proof(2, blue))
    room.arm()
    room.station_crew(1, 'retain')
    room.station_crew(2, 'secure')
    room.await_phase()
    room.witness.extend([_interact('console', 'index'),
                         _command(clear_role, _move(0, -1, 12)),
                         _command(hold_role, _interact(hold_name.lower(), 'settle')),
                         _command(hold_role, _move(0, -1, 12))])
    room.await_phase(active=False)
    room.witness.append(_interact('console', 'unload'))
    return room.finish('Dry-cycle the retainer before the pulley, then arm. The trolley indexes with the shuttle up. The room rule names the operator who holds and settles the stop block. Unload with the shuttle down. If overloaded, hit emergency stop.',
                       sampling_required=['clock', 'beam', 'stop_block'],
                       hazard=_eq('alarm', 'active'), hazard_min_crew=3,
                       probe=dict(target='console', field='probe_clearance_mm', value=380),
                       hazard_exercise=dict(at_op='index', trigger=['console', 'advance_against_stop', 0],
                                            recover=['console', 'emergency_stop']))


def build(rng, phase_bias=0):
    """Return four fresh, seeded room dictionaries in run order."""
    return [_counterweight(rng), _escapement(rng, phase_bias), _shadow(rng), _transfer(rng, phase_bias)]
