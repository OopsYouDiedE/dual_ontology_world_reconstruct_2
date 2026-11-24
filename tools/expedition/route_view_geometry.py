"""Read collision_fixture.gd's world-space XZ projections and vertical spans."""


def read_geometry(data, finite, xyz):
    if not isinstance(data, dict) or data.get('schema') != 'expedition-collision-v1':
        raise ValueError('expected expedition-collision-v1 geometry')
    if (data.get('plane'), data.get('vertical'), data.get('units')) != (['x', 'z'], 'y', 'meters'):
        raise ValueError('expected XZ footprints, Y elevation and meter units')
    if data.get('errors'):
        raise ValueError('collision snapshot reports incomplete geometry')
    if not isinstance(data.get('shapes'), list):
        raise ValueError('geometry shapes must be an array')
    result = []
    for i, row in enumerate(data['shapes']):
        def fail(message):
            raise ValueError(f'shapes[{i}]: {message}')

        if not isinstance(row, dict):
            fail('expected an object')
        if row.get('disabled') or row.get('role') == 'player':
            continue  # The replay draws its own player; disabled colliders cannot block it.
        footprints, span = row.get('footprints_xz'), row.get('y_range')
        if not isinstance(span, list) or len(span) != 2 or not all(map(finite, span)) or span[0] > span[1]:
            fail('invalid y_range')
        if not isinstance(footprints, list):
            fail('invalid footprints_xz')
        role = row.get('role', 'structure')
        style = 'trigger' if role == 'trigger' or row.get('body_type') == 'Area3D' else (
            'static' if role == 'structure' else 'mechanism')
        faces = []
        if row.get('shape') == 'ConcavePolygonShape3D':
            pose = row.get('transform')
            params = row.get('parameters')
            faces = params.get('faces') if isinstance(params, dict) else None
            if (not isinstance(pose, list) or len(pose) != 4 or not all(map(xyz, pose))
                    or not isinstance(faces, list) or len(faces) != 3*len(footprints) or not all(map(xyz, faces))):
                fail('concave geometry needs a transform and matching triangle vertices')
        for j, polygon in enumerate(footprints):
            if not isinstance(polygon, list) or not polygon or any(
                    not isinstance(p, list) or len(p) != 2 or not all(map(finite, p)) for p in polygon):
                fail(f'invalid footprint {j}')
            if faces:
                ys = [sum(pose[k][1]*p[k] for k in range(3)) + pose[3][1] for p in faces[3*j:3*j+3]]
                local_span = [min(ys), max(ys)]
            else:
                local_span = span
            result.append([style, *local_span, polygon])
    return result
