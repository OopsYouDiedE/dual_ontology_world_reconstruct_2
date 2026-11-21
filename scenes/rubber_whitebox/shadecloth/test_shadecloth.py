"""Headless cloth/illumination checks and a reference replay on both bell bands."""
import argparse
import math

from shadecloth import ShadeRun, ShadeWorld, config, dot, sub
from verify import trial


def check_surface(world):
    c = world.c
    cloth = world.cloth
    horizon = c['eye_mm'] + c['range_mm']*math.sin(math.radians(max(c['pitch_deg'])))
    mins, maxs = [math.inf]*3, [-math.inf]*3
    period = c['cloth']['period_ticks']
    assert period == 14*c['hz']
    assert cloth.vertices(0) == cloth.vertices(period)
    for t in range(period):
        verts = cloth.vertices(t)
        for axis,values in enumerate(zip(*verts)):
            mins[axis] = min(mins[axis], min(values))
            maxs[axis] = max(maxs[axis], max(values))
    assert mins[1] > max(horizon, 4400), (mins,horizon)
    assert maxs[1] < c['primary']['p'][1], maxs
    assert max(abs(mins[0]),maxs[0]) < 6200 and -8800 < mins[2] < maxs[2] < 4100, (mins,maxs)
    for g,pose in world.fixed_fans.items():
        xs = [pose.world(v)[0] for part in world.groups[g] for v in part.verts]
        clearance = max(abs(x) for x in c['lane_x_mm'])+c['half_actor_mm'][0]
        assert min(xs)>clearance or max(xs)<-clearance, (g,min(xs),max(xs),clearance)

    # A light segment terminating inside a real triangle hits the sheet from above and below.
    verts = cloth.vertices(0)
    triangle = [verts[i] for i in cloth.tri[len(cloth.tri)//2+17]]
    surface = tuple(sum(x)/3 for x in zip(*triangle))
    for source in (c['primary']['p'],(surface[0],c['eye_mm'],surface[2])):
        vector = sub(surface,source)
        length = math.sqrt(dot(vector,vector))
        assert cloth.occludes(0,source,tuple(x/length for x in vector),length+1)

    # Visibility at the actual top lamp. Compare the same sample points at two camera phases.
    a = ShadeRun(world, scan_initial=False)
    a.active = ()
    grid = [(x,5,z) for x in range(-6250,6251,500) for z in range(-9000,3001,500)]
    masks = []
    for key in ('A-section','D-sweep'):
        a.t = c['views'][key]['phase_ticks']
        a.uncovered = False
        covered_p = world.poses(a)
        a.uncovered = True
        clear_p = world.poses(a)
        trees = [world.scene_tree(p) for p in (covered_p,clear_p)]
        mask = set()
        for i,p in enumerate(grid):
            covered,clear = (world.light(ps,p,tree) for ps,tree in zip((covered_p,clear_p),trees))
            assert clear>=covered
            if covered<c['light_min']<=clear:
                mask.add(i)
        assert len(mask)>18, (key,len(mask))
        masks.append(mask)
    assert len(masks[0]^masks[1])>30
    print(f'cloth height {mins[1]}–{maxs[1]} mm; shadow changed at {len(masks[0]^masks[1])} floor probes')


def main(seeds):
    c = config()
    check_surface(ShadeWorld(c,1))
    for strong in (False,True):
        for seed in seeds:
            result = trial(ShadeWorld(c,seed,strong),'B4')
            assert result['result']=='win' and result['applied'], (strong,seed,result)
            print(f'B4 {"strong" if strong else "normal"} seed {seed}: {result["ticks"]} ticks, '
                  f'{result["peak_step_ms"]} ms CPU step, {result["peak_cycle_ms"]} ms CPU cycle')


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeds',nargs='+',type=int,default=[1,7,19])
    main(parser.parse_args().seeds)
