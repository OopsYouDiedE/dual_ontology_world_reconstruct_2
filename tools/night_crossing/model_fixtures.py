"""Build the academy's service furniture. Run through Blender 4.2 in background mode.
Units are metres. Hardware pivots are exported as named empties for the game.
"""
import math
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/architecture/night_crossing'
M = {}


def material(name, color, metal=0, rough=.42):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    shader = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    M[name] = m


def finish(obj, mat, edge=0, parent=None):
    obj.data.materials.append(M[mat])
    if parent:
        bpy.context.view_layer.update()
        world = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_world = world
    if edge:
        bevel = obj.modifiers.new('Machined arris', 'BEVEL')
        bevel.width, bevel.segments = edge, 3
        obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return obj


def slab(name, p, size, mat, edge=.012, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(ob, mat, edge, parent)


def lathe(name, p, profile, mat, parent=None, front=True):
    """Turn an axial cross section with shoulders, fillets, recesses and rolled edges."""
    verts, faces = [], []
    steps = 64
    for depth, radius in profile:
        for j in range(steps):
            a = math.tau * j / steps
            dx, dz = radius * math.cos(a), radius * math.sin(a)
            verts.append((dx, -depth, dz) if front else (dx, dz, depth))
    for k in range(len(profile)-1):
        for j in range(steps):
            a, b = k*steps+j, k*steps+(j+1)%steps
            faces.append((a, b, b+steps, a+steps))
    faces += [tuple(reversed(range(steps))), tuple(range(len(verts)-steps, len(verts)))]
    mesh = bpy.data.meshes.new(name); mesh.from_pydata(verts, [], faces); mesh.update()
    ob = bpy.data.objects.new(name, mesh); bpy.context.collection.objects.link(ob); ob.location = p
    for face in mesh.polygons: face.use_smooth = len(face.vertices) == 4
    return finish(ob, mat, parent=parent)


def pipe(name, path, radius, mat, parent=None):
    c = bpy.data.curves.new(name, 'CURVE'); c.dimensions = '3D'; c.bevel_depth = radius; c.bevel_resolution = 4
    s = c.splines.new('POLY'); s.points.add(len(path)-1)
    for node, p in zip(s.points, path): node.co = (*p, 1)
    ob = bpy.data.objects.new(name, c); bpy.context.collection.objects.link(ob)
    return finish(ob, mat, parent=parent)


def screw(p, parent=None):
    lathe('Slotted brass screw', p, [(0,.014),(.004,.015),(.008,.011)], 'brass', parent)
    slab('Screw slot', (p[0],p[1]-.0082,p[2]), (.018,.001,.003), 'dark', .0006, parent)


def pivot(name, p):
    ob = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(ob); ob.location = p
    bpy.context.view_layer.update()
    return ob


def cabinet(width=2.52, height=1.86, accent='walnut'):
    for x in (-width/2+.10, width/2-.10):
        for y in (-.16,.20):
            lathe('Turned pilaster foot', (x,y,.02), [(0,.087),(.022,.087),(.033,.071),(.056,.071),(.072,.056),(.091,.063),(.13,.052),(.25,.041)], 'walnut', front=False)
        slab('Ebonised stile',(x,-.193,height/2),(.11,.105,height-.29),'walnut',.021)
    slab('Carcass',(0,.04,(height+.17)/2),(width-.10,.55,height-.18),accent,.041)
    for z, h in ((.22,.105),(.91,.12),(height,.115)):
        slab('Projecting moulded rail',(0,-.026,z),(width,.65,h),'walnut',.027)
        slab('Beaded brass inlay',(0,-.355,z),(width-.10,.013,.012),'brass',.003)
    for x in (-.8,0,.8):
        slab('Recessed door panel',(x,-.249,.55),(.77,.046,.49),'walnut',.024)
        slab('Fielded walnut panel',(x,-.282,.55),(.68,.036,.40),accent,.028)
        pipe('Bail pull',[(x-.085,-.31,.68),(x-.085,-.35,.646),(x-.06,-.365,.624),(x+.06,-.365,.624),(x+.085,-.35,.646),(x+.085,-.31,.68)],.012,'brass')
    slab('Cast header plate',(0,-.311,1.735),(2.30,.071,.155),'dark',.024)
    for x in (-1.08,1.08):
        screw((x,-.352,1.735))
    for x in (-.407,.407):
        slab('Station divider',(x,-.288,1.29),(.022,.054,.65),'brass',.005)


def board(x, kind='paper'):
    p = (x,-.323,1.29)
    slab('Dovetailed document tray',p,(.64,.12,.53),'walnut',.024)
    # Individually cut leaves and edge binding, with dog-eared surface and a finger-rubbed clip.
    paper = pivot('ReceiptLeaf', (x,-.384,1.31))
    for i in range(5):
        slab('Deckled folio leaf',(x+i*.002,-.388-i*.002,1.29),(.52-.008*i,.004,.435-.003*i),kind,.0015,paper)
    for dx in (-.20,.20): screw((x+dx,-.398,1.517))
    slab('Spring backing and thumb clip',(x,-.416,1.483),(.172,.024,.053),'brass',.009)
    return paper


def dial(x,z,mat='brass', name='MainAction',radius=.237):
    y=-.321
    lathe('Stepped bezel',(x,y,z),[(0,radius+.023),(.018,radius+.035),(.034,radius+.034),(.051,radius+.015),(.051,radius-.021)],mat)
    lathe('Pressure enamel face',(x,y-.033,z),[(0,radius-.008),(.021,radius-.024)],'ivory')
    for i in range(15):
        a = math.radians(-28+i*17)
        mark=slab('Radial graduation',(x+math.cos(a)*(radius-.04),y-.059,z+math.sin(a)*(radius-.04)),(.007,.006,.022 if i%3 else .037),'ink',.001)
        mark.rotation_euler.y = math.pi/2-a
    hand=pivot(name,(x,y-.071,z))
    slab('Counterpoised needle',(x,y-.072,z+.053),(.016,.008,radius-.052),'oxblood',.003,hand)
    lathe('Needle collet',(x,y-.065,z),[(0,.029),(.016,.028),(.023,.018)],'brass',hand)
    return hand


def wheel(x,z,name='MainAction', radius=.198):
    y=-.43
    a=pivot(name,(x,y,z))
    lathe('Flanged bearing',(x,-.34,z),[(0,.115),(.025,.115),(.038,.090),(.078,.071),(.120,.043)],'iron')
    pipe('Cast handwheel rim',[(x+radius*math.cos(i*math.tau/64),y,z+radius*math.sin(i*math.tau/64)) for i in range(65)],.023,'iron',a)
    for i in range(5):
        t=i*math.tau/5
        pipe('Curved cast spoke',[(x+q*radius*math.cos(t+.25*(1-q)),y+.006,z+q*radius*math.sin(t+.25*(1-q))) for q in (.07,.3,.6,.8,.99)],.016,'iron',a)
    lathe('Turned wheel boss',(x,y,z),[(0,.055),(.026,.056),(.042,.040),(.049,.036)],'brass',a)
    lathe('Ebonite crank',(x+radius,y,z),[(0,.022),(.043,.028),(.086,.027),(.097,.016)],'walnut',a)
    return a


def lever(x,z,name='AuxAction', blade='brass'):
    y=-.351
    slab('Slotted throw plate',(x,y,z),(.24,.05,.39),'iron',.025)
    for xx in (x-.086,x+.086):
        for zz in (z-.153,z+.153): screw((xx,y-.026,zz))
    slab('Throw channel',(x,y-.027,z),(.043,.012,.29),'dark',.008)
    a=pivot(name,(x,y-.04,z-.072))
    pipe('Swan neck lever',[(x,y-.036,z-.073),(x,y-.078,z-.054),(x,y-.146,z+.071),(x,y-.189,z+.095)],.021,blade,a)
    lathe('Turned lever grip',(x,y-.16,z+.095),[(0,.043),(.016,.050),(.035,.049),(.058,.034),(.063,.027)],'oxblood',a)
    return a


def hatch(x,z,name='AuxAction',mat='iron'):
    y=-.33
    slab('Rebated hatch casing',(x,y,z),(.69,.12,.51),mat,.036)
    hinge=pivot(name,(x-.277,y-.066,z))
    slab('Deep-pressed hatch leaf',(x,y-.074,z),(.552,.073,.417),mat,.029,hinge)
    slab('Raised moulded face',(x,y-.115,z),(.476,.018,.340),'dark',.022,hinge)
    for zz in (z-.145,z+.145):
        lathe('Hinge barrel',(x-.279,y-.112,zz-.047),[(0,.021),(.014,.025),(.085,.024),(.094,.019)],'brass',front=False)
    for dx in (-.197,.197):
        for dz in (-.127,.127): screw((x+dx,y-.126,z+dz),hinge)
    pipe('Curled latch handle',[(x+.108,y-.13,z-.043),(x+.116,y-.194,z-.044),(x+.168,y-.205,z-.025),(x+.176,y-.187,z+.02),(x+.176,y-.135,z+.035)],.015,'brass',hinge)
    return hinge


def horn(x,z,name='MainAction'):
    y=-.341; a=pivot(name,(x,y,z))
    pipe('Swept sound pipe',[(x,y+.036,z-.24),(x,y-.006,z-.174),(x,y-.028,z-.09),(x,y-.129,z)],.044,'brass',a)
    lathe('Spun trumpet with inner wall',(x,y-.06,z),[(0,.056),(.03,.062),(.059,.078),(.092,.111),(.128,.166),(.149,.183),(.161,.185),(.166,.177),(.152,.163),(.120,.136),(.085,.086),(.058,.049),(.04,.028)],'brass',a)
    lathe('Trumpet throat',(x,y-.097,z),[(0,.038),(.019,.036)],'dark',a)
    for i in range(3):
        lathe('Throat screen',(x,y-.11-i*.004,z),[(0,.019+i*.005),(.001,.019+i*.005)],'iron',a)
    return a


def spool(x,z,name='MainAction'):
    r=pivot(name,(x,-.409,z))
    lathe('Reel spindle',(x,-.37,z),[(0,.105),(.045,.105),(.078,.049),(.15,.047)],'iron')
    lathe('Cord wound around hub',(x,-.388,z),[(0,.09),(.024,.13),(.055,.133),(.087,.127),(.125,.095)],'cord',r)
    for y in (-.38,-.505):
        pipe('Reel rim',[(x+.172*math.cos(i*math.tau/64),y,z+.172*math.sin(i*math.tau/64)) for i in range(65)],.013,'brass',r)
    for i in range(7):
        a=math.tau*i/7
        ob=slab('Reel flange spoke',(x+.102*math.cos(a),-.507,z+.102*math.sin(a)),(.144,.026,.022),'iron',.008,r)
        ob.rotation_euler.y=-a
    lathe('Reel pin',(x,-.519,z),[(0,.05),(.019,.051),(.035,.027)],'brass',r)
    return r


def cradle(x,z):
    chute=hatch(x,z,'MainAction','oxblood')
    slab('Copper photograph carrier',(x-.03,-.475,z+.05),(.33,.036,.245),'brass',.013,chute)
    slab('Black glass negative',(x-.03,-.496,z+.05),(.274,.009,.19),'ink',.005,chute)


def write(stem, accent, profile):
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    cabinet(accent=accent)
    board(-.814, 'ivory' if stem in {'airlock','meridian','hall'} else 'paper')
    profile()
    bpy.ops.export_scene.gltf(filepath=str(OUT / (stem+'.glb')), export_format='GLB', export_apply=True, export_yup=True)


for args in [
    ('brass',(.55,.29,.099),.71,.30),('iron',(.081,.121,.119),.68,.34),('walnut',(.083,.034,.018),0,.41),
    ('oak',(.22,.105,.047),0,.5),('ebon',(.027,.040,.035),0,.46),('teal',(.048,.122,.116),.21,.38),
    ('oxblood',(.25,.045,.028),.18,.39),('dark',(.018,.021,.019),.23,.42),('ink',(.026,.030,.035),0,.31),
    ('ivory',(.86,.76,.54),.03,.54),('paper',(.76,.60,.38),0,.86),('cord',(.35,.23,.106),0,.91)
]: material(*args)

def wire_return():
    spool(0, 1.28); hatch(.814, 1.28)
    # The two service tags have brass eyelets and separate lengths of twisted cord.
    for x, tint, turn in ((-.252, 'paper', -.19), (.246, 'ivory', .24)):
        p = pivot('Returned tag', (x,-.403,1.147))
        pipe('Twisted tag string', [(x,-.415,1.42),(x-.016,-.457,1.35),(x,-.447,1.282),(x,-.45,1.221)], .008,'cord',p)
        slab('Stamped porters tag',(x,-.454,1.147),(.105,.014,.15),tint,.007,p)
        lathe('Tag grommet',(x,-.456,1.205),[(0,.013),(.005,.014),(.005,.005),(.001,.005)],'brass',p)
        p.rotation_euler.y = turn


def switchboard():
    horn(0, 1.31); lever(.814, 1.27)
    for x,z in [(.10,1.64),(.624,1.55)]:
        pipe('Separate wired return',[(x,-.326,z),(x+.044,-.377,z-.026),(x+.12,-.394,z-.026),(x+.166,-.31,z-.050)],.023,'brass')
    for i in range(2):
        x=.65+i*.23
        lathe('Booth telephone jack',(x,-.32,1.58),[(0,.03),(.012,.032),(.026,.027),(.029,.018),(.008,.016)],'brass')
        lathe('Booth jack inset',(x,-.345,1.58),[(0,.017),(.001,.017)],'ink')
    spool(1.104, 1.246, 'SerialReel').scale *= .57


def pump():
    wheel(0, 1.28); dial(.814, 1.29, name='AuxAction')
    for x in (-.287,.298):
        pipe('Flanged copper gutter',[(x,-.24,1.64),(x,-.388,1.58),(x,-.408,1.48),(x,-.418,1.31),(x,-.387,1.18),(x,-.30,1.14)],.032,'brass')
        for z in (1.47,1.32):
            lathe('Drain union',(x,-.406,z),[(0,.048),(.020,.048),(.021,.042),(.041,.042)],'iron',front=False)
    # The alternative route uses a visible fold-down tray and its waxed packet.
    p = pivot('DripTray',(.814,-.392,1.006))
    slab('Hammered drip pan',(.814,-.470,1.018),(.56,.205,.033),'iron',.009,p)
    for x in (.546,1.082): slab('Drip lip',(x,-.47,1.054),(.019,.205,.069),'brass',.005,p)
    slab('Waxed packet',(.815,-.457,1.051),(.275,.131,.031),'ivory',.009,p)
    pipe('Wax packet seam',[(.685,-.507,1.07),(.816,-.47,1.073),(.945,-.507,1.07)],.004,'cord',p)


def lift():
    wheel(0,1.29,radius=.232); lever(.814,1.30,blade='iron')
    carriage = pivot('BalanceShoe', (0,-.358,1.59))
    for x in (-.18,.18):
        pipe('Suspended shoe guide',[(x,-.422,1.47),(x,-.421,1.63)],.019,'brass')
    slab('Cast balancing weight',(0,-.442,1.596),(.159,.101,.088),'iron',.017,carriage)
    lathe('Balance shoe roller',(0,-.495,1.596),[(0,.043),(.023,.048),(.043,.04)],'brass',carriage)
    for x in (.62,1.01): screw((x,-.36,1.56))


def airlock():
    hatch(0,1.28,'MainAction','brass'); hatch(.814,1.28,'AuxAction','teal')
    for x in (0,.814):
        tray = pivot('WardBench', (x,-.42,1.009))
        for y in (-.439,-.545): slab('Finger-jointed fold-down tray rail',(x,y,1.022),(.58,.065,.042),'oak',.009,tray)
        slab('Creased ward docket',(x+.05,-.493,1.055),(.24,.107,.019),'ivory',.004,tray)
        pipe('Container hasp',[(x-.268,-.417,1.01),(x-.268,-.61,1.01),(x+.268,-.61,1.01),(x+.268,-.417,1.01)],.011,'brass',tray)


def shutter():
    dial(0,1.29); lever(.814,1.30)
    p=pivot('ServiceShoe',(.824,-.41,1.04))
    slab('Drawbar shoe',(.824,-.45,1.034),(.35,.12,.064),'iron',.019,p)
    pipe('Service shoe brace',[(.65,-.42,1.02),(.675,-.48,1.116),(.977,-.48,1.116),(1.006,-.42,1.02)],.016,'brass',p)
    for dx in (-.298,.298): screw((.814+dx,-.36,1.49))


def darkroom():
    cradle(0,1.27); dial(.814,1.29,mat='iron',name='AuxAction')
    frame = pivot('DevelopedPlate',(0,-.452,1.535))
    slab('Copper-bound acetate',(.002,-.442,1.535),(.287,.027,.111),'brass',.005,frame)
    slab('Bromide test strip',(.002,-.463,1.535),(.255,.013,.087),'ink',.004,frame)
    for dx in (-.09,-.03,.03,.09):
        slab('Contact-exposure sample',(dx,-.475,1.535),(.042,.006,.059),'paper' if dx < 0 else 'iron',.003,frame)


def meridian():
    dial(0,1.29,radius=.261); wheel(.814,1.26,'AuxAction')
    # Turned bronze bell: the profile doubles back to form a real inner wall.
    b=pivot('DawnBell',(-.60,-.22,2.255))
    for x in (-.83,-.37):
        slab('Bell bracket',(x,.045,1.981),(.065,.34,.26),'walnut',.025)
    pipe('Wrought suspension rod',[(-.89,-.22,2.171),(-.79,-.22,2.239),(-.40,-.22,2.239),(-.31,-.22,2.171)],.026,'iron')
    lathe('Cast Observatory bell',(-.6,-.22,2.202),[(0,.08),(-.017,.10),(-.058,.115),(-.113,.13),(-.17,.163),(-.198,.187),(-.214,.187),(-.214,.165),(-.181,.148),(-.13,.111),(-.065,.092),(-.019,.061)],'brass',b,False)
    lathe('Swinging clapper',(-.6,-.22,1.965),[(0,.022),(.015,.041),(.040,.042),(.057,.021),(.19,.016)],'iron',b,False)


write('intake','oak',lambda:(hatch(0,1.285,'MainAction','brass'),spool(.814,1.285,'AuxAction')))
write('returns','walnut',wire_return)
write('exchange','teal',switchboard)
write('wash','teal',pump)
write('lift','ebon',lift)
write('airlock','oak',airlock)
write('shutter','oxblood',shutter)
write('hall','oak',lambda:(hatch(0,1.28,'MainAction','walnut'),spool(.814,1.28,'AuxAction')))
write('darkroom','ebon',darkroom)
write('relay','teal',lambda:(horn(0,1.32),spool(.814,1.27,'AuxAction')))
write('meridian','walnut',meridian)

# Routed exits are fully dressed doors. The floor plane and trigger are supplied by the lot.
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for x in (-.554,.554):
    slab('Jamb with rounded arris',(x,0,1.10),(.108,.33,2.20),'walnut',.021)
    slab('Jamb bronze stop',(x,-.172,1.095),(.038,.018,2.11),'brass',.005)
    slab('Plinth block',(x,-.03,.11),(.158,.36,.22),'walnut',.026)
slab('Segmented cornice',(0,-.011,2.224),(1.25,.39,.122),'walnut',.025)
slab('Routed header inset',(0,-.196,2.222),(1.0,.014,.065),'brass',.008)
slab('Threshold plate',(0,0,.016),(1.15,.51,.032),'iron',.008)
slab('Stone slip',(0,.095,.055),(1.0,.14,.013),'brass',.004)
leaf=pivot('Leaf',(-.48,.03,0))
slab('Recessed plank door',(0,.045,1.089),(.966,.078,2.115),'ebon',.023,leaf)
for x in (-.418,.418):
    slab('Continuous structural stile',(x,-.013,1.087),(.132,.067,2.112),'walnut',.018,leaf)
for z in (.126,.96,1.98):
    slab('Tenoned door rail',(0,-.018,z),(.793,.071,.17),'walnut',.022,leaf)
for z in (.569,1.487):
    slab('Ovolo raised panel',(0,-.015,z),(.68,.079,.67),'walnut',.041,leaf)
    slab('Raised centre field',(0,-.064,z),(.579,.029,.567),'oak',.036,leaf)
for z in (.285,1.155,1.86):
    lathe('Hinge knuckle',(-.48,-.058,z),[(0,.019),(.015,.021),(.070,.021),(.082,.017)],'brass',leaf,front=False)
slab('Thumb latch escutcheon',(.377,-.072,1.079),(.105,.045,.27),'brass',.018,leaf)
pipe('Thumb latch pull',[(.393,-.11,1.14),(.369,-.151,1.125),(.304,-.165,1.10),(.281,-.166,1.11)],.018,'brass',leaf)
leaf.rotation_euler.z = math.radians(15)
bpy.ops.export_scene.gltf(filepath=str(OUT / 'service_door.glb'), export_format='GLB', export_apply=True, export_yup=True)
