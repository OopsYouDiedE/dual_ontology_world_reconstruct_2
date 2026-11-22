"""Shared construction for the R5–R9 handoff contract."""


def handoff(room, role, target, op, protected_rule, live):
    """Authorize a witnessed test stroke, then hand the live circuit to its operator."""
    suffix = f'{target}_{op}'
    local = f'local_route_{suffix}'
    lead = f'lead_manual_dry_only_{suffix}'
    action = dict(target_entity_id=target, op_type=op)
    room['manuals'][0].append(dict(rule_id=lead, scope='SELF', modality='FORBID',
                                  action=action, condition=live, source='NATIVE'))
    room['room_rules'].append(dict(
        rule_id=local, scope='ROOM', modality='REQUIRE', action=action,
        condition=['or', ['and', ['actor', 0], ['not', live]],
                   ['and', ['actor', role], live]], source='ROOM_LOCAL',
        label='Lead performs the test stroke. The assigned operator takes over on the live circuit.'))
    room.setdefault('handoffs', {})[protected_rule] = dict(
        role=role, lead_rule=lead, local_rule=local, live=live)
    return room


def danger(room, target, at_op, trigger, recover, when, channel, label, x, z, *, y, at_actor=0, fault=(), reset=()):
    active = ['eq', 'alarm', channel, 1]
    fixture = next(e for e in room['entities'] if e['id'] == target)
    fixture['ops'].update({trigger: dict(when=['and', when, ['not', active]],
                                        effects=[['alarm', channel, 1], *fault]),
                           recover: dict(when=['and', ['actor', 0], active],
                                         effects=[['alarm', channel, 0], *reset])})
    room['entities'].append(dict(id='alarm', kind='alarm', label=label, pos=[x, z],
                                 size=[1150, 225, 190], color='#D85A44', y=y,
                                 state={channel: 0}, light_when=active))
    room.update(hazard=active, hazard_min_crew=len(room['manuals']),
                hazard_exercise=dict(at_op=at_op, at_actor=at_actor, trigger=[target, trigger, 0],
                                     recover=[target, recover]))
    return room
